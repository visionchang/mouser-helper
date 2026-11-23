import CoreGraphics
import Foundation
import MouseHelperCore
import QuartzCore
import os

final class SmoothScrollDriver: @unchecked Sendable {
    private struct State {
        var pump = SmoothScrollPump()
        var timer: DispatchSourceTimer?
        var lastTickTime: TimeInterval?
    }

    private let syntheticEventMarker: Int64
    private let privateEventSource = CGEventSource(stateID: .privateState)
    private let timerQueue = DispatchQueue(
        label: "com.mousehelper.smoothscroll",
        qos: .userInteractive
    )
    private let lock = OSAllocatedUnfairLock(initialState: State())

    init(syntheticEventMarker: Int64) {
        self.syntheticEventMarker = syntheticEventMarker
    }

    deinit {
        cancelImmediately()
    }

    func beginGesture(at _: CGPoint) {
        lock.withLock { state in
            state.pump.beginGesture()
            ensureTimerLocked(&state)
        }
    }

    func enqueue(deltaX: Double, deltaY: Double, at _: CGPoint) {
        lock.withLock { state in
            state.pump.enqueue(deltaX: deltaX, deltaY: deltaY)
            ensureTimerLocked(&state)
        }
    }

    func endGesture(at _: CGPoint) {
        lock.withLock { state in
            state.pump.endGesture()
            if state.pump.isActive {
                ensureTimerLocked(&state)
            } else {
                stopTimerLocked(&state)
            }
        }
    }

    func cancelImmediately() {
        lock.withLock { state in
            state.pump.cancelImmediately()
            stopTimerLocked(&state)
        }
    }

    private func ensureTimerLocked(_ state: inout State) {
        guard state.timer == nil else { return }

        let timer = DispatchSource.makeTimerSource(flags: .strict, queue: timerQueue)
        timer.schedule(
            deadline: .now(),
            repeating: .microseconds(8333), // 120Hz steady cadence
            leeway: .microseconds(500)
        )
        state.lastTickTime = CACurrentMediaTime()
        timer.setEventHandler { [weak self] in
            self?.tick()
        }
        state.timer = timer
        timer.resume()
    }

    private func stopTimerLocked(_ state: inout State) {
        if let timer = state.timer {
            timer.setEventHandler {}
            timer.cancel()
            state.timer = nil
        }
        state.lastTickTime = nil
    }

    private func tick() {
        let now = CACurrentMediaTime()
        let delta: SmoothScrollDelta? = lock.withLock { state in
            let dt: TimeInterval
            if let last = state.lastTickTime {
                dt = now - last
            } else {
                dt = 1.0 / 120.0
            }
            state.lastTickTime = now

            let emitted = state.pump.step(dt: dt)
            if !state.pump.isActive {
                stopTimerLocked(&state)
            }
            return emitted
        }

        if let delta {
            postPixelScroll(deltaX: delta.deltaX, deltaY: delta.deltaY)
        }
    }

    private func postPixelScroll(deltaX: Int32, deltaY: Int32) {
        guard let scrollEvent = CGEvent(
            scrollWheelEvent2Source: privateEventSource,
            units: .pixel,
            wheelCount: 2,
            wheel1: deltaY,
            wheel2: deltaX,
            wheel3: 0
        ) else {
            return
        }

        scrollEvent.setIntegerValueField(.eventSourceUserData, value: syntheticEventMarker)
        scrollEvent.post(tap: .cgSessionEventTap)
    }
}
