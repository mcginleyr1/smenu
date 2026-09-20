import AppKit
import ServiceManagement

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let defaults = UserDefaults.standard
    private let overlay = Overlay()
    private var divider: NSStatusItem!
    private var dividerMaxX: CGFloat = 0
    private var overflowCatcher: NSWindow?
    private var lastWidths: PillWidths?
    private var timer: Timer?

    private var collapsed: Bool {
        get { defaults.bool(forKey: "collapsed") }
        set { defaults.set(newValue, forKey: "collapsed") }
    }

    private var style: Style {
        get { Style(rawValue: defaults.string(forKey: "style") ?? "") ?? .split }
        set { defaults.set(newValue.rawValue, forKey: "style") }
    }

    private var look: Look {
        get { Look(rawValue: defaults.string(forKey: "look") ?? "") ?? .dark }
        set { defaults.set(newValue.rawValue, forKey: "look") }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        divider = NSStatusBar.system.statusItem(withLength: 8)
        divider.autosaveName = "smenu.divider"
        divider.button?.target = self
        divider.button?.action = #selector(dividerClicked)
        divider.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        applyCollapsed()
        // The divider has no position until the bar has laid it out, so size it again once it has.
        Timer.scheduledTimer(timeInterval: 1, target: self, selector: #selector(applyCollapsed), userInfo: nil, repeats: false)
        if style == .split {
            AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
        }

        let center = NotificationCenter.default
        let workspace = NSWorkspace.shared.notificationCenter
        center.addObserver(self, selector: #selector(refresh), name: NSApplication.didChangeScreenParametersNotification, object: nil)
        workspace.addObserver(self, selector: #selector(refresh), name: NSWorkspace.didActivateApplicationNotification, object: nil)
        workspace.addObserver(self, selector: #selector(refresh), name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)
        timer = Timer.scheduledTimer(timeInterval: 3, target: self, selector: #selector(refresh), userInfo: nil, repeats: true)
        refresh()
    }

    @objc private func refresh() {
        let style = style
        let look = look
        let bars = NSScreen.screens
            .map { CGRect(x: $0.frame.minX, y: $0.visibleFrame.maxY, width: $0.frame.width, height: $0.frame.maxY - $0.visibleFrame.maxY) }
            .filter { $0.height > 0 }
        guard style == .split, let primaryMaxY = NSScreen.screens.first?.frame.maxY else {
            overlay.render(style: style, look: look, widths: nil, bars: bars)
            return
        }
        // Hidden items keep reporting stale positions, so while collapsed the pill starts at the
        // divider's right end, leaving room for the system's « overflow marker drawn there.
        let extrasMinX = collapsed && dividerMaxX > 0 ? dividerMaxX - 30 : nil
        Task {
            let widths = await Task.detached { await measurePillWidths(bars: bars, primaryMaxY: primaryMaxY, extrasMinX: extrasMinX) }.value
            // A failed measurement (a menu is open, an app is mid-launch) keeps the pills where they were.
            lastWidths = widths ?? lastWidths
            overlay.render(style: style, look: look, widths: lastWidths, bars: bars)
        }
    }

    /// macOS 27 evicts a status item wider than the room right of the notch instead of letting it push
    /// its neighbours off-screen, so the divider only fills the room up to the notch. The items to its
    /// left then no longer fit there and the system moves them out of the way.
    @objc private func applyCollapsed() {
        // Status item frames go stale once an item is stretched, so only trust them while expanded.
        if divider.length == 8, let frame = divider.button?.window?.frame {
            dividerMaxX = frame.maxX
        }
        let screen = NSScreen.screens.first { $0.frame.minX <= dividerMaxX && dividerMaxX <= $0.frame.maxX }
        let boundary = screen?.auxiliaryTopRightArea?.minX ?? screen?.frame.midX ?? dividerMaxX
        divider.length = collapsed ? max(dividerMaxX - boundary, 8) : 8
        divider.button?.title = collapsed ? "" : "│"
        catchOverflowClicks(on: collapsed && dividerMaxX > 0 ? screen : nil)
        refresh()
    }

    /// While collapsed the system draws its « overflow marker at the divider's right end; clicking it would
    /// reveal the hidden items left of the notch. A click-catcher above it expands smenu in place instead.
    private func catchOverflowClicks(on screen: NSScreen?) {
        overflowCatcher?.close()
        overflowCatcher = screen.map { screen in
            let frame = CGRect(x: dividerMaxX - 36, y: screen.visibleFrame.maxY, width: 32, height: screen.frame.maxY - screen.visibleFrame.maxY)
            // Non-activating, so the click does not pull the menu bar away from the frontmost app.
            let window = BarWindow(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.isOpaque = false
            window.backgroundColor = NSColor(white: 0, alpha: 0.01)
            window.hasShadow = false
            window.ignoresMouseEvents = false
            window.level = NSWindow.Level(Int(CGWindowLevelForKey(.mainMenuWindow)) + 2)
            window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenNone]
            let view = ClickView()
            view.onClick = { [weak self] event in self?.barClicked(event, in: view) }
            window.contentView = view
            window.orderFrontRegardless()
            return window
        }
    }

    private func barClicked(_ event: NSEvent, in view: NSView) {
        guard event.type == .rightMouseDown || event.type == .rightMouseUp || event.modifierFlags.contains(.option) else {
            toggleCollapsed()
            return
        }
        let menu = NSMenu()
        menuNeedsUpdate(menu)
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: -4), in: view)
    }

    @objc private func dividerClicked() {
        guard let event = NSApp.currentEvent, let button = divider.button else { return }
        barClicked(event, in: button)
    }

    @objc private func toggleCollapsed() {
        collapsed.toggle()
        applyCollapsed()
        // The bar takes a moment to lay the returning items out; re-measure instead of waiting for the timer.
        // Common modes, so these still fire while the bar is tracking the mouse.
        for delay in [0.3, 0.8] {
            RunLoop.main.add(Timer(timeInterval: delay, target: self, selector: #selector(refresh), userInfo: nil, repeats: false), forMode: .common)
        }
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        menu.addItem(option("Hide Icons Left of │", #selector(toggleCollapsed), checked: collapsed))
        menu.addItem(.separator())
        menu.addItem(submenu("Capsule", Style.allCases.map { option($0.rawValue, #selector(pickStyle), checked: $0 == style) }))
        menu.addItem(submenu("Look", Look.allCases.map { option($0.rawValue, #selector(pickLook), checked: $0 == look) }))
        let spacing = itemSpacing
        let note = NSMenuItem(title: "Applies as apps relaunch; log out for all", action: nil, keyEquivalent: "")
        menu.addItem(submenu("Item Spacing", [
            option("Default", #selector(pickSpacing), checked: spacing == nil, value: nil),
            option("Compact", #selector(pickSpacing), checked: spacing == 6, value: 6),
            option("Tight", #selector(pickSpacing), checked: spacing == 3, value: 3),
            .separator(),
            note,
        ]))
        menu.addItem(.separator())
        menu.addItem(option("Launch at Login", #selector(toggleLaunchAtLogin), checked: SMAppService.mainApp.status == .enabled))
        menu.addItem(NSMenuItem(title: "Quit smenu", action: #selector(NSApplication.terminate), keyEquivalent: "q"))
    }

    private func submenu(_ title: String, _ items: [NSMenuItem]) -> NSMenuItem {
        let parent = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        parent.submenu = NSMenu()
        items.forEach { parent.submenu?.addItem($0) }
        return parent
    }

    private func option(_ title: String, _ action: Selector, checked: Bool, value: Int? = nil) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.state = checked ? .on : .off
        item.representedObject = value
        return item
    }

    @objc private func pickStyle(_ sender: NSMenuItem) {
        style = Style(rawValue: sender.title)!
        if style == .split {
            AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
        }
        refresh()
    }

    @objc private func pickLook(_ sender: NSMenuItem) {
        look = Look(rawValue: sender.title)!
        refresh()
    }

    private var itemSpacing: Int? {
        CFPreferencesCopyValue("NSStatusItemSpacing" as CFString, kCFPreferencesAnyApplication, kCFPreferencesCurrentUser, kCFPreferencesCurrentHost) as? Int
    }

    @objc private func pickSpacing(_ sender: NSMenuItem) {
        let value = sender.representedObject as? Int
        for key in ["NSStatusItemSpacing", "NSStatusItemSelectionPadding"] {
            CFPreferencesSetValue(key as CFString, value as CFNumber?, kCFPreferencesAnyApplication, kCFPreferencesCurrentUser, kCFPreferencesCurrentHost)
        }
        CFPreferencesSynchronize(kCFPreferencesAnyApplication, kCFPreferencesCurrentUser, kCFPreferencesCurrentHost)
    }

    @objc private func toggleLaunchAtLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            NSAlert(error: error).runModal()
        }
    }
}

let delegate = AppDelegate()
NSApplication.shared.delegate = delegate
NSApplication.shared.setActivationPolicy(.accessory)
NSApplication.shared.run()
