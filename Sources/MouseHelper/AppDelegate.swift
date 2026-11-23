import AppKit
import Combine
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store = SettingsStore()
    private var engine: ScrollEngine!
    private var trailOverlay: TrailOverlayController!
    private var gestureHUD: GestureHUDController!
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var permissionTimer: Timer?
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        trailOverlay = TrailOverlayController(
            isEnabled: store.isEnabled && store.gesturesEnabled && store.enableTrail,
            style: store.trailStyle
        )
        gestureHUD = GestureHUDController(
            isEnabled: store.isEnabled && store.gesturesEnabled && store.showGestureHUD
        )

        engine = ScrollEngine(
            initialSettings: store.snapshot,
            onStatusChange: { [weak self] isRunning in
                Task { @MainActor [weak self] in
                    self?.store.isTapRunning = isRunning
                }
            },
            onTrailEvent: { [weak self] trailEvent in
                DispatchQueue.main.async {
                    MainActor.assumeIsolated {
                        self?.trailOverlay?.handle(trailEvent)
                    }
                }
            },
            onGestureHUD: { [weak self] hudEvent in
                DispatchQueue.main.async {
                    MainActor.assumeIsolated {
                        self?.gestureHUD?.handle(hudEvent)
                    }
                }
            }
        )

        store.onSnapshotChanged = { [weak self] snapshot in
            self?.engine.updateSettings(snapshot)
            self?.trailOverlay.updateConfiguration(
                isEnabled: snapshot.isEnabled && snapshot.gestures.isEnabled && snapshot.enableTrail,
                style: snapshot.trailStyle
            )
            self?.gestureHUD.updateEnabled(
                snapshot.isEnabled && snapshot.gestures.isEnabled && snapshot.gestures.showHUD
            )
        }

        setupStatusItem()
        setupPopover()
        bindStatusIconUpdates()

        refreshPermissionAndEngine(promptIfNeeded: false)
        startPermissionMonitor()

        // If permission is not granted yet, show the popover right away so the user can authorize in 1 click.
        if !store.hasAccessibilityPermission {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
                self?.showPopover()
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        permissionTimer?.invalidate()
        permissionTimer = nil
        engine?.stop()
        trailOverlay?.clearAndHide()
        gestureHUD?.hideImmediately()
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        guard let button = statusItem.button else { return }
        button.target = self
        button.action = #selector(togglePopover(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        updateStatusIcon()
    }

    private func setupPopover() {
        let rootView = PopoverView(
            store: store,
            onRequestPermission: { [weak self] in
                ScrollEngine.openAccessibilitySettings()
                self?.refreshPermissionAndEngine(promptIfNeeded: false)
            },
            onQuit: {
                NSApp.terminate(nil)
            }
        )

        let controller = NSHostingController(rootView: rootView)
        popover = NSPopover()
        popover.contentViewController = controller
        popover.behavior = .transient
        popover.animates = true
    }

    private func bindStatusIconUpdates() {
        Publishers.CombineLatest3(
            store.$isEnabled,
            store.$hasAccessibilityPermission,
            store.$isTapRunning
        )
        .receive(on: DispatchQueue.main)
        .sink { [weak self] _, _, _ in
            self?.updateStatusIcon()
        }
        .store(in: &cancellables)
    }

    private func updateStatusIcon() {
        guard let button = statusItem?.button else { return }

        let symbolName: String
        let tooltip: String

        if !store.hasAccessibilityPermission {
            symbolName = "exclamationmark.triangle.fill"
            tooltip = "鼠标助手（需要辅助功能权限）"
        } else if store.isEnabled && store.isTapRunning {
            symbolName = "arrow.left.and.right.circle.fill"
            tooltip = "鼠标助手（中键横向滚动 · 右键手势）"
        } else {
            symbolName = "arrow.left.and.right.circle"
            tooltip = "鼠标助手（已暂停）"
        }

        let config = NSImage.SymbolConfiguration(pointSize: 15, weight: .medium)
        let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "鼠标助手")?
            .withSymbolConfiguration(config)
        image?.isTemplate = true

        button.image = image
        button.toolTip = tooltip
        button.alphaValue = (store.isEnabled || !store.hasAccessibilityPermission) ? 1.0 : 0.55
    }

    @objc private func togglePopover(_ sender: AnyObject?) {
        if popover.isShown {
            popover.performClose(sender)
        } else {
            showPopover()
        }
    }

    private func showPopover() {
        guard let button = statusItem.button else { return }
        store.refreshLaunchAtLoginStatus()
        refreshPermissionAndEngine(promptIfNeeded: false)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    private func startPermissionMonitor() {
        permissionTimer?.invalidate()
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshPermissionAndEngine(promptIfNeeded: false)
            }
        }
    }

    private func refreshPermissionAndEngine(promptIfNeeded: Bool) {
        let trusted = ScrollEngine.hasAccessibilityPermission(prompt: promptIfNeeded)
        if store.hasAccessibilityPermission != trusted {
            store.hasAccessibilityPermission = trusted
        }

        if trusted {
            if !engine.isRunning {
                _ = engine.startIfPossible()
            }
        } else {
            if engine.isRunning {
                engine.stop()
            }
        }
    }
}
