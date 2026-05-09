import SwiftUI

/// 菜单栏 Popover —— 快速切换壁纸 / 重置 / 退出
struct MenuBarView: View {

    @EnvironmentObject var displayManager: DisplayManager
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            // 标题行
            HStack {
                Image(systemName: "play.rectangle.fill")
                    .foregroundColor(.accentColor)
                Text("VibePaper")
                    .fontWeight(.semibold)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 6)

            Divider()

            // 状态摘要
            if displayManager.activeConfigs.isEmpty {
                Text("未设置壁纸")
                    .foregroundColor(.secondary)
                    .font(.caption)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
            } else {
                Text("已激活 \(displayManager.activeConfigs.count) 块屏幕")
                    .foregroundColor(.secondary)
                    .font(.caption)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
            }

            Divider()

            // 操作按钮
            MenuButton(label: "打开设置...", systemImage: "gearshape") {
                openSettings()
                NSApp.activate(ignoringOtherApps: true)
            }

            if !displayManager.activeConfigs.isEmpty {
                MenuButton(label: "重置所有壁纸", systemImage: "arrow.counterclockwise") {
                    displayManager.resetAll()
                }
            }

            Divider()

            MenuButton(label: "退出 VibePaper", systemImage: "power") {
                NSApplication.shared.terminate(nil)
            }
            .padding(.bottom, 4)
        }
        .frame(width: 220)
    }
}

// MARK: - MenuButton

private struct MenuButton: View {
    let label: String
    let systemImage: String
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Label(label, systemImage: systemImage)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isHovered ? Color.accentColor.opacity(0.15) : Color.clear)
                .padding(.horizontal, 4)
        )
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
    }
}
