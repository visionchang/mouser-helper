import CoreGraphics
import Foundation

public enum GestureDirection: String, Codable, Equatable, Sendable {
    case left
    case right
    case up
    case down

    public var arrow: String {
        switch self {
        case .left: return "←"
        case .right: return "→"
        case .up: return "↑"
        case .down: return "↓"
        }
    }
}

public enum GesturePattern: String, CaseIterable, Codable, Identifiable, Hashable, Sendable {
    case left
    case right
    case up
    case down
    case downRight
    case downLeft
    case upRight
    case upLeft

    public var id: String { rawValue }

    public var directions: [GestureDirection] {
        switch self {
        case .left: return [.left]
        case .right: return [.right]
        case .up: return [.up]
        case .down: return [.down]
        case .downRight: return [.down, .right]
        case .downLeft: return [.down, .left]
        case .upRight: return [.up, .right]
        case .upLeft: return [.up, .left]
        }
    }

    public var symbol: String {
        directions.map(\.arrow).joined(separator: " ")
    }

    public var displayName: String {
        switch self {
        case .left: return "左滑"
        case .right: return "右滑"
        case .up: return "上滑"
        case .down: return "下滑"
        case .downRight: return "下再右"
        case .downLeft: return "下再左"
        case .upRight: return "上再右"
        case .upLeft: return "上再左"
        }
    }

    public var defaultAction: GestureActionType {
        switch self {
        case .left: return .goBack
        case .right: return .goForward
        case .up: return .missionControl
        case .down: return .minimizeWindow
        case .downRight: return .closeTab
        case .downLeft: return .reopenTab
        case .upRight: return .nextTab
        case .upLeft: return .previousTab
        }
    }

    public static func from(directions: [GestureDirection]) -> GesturePattern? {
        switch directions {
        case [.left]: return .left
        case [.right]: return .right
        case [.up]: return .up
        case [.down]: return .down
        case [.down, .right]: return .downRight
        case [.down, .left]: return .downLeft
        case [.up, .right]: return .upRight
        case [.up, .left]: return .upLeft
        default: return nil
        }
    }
}

public enum GestureActionType: String, CaseIterable, Codable, Identifiable, Sendable {
    case goBack
    case goForward
    case closeTab
    case reopenTab
    case newTab
    case reloadPage
    case nextTab
    case previousTab
    case missionControl
    case appExpose
    case showDesktop
    case spaceLeft
    case spaceRight
    case minimizeWindow
    case hideApp
    case toggleFullscreen
    case scrollToTop
    case scrollToBottom

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .goBack: return "后退"
        case .goForward: return "前进"
        case .closeTab: return "关闭标签页"
        case .reopenTab: return "恢复关闭的标签页"
        case .newTab: return "新建标签页"
        case .reloadPage: return "刷新页面"
        case .nextTab: return "下一个标签页"
        case .previousTab: return "上一个标签页"
        case .missionControl: return "调度中心"
        case .appExpose: return "应用窗口 Exposé"
        case .showDesktop: return "显示桌面"
        case .spaceLeft: return "左侧桌面空间"
        case .spaceRight: return "右侧桌面空间"
        case .minimizeWindow: return "最小化窗口"
        case .hideApp: return "隐藏当前应用"
        case .toggleFullscreen: return "切换全屏"
        case .scrollToTop: return "回到页面顶部"
        case .scrollToBottom: return "跳到页面底部"
        }
    }

    public var shortcutLabel: String {
        switch self {
        case .goBack: return "⌘["
        case .goForward: return "⌘]"
        case .closeTab: return "⌘W"
        case .reopenTab: return "⇧⌘T"
        case .newTab: return "⌘T"
        case .reloadPage: return "⌘R"
        case .nextTab: return "⌃Tab"
        case .previousTab: return "⌃⇧Tab"
        case .missionControl: return "系统"
        case .appExpose: return "⌃↓"
        case .showDesktop: return "F11"
        case .spaceLeft: return "⌃←"
        case .spaceRight: return "⌃→"
        case .minimizeWindow: return "⌘M"
        case .hideApp: return "⌘H"
        case .toggleFullscreen: return "⌃⌘F"
        case .scrollToTop: return "⌘↑"
        case .scrollToBottom: return "⌘↓"
        }
    }
}

