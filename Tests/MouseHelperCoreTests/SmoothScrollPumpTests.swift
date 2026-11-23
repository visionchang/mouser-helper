import XCTest
@testable import MouseHelperCore

final class SmoothScrollPumpTests: XCTestCase {
    func testSmoothlyDrainsAndConservesTotalDistance() {
        var pump = SmoothScrollPump()
        pump.beginGesture()
        pump.enqueue(deltaX: -120.0, deltaY: 0)

        var emitted: [SmoothScrollDelta] = []
        // Simulate 6 frames at 120Hz while dragging
        for _ in 0..<6 {
            if let d = pump.step(dt: 1.0 / 120.0) {
                emitted.append(d)
            }
        }

        XCTAssertEqual(emitted.count, 6)
        XCTAssertTrue(emitted.allSatisfy { $0.deltaX < 0 && $0.deltaY == 0 })

        pump.endGesture()
        // Settle remaining glide over up to 60 frames
        for _ in 0..<60 where pump.isActive {
            if let d = pump.step(dt: 1.0 / 120.0) {
                emitted.append(d)
            }
        }

        XCTAssertFalse(pump.isActive)
        let totalDeltaX = emitted.reduce(Int32(0)) { $0 + $1.deltaX }
        XCTAssertEqual(totalDeltaX, -120, accuracy: 1)
    }

    func testCancelImmediatelyClearsPendingScroll() {
        var pump = SmoothScrollPump()
        pump.beginGesture()
        pump.enqueue(deltaX: 50, deltaY: 0)
        _ = pump.step(dt: 1.0 / 60.0)
        XCTAssertTrue(pump.isActive)

        pump.cancelImmediately()
        XCTAssertFalse(pump.isActive)
        XCTAssertNil(pump.step(dt: 1.0 / 60.0))
    }
}
