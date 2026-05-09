import SwiftUI
import UniformTypeIdentifiers

/// 完整设置窗口：视频库选择 / 多屏管理 / 能耗 / 关于
struct SettingsView: View {

    @EnvironmentObject var displayManager: DisplayManager

    var body: some View {
        TabView {
            WallpaperTab()
                .tabItem { Label("壁纸", systemImage: "photo.on.rectangle.angled") }

            EnergyTab()
                .tabItem { Label("能耗", systemImage: "bolt.fill") }

            AboutTab()
                .tabItem { Label("关于", systemImage: "info.circle") }
        }
        .frame(width: 680, height: 460)
    }
}

// MARK: - WallpaperTab

private struct WallpaperTab: View {

    @EnvironmentObject var displayManager: DisplayManager
    @StateObject private var libraryStore = VideoLibraryStore.shared
    @State private var selectedScreen: NSScreen?
    @State private var showingFilePicker = false
    @State private var errorMessage: String?

    var body: some View {
        HSplitView {
            ScreenSidebar(selectedScreen: $selectedScreen)
                .frame(minWidth: 160, maxWidth: 200)

            VideoLibraryPanel(
                showingFilePicker: $showingFilePicker,
                selectedScreen: selectedScreen,
                errorMessage: errorMessage
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear {
            if selectedScreen == nil { selectedScreen = NSScreen.main }
        }
        .fileImporter(
            isPresented: $showingFilePicker,
            allowedContentTypes: [.movie, .mpeg4Movie],
            allowsMultipleSelection: true
        ) { result in
            handleImport(result: result)
        }
    }

    private func handleImport(result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            for url in urls {
                guard url.startAccessingSecurityScopedResource() else { continue }
                // 创建 Bookmark 后即可停止访问；Bookmark 内部会重新建立作用域
                VideoLibraryStore.shared.add(securityScopedURL: url)
                url.stopAccessingSecurityScopedResource()
                if let screen = selectedScreen {
                    applyWallpaper(url: url, to: screen)
                }
            }
        case .failure(let error):
            errorMessage = error.localizedDescription
        }
    }

    private func applyWallpaper(url: URL, to screen: NSScreen) {
        let config = WallpaperConfig(
            videoURL: url,
            videoGravity: .resizeAspectFill,
            limitBitrate: EnergyMonitor.shared.isOnBattery
        )
        displayManager.setWallpaper(url: url, config: config, for: screen)
    }
}

// MARK: - ScreenSidebar

private struct ScreenSidebar: View {

    @EnvironmentObject var displayManager: DisplayManager
    @Binding var selectedScreen: NSScreen?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("显示器")
                .font(.headline)
                .padding([.horizontal, .top])

            List(displayManager.availableScreens, id: \.localizedName, selection: $selectedScreen) { screen in
                screenRow(screen)
                    .tag(screen as NSScreen?)
            }
            .listStyle(.plain)
            .background(Color.white)
            .scrollContentBackground(.hidden)

            Divider()

            Button(role: .destructive) {
                displayManager.resetAll()
            } label: {
                Label("重置所有壁纸", systemImage: "arrow.counterclockwise")
            }
            .padding()
            .disabled(displayManager.activeConfigs.isEmpty)
        }
        .background(Color.white)
    }

    private func screenRow(_ screen: NSScreen) -> some View {
        let isActive = displayManager.activeConfigs[displayManager.identifier(for: screen)] != nil
        return HStack {
            Image(systemName: isActive ? "display.and.arrow.down" : "display")
                .foregroundColor(isActive ? .accentColor : .secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(screen.localizedName)
                    .lineLimit(1)
                if isActive {
                    Text("壁纸已激活")
                        .font(.caption2)
                        .foregroundColor(.accentColor)
                }
            }
        }
    }
}

// MARK: - VideoLibraryPanel

private struct VideoLibraryPanel: View {

    @EnvironmentObject var displayManager: DisplayManager
    @ObservedObject private var libraryStore = VideoLibraryStore.shared
    @Binding var showingFilePicker: Bool
    let selectedScreen: NSScreen?
    let errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            // 顶部工具栏
            HStack {
                if let screen = selectedScreen {
                    Text("为「\(screen.localizedName)」选择壁纸")
                        .font(.headline)
                } else {
                    Text("请在左侧选择显示器")
                        .foregroundColor(.secondary)
                }
                Spacer()
                Button {
                    showingFilePicker = true
                } label: {
                    Label("导入视频...", systemImage: "plus")
                }
                .disabled(selectedScreen == nil)
            }
            .padding()

            Divider()

            // 视频库网格
            if libraryStore.assets.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 130), spacing: 12)],
                        spacing: 12
                    ) {
                        ForEach(libraryStore.assets) { asset in
                            VideoThumbnailCard(asset: asset) {
                                if let screen = selectedScreen {
                                    applyWallpaper(asset: asset, to: screen)
                                }
                            } onDelete: {
                                VideoLibraryStore.shared.remove(asset)
                            }
                        }
                    }
                    .padding()
                }
            }

            // 错误提示
            if let msg = errorMessage {
                Text(msg)
                    .foregroundColor(.red)
                    .font(.caption)
                    .padding(.horizontal)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "video.badge.plus")
                .font(.system(size: 56))
                .foregroundColor(.secondary)
            Text("还没有视频")
                .font(.title3)
                .foregroundColor(.secondary)
            Button("导入视频...") {
                showingFilePicker = true
            }
            .disabled(selectedScreen == nil)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func applyWallpaper(asset: VideoAsset, to screen: NSScreen) {
        let config = WallpaperConfig(
            videoURL: asset.url,
            videoGravity: .resizeAspectFill,
            limitBitrate: EnergyMonitor.shared.isOnBattery
        )
        displayManager.setWallpaper(url: asset.url, config: config, for: screen)
    }
}

