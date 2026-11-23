import CoreGraphics
import XCTest
@testable import MouseHelperCore

final class ScrollStateMachineTests: XCTestCase {
    func testMiddleMouseButtonIdentification() {
        XCTAssertTrue(ScrollStateMachine.isMiddleMouseButton(2))
        XCTAssertFalse(ScrollStateMachine.isMiddleMouseButton(0))
        XCTAssertFalse(ScrollStateMachine.isMiddleMouseButton(1))
        XCTAssertFalse(ScrollStateMachine.isMiddleMouseButton(3))
        XCTAssertFalse(ScrollStateMachine.isMiddleMouseButton(4))
    }

    func testNormalMiddleClickReplaysWhenNoDragWithCursorLocked() {
        var machine = ScrollStateMachine()
        let settings = ScrollSettingsSnapshot(dragThreshold: 5.0, lockCursor: true)
        let pt = CGPoint(x: 200, y: 300)

        let downAction = machine.handleMiddleMouseDown(location: pt, clickCount: 1, flags: 0, settings: settings)
        XCTAssertEqual(downAction, .suppress(lockCursor: true))
        XCTAssertTrue(machine.isCursorLocked)

        // Small jitter below threshold
        let dragAction = machine.handleMiddleMouseDragged(
            location: pt,
            rawDeltaX: 2,
            rawDeltaY: 1,
            settings: settings
        )
        XCTAssertEqual(dragAction, .suppress(lockCursor: true))

        let upAction = machine.handleMiddleMouseUp(location: pt, settings: settings)
        XCTAssertEqual(
            upAction,
            .replayMiddleClick(location: pt, clickCount: 1, flags: 0, unlockCursor: true)
        )
        XCTAssertEqual(machine.phase, .idle)
        XCTAssertFalse(machine.isCursorLocked)
    }

    func testHorizontalDragTriggersScrollAndSuppressesMiddleUp() {
        var machine = ScrollStateMachine()
        let settings = ScrollSettingsSnapshot(
            sensitivity: 1.0,
            directionMode: .viewportFollowsMouse,
            dragThreshold: 5.0,
            lockCursor: true,
            enableVerticalScroll: false,
            smoothScrolling: true
        )
        let start = CGPoint(x: 100, y: 100)

        XCTAssertEqual(
            machine.handleMiddleMouseDown(location: start, clickCount: 1, flags: 0, settings: settings),
            .suppress(lockCursor: true)
        )

        // Move 3px right -> still pending
        XCTAssertEqual(
            machine.handleMiddleMouseDragged(location: start, rawDeltaX: 3, rawDeltaY: 0, settings: settings),
            .suppress(lockCursor: true)
        )

        // Move another 4px right -> total 7px >= 5px -> begin scroll
        let beginAction = machine.handleMiddleMouseDragged(
            location: start,
            rawDeltaX: 4,
            rawDeltaY: 2,
            settings: settings
        )
        // 4 * 1.0 * 2.2 * (-1.0) = -8.8 -> -8
        XCTAssertEqual(
            beginAction,
            .beginScroll(
                anchor: start,
                lockCursor: true,
                emission: ScrollEmission(deltaX: -8, deltaY: 0, isPixelUnits: true)
            )
        )
        XCTAssertTrue(machine.isCursorLocked)

        // Subsequent drag emits horizontal scroll (vertical ignored when disabled)
        let scrollAction = machine.handleMiddleMouseDragged(
            location: start,
            rawDeltaX: 10,
            rawDeltaY: 15,
            settings: settings
        )
        // Remainder was -0.8 + (10 * -2.2) = -22.8 -> -22
        XCTAssertEqual(scrollAction, .emitScroll(ScrollEmission(deltaX: -22, deltaY: 0, isPixelUnits: true)))

        // Release unlocks cursor and does NOT replay middle click
        let endAction = machine.handleMiddleMouseUp(location: start, settings: settings)
        XCTAssertEqual(endAction, .endScroll(unlockCursor: true))
        XCTAssertEqual(machine.phase, .idle)
        XCTAssertFalse(machine.isCursorLocked)
    }

