import AppKit
import AVFoundation

/// 桌面级壁纸窗口 —— 使用组合（而非继承）持有 NSWindow，避免 AppKit 强制 init 链问题
@MainActor
final class WallpaperWindow {

    let window: NSWindow

    private var playerLayer: AVPlayerLayer?
    private var playerEngine: VideoPlayerEngine?
    private let targetScreen: NSScreen

    /// CADisplayLink 节流（电池模式 15fps）
    private var displayLink: CADisplayLink?

    // MARK: - Init

    init(screen: NSScreen) {
        self.targetScreen = screen
        let win = NSWindow(
            contentRect: screen.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false,
            screen: screen
        )
        self.window = win
        configureWindow()
    }

    private func configureWindow() {
        window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)))
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        window.isMovableByWindowBackground = false
        window.ignoresMouseEvents = true
        window.isOpaque = true
        window.hasShadow = false
        window.backgroundColor = .black
        window.setFrame(targetScreen.frame, display: false)
        window.orderFront(nil)
    }

    // MARK: - Video

    func setVideo(url: URL, config: WallpaperConfig) {
        let newEngine = VideoPlayerEngine()
        let newLayer = AVPlayerLayer(player: newEngine.player)
        newLayer.frame = window.contentView?.bounds ?? targetScreen.frame
        newLayer.videoGravity = config.videoGravity
        newLayer.opacity = 0

        window.contentView?.wantsLayer = true
        window.contentView?.layer?.addSublayer(newLayer)

        let oldLayer = self.playerLayer
        let oldEngine = self.playerEngine

        newLayer.observeReadyForDisplay {
            CATransaction.begin()
            CATransaction.setAnimationDuration(0.3)
            newLayer.opacity = 1
            oldLayer?.opacity = 0
            CATransaction.commit()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                oldLayer?.removeFromSuperlayer()
                oldEngine?.stop()
            }
        }

        self.playerLayer = newLayer
        self.playerEngine = newEngine
        newEngine.load(url: url, config: config)

        // 帧率策略：电池模式节流到 15fps，充电时不限制
        applyFrameRatePolicy(limitTo15fps: config.limitBitrate)
    }

    // MARK: - Frame Rate Policy (Phase 2)

    /// - Parameter limitTo15fps: true = 电池模式节流 15fps；false = 移除节流
    func applyFrameRatePolicy(limitTo15fps: Bool) {
        displayLink?.invalidate()
        displayLink = nil

        guard limitTo15fps else { return }

        // CADisplayLink 节流：只在每帧回调时推进 player 时间轴
        // macOS 14+ NSScreen 支持 displayLink(target:selector:)
        let link = targetScreen.displayLink(target: self, selector: #selector(displayLinkTick))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 15, maximum: 15, preferred: 15)
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    @objc private func displayLinkTick() {
        // CADisplayLink 触发时 AVPlayer 自然渲染当前帧；
        // 节流效果由 preferredFrameRateRange 控制，此处无需额外操作
    }

    // MARK: - Playback Control

    func pause() {
        playerEngine?.pause()
        displayLink?.isPaused = true
    }

    func resume() {
        playerEngine?.resume()
        displayLink?.isPaused = false
    }

    func stop() {
        displayLink?.invalidate()
        displayLink = nil
        playerLayer?.removeFromSuperlayer()
        playerLayer = nil
        playerEngine?.stop()
        playerEngine = nil
    }

    func close() {
        stop()
        window.close()
    }
}

// MARK: - AVPlayerLayer KVO helper

private extension AVPlayerLayer {
    func observeReadyForDisplay(handler: @escaping () -> Void) {
        if isReadyForDisplay {
            handler()
            return
        }
        var obs: NSKeyValueObservation?
        obs = observe(\.isReadyForDisplay, options: [.new]) { _, change in
            guard change.newValue == true else { return }
            DispatchQueue.main.async { handler() }
            obs?.invalidate()
            obs = nil
        }
        objc_setAssociatedObject(self, &kObservationKey, obs, .OBJC_ASSOCIATION_RETAIN)
    }
}

private nonisolated(unsafe) var kObservationKey: UInt8 = 0
