import CoreGraphics
import XCTest
@testable import MouseHelperCore

final class RightGestureTests: XCTestCase {
    func testShortRightClickReplaysContextMenu() {
        var machine = RightGestureStateMachine()
        let settings = GestureSettingsSnapshot()
        let start = CGPoint(x: 300, y: 300)

        XCTAssertEqual(
            machine.handleRightMouseDown(location: start, clickCount: 1, flags: 0, appEnabled: true, settings: settings),
            .suppressPending
        )
        XCTAssertEqual(
            machine.handleRightMouseDragged(location: CGPoint(x: 304, y: 302), appEnabled: true, settings: settings),
            .suppressPending
        )
        XCTAssertEqual(
            machine.handleRightMouseUp(location: CGPoint(x: 304, y: 302), settings: settings),
            .replayRightClick(location: CGPoint(x: 304, y: 302), clickCount: 1, flags: 0)
        )
        XCTAssertEqual(machine.phase, .idle)
    }

    func testCardinalLeftSwipeExecutesGoBack() {
        var machine = RightGestureStateMachine()
        let settings = GestureSettingsSnapshot()
        let start = CGPoint(x: 500, y: 400)

        _ = machine.handleRightMouseDown(location: start, clickCount: 1, flags: 0, appEnabled: true, settings: settings)
        let begin = machine.handleRightMouseDragged(location: CGPoint(x: 485, y: 400), appEnabled: true, settings: settings)
        XCTAssertEqual(begin, .beginDrawing(anchor: start, current: CGPoint(x: 485, y: 400), match: .pending))

        let update = machine.handleRightMouseDragged(location: CGPoint(x: 455, y: 400), appEnabled: true, settings: settings)
        XCTAssertEqual(
            update,
            .updateDrawing(current: CGPoint(x: 455, y: 400), match: .matched(pattern: .left, action: .goBack))
        )

        let finish = machine.handleRightMouseUp(location: CGPoint(x: 455, y: 400), settings: settings)
        XCTAssertEqual(finish, .finishDrawing(action: .goBack))
    }

    func testLShapedDownRightExecutesCloseTab() {
        var machine = RightGestureStateMachine()
        let settings = GestureSettingsSnapshot()
        let start = CGPoint(x: 400, y: 300)

        _ = machine.handleRightMouseDown(location: start, clickCount: 1, flags: 0, appEnabled: true, settings: settings)
        // Move down (+Y in Quartz) 50px -> recognizes Down
        _ = machine.handleRightMouseDragged(location: CGPoint(x: 400, y: 315), appEnabled: true, settings: settings)
        let downStep = machine.handleRightMouseDragged(location: CGPoint(x: 400, y: 350), appEnabled: true, settings: settings)
        XCTAssertEqual(
            downStep,
            .updateDrawing(current: CGPoint(x: 400, y: 350), match: .matched(pattern: .down, action: .minimizeWindow))
        )

        // Continue down a bit more (anchor slides forward to corner), then turn right 40px
        _ = machine.handleRightMouseDragged(location: CGPoint(x: 400, y: 370), appEnabled: true, settings: settings)
        let rightTurn = machine.handleRightMouseDragged(location: CGPoint(x: 440, y: 370), appEnabled: true, settings: settings)
        XCTAssertEqual(
            rightTurn,
            .updateDrawing(current: CGPoint(x: 440, y: 370), match: .matched(pattern: .downRight, action: .closeTab))
        )

        let finish = machine.handleRightMouseUp(location: CGPoint(x: 440, y: 370), settings: settings)
        XCTAssertEqual(finish, .finishDrawing(action: .closeTab))
    }

    func testDisabledGestureDoesNotExecuteAction() {
        var machine = RightGestureStateMachine()
        var bindings = GestureSettingsSnapshot.defaultBindings
        bindings[.downRight] = GestureBinding(isEnabled: false, action: .closeTab)
        let settings = GestureSettingsSnapshot(isEnabled: true, showHUD: true, bindings: bindings)

        let start = CGPoint(x: 400, y: 300)
        _ = machine.handleRightMouseDown(location: start, clickCount: 1, flags: 0, appEnabled: true, settings: settings)
        _ = machine.handleRightMouseDragged(location: CGPoint(x: 400, y: 350), appEnabled: true, settings: settings)
        let turn = machine.handleRightMouseDragged(location: CGPoint(x: 445, y: 350), appEnabled: true, settings: settings)
        XCTAssertEqual(turn, .updateDrawing(current: CGPoint(x: 445, y: 350), match: .disabled(pattern: .downRight)))

        let finish = machine.handleRightMouseUp(location: CGPoint(x: 445, y: 350), settings: settings)
        XCTAssertEqual(finish, .finishDrawing(action: nil))
    }

    func testThirdSegmentCancelsGestureSafely() {
        var machine = RightGestureStateMachine()
        let settings = GestureSettingsSnapshot()
        let start = CGPoint(x: 400, y: 300)

        _ = machine.handleRightMouseDown(location: start, clickCount: 1, flags: 0, appEnabled: true, settings: settings)
        _ = machine.handleRightMouseDragged(location: CGPoint(x: 400, y: 350), appEnabled: true, settings: settings) // Down
        _ = machine.handleRightMouseDragged(location: CGPoint(x: 450, y: 350), appEnabled: true, settings: settings) // Right
        let third = machine.handleRightMouseDragged(location: CGPoint(x: 450, y: 300), appEnabled: true, settings: settings) // Up -> 3 segments = cancelled

        if case .updateDrawing(_, .cancelled) = third {
            // Expected
        } else {
            XCTFail("Expected cancelled gesture on 3rd segment, got \(third)")
        }

        let finish = machine.handleRightMouseUp(location: CGPoint(x: 450, y: 300), settings: settings)
        XCTAssertEqual(finish, .finishDrawing(action: nil))
    }

    func testMasterGestureOffPassesThroughRightClick() {
        var machine = RightGestureStateMachine()
        let settings = GestureSettingsSnapshot(isEnabled: false)
        let pt = CGPoint(x: 100, y: 100)

        XCTAssertEqual(
            machine.handleRightMouseDown(location: pt, clickCount: 1, flags: 0, appEnabled: true, settings: settings),
            .passThrough
        )
        XCTAssertEqual(
            machine.handleRightMouseDragged(location: CGPoint(x: 200, y: 100), appEnabled: true, settings: settings),
            .passThrough
        )
        XCTAssertEqual(
            machine.handleRightMouseUp(location: CGPoint(x: 200, y: 100), settings: settings),
            .passThrough
        )
    }
}
