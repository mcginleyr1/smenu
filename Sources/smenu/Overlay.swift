import AppKit

enum Style: String, CaseIterable {
    case off = "Off"
    case full = "Full Bar"
    case split = "Split Pills"
}

enum Look: String, CaseIterable {
    case light = "Light"
    case dark = "Dark"

    var fill: NSColor {
        switch self {
        case .light: NSColor(white: 1, alpha: 0.18)
        case .dark: NSColor(white: 0, alpha: 0.28)
        }
    }
}

/// AppKit otherwise pushes windows down out of the menu bar area.
final class BarWindow: NSPanel {
    override init(contentRect: NSRect, styleMask style: NSWindow.StyleMask, backing: NSWindow.BackingStoreType, defer flag: Bool) {
        super.init(contentRect: contentRect, styleMask: style, backing: backing, defer: flag)
        // Panels hide when their app is inactive, which a menu bar utility always is.
        hidesOnDeactivate = false
    }

    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

final class ClickView: NSView {
    var onClick: (NSEvent) -> Void = { _ in }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) { onClick(event) }
    override func rightMouseDown(with event: NSEvent) { onClick(event) }
}

/// Click-through windows sitting just above the menu bar, one per screen. The bar only ever shows the
/// wallpaper through itself, so anything beneath it is invisible; the pills are kept translucent instead.
@MainActor
final class Overlay {
    private struct Inputs: Equatable {
        var style: Style
        var look: Look
        var widths: PillWidths?
        var bars: [CGRect]
    }

    private var rendered: Inputs?
    private var windows: [NSWindow] = []

    func render(style: Style, look: Look, widths: PillWidths?, bars: [CGRect]) {
        let inputs = Inputs(style: style, look: look, widths: widths, bars: bars)
        guard inputs != rendered else { return }
        let shown = style == .off ? [] : bars
        if shown != windows.map(\.frame) {
            windows.forEach { $0.close() }
            windows = shown.map { bar in
                let window = BarWindow(contentRect: bar, styleMask: .borderless, backing: .buffered, defer: false)
                window.isReleasedWhenClosed = false
                window.isOpaque = false
                window.backgroundColor = .clear
                window.hasShadow = false
                window.ignoresMouseEvents = true
                window.level = NSWindow.Level(Int(CGWindowLevelForKey(.mainMenuWindow)) + 1)
                window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenNone]
                window.orderFrontRegardless()
                return window
            }
        }
        let restyled = look != rendered?.look
        rendered = inputs
        for window in windows {
            let frames = pillFrames(in: CGRect(origin: .zero, size: window.frame.size), style: style, widths: widths)
            guard let content = window.contentView else { continue }
            // The same pills slide to their new frames; a different number of them is a different picture.
            if restyled || content.subviews.count != frames.count {
                content.subviews = frames.map { pill($0, look: look) }
                continue
            }
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.3
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                for (view, frame) in zip(content.subviews, frames) {
                    view.animator().frame = frame
                }
            }
        }
    }

    private func pillFrames(in bar: CGRect, style: Style, widths: PillWidths?) -> [CGRect] {
        let margin: CGFloat = 6
        let capsule = bar.insetBy(dx: margin, dy: (bar.height / 8).rounded())
        guard style == .split else { return [capsule] }
        guard let widths else { return [] }
        let (menus, _) = capsule.divided(atDistance: widths.menus, from: .minXEdge)
        let (extras, _) = capsule.divided(atDistance: widths.extras, from: .maxXEdge)
        return menus.intersects(extras) ? [capsule] : [menus, extras]
    }

    private func pill(_ frame: CGRect, look: Look) -> NSView {
        let view = NSView(frame: frame)
        view.wantsLayer = true
        view.layer?.backgroundColor = look.fill.cgColor
        view.layer?.cornerRadius = frame.height / 2
        view.layer?.borderWidth = 1
        view.layer?.borderColor = NSColor(white: 1, alpha: 0.3).cgColor
        return view
    }
}
