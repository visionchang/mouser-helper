import AppKit
import ApplicationServices
import CoreGraphics
import Foundation
import MouseHelperCore
import os

final class ScrollEngine: @unchecked Sendable {
    private static let syntheticEventMarker: Int64 = 0x4D48_5343_524F_4C4C

    private struct SharedState {
        var settings: ScrollSettingsSnapshot
        var isRunning: Bool = false
        var cursorLocked: Bool = false
        var eventTap: CFMachPort?
        var runLoop: CFRunLoop?
        var runLoopSource: CFRunLoopSource?
    }

    private let lock = OSAllocatedUnfairLock(initialState: SharedState(settings: ScrollSettingsSnapshot()))
    private var stateMachine = ScrollStateMachine()
    private var rightGestureMachine = RightGestureStateMachine()
    private let privateEventSource = CGEventSource(stateID: .privateState)
    private let smoothDriver = SmoothScrollDriver(syntheticEventMarker: syntheticEventMarker)
    private var workerThread: Thread?
    private let onStatusChange: @Sendable (Bool) -> Void
    private let onTrailEvent: @Sendable (TrailEvent) -> Void
    private let onGestureHUD: @Sendable (GestureHUDEvent) -> Void

    init(
        initialSettings: ScrollSettingsSnapshot,
        onStatusChange: @escaping @Sendable (Bool) -> Void,
        onTrailEvent: @escaping @Sendable (TrailEvent) -> Void = { _ in },
        onGestureHUD: @escaping @Sendable (GestureHUDEvent) -> Void = { _ in }
    ) {
        self.onStatusChange = onStatusChange
        self.onTrailEvent = onTrailEvent
        self.onGestureHUD = onGestureHUD
        lock.withLock { $0.settings = initialSettings }
    }

    deinit {
        stop()
    }

