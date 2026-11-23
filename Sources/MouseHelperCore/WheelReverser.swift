import Foundation

public struct ScrollWheelEventInfo: Equatable, Sendable {
    public let isContinuous: Bool
    public let scrollPhase: Int64
    public let momentumPhase: Int64
    public let deltaAxis1: Int64
    public let pointDeltaAxis1: Int64
    public let fixedPtDeltaAxis1: Double
    public let deltaAxis2: Int64
    public let pointDeltaAxis2: Int64
    public let fixedPtDeltaAxis2: Double

    public init(
        isContinuous: Bool,
        scrollPhase: Int64,
        momentumPhase: Int64,
        deltaAxis1: Int64,
        pointDeltaAxis1: Int64,
        fixedPtDeltaAxis1: Double,
        deltaAxis2: Int64 = 0,
        pointDeltaAxis2: Int64 = 0,
        fixedPtDeltaAxis2: Double = 0
    ) {
        self.isContinuous = isContinuous
        self.scrollPhase = scrollPhase
        self.momentumPhase = momentumPhase
        self.deltaAxis1 = deltaAxis1
        self.pointDeltaAxis1 = pointDeltaAxis1
        self.fixedPtDeltaAxis1 = fixedPtDeltaAxis1
        self.deltaAxis2 = deltaAxis2
        self.pointDeltaAxis2 = pointDeltaAxis2
        self.fixedPtDeltaAxis2 = fixedPtDeltaAxis2
    }
}

public struct ReversedScrollDeltas: Equatable, Sendable {
    public let deltaAxis1: Int64
    public let pointDeltaAxis1: Int64
    public let fixedPtDeltaAxis1: Double
    public let deltaAxis2: Int64
    public let pointDeltaAxis2: Int64
    public let fixedPtDeltaAxis2: Double

    public init(
        deltaAxis1: Int64,
        pointDeltaAxis1: Int64,
        fixedPtDeltaAxis1: Double,
        deltaAxis2: Int64,
        pointDeltaAxis2: Int64,
        fixedPtDeltaAxis2: Double
    ) {
        self.deltaAxis1 = deltaAxis1
        self.pointDeltaAxis1 = pointDeltaAxis1
        self.fixedPtDeltaAxis1 = fixedPtDeltaAxis1
        self.deltaAxis2 = deltaAxis2
        self.pointDeltaAxis2 = pointDeltaAxis2
        self.fixedPtDeltaAxis2 = fixedPtDeltaAxis2
    }
}

/// Identifies discrete physical scroll-wheel mice and reverses their scroll deltas
/// without touching macOS system settings, Trackpads, or Apple Magic Mouse.
///
/// On macOS, both Trackpads and Apple Magic Mouse report continuous multi-touch
/// scroll events (`scrollWheelEventIsContinuous != 0`) with gesture/momentum phases,
/// whereas ordinary notched scroll-wheel mice emit discrete events
/// (`isContinuous == 0`, `scrollPhase == 0`, `momentumPhase == 0`).
public enum WheelReverser {
    public static func isRegularWheelMouse(_ info: ScrollWheelEventInfo) -> Bool {
        !info.isContinuous && info.scrollPhase == 0 && info.momentumPhase == 0
    }

    public static func reversedDeltasIfApplicable(
        for info: ScrollWheelEventInfo,
        settings: ScrollSettingsSnapshot
    ) -> ReversedScrollDeltas? {
        guard settings.isEnabled, settings.reverseMouseWheel else {
            return nil
        }
        guard isRegularWheelMouse(info) else {
            return nil
        }

        let hasAnyDelta =
            info.deltaAxis1 != 0 ||
            info.pointDeltaAxis1 != 0 ||
            info.fixedPtDeltaAxis1 != 0 ||
            info.deltaAxis2 != 0 ||
            info.pointDeltaAxis2 != 0 ||
            info.fixedPtDeltaAxis2 != 0

        guard hasAnyDelta else {
            return nil
        }

        return ReversedScrollDeltas(
            deltaAxis1: -info.deltaAxis1,
            pointDeltaAxis1: -info.pointDeltaAxis1,
            fixedPtDeltaAxis1: -info.fixedPtDeltaAxis1,
            deltaAxis2: -info.deltaAxis2,
            pointDeltaAxis2: -info.pointDeltaAxis2,
            fixedPtDeltaAxis2: -info.fixedPtDeltaAxis2
        )
    }
}
