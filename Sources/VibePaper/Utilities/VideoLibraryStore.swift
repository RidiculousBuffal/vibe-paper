import Foundation

/// 视频库持久化 —— Security-Scoped Bookmark 保存用户选择的视频文件路径
/// App 重启后可继续访问，无需用户重新选择
@MainActor
final class VideoLibraryStore: ObservableObject {

    static let shared = VideoLibraryStore()

    @Published private(set) var assets: [VideoAsset] = []

    private let udKey = "VibePaper.VideoLibrary"

    private init() {
        load()
    }

    // MARK: - Public API

    /// 从 fileImporter 返回的安全作用域 URL 添加视频
    /// 内部自动创建 Bookmark 以便下次启动时重新访问
    func add(securityScopedURL url: URL) {
        guard !assets.contains(where: { $0.url == url }) else { return }

        do {
            let bookmark = try url.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            var stored = loadRaw()
            stored[url.absoluteString] = bookmark
            saveRaw(stored)
            assets.append(VideoAsset(url: url))
        } catch {
            // Bookmark 创建失败（如无沙箱权限时），仍添加但重启后无法恢复
            print("[VideoLibraryStore] bookmark error: \(error)")
            assets.append(VideoAsset(url: url))
        }
    }

    func remove(_ asset: VideoAsset) {
        assets.removeAll { $0.id == asset.id }
        var stored = loadRaw()
        stored.removeValue(forKey: asset.url.absoluteString)
        saveRaw(stored)
    }

    // MARK: - Persistence

    private func load() {
        var result: [VideoAsset] = []
        for (_, bookmark) in loadRaw() {
            var isStale = false
            do {
                let url = try URL(
                    resolvingBookmarkData: bookmark,
                    options: .withSecurityScope,
                    relativeTo: nil,
                    bookmarkDataIsStale: &isStale
                )
                _ = url.startAccessingSecurityScopedResource()
                result.append(VideoAsset(url: url))
                if isStale { refreshBookmark(for: url) }
            } catch {
                print("[VideoLibraryStore] resolve error: \(error)")
            }
        }
        assets = result
    }

    private func refreshBookmark(for url: URL) {
        guard let bookmark = try? url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        ) else { return }
        var stored = loadRaw()
        stored[url.absoluteString] = bookmark
        saveRaw(stored)
    }

    private func loadRaw() -> [String: Data] {
        UserDefaults.standard.dictionary(forKey: udKey) as? [String: Data] ?? [:]
    }

    private func saveRaw(_ dict: [String: Data]) {
        UserDefaults.standard.set(dict, forKey: udKey)
    }
}
