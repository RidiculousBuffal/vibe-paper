import Foundation
import ServiceManagement

/// 开机自启管理 —— 封装 SMAppService（macOS 13+）
enum LaunchAtLoginManager {

    private static let service = SMAppService.mainApp

    static var isEnabled: Bool {
        service.status == .enabled
    }

    static func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                if service.status == .notRegistered {
                    try service.register()
                }
            } else {
                if service.status == .enabled {
                    try service.unregister()
                }
            }
        } catch {
            print("[LaunchAtLogin] error: \(error.localizedDescription)")
        }
    }
}