public struct GestureBinding: Equatable, Codable, Sendable {
    public var isEnabled: Bool
    public var action: GestureActionType

    public init(isEnabled: Bool = true, action: GestureActionType) {
        self.isEnabled = isEnabled
        self.action = action
    }
}

public struct GestureSettingsSnapshot: Equatable, Codable, Sendable {
    public var isEnabled: Bool
    public var showHUD: Bool
    public var bindings: [GesturePattern: GestureBinding]

    public init(
        isEnabled: Bool = true,
        showHUD: Bool = true,
        bindings: [GesturePattern: GestureBinding] = Self.defaultBindings
    ) {
        self.isEnabled = isEnabled
        self.showHUD = showHUD
        self.bindings = bindings
    }

    public static var defaultBindings: [GesturePattern: GestureBinding] {
        var map: [GesturePattern: GestureBinding] = [:]
        for pattern in GesturePattern.allCases {
            map[pattern] = GestureBinding(isEnabled: true, action: pattern.defaultAction)
        }
        return map
    }

    public func binding(for pattern: GesturePattern) -> GestureBinding {
        bindings[pattern] ?? GestureBinding(isEnabled: true, action: pattern.defaultAction)
    }

    public func match(for directions: [GestureDirection]) -> GestureMatch {
        guard !directions.isEmpty else {
            return .pending
        }
        guard let pattern = GesturePattern.from(directions: directions) else {
            return .cancelled(arrows: directions.map(\.arrow).joined(separator: " "))
        }
        let b = binding(for: pattern)
        if b.isEnabled {
            return .matched(pattern: pattern, action: b.action)
        } else {
            return .disabled(pattern: pattern)
        }
    }
}

public enum GestureMatch: Equatable, Sendable {
    case pending
    case matched(pattern: GesturePattern, action: GestureActionType)
    case disabled(pattern: GesturePattern)
    case cancelled(arrows: String)

    public var executableAction: GestureActionType? {
        if case .matched(_, let action) = self {
            return action
        }
        return nil
    }
}

public enum RightGestureResult: Equatable, Sendable {
    case passThrough
    case suppressPending
    case replayRightClick(location: CGPoint, clickCount: Int64, flags: UInt64)
    case beginDrawing(anchor: CGPoint, current: CGPoint, match: GestureMatch)
    case updateDrawing(current: CGPoint, match: GestureMatch)
    case finishDrawing(action: GestureActionType?)
    case cancelDrawing
}

/// Pure, thread-agnostic right-click gesture recognizer (4 cardinal + 4 L-shaped combos)
/// that preserves normal right-click context menus when movement stays below threshold.
public struct RightGestureStateMachine: Sendable {
    public enum Phase: Equatable, Sendable {
        case idle
        case pendingRightClick(downLocation: CGPoint, clickCount: Int64, flags: UInt64)
        case drawing(segmentAnchor: CGPoint, directions: [GestureDirection])
    }

    public static let defaultActivationDistance: Double = 10.0
    public static let defaultSegmentDistance: Double = 32.0

    public let activationDistance: Double
    public let segmentDistance: Double
    public private(set) var phase: Phase = .idle

    public init(
        activationDistance: Double = defaultActivationDistance,
        segmentDistance: Double = defaultSegmentDistance
    ) {
        self.activationDistance = activationDistance
        self.segmentDistance = segmentDistance
    }

    public var isDrawing: Bool {
        if case .drawing = phase {
            return true
        }
        return false
    }

    public mutating func handleRightMouseDown(
        location: CGPoint,
        clickCount: Int64,
        flags: UInt64,
        appEnabled: Bool,
        settings: GestureSettingsSnapshot
    ) -> RightGestureResult {
        guard appEnabled, settings.isEnabled else {
            return resetIfNeeded()
        }
        phase = .pendingRightClick(downLocation: location, clickCount: clickCount, flags: flags)
        return .suppressPending
    }