    func testContentFollowsMouseDirectionSign() {
        var machine = ScrollStateMachine()
        let settings = ScrollSettingsSnapshot(
            sensitivity: 1.0,
            directionMode: .contentFollowsMouse,
            dragThreshold: 3.0,
            lockCursor: false,
            smoothScrolling: true
        )
        let start = CGPoint(x: 50, y: 50)
        _ = machine.handleMiddleMouseDown(location: start, clickCount: 1, flags: 0, settings: settings)

        let action = machine.handleMiddleMouseDragged(
            location: CGPoint(x: 55, y: 50),
            rawDeltaX: 5,
            rawDeltaY: 0,
            settings: settings
        )
        // 5 * 1.0 * 2.2 * (+1.0) = +11
        XCTAssertEqual(
            action,
            .beginScroll(
                anchor: start,
                lockCursor: false,
                emission: ScrollEmission(deltaX: 11, deltaY: 0, isPixelUnits: true)
            )
        )
    }

    func testDisabledPassesThroughEvents() {
        var machine = ScrollStateMachine()
        let settings = ScrollSettingsSnapshot(isEnabled: false)
        let pt = CGPoint(x: 10, y: 10)

        XCTAssertEqual(machine.handleMiddleMouseDown(location: pt, clickCount: 1, flags: 0, settings: settings), .passThrough)
        XCTAssertEqual(machine.handleMiddleMouseDragged(location: pt, rawDeltaX: 20, rawDeltaY: 0, settings: settings), .passThrough)
        XCTAssertEqual(machine.handleMiddleMouseUp(location: pt, settings: settings), .passThrough)
    }

    func testScreenEdgeRawDeltaStillTriggersScroll() {
        var machine = ScrollStateMachine()
        let settings = ScrollSettingsSnapshot(dragThreshold: 5.0, lockCursor: true)
        let edge = CGPoint(x: 1440, y: 500)
        _ = machine.handleMiddleMouseDown(location: edge, clickCount: 1, flags: 0, settings: settings)

        let action = machine.handleMiddleMouseDragged(location: edge, rawDeltaX: 6, rawDeltaY: 0, settings: settings)
        if case .beginScroll(let anchor, let lock, let emission) = action {
            XCTAssertEqual(anchor, edge)
            XCTAssertTrue(lock)
            XCTAssertNotNil(emission)
            XCTAssertLessThan(emission?.deltaX ?? 0, 0)
        } else {
            XCTFail("Expected beginScroll at screen edge, got \(action)")
        }
    }

    func testLineModeAccumulatesSubSteps() {
        var machine = ScrollStateMachine()
        let settings = ScrollSettingsSnapshot(
            sensitivity: 1.0,
            directionMode: .viewportFollowsMouse,
            dragThreshold: 4.0,
            lockCursor: false,
            smoothScrolling: false
        )
        let start = CGPoint(x: 100, y: 100)
        _ = machine.handleMiddleMouseDown(location: start, clickCount: 1, flags: 0, settings: settings)

        // 5px crosses threshold, but 5 / 14 < 1 line so initial emission is nil
        let begin = machine.handleMiddleMouseDragged(location: CGPoint(x: 105, y: 100), rawDeltaX: 5, rawDeltaY: 0, settings: settings)
        XCTAssertEqual(begin, .beginScroll(anchor: start, lockCursor: false, emission: nil))

        // Another 10px -> total 15 / 14 = 1.07 -> emits -1 line
        let next = machine.handleMiddleMouseDragged(location: CGPoint(x: 115, y: 100), rawDeltaX: 10, rawDeltaY: 0, settings: settings)
        XCTAssertEqual(next, .emitScroll(ScrollEmission(deltaX: -1, deltaY: 0, isPixelUnits: false)))
    }
}
