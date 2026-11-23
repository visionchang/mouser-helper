import Foundation
import ServiceManagement

@MainActor
enum LaunchAtLoginManager {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    @discardableResult
    static func setEnabled(_ enabled: Bool) -> Bool {
        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else {
                if SMAppService.mainApp.status == .enabled {
                    try SMAppService.mainApp.unregister()
                }
            }
            return SMAppService.mainApp.status == .enabled
        } catch {
            NSLog("MouseHelper: Failed to update LaunchAtLogin (\(enabled)): \(error.localizedDescription)")
            return SMAppService.mainApp.status == .enabled
        }
    }
}
