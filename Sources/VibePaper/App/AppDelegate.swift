import AppKit
import Foundation

/// App 生命周期管理：休眠/唤醒/屏幕变化事件
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    let displayManager = DisplayManager()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 系统版本检查（最低 macOS 14 Sonoma）
        checkSystemVersion()

        // 隐藏 Dock 图标（纯菜单栏应用）
        NSApp.setActivationPolicy(.accessory)

        // 首次启动时快照各屏幕原始壁纸
        OriginalWallpaperStore.shared.snapshotIfNeeded()

        // 启动屏幕 / 休眠监听
        displayManager.startMonitoring()

        // 恢复上次各屏壁纸配置
        displayManager.restorePersistedConfigs()
    }

    func applicationWillTerminate(_ notification: Notification) {
        displayManager.stopMonitoring()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    // MARK: - Private

    private func checkSystemVersion() {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        guard version.majorVersion >= 14 else {
            let alert = NSAlert()
            alert.messageText = "系统版本过低"
            alert.informativeText = "VibePaper 需要 macOS 14 Sonoma 或更高版本。\n当前系统：\(version.majorVersion).\(version.minorVersion)"
            alert.alertStyle = .warning
            alert.addButton(withTitle: "退出")
            alert.runModal()
            NSApp.terminate(nil)
            return
        }
    }
}