// MARK: - VideoThumbnailCard

struct VideoThumbnailCard: View {

    let asset: VideoAsset
    let onSelect: () -> Void
    let onDelete: () -> Void

    @State private var thumbnail: NSImage?
    @State private var isHovered = false

    var body: some View {
        VStack(spacing: 6) {
            ZStack(alignment: .topTrailing) {
                // 缩略图
                Group {
                    if let img = thumbnail {
                        Image(nsImage: img)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } else {
                        Rectangle()
                            .fill(Color.secondary.opacity(0.2))
                            .overlay {
                                ProgressView()
                            }
                    }
                }
                .frame(width: 130, height: 73)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .shadow(radius: isHovered ? 4 : 1)

                // 悬浮删除按钮
                if isHovered {
                    Button(action: onDelete) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.white, .black.opacity(0.6))
                    }
                    .buttonStyle(.plain)
                    .padding(4)
                }
            }
            .onHover { isHovered = $0 }
            .onTapGesture { onSelect() }

            Text(asset.displayName)
                .font(.caption)
                .lineLimit(1)
                .frame(width: 130)
        }
        .task {
            thumbnail = await ThumbnailGenerator.generate(for: asset.url)
        }
    }
}

// MARK: - EnergyTab

private struct EnergyTab: View {

    @EnvironmentObject var displayManager: DisplayManager
    @AppStorage("VibePaper.limitBitrateOnBattery") private var limitBitrateOnBattery = true
    @AppStorage("VibePaper.use15fpsBattery") private var use15fpsBattery = true
    @AppStorage("VibePaper.playbackRate") private var playbackRate: Double = 1.0

    private let rateSteps: [(label: String, value: Double)] = [
        ("0.5x", 0.5), ("0.75x", 0.75), ("1x（正常）", 1.0),
        ("1.25x", 1.25), ("1.5x", 1.5), ("2x", 2.0)
    ]

    var body: some View {
        Form {
            Section("播放速率") {
                Picker("速率", selection: $playbackRate) {
                    ForEach(rateSteps, id: \.value) { step in
                        Text(step.label).tag(step.value)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: playbackRate) { _, newRate in
                    applyPlaybackRate(Float(newRate))
                }
            }

            Section("电池优化") {
                Toggle("电池时限制码率（≤ 2 Mbps）", isOn: $limitBitrateOnBattery)
                    .help("降低视频码率可显著减少 GPU/CPU 占用，延长续航")
                Toggle("电池时节流帧率（15fps）", isOn: $use15fpsBattery)
                    .help("CADisplayLink 精确限制渲染帧率，进一步降低 GPU 占用")
            }

            Section("状态") {
                LabeledContent("当前电源") {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(EnergyMonitor.shared.isOnBattery ? Color.orange : Color.green)
                            .frame(width: 8, height: 8)
                        Text(EnergyMonitor.shared.isOnBattery ? "电池供电" : "已接电源")
                    }
                }
                LabeledContent("活跃壁纸屏幕") {
                    Text("\(displayManager.activeConfigs.count) 块")
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private func applyPlaybackRate(_ rate: Float) {
        for (screenID, var config) in displayManager.activeConfigs {
            config.playbackRate = rate
            // 找到对应屏幕重新加载（通过 identifier 反查 screen）
            if let screen = NSScreen.screens.first(where: {
                displayManager.identifier(for: $0) == screenID
            }) {
                displayManager.setWallpaper(url: config.videoURL, config: config, for: screen)
            }
        }
    }
}

// MARK: - AboutTab

private struct AboutTab: View {

    @State private var launchAtLogin = LaunchAtLoginManager.isEnabled

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            Image(systemName: "play.rectangle.fill")
                .font(.system(size: 64))
                .foregroundColor(.accentColor)

            Text("VibePaper")
                .font(.largeTitle.bold())
                .padding(.top, 8)

            Text("轻量级 macOS 动态壁纸应用")
                .foregroundColor(.secondary)
                .padding(.top, 2)

            HStack(spacing: 4) {
                Text("版本")
                Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0")
                    .foregroundColor(.secondary)
            }
            .font(.caption)
            .padding(.top, 4)

            Spacer()

            // 开机自启 Toggle
            GroupBox {
                Toggle("登录时自动启动", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in
                        LaunchAtLoginManager.setEnabled(enabled)
                    }
            }
            .padding(.horizontal, 40)

            Spacer()

            Text("零第三方依赖 · AVFoundation GPU 渲染 · macOS 14+")
                .font(.caption2)
                .foregroundColor(.secondary)
                .padding(.bottom, 16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
