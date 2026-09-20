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
private final class BarWindow: NSWindow {
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
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
        rendered = inputs
        windows.forEach { $0.close() }
        windows = style == .off ? [] : bars.map { bar in
            let window = BarWindow(contentRect: bar, styleMask: .borderless, backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = false
            window.ignoresMouseEvents = true
            window.level = NSWindow.Level(Int(CGWindowLevelForKey(.mainMenuWindow)) + 1)
            window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenNone]
            for frame in pillFrames(in: CGRect(origin: .zero, size: bar.size), style: style, widths: widths) {
                window.contentView?.addSubview(pill(frame, look: look))
            }
            window.orderFrontRegardless()
            return window
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
