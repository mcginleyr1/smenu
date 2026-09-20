import AppKit

enum Style: String, CaseIterable {
    case off = "Off"
    case full = "Full Bar"
    case split = "Split Pills"
}

enum Look: String, CaseIterable {
    case glass = "Glass"
    case frosted = "Frosted"
}

/// AppKit otherwise pushes windows down out of the menu bar area.
private final class BarWindow: NSWindow {
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

/// Click-through windows sitting just beneath the (transparent) menu bar, one per screen.
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
            window.level = NSWindow.Level(Int(CGWindowLevelForKey(.mainMenuWindow)) - 1)
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
        guard style == .split, let widths else { return [capsule] }
        let (menus, _) = capsule.divided(atDistance: widths.menus, from: .minXEdge)
        let (extras, _) = capsule.divided(atDistance: widths.extras, from: .maxXEdge)
        return menus.intersects(extras) ? [capsule] : [menus, extras]
    }

    private func pill(_ frame: CGRect, look: Look) -> NSView {
        switch look {
        case .glass:
            let glass = NSGlassEffectView(frame: frame)
            glass.cornerRadius = frame.height / 2
            return glass
        case .frosted:
            let blur = NSVisualEffectView(frame: frame)
            blur.material = .hudWindow
            blur.blendingMode = .behindWindow
            blur.state = .active
            blur.maskImage = capsuleMask(height: frame.height)
            return blur
        }
    }

    private func capsuleMask(height: CGFloat) -> NSImage {
        let mask = NSImage(size: NSSize(width: height + 1, height: height), flipped: false) { rect in
            NSBezierPath(roundedRect: rect, xRadius: height / 2, yRadius: height / 2).fill()
            return true
        }
        mask.capInsets = NSEdgeInsets(top: 0, left: height / 2, bottom: 0, right: height / 2)
        mask.resizingMode = .stretch
        return mask
    }
}
