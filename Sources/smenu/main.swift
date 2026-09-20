import AppKit
import ServiceManagement

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let defaults = UserDefaults.standard
    private let overlay = Overlay()
    private var toggle: NSStatusItem!
    private var divider: NSStatusItem!
    private var filler: NSStatusItem!
    private var dividerMaxX: CGFloat = 0
    private var timer: Timer?

    private var style: Style {
        get { Style(rawValue: defaults.string(forKey: "style") ?? "") ?? .full }
        set { defaults.set(newValue.rawValue, forKey: "style") }
    }

    private var look: Look {
        get { Look(rawValue: defaults.string(forKey: "look") ?? "") ?? .glass }
        set { defaults.set(newValue.rawValue, forKey: "look") }
    }

    private var collapsed: Bool {
        get { defaults.bool(forKey: "collapsed") }
        set { defaults.set(newValue, forKey: "collapsed") }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Created first so it sits to the right of the divider; everything left of the divider hides.
        toggle = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        toggle.autosaveName = "smenu.toggle"
        toggle.button?.target = self
        toggle.button?.action = #selector(toggleClicked)
        toggle.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        divider = NSStatusBar.system.statusItem(withLength: 8)
        divider.autosaveName = "smenu.divider"
        filler = NSStatusBar.system.statusItem(withLength: 8)
        filler.autosaveName = "smenu.filler"
        applyCollapsed()
        // The divider has no position until the bar has laid it out, so size it again once it has.
        Timer.scheduledTimer(timeInterval: 1, target: self, selector: #selector(applyCollapsed), userInfo: nil, repeats: false)

        let center = NotificationCenter.default
        let workspace = NSWorkspace.shared.notificationCenter
        center.addObserver(self, selector: #selector(refresh), name: NSApplication.didChangeScreenParametersNotification, object: nil)
        workspace.addObserver(self, selector: #selector(refresh), name: NSWorkspace.didActivateApplicationNotification, object: nil)
        workspace.addObserver(self, selector: #selector(refresh), name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)
        // The filler is sized against the active app's menus.
        workspace.addObserver(self, selector: #selector(applyCollapsed), name: NSWorkspace.didActivateApplicationNotification, object: nil)
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
        Task {
            let widths = await Task.detached { measurePillWidths(bars: bars, primaryMaxY: primaryMaxY) }.value
            overlay.render(style: style, look: look, widths: widths, bars: bars)
        }
    }

    @objc private func applyCollapsed() {
        // Status item frames go stale once an item is stretched, so only trust them while expanded.
        if divider.length == 8, let frame = divider.button?.window?.frame {
            dividerMaxX = frame.maxX
        }
        let lengths = collapsed ? collapsedLengths : (divider: 8, filler: 8)
        divider.length = max(lengths.divider, 8)
        filler.length = max(lengths.filler, 8)
        divider.button?.title = collapsed ? "" : "│"
        filler.button?.title = collapsed ? "" : "┊"
        divider.button?.appearsDisabled = true
        filler.button?.appearsDisabled = true
        toggle.button?.image = NSImage(systemSymbolName: collapsed ? "chevron.left" : "chevron.right", accessibilityDescription: "smenu")
    }

    /// macOS 27 evicts a status item wider than the room on its side of the notch instead of letting it
    /// push its neighbours off-screen, and wraps items that run out of room to the other side of the notch.
    /// So the divider fills the room up to the notch and the filler fills the room between the notch
    /// and the app menus, leaving the items to their left nowhere to go.
    private var collapsedLengths: (divider: CGFloat, filler: CGFloat) {
        guard let screen = NSScreen.screens.first(where: { $0.frame.minX <= dividerMaxX && dividerMaxX <= $0.frame.maxX }) else { return (8, 8) }
        let menusMaxX = NSWorkspace.shared.frontmostApplication
            .flatMap { barItemFrames(pid: $0.processIdentifier, bar: kAXMenuBarAttribute).map(\.maxX).max() }
        guard let notchMinX = screen.auxiliaryTopLeftArea?.maxX, let notchMaxX = screen.auxiliaryTopRightArea?.minX else {
            return (dividerMaxX - (menusMaxX ?? screen.frame.midX) - 16, 8)
        }
        return (dividerMaxX - notchMaxX, menusMaxX.map { notchMinX - $0 - 16 } ?? 8)
    }

    @objc private func toggleClicked() {
        let event = NSApp.currentEvent
        guard event?.type == .rightMouseUp || event?.modifierFlags.contains(.option) == true else {
            collapsed.toggle()
            if collapsed {
                AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
            }
            applyCollapsed()
            refresh()
            return
        }
        toggle.menu = buildMenu()
        toggle.button?.performClick(nil)
        toggle.menu = nil
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
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
        return menu
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
