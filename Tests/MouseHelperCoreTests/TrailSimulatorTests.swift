import CoreGraphics
import XCTest
@testable import MouseHelperCore

final class TrailSimulatorTests: XCTestCase {
    func testTrailFadesOutCompletelyAfterRelease() {
        var sim = TrailSimulator(pointLifetime: 0.4)
        let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)

        sim.beginStroke(at: CGPoint(x: 300, y: 400), now: 10.0)
        sim.advanceStroke(
            cocoaCursorPoint: CGPoint(x: 340, y: 400),
            rawDeltaX: 40,
            rawDeltaY: 0,
            lockCursor: false,
            enableVertical: false,
            screenBounds: screen,
            now: 10.05
        )
        sim.advanceStroke(
            cocoaCursorPoint: CGPoint(x: 390, y: 400),
            rawDeltaX: 50,
            rawDeltaY: 0,
            lockCursor: false,
            enableVertical: false,
            screenBounds: screen,
            now: 10.10
        )

        XCTAssertTrue(sim.hasVisibleContent)
        XCTAssertEqual(sim.points.count, 3)
        XCTAssertGreaterThan(sim.particles.count, 0)

        sim.endStroke()
        // Shortly after release, trail is still fading out
        XCTAssertTrue(sim.step(now: 10.20))
        XCTAssertTrue(sim.hasVisibleContent)

        // After pointLifetime + max particle lifetime, everything disappears completely
        let stillVisible = sim.step(now: 11.20)
        XCTAssertFalse(stillVisible)
        XCTAssertFalse(sim.hasVisibleContent)
        XCTAssertTrue(sim.points.isEmpty)
        XCTAssertTrue(sim.particles.isEmpty)
    }

    func testLockedCursorAdvancesVirtualTrailHeadAndClampsToScreen() {
        var sim = TrailSimulator(pointLifetime: 0.4)
        let screen = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let lockedAnchor = CGPoint(x: 950, y: 400)

        sim.beginStroke(at: lockedAnchor, now: 1.0)
        // Even though OS cursor stays at lockedAnchor, rawDeltaX moves virtual trail head right
        sim.advanceStroke(
            cocoaCursorPoint: lockedAnchor,
            rawDeltaX: 20,
            rawDeltaY: 0,
            lockCursor: true,
            enableVertical: false,
            screenBounds: screen,
            now: 1.02
        )
        XCTAssertEqual(sim.headPosition?.x ?? 0, 970, accuracy: 0.01)

        // Pushing far past right edge clamps inside inset screen bounds (1000 - 16 = 984)
        sim.advanceStroke(
            cocoaCursorPoint: lockedAnchor,
            rawDeltaX: 200,
            rawDeltaY: 0,
            lockCursor: true,
            enableVertical: false,
            screenBounds: screen,
            now: 1.04
        )
        XCTAssertEqual(sim.headPosition?.x ?? 0, 984, accuracy: 0.01)
        XCTAssertGreaterThan(sim.particles.count, 0)
    }

    func testClearAllImmediatelyHidesTrail() {
        var sim = TrailSimulator()
        let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
        sim.beginStroke(at: CGPoint(x: 200, y: 200), now: 5.0)
        sim.advanceStroke(
            cocoaCursorPoint: CGPoint(x: 260, y: 200),
            rawDeltaX: 60,
            rawDeltaY: 0,
            lockCursor: false,
            enableVertical: false,
            screenBounds: screen,
            now: 5.05
        )
        XCTAssertTrue(sim.hasVisibleContent)

        sim.clearAll()
        XCTAssertFalse(sim.hasVisibleContent)
        XCTAssertTrue(sim.points.isEmpty)
        XCTAssertTrue(sim.particles.isEmpty)
    }
}
