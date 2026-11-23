import Foundation

public struct SmoothScrollDelta: Equatable, Sendable {
    public let deltaX: Int32
    public let deltaY: Int32

    public init(deltaX: Int32, deltaY: Int32) {
        self.deltaX = deltaX
        self.deltaY = deltaY
    }
}

/// High-frequency smooth scroll accumulator that converts uneven HID mouse polling
/// deltas (e.g. 125Hz discrete reports) into evenly-paced 120Hz pixel scroll frames.
public struct SmoothScrollPump: Sendable {
    public private(set) var pendingX: Double = 0
    public private(set) var pendingY: Double = 0
    private var remainderX: Double = 0
    private var remainderY: Double = 0
    public private(set) var isDragging: Bool = false

    public init() {}

    public var isActive: Bool {
        isDragging || abs(pendingX) >= 0.05 || abs(pendingY) >= 0.05
    }

    public mutating func beginGesture() {
        isDragging = true
    }

    public mutating func enqueue(deltaX: Double, deltaY: Double) {
        pendingX += deltaX
        pendingY += deltaY
    }

    public mutating func endGesture() {
        isDragging = false
    }

    public mutating func cancelImmediately() {
        pendingX = 0
        pendingY = 0
        remainderX = 0
        remainderY = 0
        isDragging = false
    }

    public mutating func step(dt: TimeInterval) -> SmoothScrollDelta? {
        let clampedDt = max(1.0 / 240.0, min(0.05, dt))
        // Crisp, responsive tracking while dragging; short smooth glide-out on release.
        let stiffness = isDragging ? 38.0 : 26.0
        let alpha = 1.0 - exp(-clampedDt * stiffness)

        var stepX = pendingX * alpha
        var stepY = pendingY * alpha

        if abs(pendingX) < 0.35 {
            stepX = pendingX
        }
        if abs(pendingY) < 0.35 {
            stepY = pendingY
        }

        pendingX -= stepX
        pendingY -= stepY

        remainderX += stepX
        remainderY += stepY

        let emitX = Int32(remainderX.rounded(.towardZero))
        let emitY = Int32(remainderY.rounded(.towardZero))

        remainderX -= Double(emitX)
        remainderY -= Double(emitY)

        if !isDragging && abs(pendingX) < 0.05 && abs(pendingY) < 0.05 {
            pendingX = 0
            pendingY = 0
            remainderX = 0
            remainderY = 0
        }

        if emitX == 0 && emitY == 0 {
            return nil
        }

        return SmoothScrollDelta(deltaX: emitX, deltaY: emitY)
    }
}
