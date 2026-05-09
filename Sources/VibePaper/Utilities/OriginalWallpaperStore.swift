import AppKit
import Foundation

/// 首次设置壁纸前，快照每块屏幕的系统壁纸路径；重置时还原
final class OriginalWallpaperStore {

    static let shared = OriginalWallpaperStore()

    private let udKey = "VibePaper.OriginalWallpapers"
    /// screenLocalizedName -> originalURL
    private var cache: [String: URL] = [:]

    private init() {}

    // MARK: - Public API

    /// 若尚未快照，立即对所有屏幕进行一次快照（必须在主线程调用）
    @MainActor
    func snapshotIfNeeded() {
        // 若 UserDefaults 中已有快照，只需加载缓存
        if let stored = UserDefaults.standard.dictionary(forKey: udKey) as? [String: String],
           !stored.isEmpty {
            for (k, v) in stored {
                cache[k] = URL(string: v)
            }
            return
        }
        performSnapshot()
    }

    /// 还原所有屏幕到原始壁纸，并清除快照
    @MainActor
    func restoreAll() {
        for screen in NSScreen.screens {
            let key = screen.localizedName
            if let url = cache[key] {
                try? NSWorkspace.shared.setDesktopImageURL(url, for: screen, options: [:])
            }
        }
        // 清除快照，以便下次 App 启动时重新获取当前壁纸
        UserDefaults.standard.removeObject(forKey: udKey)
        cache.removeAll()
    }

    // MARK: - Private

    @MainActor
    private func performSnapshot() {
        var urls: [String: String] = [:]
        for screen in NSScreen.screens {
            guard let url = NSWorkspace.shared.desktopImageURL(for: screen) else { continue }
            let key = screen.localizedName
            urls[key] = url.absoluteString
            cache[key] = url
        }
        UserDefaults.standard.set(urls, forKey: udKey)
    }
}
