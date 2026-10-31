import AppKit

enum ScreenPositionHelper {
    static func screen(at point: NSPoint, screens: [NSScreen] = NSScreen.screens) -> NSScreen? {
        screens.first { $0.frame.contains(point) } ?? screens.min {
            distanceSquared(from: point, to: $0.frame) < distanceSquared(from: point, to: $1.frame)
        }
    }

    private static func distanceSquared(from point: NSPoint, to rect: NSRect) -> CGFloat {
        let dx = max(rect.minX - point.x, 0, point.x - rect.maxX)
        let dy = max(rect.minY - point.y, 0, point.y - rect.maxY)
        return dx * dx + dy * dy
    }

    static func frame(near point: NSPoint, size: NSSize, visibleFrame: NSRect, gap: CGFloat = 12) -> NSRect {
        let bounds = visibleFrame.insetBy(dx: 8, dy: 8)
        let width = min(size.width, bounds.width)
        let height = min(size.height, bounds.height)
        var x = point.x + gap
        var y = point.y - gap - height // AppKit coordinates increase upwards.
        if x + width > bounds.maxX { x = point.x - gap - width }
        if y < bounds.minY { y = point.y + gap }
        x = min(max(x, bounds.minX), bounds.maxX - width)
        y = min(max(y, bounds.minY), bounds.maxY - height)
        return NSRect(x: x, y: y, width: width, height: height)
    }
}
