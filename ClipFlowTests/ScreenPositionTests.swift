import AppKit
import XCTest
@testable import ClipFlow

final class ScreenPositionTests: XCTestCase {
    private let size = NSSize(width: 500, height: 420)

    func testNormallyOpensBelowAndToRightOfPointer() {
        let point = NSPoint(x: 200, y: 800)
        let frame = ScreenPositionHelper.frame(near: point, size: size, visibleFrame: NSRect(x: 0, y: 25, width: 1440, height: 850))
        XCTAssertEqual(frame.minX, 212)
        XCTAssertEqual(frame.maxY, 788)
    }

    func testBottomRightEdgeFlipsBothAxes() {
        let bounds = NSRect(x: 0, y: 25, width: 1440, height: 850)
        let point = NSPoint(x: 1435, y: 30)
        let frame = ScreenPositionHelper.frame(near: point, size: size, visibleFrame: bounds)
        XCTAssertLessThan(frame.maxX, point.x)
        XCTAssertGreaterThan(frame.minY, point.y)
        XCTAssertTrue(bounds.contains(frame))
    }

    func testNegativeMonitorOriginsAndAllEdgesStayVisible() {
        for bounds in [NSRect(x: -1920, y: 0, width: 1920, height: 1055),
                       NSRect(x: 1440, y: -900, width: 1280, height: 875),
                       NSRect(x: 0, y: 1080, width: 1440, height: 850)] {
            for point in [NSPoint(x: bounds.minX, y: bounds.minY), NSPoint(x: bounds.maxX - 1, y: bounds.maxY - 1),
                          NSPoint(x: bounds.midX, y: bounds.midY)] {
                let frame = ScreenPositionHelper.frame(near: point, size: size, visibleFrame: bounds)
                XCTAssertTrue(bounds.contains(frame))
                XCTAssertEqual(frame.size, size)
            }
        }
    }

    func testSmallVisibleAreaAdaptsSize() {
        let bounds = NSRect(x: -100, y: -100, width: 400, height: 300)
        let frame = ScreenPositionHelper.frame(near: .zero, size: size, visibleFrame: bounds)
        XCTAssertTrue(bounds.contains(frame))
        XCTAssertEqual(frame.size, NSSize(width: 384, height: 284))
    }
}
