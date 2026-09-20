import AppKit

/// How far the app menus reach in from the left edge of the bar, and the status items from the right.
struct PillWidths: Equatable, Sendable {
    var menus: CGFloat
    var extras: CGFloat
}

/// macOS 27 draws every status item inside one MenuBarAgent window, so item positions
/// are only available through Accessibility. `bars` are menu bar rects in Cocoa coordinates.
func measurePillWidths(bars: [CGRect], primaryMaxY: CGFloat, extrasMinX: CGFloat?) -> PillWidths? {
    let apps = NSWorkspace.shared.runningApplications
    let frames = { (app: NSRunningApplication, bar: String) in
        barItemFrames(pid: app.processIdentifier, bar: bar).map { $0.offsetBy(dx: 0, dy: primaryMaxY - 2 * $0.midY) }
    }
    guard let active = apps.first(where: \.isActive),
          let menusMaxX = frames(active, kAXMenuBarAttribute).map(\.maxX).max(),
          let bar = bars.first(where: { $0.minX < menusMaxX && menusMaxX <= $0.maxX })
    else { return nil }
    guard let extrasMinX = extrasMinX ?? apps.flatMap({ frames($0, kAXExtrasMenuBarAttribute) })
        .filter({ bar.contains(CGPoint(x: $0.midX, y: $0.midY)) })
        .map(\.minX).min()
    else { return nil }
    return PillWidths(menus: menusMaxX - bar.minX, extras: bar.maxX - extrasMinX)
}

private func barItemFrames(pid: pid_t, bar: String) -> [CGRect] {
    let app = AXUIElementCreateApplication(pid)
    AXUIElementSetMessagingTimeout(app, 0.25)
    var barElement: CFTypeRef?
    guard AXUIElementCopyAttributeValue(app, bar as CFString, &barElement) == .success else { return [] }
    var items: CFTypeRef?
    AXUIElementCopyAttributeValue(barElement as! AXUIElement, kAXChildrenAttribute as CFString, &items)
    return (items as? [AXUIElement] ?? []).compactMap { item in
        var position: CFTypeRef?
        var size: CFTypeRef?
        guard AXUIElementCopyAttributeValue(item, kAXPositionAttribute as CFString, &position) == .success,
              AXUIElementCopyAttributeValue(item, kAXSizeAttribute as CFString, &size) == .success
        else { return nil }
        var origin = CGPoint.zero
        var extent = CGSize.zero
        AXValueGetValue(position as! AXValue, .cgPoint, &origin)
        AXValueGetValue(size as! AXValue, .cgSize, &extent)
        return CGRect(origin: origin, size: extent)
    }
}
