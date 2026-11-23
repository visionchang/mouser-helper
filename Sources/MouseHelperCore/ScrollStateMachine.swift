import CoreGraphics
import Foundation

public enum ScrollDirectionMode: String, CaseIterable, Codable, Sendable {
    /// Moving mouse right scrolls the viewport right (reveals content on the right).
    case viewportFollowsMouse
    /// Moving mouse right pulls the page content right (hand-grab / natural trackpad feel).
    case contentFollowsMouse

    /// Multiplier applied to hardware mouse delta to produce CGEvent scroll wheel delta.
    public var sign: Double {
        switch self {
        case .viewportFollowsMouse:
            return -1.0
        case .contentFollowsMouse:
            return 1.0
        }
    }
}

public struct ScrollSettingsSnapshot: Equatable, Sendable {
    public var isEnabled: Bool
    public var sensitivity: Double
    public var directionMode: ScrollDirectionMode
    public var dragThreshold: Double
    public var lockCursor: Bool
    public var enableVerticalScroll: Bool
    public var smoothScrolling: Bool
    public var reverseMouseWheel: Bool
    public var enableTrail: Bool
    public var trailStyle: TrailStyle
    public var gestures: GestureSettingsSnapshot

    public init(
        isEnabled: Bool = true,
        sensitivity: Double = 1.5,
        directionMode: ScrollDirectionMode = .viewportFollowsMouse,
        dragThreshold: Double = 5.0,
        lockCursor: Bool = true,
        enableVerticalScroll: Bool = false,
        smoothScrolling: Bool = true,
        reverseMouseWheel: Bool = false,
        enableTrail: Bool = true,
        trailStyle: TrailStyle = .neonCyan,
        gestures: GestureSettingsSnapshot = GestureSettingsSnapshot()
    ) {
        self.isEnabled = isEnabled
        self.sensitivity = sensitivity
        self.directionMode = directionMode
        self.dragThreshold = dragThreshold
        self.lockCursor = lockCursor
        self.enableVerticalScroll = enableVerticalScroll
        self.smoothScrolling = smoothScrolling
        self.reverseMouseWheel = reverseMouseWheel
        self.enableTrail = enableTrail
        self.trailStyle = trailStyle
        self.gestures = gestures
    }
}

public struct ScrollEmission: Equatable, Sendable {
    public let deltaX: Int32
    public let deltaY: Int32
    public let isPixelUnits: Bool

    public init(deltaX: Int32, deltaY: Int32, isPixelUnits: Bool) {
        self.deltaX = deltaX
        self.deltaY = deltaY
        self.isPixelUnits = isPixelUnits
    }
}

public enum ScrollAction: Equatable, Sendable {
    case passThrough
    case suppress(lockCursor: Bool = false)
    case replayMiddleClick(location: CGPoint, clickCount: Int64, flags: UInt64, unlockCursor: Bool)
    case beginScroll(anchor: CGPoint, lockCursor: Bool, emission: ScrollEmission?)
    case emitScroll(ScrollEmission)
    case endScroll(unlockCursor: Bool)
    case reset(unlockCursor: Bool)
}

/// Pure, thread-agnostic state machine converting middle-button drag gestures into
/// horizontal (and optionally vertical) scroll wheel emissions while preserving
/// normal middle-clicks (e.g. open/close tabs).
public struct ScrollStateMachine: Sendable {
    public enum Phase: Equatable, Sendable {
        case idle
        case pendingMiddleClick(
            downLocation: CGPoint,
            clickCount: Int64,
            flags: UInt64,
            cursorLocked: Bool,
            pendingDeltaX: Double,
            pendingDeltaY: Double
        )
        case scrolling(cursorLocked: Bool)
    }

    /// macOS CGEvent mouse button number for the middle (scroll wheel) button.
    public static let middleMouseButtonNumber: Int64 = 2
    /// Base pixel multiplier at sensitivity 1.0 so gentle mouse motion feels responsive.
    public static let pixelBaseScale: Double = 2.2
    /// Hardware delta pixels per 1 discrete line step at sensitivity 1.0.
    public static let lineBaseDivisor: Double = 14.0

    public private(set) var phase: Phase = .idle
    private var remainderX: Double = 0
    private var remainderY: Double = 0

    public init() {}

    public var isScrolling: Bool {
        if case .scrolling = phase {
            return true
        }
        return false
    }

    public var isCursorLocked: Bool {
        switch phase {
        case .idle:
            return false
        case .pendingMiddleClick(_, _, _, let locked, _, _):
            return locked
        case .scrolling(let locked):
            return locked
        }
    }

    public static func isMiddleMouseButton(_ buttonNumber: Int64) -> Bool {
        buttonNumber == middleMouseButtonNumber
    }

    public mutating func handleMiddleMouseDown(
        location: CGPoint,
        clickCount: Int64,
        flags: UInt64,
        settings: ScrollSettingsSnapshot
    ) -> ScrollAction {
        guard settings.isEnabled else {
            return resetIfNeeded()
        }

        let wasLocked = isCursorLocked
        remainderX = 0
        remainderY = 0
        phase = .pendingMiddleClick(
            downLocation: location,
            clickCount: clickCount,
            flags: flags,
            cursorLocked: settings.lockCursor,
            pendingDeltaX: 0,
            pendingDeltaY: 0
        )

        if wasLocked && !settings.lockCursor {
            return .reset(unlockCursor: true)
        }
        return .suppress(lockCursor: settings.lockCursor)
    }

