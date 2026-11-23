import XCTest
@testable import MouseHelperCore

final class WheelReverserTests: XCTestCase {
    func testReversesRegularDiscreteMouseWheel() {
        let settings = ScrollSettingsSnapshot(isEnabled: true, reverseMouseWheel: true)
        let event = ScrollWheelEventInfo(
            isContinuous: false,
            scrollPhase: 0,
            momentumPhase: 0,
            deltaAxis1: -3,
            pointDeltaAxis1: -30,
            fixedPtDeltaAxis1: -3.5,
            deltaAxis2: 1,
            pointDeltaAxis2: 10,
            fixedPtDeltaAxis2: 1.25
        )

        let reversed = WheelReverser.reversedDeltasIfApplicable(for: event, settings: settings)
        XCTAssertEqual(
            reversed,
            ReversedScrollDeltas(
                deltaAxis1: 3,
                pointDeltaAxis1: 30,
                fixedPtDeltaAxis1: 3.5,
                deltaAxis2: -1,
                pointDeltaAxis2: -10,
                fixedPtDeltaAxis2: -1.25
            )
        )
    }

    func testIgnoresMagicMouseAndTrackpadContinuousScroll() {
        let settings = ScrollSettingsSnapshot(isEnabled: true, reverseMouseWheel: true)

        // Apple Magic Mouse / Trackpad active touch scroll
        let touchScroll = ScrollWheelEventInfo(
            isContinuous: true,
            scrollPhase: 2,
            momentumPhase: 0,
            deltaAxis1: -2,
            pointDeltaAxis1: -18,
            fixedPtDeltaAxis1: -1.8
        )
        XCTAssertFalse(WheelReverser.isRegularWheelMouse(touchScroll))
        XCTAssertNil(WheelReverser.reversedDeltasIfApplicable(for: touchScroll, settings: settings))

        // Apple Magic Mouse / Trackpad inertia momentum scroll
        let momentumScroll = ScrollWheelEventInfo(
            isContinuous: true,
            scrollPhase: 0,
            momentumPhase: 2,
            deltaAxis1: -1,
            pointDeltaAxis1: -9,
            fixedPtDeltaAxis1: -0.9
        )
        XCTAssertFalse(WheelReverser.isRegularWheelMouse(momentumScroll))
        XCTAssertNil(WheelReverser.reversedDeltasIfApplicable(for: momentumScroll, settings: settings))

        // Continuous without phases (still multi-touch / smooth device)
        let continuousNoPhase = ScrollWheelEventInfo(
            isContinuous: true,
            scrollPhase: 0,
            momentumPhase: 0,
            deltaAxis1: 1,
            pointDeltaAxis1: 10,
            fixedPtDeltaAxis1: 1.0
        )
        XCTAssertNil(WheelReverser.reversedDeltasIfApplicable(for: continuousNoPhase, settings: settings))
    }

    func testIgnoresWhenFeatureOffOrAppDisabled() {
        let regularWheel = ScrollWheelEventInfo(
            isContinuous: false,
            scrollPhase: 0,
            momentumPhase: 0,
            deltaAxis1: 3,
            pointDeltaAxis1: 30,
            fixedPtDeltaAxis1: 3.0
        )

        let featureOff = ScrollSettingsSnapshot(isEnabled: true, reverseMouseWheel: false)
        XCTAssertNil(WheelReverser.reversedDeltasIfApplicable(for: regularWheel, settings: featureOff))

        let appDisabled = ScrollSettingsSnapshot(isEnabled: false, reverseMouseWheel: true)
        XCTAssertNil(WheelReverser.reversedDeltasIfApplicable(for: regularWheel, settings: appDisabled))
    }

    func testIgnoresZeroDeltaEvent() {
        let settings = ScrollSettingsSnapshot(isEnabled: true, reverseMouseWheel: true)
        let zeroEvent = ScrollWheelEventInfo(
            isContinuous: false,
            scrollPhase: 0,
            momentumPhase: 0,
            deltaAxis1: 0,
            pointDeltaAxis1: 0,
            fixedPtDeltaAxis1: 0
        )
        XCTAssertNil(WheelReverser.reversedDeltasIfApplicable(for: zeroEvent, settings: settings))
    }
}
