import CoreGraphics
import Foundation

public enum TrailStyle: String, CaseIterable, Codable, Sendable {
    case neonCyan
    case cyberMagenta
    case aurora
    case solarGold

    public var displayName: String {
        switch self {
        case .neonCyan: return "霓虹青蓝"
        case .cyberMagenta: return "赛博霓虹"
        case .aurora: return "极光流彩"
        case .solarGold: return "烈焰流金"
        }
    }
}

public struct TrailPoint: Equatable, Sendable {
    public let position: CGPoint
    public let timestamp: TimeInterval
    public let speed: Double

    public init(position: CGPoint, timestamp: TimeInterval, speed: Double) {
        self.position = position
        self.timestamp = timestamp
        self.speed = speed
    }
}

public struct TrailParticle: Equatable, Sendable {
    public var position: CGPoint
    public var velocity: CGVector
    public let bornAt: TimeInterval
    public let lifetime: TimeInterval
    public let size: CGFloat
    public let colorPhase: Double

    public init(
        position: CGPoint,
        velocity: CGVector,
        bornAt: TimeInterval,
        lifetime: TimeInterval,
        size: CGFloat,
        colorPhase: Double
    ) {
        self.position = position
        self.velocity = velocity
        self.bornAt = bornAt
        self.lifetime = lifetime
        self.size = size
        self.colorPhase = colorPhase
    }
}

/// Pure, testable trail & spark particle simulator for the right-drag horizontal scroll glow.
/// All points and particles automatically decay and disappear within ~0.45 seconds.
public struct TrailSimulator: Sendable {
    public static let defaultPointLifetime: TimeInterval = 0.42
    public static let maxPoints = 96
    public static let maxParticles = 72

    public let pointLifetime: TimeInterval
    public private(set) var points: [TrailPoint] = []
    public private(set) var particles: [TrailParticle] = []
    public private(set) var isActive: Bool = false
    public private(set) var headPosition: CGPoint?
    public private(set) var headSpeed: Double = 0

    private var lastStepTime: TimeInterval?
    private var rngState: UInt64 = 0x5EED_CAFE_1234_5678

    public init(pointLifetime: TimeInterval = defaultPointLifetime) {
        self.pointLifetime = pointLifetime
    }

    public var hasVisibleContent: Bool {
        !points.isEmpty || !particles.isEmpty || isActive
    }

    public mutating func beginStroke(at cocoaPoint: CGPoint, now: TimeInterval) {
        // Clear previous stroke's ribbon points so a new drag starts cleanly without jumping across screen,
        // while keeping any lingering fading particles from the prior swipe!
        points.removeAll(keepingCapacity: true)
        isActive = true
        headPosition = cocoaPoint
        headSpeed = 0
        lastStepTime = now
        points.append(TrailPoint(position: cocoaPoint, timestamp: now, speed: 0))
    }

    public mutating func advanceStroke(
        cocoaCursorPoint: CGPoint,
        rawDeltaX: Double,
        rawDeltaY: Double,
        lockCursor: Bool,
        enableVertical: Bool,
        screenBounds: CGRect,
        now: TimeInterval
    ) {
        if !isActive {
            beginStroke(at: cocoaCursorPoint, now: now)
        }

        let prev = headPosition ?? cocoaCursorPoint
        let nextPoint: CGPoint

        if lockCursor {
            // Hardware rawDeltaY is positive downward; Cocoa Y is positive upward.
            let dy = enableVertical ? -rawDeltaY : (-rawDeltaY * 0.14)
            var candidate = CGPoint(x: prev.x + CGFloat(rawDeltaX), y: prev.y + CGFloat(dy))
            if !screenBounds.isNull && !screenBounds.isEmpty {
                let insetBounds = screenBounds.insetBy(dx: 16, dy: 16)
                if !insetBounds.isEmpty {
                    candidate.x = min(max(candidate.x, insetBounds.minX), insetBounds.maxX)
                    candidate.y = min(max(candidate.y, insetBounds.minY), insetBounds.maxY)
                }
            }
            nextPoint = candidate
        } else {
            nextPoint = cocoaCursorPoint
        }

        let moveDX = Double(nextPoint.x - prev.x)
        let moveDY = Double(nextPoint.y - prev.y)
        let visualDist = hypot(moveDX, moveDY)
        let rawDist = hypot(rawDeltaX, enableVertical ? rawDeltaY : rawDeltaY * 0.14)
        let effectiveSpeed = max(visualDist, rawDist)

        headPosition = nextPoint
        headSpeed = headSpeed * 0.55 + effectiveSpeed * 0.45

        let lastRecorded = points.last?.position
        let distFromLast = lastRecorded.map { hypot(Double(nextPoint.x - $0.x), Double(nextPoint.y - $0.y)) } ?? .infinity

        if distFromLast >= 2.5 {
            points.append(TrailPoint(position: nextPoint, timestamp: now, speed: effectiveSpeed))
            if points.count > Self.maxPoints {
                points.removeFirst(points.count - Self.maxPoints)
            }
        } else if !points.isEmpty {
            // Refresh head timestamp gently if pinned at screen edge while still sliding
            if rawDist >= 2.0 {
                points[points.count - 1] = TrailPoint(position: nextPoint, timestamp: now, speed: effectiveSpeed)
            }
        }

        // Spawn shimmering kinetic sparks proportional to slide speed
        if effectiveSpeed >= 4.0 {
            let dirX: Double
            let dirY: Double
            if visualDist > 0.5 {
                dirX = moveDX / visualDist
                dirY = moveDY / visualDist
            } else if rawDist > 0.5 {
                dirX = rawDeltaX / rawDist
                dirY = (enableVertical ? -rawDeltaY : 0) / rawDist
            } else {
                dirX = 1
                dirY = 0
            }

            let count = effectiveSpeed > 22 ? 3 : (effectiveSpeed > 11 ? 2 : 1)
            for _ in 0..<count {
                spawnSpark(at: nextPoint, dirX: dirX, dirY: dirY, speed: effectiveSpeed, now: now)
            }
        }
    }