    static func hasAccessibilityPermission(prompt: Bool = false) -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [key: prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    static func openAccessibilitySettings() {
        _ = hasAccessibilityPermission(prompt: true)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    var isRunning: Bool {
        lock.withLock { $0.isRunning }
    }

    func updateSettings(_ newSettings: ScrollSettingsSnapshot) {
        let wasEnabled = lock.withLock { state -> Bool in
            let prev = state.settings.isEnabled
            state.settings = newSettings
            return prev
        }

        // If disabled while a drag might be active, perform a safe cursor unlock on the tap run loop.
        if wasEnabled && !newSettings.isEnabled {
            scheduleResetOnTapThread()
        }
    }

    @discardableResult
    func startIfPossible() -> Bool {
        guard !isRunning else { return true }
        guard Self.hasAccessibilityPermission(prompt: false) else {
            onStatusChange(false)
            return false
        }

        let startResult = OSAllocatedUnfairLock(initialState: false)
        let readySemaphore = DispatchSemaphore(value: 0)

        let thread = Thread { [weak self] in
            guard let self else {
                readySemaphore.signal()
                return
            }
            self.runTapLoop(startResult: startResult, readySemaphore: readySemaphore)
        }
        thread.name = "com.mousehelper.eventtap"
        thread.qualityOfService = .userInteractive
        self.workerThread = thread
        thread.start()

        _ = readySemaphore.wait(timeout: .now() + 2.0)
        let started = startResult.withLock { $0 }
        onStatusChange(started)
        return started
    }

    func stop() {
        let (tap, runLoop, source) = lock.withLock { state -> (CFMachPort?, CFRunLoop?, CFRunLoopSource?) in
            let tuple = (state.eventTap, state.runLoop, state.runLoopSource)
            state.eventTap = nil
            state.runLoop = nil
            state.runLoopSource = nil
            state.isRunning = false
            return tuple
        }

        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        if let runLoop, let source {
            CFRunLoopRemoveSource(runLoop, source, .commonModes)
        }
        if let runLoop {
            CFRunLoopStop(runLoop)
        }

        unlockCursorSafety()
        workerThread = nil
        smoothDriver.cancelImmediately()
        onTrailEvent(.end)
        onGestureHUD(.hide)
        onStatusChange(false)
    }

    private func scheduleResetOnTapThread() {
        let runLoop = lock.withLock { $0.runLoop }
        guard let runLoop else {
            unlockCursorSafety()
            smoothDriver.cancelImmediately()
            onTrailEvent(.end)
            onGestureHUD(.hide)
            return
        }
        CFRunLoopPerformBlock(runLoop, CFRunLoopMode.commonModes.rawValue) { [weak self] in
            guard let self else { return }
            let action = self.stateMachine.reset()
            if case .reset(let unlockCursor) = action, unlockCursor {
                self.setCursorLocked(false)
            }
            _ = self.rightGestureMachine.reset()
            self.smoothDriver.cancelImmediately()
            self.onTrailEvent(.end)
            self.onGestureHUD(.hide)
        }
        CFRunLoopWakeUp(runLoop)
    }

    private func runTapLoop(
        startResult: OSAllocatedUnfairLock<Bool>,
        readySemaphore: DispatchSemaphore
    ) {
        let eventMask: CGEventMask =
            (1 << CGEventType.otherMouseDown.rawValue) |
            (1 << CGEventType.otherMouseDragged.rawValue) |
            (1 << CGEventType.otherMouseUp.rawValue) |
            (1 << CGEventType.rightMouseDown.rawValue) |
            (1 << CGEventType.rightMouseDragged.rawValue) |
            (1 << CGEventType.rightMouseUp.rawValue) |
            (1 << CGEventType.scrollWheel.rawValue)

        let callback: CGEventTapCallBack = { _, type, event, userInfo in
            guard let userInfo else {
                return Unmanaged.passUnretained(event)
            }
            let engine = Unmanaged<ScrollEngine>.fromOpaque(userInfo).takeUnretainedValue()
            return engine.handleTapEvent(type: type, event: event)
        }

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: callback,
            userInfo: selfPtr
        ) else {
            startResult.withLock { $0 = false }
            readySemaphore.signal()
            return
        }

        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
            CFMachPortInvalidate(tap)
            startResult.withLock { $0 = false }
            readySemaphore.signal()
            return
        }

        let currentRunLoop = CFRunLoopGetCurrent()
        CFRunLoopAddSource(currentRunLoop, source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        lock.withLock { state in
            state.eventTap = tap
            state.runLoop = currentRunLoop
            state.runLoopSource = source
            state.isRunning = true
        }

        startResult.withLock { $0 = true }
        readySemaphore.signal()

        CFRunLoopRun()

        // Cleanup after run loop exits
        let resetAction = stateMachine.reset()
        if case .reset(let unlockCursor) = resetAction, unlockCursor {
            setCursorLocked(false)
        }
        unlockCursorSafety()

        lock.withLock { state in
            if state.eventTap === tap {
                state.eventTap = nil
                state.runLoop = nil
                state.runLoopSource = nil
                state.isRunning = false
            }
        }
    }

    private func handleTapEvent(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // Recover automatically if macOS temporarily disabled the tap.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            let resetAction = stateMachine.reset()
            if case .reset(let unlockCursor) = resetAction, unlockCursor {
                setCursorLocked(false)
            }
            _ = rightGestureMachine.reset()
            smoothDriver.cancelImmediately()
            onTrailEvent(.end)
            onGestureHUD(.hide)
            if let tap = lock.withLock({ $0.eventTap }) {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        // Ignore events synthesized by this app to prevent infinite recursion.
        if event.getIntegerValueField(.eventSourceUserData) == Self.syntheticEventMarker {
            return Unmanaged.passUnretained(event)
        }

        let settings = lock.withLock { $0.settings }

        // Route right-button events to the Right-Click Gesture engine (with neon trail + HUD).
        if type == .rightMouseDown || type == .rightMouseDragged || type == .rightMouseUp {
            return handleRightGestureEvent(type: type, event: event, settings: settings)
        }

        let action: ScrollAction
        var dragRawDeltaX: Double = 0
        var dragRawDeltaY: Double = 0

        switch type {
        case .otherMouseDown:
            let buttonNumber = event.getIntegerValueField(.mouseEventButtonNumber)
            guard ScrollStateMachine.isMiddleMouseButton(buttonNumber) else {
                return Unmanaged.passUnretained(event)
            }
            action = stateMachine.handleMiddleMouseDown(
                location: event.location,
                clickCount: event.getIntegerValueField(.mouseEventClickState),
                flags: event.flags.rawValue,
                settings: settings
            )

        case .otherMouseDragged:
            let buttonNumber = event.getIntegerValueField(.mouseEventButtonNumber)
            guard ScrollStateMachine.isMiddleMouseButton(buttonNumber) else {
                return Unmanaged.passUnretained(event)
            }
            dragRawDeltaX = event.getDoubleValueField(.mouseEventDeltaX)
            dragRawDeltaY = event.getDoubleValueField(.mouseEventDeltaY)
            action = stateMachine.handleMiddleMouseDragged(
                location: event.location,
                rawDeltaX: dragRawDeltaX,
                rawDeltaY: dragRawDeltaY,
                settings: settings
            )

        case .otherMouseUp:
            let buttonNumber = event.getIntegerValueField(.mouseEventButtonNumber)
            guard ScrollStateMachine.isMiddleMouseButton(buttonNumber) else {
                return Unmanaged.passUnretained(event)
            }
            action = stateMachine.handleMiddleMouseUp(
                location: event.location,
                settings: settings
            )

        case .scrollWheel:
            reverseRegularMouseScrollIfNeeded(event: event, settings: settings)
            return Unmanaged.passUnretained(event)

        default:
            return Unmanaged.passUnretained(event)
        }

        switch action {
        case .passThrough:
            return Unmanaged.passUnretained(event)

        case .suppress(let lockCursor):
            if lockCursor {
                setCursorLocked(true)
            }
            if type == .otherMouseDragged {
                if stateMachine.isScrolling && settings.smoothScrolling {
                    enqueueSmoothScroll(
                        rawDeltaX: dragRawDeltaX,
                        rawDeltaY: dragRawDeltaY,
                        at: event.location,
                        settings: settings
                    )
                }
                if !stateMachine.isCursorLocked {
                    return passThroughAsMouseMoved(event)
                }
            }
            return nil

        case .replayMiddleClick(let location, let clickCount, let flags, let unlockCursor):
            if unlockCursor {
                setCursorLocked(false)
            }
            replayMiddleClick(location: location, clickCount: clickCount, flags: flags)
            return nil

        case .beginScroll(_, let lockCursor, let emission):
            if lockCursor {
                setCursorLocked(true)
            }
            if settings.smoothScrolling {
                smoothDriver.beginGesture(at: event.location)
                enqueueSmoothScroll(
                    rawDeltaX: dragRawDeltaX,
                    rawDeltaY: dragRawDeltaY,
                    at: event.location,
                    settings: settings
                )
            } else if let emission {
                postScroll(emission, at: event.location)
            }
            return lockCursor ? nil : passThroughAsMouseMoved(event)

        case .emitScroll(let emission):
            if settings.smoothScrolling {
                enqueueSmoothScroll(
                    rawDeltaX: dragRawDeltaX,
                    rawDeltaY: dragRawDeltaY,
                    at: event.location,
                    settings: settings
                )
            } else {
                postScroll(emission, at: event.location)
            }
            return stateMachine.isCursorLocked ? nil : passThroughAsMouseMoved(event)

        case .endScroll(let unlockCursor):
            if unlockCursor {
                setCursorLocked(false)
            }
            if settings.smoothScrolling {
                smoothDriver.endGesture(at: event.location)
            }
            return nil

        case .reset(let unlockCursor):
            if unlockCursor {
                setCursorLocked(false)
            }
            smoothDriver.cancelImmediately()
            return Unmanaged.passUnretained(event)
        }
    }

    private func handleRightGestureEvent(
        type: CGEventType,
        event: CGEvent,
        settings: ScrollSettingsSnapshot
    ) -> Unmanaged<CGEvent>? {
        let result: RightGestureResult
        var dragRawDeltaX: Double = 0
        var dragRawDeltaY: Double = 0

        switch type {
        case .rightMouseDown:
            result = rightGestureMachine.handleRightMouseDown(
                location: event.location,
                clickCount: event.getIntegerValueField(.mouseEventClickState),
                flags: event.flags.rawValue,
                appEnabled: settings.isEnabled,
                settings: settings.gestures
            )

        case .rightMouseDragged:
            dragRawDeltaX = event.getDoubleValueField(.mouseEventDeltaX)
            dragRawDeltaY = event.getDoubleValueField(.mouseEventDeltaY)
            result = rightGestureMachine.handleRightMouseDragged(
                location: event.location,
                appEnabled: settings.isEnabled,
                settings: settings.gestures
            )

        case .rightMouseUp:
            result = rightGestureMachine.handleRightMouseUp(
                location: event.location,
                settings: settings.gestures
            )

        default:
            return Unmanaged.passUnretained(event)
        }

        switch result {
        case .passThrough:
            return Unmanaged.passUnretained(event)

        case .suppressPending:
            return type == .rightMouseDragged ? passThroughAsMouseMoved(event) : nil

        case .replayRightClick(let location, let clickCount, let flags):
            replayRightClick(location: location, clickCount: clickCount, flags: flags)
            return nil

        case .beginDrawing(let anchor, let current, let match):
            if settings.enableTrail {
                onTrailEvent(.begin(quartzPoint: anchor, lockCursor: false))
                onTrailEvent(.move(
                    quartzPoint: current,
                    rawDeltaX: dragRawDeltaX,
                    rawDeltaY: dragRawDeltaY,
                    lockCursor: false,
                    enableVertical: true
                ))
            }
            if settings.gestures.showHUD {
                onGestureHUD(.update(match: match, quartzPoint: current))
            }
            return passThroughAsMouseMoved(event)

        case .updateDrawing(let current, let match):
            if settings.enableTrail {
                onTrailEvent(.move(
                    quartzPoint: current,
                    rawDeltaX: dragRawDeltaX,
                    rawDeltaY: dragRawDeltaY,
                    lockCursor: false,
                    enableVertical: true
                ))
            }
            if settings.gestures.showHUD {
                onGestureHUD(.update(match: match, quartzPoint: current))
            }
            return passThroughAsMouseMoved(event)

        case .finishDrawing(let action):
            onTrailEvent(.end)
            onGestureHUD(.hide)
            if let action {
                GestureActionExecutor.execute(action)
            }
            return nil

        case .cancelDrawing:
            onTrailEvent(.end)
            onGestureHUD(.hide)
            return Unmanaged.passUnretained(event)
        }
    }

    private func enqueueSmoothScroll(
        rawDeltaX: Double,
        rawDeltaY: Double,
        at location: CGPoint,
        settings: ScrollSettingsSnapshot
    ) {
        let clampedSensitivity = max(0.1, min(10.0, settings.sensitivity))
        let factor = clampedSensitivity * ScrollStateMachine.pixelBaseScale * settings.directionMode.sign
        let scaledX = rawDeltaX * factor
        let scaledY = settings.enableVerticalScroll ? (rawDeltaY * factor) : 0
        if scaledX != 0 || scaledY != 0 {
            smoothDriver.enqueue(deltaX: scaledX, deltaY: scaledY, at: location)
        }
    }

    private func passThroughAsMouseMoved(_ event: CGEvent) -> Unmanaged<CGEvent> {
        // Convert suppressed rightMouseDragged into a harmless mouseMoved so macOS WindowServer
        // keeps moving the cursor smoothly from pixel 1 without sending a right-drag to apps.
        event.type = .mouseMoved
        event.setIntegerValueField(.mouseEventButtonNumber, value: 0)
        return Unmanaged.passUnretained(event)
    }

    private func setCursorLocked(_ locked: Bool) {
        if locked {
            let shouldDisassociate = lock.withLock { state -> Bool in
                guard !state.cursorLocked else { return false }
                state.cursorLocked = true
                return true
            }
            if shouldDisassociate {
                CGAssociateMouseAndMouseCursorPosition(0)
            }
        } else {
            let shouldReassociate = lock.withLock { state -> Bool in
                guard state.cursorLocked else { return false }
                state.cursorLocked = false
                return true
            }
            if shouldReassociate {
                CGAssociateMouseAndMouseCursorPosition(1)
            }
        }
    }

    private func unlockCursorSafety() {
        setCursorLocked(false)
    }

    private func replayMiddleClick(location: CGPoint, clickCount: Int64, flags: UInt64) {
        guard let down = CGEvent(
            mouseEventSource: privateEventSource,
            mouseType: .otherMouseDown,
            mouseCursorPosition: location,
            mouseButton: .center
        ),
        let up = CGEvent(
            mouseEventSource: privateEventSource,
            mouseType: .otherMouseUp,
            mouseCursorPosition: location,
            mouseButton: .center
        ) else {
            return
        }

        down.flags = CGEventFlags(rawValue: flags)
        up.flags = CGEventFlags(rawValue: flags)
        down.setIntegerValueField(.mouseEventClickState, value: clickCount)
        up.setIntegerValueField(.mouseEventClickState, value: clickCount)
        down.setIntegerValueField(.mouseEventButtonNumber, value: ScrollStateMachine.middleMouseButtonNumber)
        up.setIntegerValueField(.mouseEventButtonNumber, value: ScrollStateMachine.middleMouseButtonNumber)
        down.setIntegerValueField(.eventSourceUserData, value: Self.syntheticEventMarker)
        up.setIntegerValueField(.eventSourceUserData, value: Self.syntheticEventMarker)

        down.post(tap: .cgSessionEventTap)
        up.post(tap: .cgSessionEventTap)
    }

    private func replayRightClick(location: CGPoint, clickCount: Int64, flags: UInt64) {
        guard let down = CGEvent(
            mouseEventSource: privateEventSource,
            mouseType: .rightMouseDown,
            mouseCursorPosition: location,
            mouseButton: .right
        ),
        let up = CGEvent(
            mouseEventSource: privateEventSource,
            mouseType: .rightMouseUp,
            mouseCursorPosition: location,
            mouseButton: .right
        ) else {
            return
        }

        down.flags = CGEventFlags(rawValue: flags)
        up.flags = CGEventFlags(rawValue: flags)
        down.setIntegerValueField(.mouseEventClickState, value: clickCount)
        up.setIntegerValueField(.mouseEventClickState, value: clickCount)
        down.setIntegerValueField(.mouseEventButtonNumber, value: 1)
        up.setIntegerValueField(.mouseEventButtonNumber, value: 1)
        down.setIntegerValueField(.eventSourceUserData, value: Self.syntheticEventMarker)
        up.setIntegerValueField(.eventSourceUserData, value: Self.syntheticEventMarker)

        down.post(tap: .cgSessionEventTap)
        up.post(tap: .cgSessionEventTap)
    }

    private func postScroll(_ emission: ScrollEmission, at location: CGPoint) {
        let units: CGScrollEventUnit = emission.isPixelUnits ? .pixel : .line
        guard let scrollEvent = CGEvent(
            scrollWheelEvent2Source: privateEventSource,
            units: units,
            wheelCount: 2,
            wheel1: emission.deltaY,
            wheel2: emission.deltaX,
            wheel3: 0
        ) else {
            return
        }

        scrollEvent.setIntegerValueField(.eventSourceUserData, value: Self.syntheticEventMarker)
        scrollEvent.post(tap: .cgSessionEventTap)
    }

    private func reverseRegularMouseScrollIfNeeded(event: CGEvent, settings: ScrollSettingsSnapshot) {
        guard settings.isEnabled, settings.reverseMouseWheel else {
            return
        }

        let info = ScrollWheelEventInfo(
            isContinuous: event.getIntegerValueField(.scrollWheelEventIsContinuous) != 0,
            scrollPhase: event.getIntegerValueField(.scrollWheelEventScrollPhase),
            momentumPhase: event.getIntegerValueField(.scrollWheelEventMomentumPhase),
            deltaAxis1: event.getIntegerValueField(.scrollWheelEventDeltaAxis1),
            pointDeltaAxis1: event.getIntegerValueField(.scrollWheelEventPointDeltaAxis1),
            fixedPtDeltaAxis1: event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1),
            deltaAxis2: event.getIntegerValueField(.scrollWheelEventDeltaAxis2),
            pointDeltaAxis2: event.getIntegerValueField(.scrollWheelEventPointDeltaAxis2),
            fixedPtDeltaAxis2: event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2)
        )

        guard let reversed = WheelReverser.reversedDeltasIfApplicable(for: info, settings: settings) else {
            return
        }

        // Write integer line deltas BEFORE point/fixed-point deltas because CoreGraphics
        // recalculates point/fixed-point fields whenever DeltaAxis is mutated.
        if info.deltaAxis1 != 0 || info.pointDeltaAxis1 != 0 || info.fixedPtDeltaAxis1 != 0 {
            event.setIntegerValueField(.scrollWheelEventDeltaAxis1, value: reversed.deltaAxis1)
            event.setIntegerValueField(.scrollWheelEventPointDeltaAxis1, value: reversed.pointDeltaAxis1)
            event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1, value: reversed.fixedPtDeltaAxis1)
        }

        if info.deltaAxis2 != 0 || info.pointDeltaAxis2 != 0 || info.fixedPtDeltaAxis2 != 0 {
            event.setIntegerValueField(.scrollWheelEventDeltaAxis2, value: reversed.deltaAxis2)
            event.setIntegerValueField(.scrollWheelEventPointDeltaAxis2, value: reversed.pointDeltaAxis2)
            event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2, value: reversed.fixedPtDeltaAxis2)
        }
    }
}
