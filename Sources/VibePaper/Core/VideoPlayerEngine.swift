import AVFoundation
import Foundation

/// AVQueuePlayer + AVPlayerLooper 封装 —— 硬件加速、无缝循环、静音播放
@MainActor
final class VideoPlayerEngine {

    let player: AVQueuePlayer
    private var playerLooper: AVPlayerLooper?

    // MARK: - Init

    init() {
        player = AVQueuePlayer()
        player.isMuted = true
        player.actionAtItemEnd = .none
        player.automaticallyWaitsToMinimizeStalling = false
    }

    // MARK: - Playback Control

    func load(url: URL, config: WallpaperConfig) {
        // 停止旧循环
        playerLooper = nil
        player.removeAllItems()

        let asset = AVAsset(url: url)
        let playerItem = AVPlayerItem(asset: asset)

        applyEnergyPolicy(to: playerItem, config: config)

        // AVPlayerLooper 自动管理无缝循环，无需手动监听 didPlayToEndTime
        playerLooper = AVPlayerLooper(player: player, templateItem: playerItem)

        if config.playbackRate != 1.0 {
            player.rate = config.playbackRate
        } else {
            player.play()
        }
    }

    func pause() {
        player.pause()
    }

    func resume() {
        player.play()
    }

    func stop() {
        playerLooper = nil
        player.pause()
        player.removeAllItems()
    }

    // MARK: - Energy Policy

    private func applyEnergyPolicy(to item: AVPlayerItem, config: WallpaperConfig) {
        if config.limitBitrate {
            // 电池模式：限制峰值码率为 2 Mbps（MVP 方案）
            item.preferredPeakBitRate = 2_000_000
        }
    }
}
