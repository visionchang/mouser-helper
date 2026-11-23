import AppKit
import MouseHelperCore
import SwiftUI

enum GestureHUDEvent: Sendable {
    case update(match: GestureMatch, quartzPoint: CGPoint)
    case hide
}

@MainActor
final class GestureHUDController {
    private let panel: NSPanel
    private let model = GestureHUDModel()
    private var isEnabled: Bool = true
    private var hideWorkItem: DispatchWorkItem?

    init(isEnabled: Bool) {
        self.isEnabled = isEnabled

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 260, height: 54),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.level = .screenSaver
        panel.collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .stationary,
            .ignoresCycle
        ]
        panel.isReleasedWhenClosed = false
        panel.alphaValue = 0

        let hosting = NSHostingView(rootView: GestureHUDView(model: model))
        hosting.wantsLayer = true
        hosting.layer?.backgroundColor = NSColor.clear.cgColor
        panel.contentView = hosting

        self.panel = panel
    }

    func updateEnabled(_ enabled: Bool) {
        isEnabled = enabled
        if !enabled {
            hideImmediately()
        }
    }

    func handle(_ event: GestureHUDEvent) {
        guard isEnabled else { return }

        switch event {
        case .update(let match, let quartzPoint):
            hideWorkItem?.cancel()
            hideWorkItem = nil

            // Don't pop HUD before a direction is recognized unless already showing.
            if case .pending = match, !panel.isVisible {
                return
            }

            model.match = match
            positionPanel(forQuartzPoint: quartzPoint)

            if !panel.isVisible {
                panel.alphaValue = 0
                panel.orderFrontRegardless()
            }
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.12
                panel.animator().alphaValue = 1.0
            }

        case .hide:
            guard panel.isVisible else { return }
            hideWorkItem?.cancel()
            let work = DispatchWorkItem { [weak self] in
                guard let self else { return }
                NSAnimationContext.runAnimationGroup({ ctx in
                    ctx.duration = 0.16
                    self.panel.animator().alphaValue = 0
                }, completionHandler: { [weak self] in
                    Task { @MainActor [weak self] in
                        if self?.panel.alphaValue == 0 {
                            self?.panel.orderOut(nil)
                        }
                    }
                })
            }
            hideWorkItem = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.06, execute: work)
        }
    }

    func hideImmediately() {
        hideWorkItem?.cancel()
        hideWorkItem = nil
        panel.alphaValue = 0
        if panel.isVisible {
            panel.orderOut(nil)
        }
    }

    private func positionPanel(forQuartzPoint quartzPoint: CGPoint) {
        let primaryHeight = CGDisplayBounds(CGMainDisplayID()).height
        let cocoaPoint = CGPoint(x: quartzPoint.x, y: primaryHeight - quartzPoint.y)

        let screen = NSScreen.screens.first(where: { $0.frame.contains(cocoaPoint) })
            ?? NSScreen.main
            ?? NSScreen.screens.first
        guard let screen else { return }

        let fittingSize = panel.contentView?.fittingSize ?? NSSize(width: 240, height: 50)
        let width = max(170, min(320, fittingSize.width))
        let height = max(46, fittingSize.height)

        let visible = screen.visibleFrame
        let x = visible.midX - width / 2.0
        let y = visible.minY + max(88, visible.height * 0.14)
        panel.setFrame(NSRect(x: x, y: y, width: width, height: height), display: true)
    }
}

@MainActor
private final class GestureHUDModel: ObservableObject {
    @Published var match: GestureMatch = .pending
}

private struct GestureHUDView: View {
    @ObservedObject var model: GestureHUDModel

    var body: some View {
        HStack(spacing: 10) {
            switch model.match {
            case .pending:
                Image(systemName: "hand.draw")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text("继续滑动…")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)

            case .matched(let pattern, let action):
                Text(pattern.symbol)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Color.accentColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        Capsule()
                            .fill(Color.accentColor.opacity(0.18))
                    )

                Text(action.displayName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary)

                Text(action.shortcutLabel)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(Color.primary.opacity(0.08))
                    )

            case .disabled(let pattern):
                Text(pattern.symbol)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.secondary)
                Text("该手势已关闭")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)

            case .cancelled(let arrows):
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text(arrows.isEmpty ? "取消手势" : "\(arrows) · 取消手势")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            HUDGlassBackground()
        )
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .strokeBorder(Color.white.opacity(0.22), lineWidth: 1)
        )
        .fixedSize()
    }
}

private struct HUDGlassBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
