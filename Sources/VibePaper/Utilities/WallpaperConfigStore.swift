import Foundation

/// 各屏幕壁纸配置持久化 —— JSON 存入 UserDefaults，App 重启后自动恢复
@MainActor
final class WallpaperConfigStore {

    static let shared = WallpaperConfigStore()

    private let udKey = "VibePaper.ScreenConfigs"
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private init() {}

    // MARK: - Public API

    func save(_ config: WallpaperConfig, for screenID: String) {
        var all = loadAll()
        all[screenID] = config
        persist(all)
    }

    func remove(for screenID: String) {
        var all = loadAll()
        all.removeValue(forKey: screenID)
        persist(all)
    }

    func loadAll() -> [String: WallpaperConfig] {
        guard
            let data = UserDefaults.standard.data(forKey: udKey),
            let dict = try? decoder.decode([String: WallpaperConfig].self, from: data)
        else { return [:] }
        return dict
    }

    func removeAll() {
        UserDefaults.standard.removeObject(forKey: udKey)
    }

    // MARK: - Private

    private func persist(_ dict: [String: WallpaperConfig]) {
        guard let data = try? encoder.encode(dict) else { return }
        UserDefaults.standard.set(data, forKey: udKey)
    }
}
