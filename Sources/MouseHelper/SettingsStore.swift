import Combine
import Foundation
import MouseHelperCore

@MainActor
final class SettingsStore: ObservableObject {
    private enum Keys {
        static let isEnabled = "MouseHelper.isEnabled"
        static let sensitivity = "MouseHelper.sensitivity"
        static let directionMode = "MouseHelper.directionMode"
        static let dragThreshold = "MouseHelper.dragThreshold"
        static let lockCursor = "MouseHelper.lockCursorV3"
        static let enableVerticalScroll = "MouseHelper.enableVerticalScroll"
        static let smoothScrolling = "MouseHelper.smoothScrolling"
        static let reverseMouseWheel = "MouseHelper.reverseMouseWheel"
        static let enableTrail = "MouseHelper.enableTrail"
        static let trailStyle = "MouseHelper.trailStyle"
        static let gesturesEnabled = "MouseHelper.gesturesEnabled"
        static let showGestureHUD = "MouseHelper.showGestureHUD"
        static let gestureBindings = "MouseHelper.gestureBindings"
    }

    private let defaults: UserDefaults

    @Published var isEnabled: Bool {
        didSet {
            defaults.set(isEnabled, forKey: Keys.isEnabled)
            notifySnapshotChanged()
        }
    }

    @Published var sensitivity: Double {
        didSet {
            defaults.set(sensitivity, forKey: Keys.sensitivity)
            notifySnapshotChanged()
        }
    }

    @Published var directionMode: ScrollDirectionMode {
        didSet {
            defaults.set(directionMode.rawValue, forKey: Keys.directionMode)
            notifySnapshotChanged()
        }
    }

    @Published var dragThreshold: Double {
        didSet {
            defaults.set(dragThreshold, forKey: Keys.dragThreshold)
            notifySnapshotChanged()
        }
    }

    @Published var lockCursor: Bool {
        didSet {
            defaults.set(lockCursor, forKey: Keys.lockCursor)
            notifySnapshotChanged()
        }
    }

    @Published var enableVerticalScroll: Bool {
        didSet {
            defaults.set(enableVerticalScroll, forKey: Keys.enableVerticalScroll)
            notifySnapshotChanged()
        }
    }

    @Published var smoothScrolling: Bool {
        didSet {
            defaults.set(smoothScrolling, forKey: Keys.smoothScrolling)
            notifySnapshotChanged()
        }
    }

    @Published var reverseMouseWheel: Bool {
        didSet {
            defaults.set(reverseMouseWheel, forKey: Keys.reverseMouseWheel)
            notifySnapshotChanged()
        }
    }

    @Published var enableTrail: Bool {
        didSet {
            defaults.set(enableTrail, forKey: Keys.enableTrail)
            notifySnapshotChanged()
        }
    }

    @Published var trailStyle: TrailStyle {
        didSet {
            defaults.set(trailStyle.rawValue, forKey: Keys.trailStyle)
            notifySnapshotChanged()
        }
    }

    @Published var gesturesEnabled: Bool {
        didSet {
            defaults.set(gesturesEnabled, forKey: Keys.gesturesEnabled)
            notifySnapshotChanged()
        }
    }

    @Published var showGestureHUD: Bool {
        didSet {
            defaults.set(showGestureHUD, forKey: Keys.showGestureHUD)
            notifySnapshotChanged()
        }
    }

    @Published var gestureBindings: [GesturePattern: GestureBinding] {
        didSet {
            if let encoded = try? JSONEncoder().encode(gestureBindings) {
                defaults.set(encoded, forKey: Keys.gestureBindings)
            }
            notifySnapshotChanged()
        }
    }

    @Published var launchAtLogin: Bool {
        didSet {
            guard !isSyncingLaunchAtLogin else { return }
            let actual = LaunchAtLoginManager.setEnabled(launchAtLogin)
            if actual != launchAtLogin {
                isSyncingLaunchAtLogin = true
                launchAtLogin = actual
                isSyncingLaunchAtLogin = false
            }
        }
    }

    @Published var hasAccessibilityPermission: Bool = false
    @Published var isTapRunning: Bool = false

    private var isSyncingLaunchAtLogin = false
    var onSnapshotChanged: ((ScrollSettingsSnapshot) -> Void)?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        let defaultSnapshot = ScrollSettingsSnapshot()