    public mutating func endStroke() {
        isActive = false
        headSpeed = 0
    }

    public mutating func clearAll() {
        isActive = false
        headPosition = nil
        headSpeed = 0
        points.removeAll()
        particles.removeAll()
        lastStepTime = nil
    }

    @discardableResult
    public mutating func step(now: TimeInterval) -> Bool {
        let dt: TimeInterval
        if let last = lastStepTime {
            dt = max(0, min(0.05, now - last))
        } else {
            dt = 1.0 / 60.0
        }
        lastStepTime = now

        // Expire old trail points so the ribbon continuously dissolves from the tail
        let cutoff = now - pointLifetime
        if let firstValidIndex = points.firstIndex(where: { $0.timestamp > cutoff }) {
            if firstValidIndex > 0 {
                points.removeFirst(firstValidIndex)
            }
        } else {
            points.removeAll(keepingCapacity: true)
        }

        // Decay head speed smoothly when holding still
        if !isActive {
            headSpeed *= pow(0.01, dt)
        } else {
            headSpeed *= pow(0.15, dt)
        }

        // Update particles with smooth aerodynamic drag and remove expired ones
        let drag = CGFloat(pow(0.05, dt))
        let dtCG = CGFloat(dt)
        var writeIdx = 0
        for readIdx in 0..<particles.count {
            var p = particles[readIdx]
            if now - p.bornAt >= p.lifetime {
                continue
            }
            p.position.x += p.velocity.dx * dtCG
            p.position.y += p.velocity.dy * dtCG
            p.velocity.dx *= drag
            p.velocity.dy *= drag
            particles[writeIdx] = p
            writeIdx += 1
        }
        if writeIdx < particles.count {
            particles.removeSubrange(writeIdx..<particles.count)
        }

        return hasVisibleContent
    }

    private mutating func spawnSpark(
        at origin: CGPoint,
        dirX: Double,
        dirY: Double,
        speed: Double,
        now: TimeInterval
    ) {
        if particles.count >= Self.maxParticles {
            particles.removeFirst()
        }

        let perpX = -dirY
        let perpY = dirX

        let spread = (nextUnitRandom() - 0.5) * 2.0
        let jitterOffset = (nextUnitRandom() - 0.5) * 8.0
        let backward = 25.0 + nextUnitRandom() * min(160.0, speed * 5.5)
        let lateral = spread * (35.0 + min(130.0, speed * 3.8))

        let spawnPos = CGPoint(
            x: origin.x + CGFloat(perpX * jitterOffset),
            y: origin.y + CGFloat(perpY * jitterOffset)
        )
        let vel = CGVector(
            dx: CGFloat(-dirX * backward + perpX * lateral),
            dy: CGFloat(-dirY * backward + perpY * lateral)
        )

        let lifetime = 0.24 + nextUnitRandom() * 0.28
        let size = CGFloat(2.0 + nextUnitRandom() * 3.4)
        let phase = nextUnitRandom()

        particles.append(
            TrailParticle(
                position: spawnPos,
                velocity: vel,
                bornAt: now,
                lifetime: lifetime,
                size: size,
                colorPhase: phase
            )
        )
    }

    private mutating func nextUnitRandom() -> Double {
        // Fast deterministic SplitMix64 PRNG (zero allocation, Sendable, deterministic for tests)
        rngState &+= 0x9E37_79B9_7F4A_7C15
        var z = rngState
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        z = z ^ (z >> 31)
        return Double(z >> 11) * (1.0 / Double(1 << 53))
    }
}
