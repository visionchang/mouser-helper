import AppKit
import CoreGraphics
import Foundation
import MouseHelperCore

enum GestureActionExecutor {
    private static let syntheticEventMarker: Int64 = 0x4D48_5343_524F_4C4C

    static func execute(_ action: GestureActionType) {
        switch action {
        case .goBack:
            postKeyCombo(keyCode: 33, flags: .maskCommand) // ⌘[
        case .goForward:
            postKeyCombo(keyCode: 30, flags: .maskCommand) // ⌘]
        case .closeTab:
            postKeyCombo(keyCode: 13, flags: .maskCommand) // ⌘W
        case .reopenTab:
            postKeyCombo(keyCode: 17, flags: [.maskCommand, .maskShift]) // ⇧⌘T
        case .newTab:
            postKeyCombo(keyCode: 17, flags: .maskCommand) // ⌘T
        case .reloadPage:
            postKeyCombo(keyCode: 15, flags: .maskCommand) // ⌘R
        case .nextTab:
            postKeyCombo(keyCode: 48, flags: .maskControl) // ⌃Tab
        case .previousTab:
            postKeyCombo(keyCode: 48, flags: [.maskControl, .maskShift]) // ⌃⇧Tab
        case .missionControl:
            openSystemApp("/System/Applications/Mission Control.app")
        case .appExpose:
            postKeyCombo(keyCode: 125, flags: .maskControl) // ⌃↓
        case .showDesktop:
            postKeyCombo(keyCode: 103, flags: []) // F11
        case .spaceLeft:
            postKeyCombo(keyCode: 123, flags: .maskControl) // ⌃←
        case .spaceRight:
            postKeyCombo(keyCode: 124, flags: .maskControl) // ⌃→
        case .minimizeWindow:
            postKeyCombo(keyCode: 46, flags: .maskCommand) // ⌘M
        case .hideApp:
            postKeyCombo(keyCode: 4, flags: .maskCommand) // ⌘H
        case .toggleFullscreen:
            postKeyCombo(keyCode: 3, flags: [.maskControl, .maskCommand]) // ⌃⌘F
        case .scrollToTop:
            postKeyCombo(keyCode: 126, flags: .maskCommand) // ⌘↑
        case .scrollToBottom:
            postKeyCombo(keyCode: 125, flags: .maskCommand) // ⌘↓
        }
    }

    private static func postKeyCombo(keyCode: CGKeyCode, flags: CGEventFlags) {
        let source = CGEventSource(stateID: .combinedSessionState)
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false) else {
            return
        }

        keyDown.flags = flags
        keyUp.flags = flags
        keyDown.setIntegerValueField(.eventSourceUserData, value: syntheticEventMarker)
        keyUp.setIntegerValueField(.eventSourceUserData, value: syntheticEventMarker)

        keyDown.post(tap: .cgSessionEventTap)
        keyUp.post(tap: .cgSessionEventTap)
    }

    private static func openSystemApp(_ path: String) {
        DispatchQueue.main.async {
            let url = URL(fileURLWithPath: path)
            let config = NSWorkspace.OpenConfiguration()
            config.activates = true
            NSWorkspace.shared.openApplication(at: url, configuration: config, completionHandler: nil)
        }
    }
}
