import AppKit
import Foundation

/// 多屏幕壁纸窗口管理器
/// - 维护每块屏幕对应的 WallpaperWindow 池
/// - 监听屏幕插拔、休眠/唤醒事件
@MainActor
final class DisplayManager: ObservableObject {

    // MARK: - Published State

    @Published private(set) var wallpaperWindows: [String: WallpaperWindow] = [:]
    @Published private(set) var activeConfigs: [String: WallpaperConfig] = [:]

    // MARK: - Private

    private var screenObserver: (any NSObjectProtocol)?
    private var sleepObserver: (any NSObjectProtocol)?
    private var wakeObserver: (any NSObjectProtocol)?
    private var energyObserver: (any NSObjectProtocol)?

    // MARK: - Monitoring

    func startMonitoring() {
        // 屏幕插拔
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.handleScreenChange() }
        }

        // 系统休眠（willSleep：屏幕关闭前停止解码，降低能耗）
        sleepObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.pauseAll() }
        }

        // 系统唤醒
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.resumeAll() }
        }

        // 充电状态变化 → 调整码率 + 帧率策略
        energyObserver = NotificationCenter.default.addObserver(
            forName: EnergyMonitor.powerStateChangedNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.reloadWithCurrentEnergyPolicy() }
        }

        // 屏幕保护程序启动
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.screensDidSleepNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.pauseAll() }
        }

        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.screensDidWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.resumeAll() }
        }
    }

    func stopMonitoring() {
        [screenObserver, sleepObserver, wakeObserver, energyObserver]
            .compactMap { $0 }
            .forEach { NotificationCenter.default.removeObserver($0) }

        let wsCenter = NSWorkspace.shared.notificationCenter
        [sleepObserver, wakeObserver]
            .compactMap { $0 }
            .forEach { wsCenter.removeObserver($0) }
    }

    // MARK: - Wallpaper Control

    /// 为指定屏幕设置视频壁纸
    func setWallpaper(url: URL, config: WallpaperConfig, for screen: NSScreen) {
        let id = identifier(for: screen)

        let wallpaperWin: WallpaperWindow
        if let existing = wallpaperWindows[id] {
            wallpaperWin = existing
        } else {
            wallpaperWin = WallpaperWindow(screen: screen)
            wallpaperWindows[id] = wallpaperWin
        }

        wallpaperWin.setVideo(url: url, config: config)
        activeConfigs[id] = config

        // 持久化
        WallpaperConfigStore.shared.save(config, for: id)
    }

    /// 停止所有视频壁纸，还原系统壁纸
    func resetAll() {
        for (_, window) in wallpaperWindows {
            window.close()
        }
        wallpaperWindows.removeAll()
        activeConfigs.removeAll()
        WallpaperConfigStore.shared.removeAll()
        OriginalWallpaperStore.shared.restoreAll()
    }

    /// App 启动后恢复上次各屏配置
    func restorePersistedConfigs() {
        let stored = WallpaperConfigStore.shared.loadAll()
        guard !stored.isEmpty else { return }

        for screen in availableScreens {
            let id = identifier(for: screen)
            guard let config = stored[id] else { continue }
            // 文件仍可访问才恢复
            guard FileManager.default.fileExists(atPath: config.videoURL.path) else { continue }
            setWallpaper(url: config.videoURL, config: config, for: screen)
        }
    }

    // MARK: - Computed

    /// 过滤 Sidecar / Universal Control 虚拟屏后的物理显示器列表
    var availableScreens: [NSScreen] {
        NSScreen.screens.filter { screen in
            // Sidecar 屏幕名称包含 "iPad"，Universal Control 包含 "Universal Control"
            let name = screen.localizedName
            return !name.contains("iPad") && !name.contains("Universal Control")
        }
    }

    // MARK: - Private Handlers

    private func handleScreenChange() {
        let current = Set(availableScreens.map { identifier(for: $0) })
        let existing = Set(wallpaperWindows.keys)

        // 移除已断开屏幕的窗口
        for id in existing.subtracting(current) {
            wallpaperWindows[id]?.close()
            wallpaperWindows.removeValue(forKey: id)
            activeConfigs.removeValue(forKey: id)
        }
    }

    private func pauseAll() {
        wallpaperWindows.values.forEach { $0.pause() }
    }

    private func resumeAll() {
        wallpaperWindows.values.forEach { $0.resume() }
    }

    private func reloadWithCurrentEnergyPolicy() {
        let onBattery = EnergyMonitor.shared.isOnBattery
        for screen in availableScreens {
            let id = identifier(for: screen)
            guard var config = activeConfigs[id] else { continue }
            config.limitBitrate = onBattery
            activeConfigs[id] = config
            if let wallpaperWin = wallpaperWindows[id] {
                // 帧率策略即时生效，无需重新加载整个视频
                wallpaperWin.applyFrameRatePolicy(limitTo15fps: onBattery)
                // 码率策略需要重载 playerItem
                wallpaperWin.setVideo(url: config.videoURL, config: config)
            }
        }
    }

    // MARK: - Helpers

    func identifier(for screen: NSScreen) -> String {
        screen.localizedName
    }
}