    public mutating func handleRightMouseDragged(
        location: CGPoint,
        appEnabled: Bool,
        settings: GestureSettingsSnapshot
    ) -> RightGestureResult {
        guard appEnabled, settings.isEnabled else {
            return resetIfNeeded()
        }

        switch phase {
        case .idle:
            return .passThrough

        case .pendingRightClick(let downLocation, _, _):
            let dx = Double(location.x - downLocation.x)
            let dy = Double(location.y - downLocation.y)
            if hypot(dx, dy) < activationDistance {
                return .suppressPending
            }

            var directions: [GestureDirection] = []
            var nextAnchor = downLocation
            if hypot(dx, dy) >= segmentDistance, let dir = dominantDirection(dx: dx, dy: dy) {
                directions.append(dir)
                nextAnchor = location
            }
            phase = .drawing(segmentAnchor: nextAnchor, directions: directions)
            return .beginDrawing(
                anchor: downLocation,
                current: location,
                match: settings.match(for: directions)
            )

        case .drawing(let segmentAnchor, var directions):
            let dx = Double(location.x - segmentAnchor.x)
            let dy = Double(location.y - segmentAnchor.y)
            let dist = hypot(dx, dy)

            var updatedAnchor = segmentAnchor
            if dist >= segmentDistance, let dir = dominantDirection(dx: dx, dy: dy) {
                if directions.last == dir {
                    // Continuing along same direction: slide anchor forward so turning a corner responds immediately.
                    updatedAnchor = location
                } else {
                    if directions.count < 3 {
                        directions.append(dir)
                    }
                    updatedAnchor = location
                }
            } else if let lastDir = directions.last, dist >= 6.0 {
                // Keep advancing anchor when moving in the same cardinal direction to make L-turns super crisp.
                if isMovingAlong(direction: lastDir, dx: dx, dy: dy) {
                    updatedAnchor = location
                }
            }

            phase = .drawing(segmentAnchor: updatedAnchor, directions: directions)
            return .updateDrawing(
                current: location,
                match: settings.match(for: directions)
            )
        }
    }

    public mutating func handleRightMouseUp(
        location: CGPoint,
        settings: GestureSettingsSnapshot
    ) -> RightGestureResult {
        switch phase {
        case .idle:
            return .passThrough

        case .pendingRightClick(let downLocation, let clickCount, let flags):
            phase = .idle
            let clickLoc = hypot(location.x - downLocation.x, location.y - downLocation.y) <= 20
                ? location
                : downLocation
            return .replayRightClick(
                location: clickLoc,
                clickCount: max(1, clickCount),
                flags: flags
            )

        case .drawing(_, let directions):
            phase = .idle
            let match = settings.match(for: directions)
            return .finishDrawing(action: match.executableAction)
        }
    }

    public mutating func reset() -> RightGestureResult {
        let wasDrawing = isDrawing
        phase = .idle
        return wasDrawing ? .cancelDrawing : .passThrough
    }

    private mutating func resetIfNeeded() -> RightGestureResult {
        if phase == .idle {
            return .passThrough
        }
        return reset()
    }

    /// Quartz global display coordinates: +X is right, +Y is down.
    private func dominantDirection(dx: Double, dy: Double) -> GestureDirection? {
        let absX = abs(dx)
        let absY = abs(dy)
        guard max(absX, absY) > 0 else { return nil }
        // Require a clear cardinal bias (avoid ambiguous 45-degree diagonals).
        if absX >= absY * 1.15 {
            return dx > 0 ? .right : .left
        } else if absY >= absX * 1.15 {
            return dy > 0 ? .down : .up
        }
        return absX >= absY ? (dx > 0 ? .right : .left) : (dy > 0 ? .down : .up)
    }

    private func isMovingAlong(direction: GestureDirection, dx: Double, dy: Double) -> Bool {
        switch direction {
        case .right: return dx > 0 && abs(dx) > abs(dy) * 1.3
        case .left:  return dx < 0 && abs(dx) > abs(dy) * 1.3
        case .down:  return dy > 0 && abs(dy) > abs(dx) * 1.3
        case .up:    return dy < 0 && abs(dy) > abs(dx) * 1.3
        }
    }
}
