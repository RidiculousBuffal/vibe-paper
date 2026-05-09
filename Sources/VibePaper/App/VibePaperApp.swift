import SwiftUI
import AppKit

@main
struct VibePaperApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // 菜单栏图标 + Popover
        MenuBarExtra("VibePaper", systemImage: "play.rectangle.fill") {
            MenuBarView()
                .environmentObject(appDelegate.displayManager)
        }
        .menuBarExtraStyle(.window)

        // 设置窗口
        Settings {
            SettingsView()
                .environmentObject(appDelegate.displayManager)
        }
    }
}