        self.isEnabled = defaults.object(forKey: Keys.isEnabled) as? Bool ?? defaultSnapshot.isEnabled
        self.sensitivity = defaults.object(forKey: Keys.sensitivity) as? Double ?? defaultSnapshot.sensitivity
        if let rawMode = defaults.string(forKey: Keys.directionMode),
           let parsed = ScrollDirectionMode(rawValue: rawMode) {
            self.directionMode = parsed
        } else {
            self.directionMode = defaultSnapshot.directionMode
        }
        self.dragThreshold = defaults.object(forKey: Keys.dragThreshold) as? Double ?? defaultSnapshot.dragThreshold
        self.lockCursor = defaults.object(forKey: Keys.lockCursor) as? Bool ?? defaultSnapshot.lockCursor
        self.enableVerticalScroll = defaults.object(forKey: Keys.enableVerticalScroll) as? Bool ?? defaultSnapshot.enableVerticalScroll
        self.smoothScrolling = defaults.object(forKey: Keys.smoothScrolling) as? Bool ?? defaultSnapshot.smoothScrolling
        self.reverseMouseWheel = defaults.object(forKey: Keys.reverseMouseWheel) as? Bool ?? defaultSnapshot.reverseMouseWheel
        self.enableTrail = defaults.object(forKey: Keys.enableTrail) as? Bool ?? defaultSnapshot.enableTrail
        if let rawStyle = defaults.string(forKey: Keys.trailStyle),
           let parsedStyle = TrailStyle(rawValue: rawStyle) {
            self.trailStyle = parsedStyle
        } else {
            self.trailStyle = defaultSnapshot.trailStyle
        }

        let defaultGestures = defaultSnapshot.gestures
        self.gesturesEnabled = defaults.object(forKey: Keys.gesturesEnabled) as? Bool ?? defaultGestures.isEnabled
        self.showGestureHUD = defaults.object(forKey: Keys.showGestureHUD) as? Bool ?? defaultGestures.showHUD
        if let data = defaults.data(forKey: Keys.gestureBindings),
           let decoded = try? JSONDecoder().decode([GesturePattern: GestureBinding].self, from: data) {
            var merged = GestureSettingsSnapshot.defaultBindings
            for (k, v) in decoded {
                merged[k] = v
            }
            self.gestureBindings = merged
        } else {
            self.gestureBindings = GestureSettingsSnapshot.defaultBindings
        }

        self.isSyncingLaunchAtLogin = true
        self.launchAtLogin = LaunchAtLoginManager.isEnabled
        self.isSyncingLaunchAtLogin = false
    }

    var snapshot: ScrollSettingsSnapshot {
        ScrollSettingsSnapshot(
            isEnabled: isEnabled,
            sensitivity: sensitivity,
            directionMode: directionMode,
            dragThreshold: dragThreshold,
            lockCursor: lockCursor,
            enableVerticalScroll: enableVerticalScroll,
            smoothScrolling: smoothScrolling,
            reverseMouseWheel: reverseMouseWheel,
            enableTrail: enableTrail,
            trailStyle: trailStyle,
            gestures: GestureSettingsSnapshot(
                isEnabled: gesturesEnabled,
                showHUD: showGestureHUD,
                bindings: gestureBindings
            )
        )
    }

    func binding(for pattern: GesturePattern) -> GestureBinding {
        gestureBindings[pattern] ?? GestureBinding(isEnabled: true, action: pattern.defaultAction)
    }

    func setGestureEnabled(_ enabled: Bool, for pattern: GesturePattern) {
        var current = binding(for: pattern)
        current.isEnabled = enabled
        gestureBindings[pattern] = current
    }

    func setGestureAction(_ action: GestureActionType, for pattern: GesturePattern) {
        var current = binding(for: pattern)
        current.action = action
        gestureBindings[pattern] = current
    }

    func refreshLaunchAtLoginStatus() {
        let actual = LaunchAtLoginManager.isEnabled
        if actual != launchAtLogin {
            isSyncingLaunchAtLogin = true
            launchAtLogin = actual
            isSyncingLaunchAtLogin = false
        }
    }

    func resetToDefaults() {
        let d = ScrollSettingsSnapshot()
        isEnabled = d.isEnabled
        sensitivity = d.sensitivity
        directionMode = d.directionMode
        dragThreshold = d.dragThreshold
        lockCursor = d.lockCursor
        enableVerticalScroll = d.enableVerticalScroll
        smoothScrolling = d.smoothScrolling
        reverseMouseWheel = d.reverseMouseWheel
        enableTrail = d.enableTrail
        trailStyle = d.trailStyle
        gesturesEnabled = d.gestures.isEnabled
        showGestureHUD = d.gestures.showHUD
        gestureBindings = GestureSettingsSnapshot.defaultBindings
    }

    private func notifySnapshotChanged() {
        onSnapshotChanged?(snapshot)
    }
}
