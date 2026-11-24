import AppKit
import CoreGraphics
import Foundation
import MouseHelperCore
import QuartzCore

enum TrailEvent: Sendable {
    case begin(quartzPoint: CGPoint, lockCursor: Bool)
    case move(quartzPoint: CGPoint, rawDeltaX: Double, rawDeltaY: Double, lockCursor: Bool, enableVertical: Bool)
    case end
}

@MainActor
final class TrailOverlayController: NSObject {
    private struct ScreenOverlay {
        let window: NSWindow
        let canvasView: TrailCanvasView
    }

    private var overlays: [ScreenOverlay] = []
    private var simulator = TrailSimulator()
    private var displayLink: CADisplayLink?
    private weak var displayLinkView: TrailCanvasView?
    private var isEnabled: Bool = true
    private var style: TrailStyle = .neonCyan
    private var screenObserver: NSObjectProtocol?

    init(isEnabled: Bool, style: TrailStyle) {
        self.isEnabled = isEnabled
        self.style = style
        super.init()

        syncOverlayWindowsToScreens()

        self.screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.syncOverlayWindowsToScreens()
            }
        }
    }

    deinit {
        if let observer = screenObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    func updateConfiguration(isEnabled: Bool, style: TrailStyle) {
        self.isEnabled = isEnabled
        self.style = style
        for overlay in overlays {
            overlay.canvasView.style = style
        }

        if !isEnabled {
            clearAndHide()
        }
    }

    func handle(_ event: TrailEvent) {
        guard isEnabled else { return }

        let now = CACurrentMediaTime()

        switch event {
        case .begin(let quartzPoint, _):
            syncOverlayWindowsToScreens()
            let cocoaPoint = Self.quartzToCocoa(quartzPoint)
            simulator.beginStroke(at: cocoaPoint, now: now)
            ensureAnimating(for: cocoaPoint)

        case .move(let quartzPoint, let rawDeltaX, let rawDeltaY, let lockCursor, let enableVertical):
            let cocoaPoint = Self.quartzToCocoa(quartzPoint)
            let activeScreenBounds = Self.screenBounds(containing: simulator.headPosition ?? cocoaPoint)
            simulator.advanceStroke(
                cocoaCursorPoint: cocoaPoint,
                rawDeltaX: rawDeltaX,
                rawDeltaY: rawDeltaY,
                lockCursor: lockCursor,
                enableVertical: enableVertical,
                screenBounds: activeScreenBounds,
                now: now
            )
            ensureAnimating(for: simulator.headPosition ?? cocoaPoint)

        case .end:
            simulator.endStroke()
            if simulator.hasVisibleContent {
                ensureAnimating(for: simulator.headPosition)
            } else {
                stopAndHide()
            }
        }
    }

    func clearAndHide() {
        simulator.clearAll()
        stopAndHide()
    }

    private func ensureAnimating(for cocoaPoint: CGPoint? = nil) {
        if overlays.isEmpty {
            syncOverlayWindowsToScreens()
        }
        guard !overlays.isEmpty else { return }

        for overlay in overlays where !overlay.window.isVisible {
            overlay.window.orderFrontRegardless()
        }

        let targetOverlay = cocoaPoint.flatMap { point in
            overlays.first { $0.window.frame.contains(point) }
        } ?? overlays[0]

        if displayLink == nil || displayLinkView !== targetOverlay.canvasView {
            displayLink?.invalidate()
            let link = targetOverlay.canvasView.displayLink(target: self, selector: #selector(onDisplayLink(_:)))
            link.add(to: .main, forMode: .common)
            displayLink = link
            displayLinkView = targetOverlay.canvasView
        }
        displayLink?.isPaused = false
    }

    private func stopAndHide() {
        displayLink?.isPaused = true
        for overlay in overlays {
            overlay.canvasView.clear()
            if overlay.window.isVisible {
                overlay.window.orderOut(nil)
            }
        }
    }

    @objc private func onDisplayLink(_ sender: CADisplayLink) {
        let now = CACurrentMediaTime()
        let keepRunning = simulator.step(now: now)
        if keepRunning {
            pushRenderState(now: now)
        } else {
            stopAndHide()
        }
    }

    private func pushRenderState(now: TimeInterval) {
        let head = simulator.isActive ? simulator.headPosition : nil
        for overlay in overlays {
            overlay.canvasView.update(
                points: simulator.points,
                particles: simulator.particles,
                headPosition: head,
                headSpeed: simulator.headSpeed,
                windowOrigin: overlay.window.frame.origin,
                pointLifetime: simulator.pointLifetime,
                style: style,
                now: now
            )
        }
    }

    private func syncOverlayWindowsToScreens() {
        let targetFrames = Self.screenFrames()
        let currentFrames = overlays.map(\.window.frame)
        guard currentFrames != targetFrames else { return }

        let wasVisible = overlays.contains { $0.window.isVisible }

        displayLink?.invalidate()
        displayLink = nil
        displayLinkView = nil

        for overlay in overlays {
            overlay.canvasView.clear()
            overlay.window.orderOut(nil)
            overlay.window.close()
        }

        overlays = targetFrames.map { makeOverlay(for: $0) }

        if wasVisible && simulator.hasVisibleContent && isEnabled {
            ensureAnimating(for: simulator.headPosition)
        }
    }

    private func makeOverlay(for frame: NSRect) -> ScreenOverlay {
        let window = NSWindow(
            contentRect: frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.setFrame(frame, display: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.level = .screenSaver
        window.collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .stationary,
            .ignoresCycle
        ]
        window.isReleasedWhenClosed = false

        let view = TrailCanvasView(frame: NSRect(origin: .zero, size: frame.size))
        view.style = style
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.clear.cgColor
        view.layer?.drawsAsynchronously = true
        window.contentView = view

        return ScreenOverlay(window: window, canvasView: view)
    }

    private static func screenFrames() -> [NSRect] {
        let screens = NSScreen.screens
        guard !screens.isEmpty else {
            return [NSRect(x: 0, y: 0, width: 1440, height: 900)]
        }
        return screens.map(\.frame)
    }

    private static func combinedScreenFrame() -> NSRect {
        let screens = NSScreen.screens
        guard !screens.isEmpty else {
            return NSRect(x: 0, y: 0, width: 1440, height: 900)
        }
        return screens.reduce(NSRect.null) { $0.union($1.frame) }
    }

    private static func screenBounds(containing cocoaPoint: CGPoint) -> CGRect {
        for screen in NSScreen.screens where screen.frame.contains(cocoaPoint) {
            return screen.frame
        }
        return NSScreen.main?.frame ?? combinedScreenFrame()
    }

    private static func quartzToCocoa(_ quartzPoint: CGPoint) -> CGPoint {
        let primaryHeight = CGDisplayBounds(CGMainDisplayID()).height
        return CGPoint(x: quartzPoint.x, y: primaryHeight - quartzPoint.y)
    }
}

private final class TrailCanvasView: NSView {
    private var points: [TrailPoint] = []
    private var particles: [TrailParticle] = []
    private var headPosition: CGPoint?
    private var headSpeed: Double = 0
    private var windowOrigin: CGPoint = .zero
    private var pointLifetime: TimeInterval = TrailSimulator.defaultPointLifetime
    private var renderTime: TimeInterval = 0
    private var previousDirtyRect: NSRect = .null
    var style: TrailStyle = .neonCyan

    override var isOpaque: Bool { false }

    func update(
        points: [TrailPoint],
        particles: [TrailParticle],
        headPosition: CGPoint?,
        headSpeed: Double,
        windowOrigin: CGPoint,
        pointLifetime: TimeInterval,
        style: TrailStyle,
        now: TimeInterval
    ) {
        self.points = points
        self.particles = particles
        self.headPosition = headPosition
        self.headSpeed = headSpeed
        self.windowOrigin = windowOrigin
        self.pointLifetime = pointLifetime
        self.style = style
        self.renderTime = now

        let rawCurrent = computeContentBounds()
        let currentRect: NSRect
        if rawCurrent.isNull {
            currentRect = .null
        } else {
            let intersected = rawCurrent.intersection(bounds)
            currentRect = intersected.isEmpty ? .null : intersected
        }
        let unionRect: NSRect
        if previousDirtyRect.isNull {
            unionRect = currentRect
        } else if currentRect.isNull {
            unionRect = previousDirtyRect
        } else {
            unionRect = previousDirtyRect.union(currentRect)
        }
        previousDirtyRect = currentRect

        if !unionRect.isNull && !unionRect.isEmpty {
            let clamped = unionRect.intersection(bounds)
            if !clamped.isEmpty {
                setNeedsDisplay(clamped)
            }
        }
    }

    func clear() {
        let oldRect = previousDirtyRect
        points.removeAll(keepingCapacity: true)
        particles.removeAll(keepingCapacity: true)
        headPosition = nil
        previousDirtyRect = .null
        if !oldRect.isNull && !oldRect.isEmpty {
            let clamped = oldRect.intersection(bounds)
            if !clamped.isEmpty {
                setNeedsDisplay(clamped)
            }
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.clear(dirtyRect)
        guard !points.isEmpty || !particles.isEmpty || headPosition != nil else { return }

        ctx.setShouldAntialias(true)
        ctx.setAllowsAntialiasing(true)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)

        drawRibbon(in: ctx)
        drawParticles(in: ctx)
        if let head = headPosition {
            drawCometHead(at: toLocal(head), in: ctx)
        }
    }

    private func computeContentBounds() -> NSRect {
        var minX = CGFloat.greatestFiniteMagnitude
        var minY = CGFloat.greatestFiniteMagnitude
        var maxX = -CGFloat.greatestFiniteMagnitude
        var maxY = -CGFloat.greatestFiniteMagnitude
        var hasAny = false

        func include(_ cocoaPoint: CGPoint) {
            let p = toLocal(cocoaPoint)
            minX = min(minX, p.x)
            minY = min(minY, p.y)
            maxX = max(maxX, p.x)
            maxY = max(maxY, p.y)
            hasAny = true
        }

        for pt in points {
            include(pt.position)
        }
        for p in particles {
            include(p.position)
        }
        if let head = headPosition {
            include(head)
        }

        guard hasAny else { return .null }
        let pad: CGFloat = 44
        return NSRect(
            x: floor(minX - pad),
            y: floor(minY - pad),
            width: ceil((maxX - minX) + pad * 2),
            height: ceil((maxY - minY) + pad * 2)
        )
    }

    private func toLocal(_ cocoaPoint: CGPoint) -> CGPoint {
        CGPoint(x: cocoaPoint.x - windowOrigin.x, y: cocoaPoint.y - windowOrigin.y)
    }

    private func drawRibbon(in ctx: CGContext) {
        let count = points.count
        guard count >= 2 else { return }

        let localPts = points.map { toLocal($0.position) }
        let lives = points.map { pt -> CGFloat in
            let age = max(0, renderTime - pt.timestamp)
            return CGFloat(max(0, min(1, 1.0 - age / pointLifetime)))
        }

        // Build smooth quadratic segments using midpoints so fast gestures curve organically.
        for i in 1..<count {
            let pPrev = localPts[i - 1]
            let pCurr = localPts[i]
            let segStart: CGPoint
            let segEnd: CGPoint
            let control: CGPoint

            if i == 1 {
                segStart = pPrev
                segEnd = (count > 2) ? midpoint(pPrev, pCurr) : pCurr
                control = midpoint(segStart, segEnd)
            } else if i == count - 1 {
                segStart = midpoint(localPts[i - 2], pPrev)
                segEnd = pCurr
                control = pPrev
            } else {
                segStart = midpoint(localPts[i - 2], pPrev)
                segEnd = midpoint(pPrev, pCurr)
                control = pPrev
            }

            let life = (lives[i - 1] + lives[i]) * 0.5
            guard life > 0.015 else { continue }

            let t = CGFloat(i) / CGFloat(max(1, count - 1)) // 0 = tail, 1 = head
            let easedLife = life * life
            let taper = pow(life, 0.85) * (0.28 + 0.72 * t)
            let speedBoost = CGFloat(min(1.35, 1.0 + points[i].speed * 0.012))

            let baseColor = paletteColor(t: t, style: style)
            let auraColor = paletteAuraColor(t: t, style: style)

            // Pass 1: Wide outer neon bloom aura
            ctx.beginPath()
            ctx.move(to: segStart)
            ctx.addQuadCurve(to: segEnd, control: control)
            ctx.setStrokeColor(auraColor.withAlphaComponent(0.24 * easedLife).cgColor)
            ctx.setLineWidth(max(1.5, 22.0 * taper * speedBoost))
            ctx.strokePath()

            // Pass 2: Mid saturated energy body
            ctx.beginPath()
            ctx.move(to: segStart)
            ctx.addQuadCurve(to: segEnd, control: control)
            ctx.setStrokeColor(baseColor.withAlphaComponent(0.78 * pow(life, 1.45)).cgColor)
            ctx.setLineWidth(max(1.0, 9.5 * taper * speedBoost))
            ctx.strokePath()

            // Pass 3: Razor-bright luminous plasma core
            ctx.beginPath()
            ctx.move(to: segStart)
            ctx.addQuadCurve(to: segEnd, control: control)
            let coreColor = baseColor.blended(withFraction: 0.76, of: .white) ?? .white
            ctx.setStrokeColor(coreColor.withAlphaComponent(0.95 * pow(life, 1.2)).cgColor)
            ctx.setLineWidth(max(0.7, 3.4 * taper))
            ctx.strokePath()
        }
    }

    private func drawParticles(in ctx: CGContext) {
        for p in particles {
            let age = renderTime - p.bornAt
            guard age >= 0, age < p.lifetime else { continue }
            let life = CGFloat(1.0 - age / p.lifetime)
            let eased = life * life
            let center = toLocal(p.position)
            let radius = p.size * (0.35 + 0.65 * life)

            let color = paletteColor(t: CGFloat(p.colorPhase), style: style)

            // Outer soft spark glow
            let glowR = radius * 2.6
            ctx.setFillColor(color.withAlphaComponent(0.32 * eased).cgColor)
            ctx.fillEllipse(in: CGRect(x: center.x - glowR, y: center.y - glowR, width: glowR * 2, height: glowR * 2))

            // Bright crisp spark center
            let coreColor = color.blended(withFraction: 0.72, of: .white) ?? .white
            ctx.setFillColor(coreColor.withAlphaComponent(0.95 * life).cgColor)
            ctx.fillEllipse(in: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
        }
    }

    private func drawCometHead(at center: CGPoint, in ctx: CGContext) {
        let energy = CGFloat(min(1.0, 0.45 + headSpeed * 0.03))
        let outerRadius = 15.0 + energy * 11.0
        let headColor = paletteColor(t: 1.0, style: style)
        let coreColor = headColor.blended(withFraction: 0.82, of: .white) ?? .white

        let colors = [
            coreColor.withAlphaComponent(0.92).cgColor,
            headColor.withAlphaComponent(0.45 * energy).cgColor,
            headColor.withAlphaComponent(0.0).cgColor
        ] as CFArray

        if let gradient = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: colors,
            locations: [0.0, 0.38, 1.0]
        ) {
            ctx.drawRadialGradient(
                gradient,
                startCenter: center,
                startRadius: 0,
                endCenter: center,
                endRadius: outerRadius,
                options: []
            )
        }
    }

    private func midpoint(_ a: CGPoint, _ b: CGPoint) -> CGPoint {
        CGPoint(x: (a.x + b.x) * 0.5, y: (a.y + b.y) * 0.5)
    }

    private func paletteColor(t: CGFloat, style: TrailStyle) -> NSColor {
        let clamped = max(0, min(1, t))
        switch style {
        case .neonCyan:
            // Deep indigo -> electric blue -> bright sky cyan
            return interpolateRGB(
                stops: [
                    (0.0, (0.48, 0.36, 0.98)),
                    (0.5, (0.16, 0.52, 1.00)),
                    (1.0, (0.22, 0.86, 0.98))
                ],
                t: clamped
            )
        case .cyberMagenta:
            // Neon violet -> hot magenta -> luminous rose-cyan
            return interpolateRGB(
                stops: [
                    (0.0, (0.45, 0.22, 0.96)),
                    (0.55, (0.96, 0.24, 0.62)),
                    (1.0, (0.20, 0.90, 0.98))
                ],
                t: clamped
            )
        case .aurora:
            // Shimmering aurora spectrum shifting gently over time
            let timeOffset = CGFloat((renderTime * 0.35).truncatingRemainder(dividingBy: 1.0))
            let hue = (0.45 + clamped * 0.42 + timeOffset).truncatingRemainder(dividingBy: 1.0)
            return NSColor(calibratedHue: hue, saturation: 0.85, brightness: 0.98, alpha: 1.0)
        case .solarGold:
            // Ember crimson -> vivid orange -> radiant gold
            return interpolateRGB(
                stops: [
                    (0.0, (0.94, 0.24, 0.22)),
                    (0.55, (0.99, 0.52, 0.12)),
                    (1.0, (1.00, 0.86, 0.28))
                ],
                t: clamped
            )
        }
    }

    private func paletteAuraColor(t: CGFloat, style: TrailStyle) -> NSColor {
        switch style {
        case .neonCyan:
            return paletteColor(t: t * 0.8, style: .neonCyan)
        case .cyberMagenta:
            return paletteColor(t: max(0, t - 0.15), style: .cyberMagenta)
        case .aurora:
            return paletteColor(t: t, style: .aurora)
        case .solarGold:
            return paletteColor(t: t * 0.75, style: .solarGold)
        }
    }

    private func interpolateRGB(
        stops: [(CGFloat, (CGFloat, CGFloat, CGFloat))],
        t: CGFloat
    ) -> NSColor {
        guard let first = stops.first, let last = stops.last else { return .white }
        if t <= first.0 {
            return NSColor(calibratedRed: first.1.0, green: first.1.1, blue: first.1.2, alpha: 1.0)
        }
        if t >= last.0 {
            return NSColor(calibratedRed: last.1.0, green: last.1.1, blue: last.1.2, alpha: 1.0)
        }
        for i in 0..<(stops.count - 1) {
            let a = stops[i]
            let b = stops[i + 1]
            if t >= a.0 && t <= b.0 {
                let frac = (t - a.0) / max(0.0001, b.0 - a.0)
                let r = a.1.0 + (b.1.0 - a.1.0) * frac
                let g = a.1.1 + (b.1.1 - a.1.1) * frac
                let bl = a.1.2 + (b.1.2 - a.1.2) * frac
                return NSColor(calibratedRed: r, green: g, blue: bl, alpha: 1.0)
            }
        }
        return NSColor(calibratedRed: last.1.0, green: last.1.1, blue: last.1.2, alpha: 1.0)
    }
}
