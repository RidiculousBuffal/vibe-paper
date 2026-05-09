import Foundation

/// 视频文件模型 —— 携带元数据与缩略图缓存引用
struct VideoAsset: Identifiable, Equatable, Hashable {

    let id: UUID
    /// 原始文件 URL（Security-Scoped）
    let url: URL
    /// 展示名称（去除扩展名的文件名）
    var displayName: String

    init(url: URL) {
        self.id = UUID()
        self.url = url
        self.displayName = url.deletingPathExtension().lastPathComponent
    }
}
