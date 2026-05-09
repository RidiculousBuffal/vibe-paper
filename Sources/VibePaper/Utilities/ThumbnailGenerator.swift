import AVFoundation
import AppKit
import CoreMedia

/// 异步生成视频缩略图（使用 AVAssetImageGenerator 硬件加速解码）
enum ThumbnailGenerator {

    /// 从视频文件 URL 生成指定时间点的缩略图
    /// - Parameters:
    ///   - url: 视频文件 URL
    ///   - time: 截帧时间点，默认取第 1 秒（避免片头黑帧）
    ///   - maxSize: 缩略图最大尺寸，默认 240×135（16:9 预览图）
    /// - Returns: 成功返回 NSImage，失败返回 nil
    static func generate(
        for url: URL,
        at time: CMTime = CMTime(seconds: 1, preferredTimescale: 600),
        maxSize: CGSize = CGSize(width: 240, height: 135)
    ) async -> NSImage? {
        let asset = AVAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = maxSize
        generator.requestedTimeToleranceBefore = CMTime(seconds: 0.5, preferredTimescale: 600)
        generator.requestedTimeToleranceAfter  = CMTime(seconds: 0.5, preferredTimescale: 600)

        return await withCheckedContinuation { continuation in
            generator.generateCGImageAsynchronously(for: time) { cgImage, _, error in
                guard let cgImage, error == nil else {
                    continuation.resume(returning: nil)
                    return
                }
                let image = NSImage(
                    cgImage: cgImage,
                    size: NSSize(width: cgImage.width, height: cgImage.height)
                )
                continuation.resume(returning: image)
            }
        }
    }
}
