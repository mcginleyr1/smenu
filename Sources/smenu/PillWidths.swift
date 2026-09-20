import AppKit

/// How far the app menus reach in from the left edge of the bar, and the status items from the right.
struct PillWidths: Equatable, Sendable {
    var menus: CGFloat
    var extras: CGFloat
}

/// macOS 27 draws every status item inside one MenuBarAgent window, so item positions
/// are only available through Accessibility. `bars` are menu bar rects in Cocoa coordinates.
func measurePillWidths(bars: [CGRect], primaryMaxY: CGFloat, extrasMinX: CGFloat?) async -> PillWidths? {
    let apps = NSWorkspace.shared.runningApplications
    let frames = { @Sendable (pid: pid_t, bar: String) in
        barItemFrames(pid: pid, bar: bar).map { $0.offsetBy(dx: 0, dy: primaryMaxY - 2 * $0.midY) }
    }
    // Not the active app: clicking smenu's own items can make smenu active, and it has no menus.
    guard let active = NSWorkspace.shared.menuBarOwningApplication,
          let menusMaxX = frames(active.processIdentifier, kAXMenuBarAttribute).map(\.maxX).max(),
          let bar = bars.first(where: { $0.minX < menusMaxX && menusMaxX <= $0.maxX })
    else { return nil }
    if let extrasMinX {
        return PillWidths(menus: menusMaxX - bar.minX, extras: bar.maxX - extrasMinX)
    }
    // Apps that never answer cost a full timeout each, so ask them all at once.
    let extras = await withTaskGroup(of: [CGRect].self) { group in
        for app in apps {
            let pid = app.processIdentifier
            group.addTask { frames(pid, kAXExtrasMenuBarAttribute) }
        }
        return await group.reduce(into: []) { $0 += $1 }
    }
    guard let extrasMinX = extras.filter({ bar.contains(CGPoint(x: $0.midX, y: $0.midY)) }).map(\.minX).min() else { return nil }
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