    public mutating func handleMiddleMouseDragged(
        location: CGPoint,
        rawDeltaX: Double,
        rawDeltaY: Double,
        settings: ScrollSettingsSnapshot
    ) -> ScrollAction {
        guard settings.isEnabled else {
            return resetIfNeeded()
        }

        switch phase {
        case .idle:
            return .passThrough

        case .pendingMiddleClick(
            let downLocation,
            let clickCount,
            let flags,
            let cursorLocked,
            let prevPendingX,
            let prevPendingY
        ):
            let newPendingX = prevPendingX + rawDeltaX
            let newPendingY = prevPendingY + rawDeltaY

            // Fallback to screen location diff if rawDelta is zero (e.g. synthesized drag events).
            let locDX = Double(location.x - downLocation.x)
            let locDY = Double(location.y - downLocation.y)
            let effectiveX = abs(newPendingX) >= abs(locDX) ? newPendingX : locDX
            let effectiveY = abs(newPendingY) >= abs(locDY) ? newPendingY : locDY

            let threshold = max(1.0, settings.dragThreshold)
            let triggered: Bool
            if settings.enableVerticalScroll {
                triggered = hypot(effectiveX, effectiveY) >= threshold
            } else {
                triggered = abs(effectiveX) >= threshold
            }

            if !triggered {
                phase = .pendingMiddleClick(
                    downLocation: downLocation,
                    clickCount: clickCount,
                    flags: flags,
                    cursorLocked: cursorLocked,
                    pendingDeltaX: newPendingX,
                    pendingDeltaY: newPendingY
                )
                return .suppress(lockCursor: cursorLocked)
            }

            let shouldLock = cursorLocked || settings.lockCursor
            phase = .scrolling(cursorLocked: shouldLock)
            remainderX = 0
            remainderY = 0

            let initialEmission = computeEmission(
                deltaX: rawDeltaX != 0 ? rawDeltaX : effectiveX,
                deltaY: settings.enableVerticalScroll ? (rawDeltaY != 0 ? rawDeltaY : effectiveY) : 0,
                settings: settings
            )

            return .beginScroll(
                anchor: downLocation,
                lockCursor: shouldLock,
                emission: initialEmission
            )

        case .scrolling(let cursorLocked):
            let emission = computeEmission(
                deltaX: rawDeltaX,
                deltaY: settings.enableVerticalScroll ? rawDeltaY : 0,
                settings: settings
            )
            if let emission {
                return .emitScroll(emission)
            }
            return .suppress(lockCursor: cursorLocked)
        }
    }

    public mutating func handleMiddleMouseUp(
        location: CGPoint,
        settings: ScrollSettingsSnapshot
    ) -> ScrollAction {
        switch phase {
        case .idle:
            return .passThrough

        case .pendingMiddleClick(let downLocation, let clickCount, let flags, let cursorLocked, _, _):
            phase = .idle
            remainderX = 0
            remainderY = 0
            let clickLocation = cursorLocked
                ? downLocation
                : (hypot(location.x - downLocation.x, location.y - downLocation.y) <= 20 ? location : downLocation)
            return .replayMiddleClick(
                location: clickLocation,
                clickCount: max(1, clickCount),
                flags: flags,
                unlockCursor: cursorLocked
            )

        case .scrolling(let cursorLocked):
            phase = .idle
            remainderX = 0
            remainderY = 0
            return .endScroll(unlockCursor: cursorLocked)
        }
    }

    public mutating func reset() -> ScrollAction {
        let shouldUnlock = isCursorLocked
        phase = .idle
        remainderX = 0
        remainderY = 0
        return .reset(unlockCursor: shouldUnlock)
    }

    private mutating func resetIfNeeded() -> ScrollAction {
        if phase == .idle {
            return .passThrough
        }
        return reset()
    }

    private mutating func computeEmission(
        deltaX: Double,
        deltaY: Double,
        settings: ScrollSettingsSnapshot
    ) -> ScrollEmission? {
        let sign = settings.directionMode.sign
        let clampedSensitivity = max(0.1, min(10.0, settings.sensitivity))

        let scaledX: Double
        let scaledY: Double

        if settings.smoothScrolling {
            scaledX = deltaX * clampedSensitivity * Self.pixelBaseScale * sign
            scaledY = deltaY * clampedSensitivity * Self.pixelBaseScale * sign
        } else {
            scaledX = (deltaX * clampedSensitivity / Self.lineBaseDivisor) * sign
            scaledY = (deltaY * clampedSensitivity / Self.lineBaseDivisor) * sign
        }

        remainderX += scaledX
        remainderY += scaledY

        let emitX = Int32(remainderX.rounded(.towardZero))
        let emitY = Int32(remainderY.rounded(.towardZero))

        remainderX -= Double(emitX)
        remainderY -= Double(emitY)

        if emitX == 0 && emitY == 0 {
            return nil
        }

        return ScrollEmission(
            deltaX: emitX,
            deltaY: emitY,
            isPixelUnits: settings.smoothScrolling
        )
    }
}
