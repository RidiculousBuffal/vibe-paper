import AVFoundation
import Foundation

/// 每块屏幕的壁纸配置（视频路径 + 播放参数）
struct WallpaperConfig: Equatable {

    var videoURL: URL
    var videoGravity: AVLayerVideoGravity
    /// 电池模式下是否限制码率
    var limitBitrate: Bool
    /// 播放速率（0.5 ~ 2.0，1.0 为正常速度）
    var playbackRate: Float

    init(
        videoURL: URL,
        videoGravity: AVLayerVideoGravity = .resizeAspectFill,
        limitBitrate: Bool = false,
        playbackRate: Float = 1.0
    ) {
        self.videoURL = videoURL
        self.videoGravity = videoGravity
        self.limitBitrate = limitBitrate
        self.playbackRate = playbackRate
    }
}

// MARK: - Codable

extension WallpaperConfig: Codable {

    enum CodingKeys: String, CodingKey {
        case videoURL, videoGravity, limitBitrate, playbackRate
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        videoURL       = try c.decode(URL.self, forKey: .videoURL)
        let rawGravity = try c.decode(String.self, forKey: .videoGravity)
        videoGravity   = AVLayerVideoGravity(rawValue: rawGravity)
        limitBitrate   = try c.decode(Bool.self, forKey: .limitBitrate)
        playbackRate   = try c.decode(Float.self, forKey: .playbackRate)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(videoURL, forKey: .videoURL)
        try c.encode(videoGravity.rawValue, forKey: .videoGravity)
        try c.encode(limitBitrate, forKey: .limitBitrate)
        try c.encode(playbackRate, forKey: .playbackRate)
    }
}
