# VibePaper — macOS 动态壁纸应用技术方案

> **方案版本**：v2.0（2026-05-09 更新）  
> 综合原始方案 + 审计报告 + macOS 26 Tahoe / Swift 6.3 发布说明修订

## 概述

VibePaper 是一款轻量级 macOS 原生动态壁纸应用，支持导入 4K 视频并将其设置为桌面壁纸，
支持多显示器独立壁纸、低能耗策略及一键恢复原始壁纸。

- 分发方式：DMG 直接分发（无 App Store 沙箱限制）
- 最低系统：macOS 14 Sonoma（使用 macOS 26 SDK 编译，`@available` 保护新 API）
- 目标体积：< 5 MB（零第三方依赖）

---

## 技术选型

| 层面       | 选择                                    | 理由                              |
|------------|-----------------------------------------|-----------------------------------|
| 语言       | Swift 6.3（MVP 阶段用 Swift 5 兼容模式）| 原生 macOS，二进制最小，能耗最低  |
| UI 框架    | SwiftUI + AppKit                        | SwiftUI 写界面，AppKit 管底层窗口 |
| 视频引擎   | AVFoundation (AVQueuePlayer + AVPlayerLooper) | 硬件加速 H.264/HEVC，无缝循环播放 |
| 渲染层     | AVPlayerLayer + CALayer                 | GPU 渲染，不占 CPU                |
| 帧率控制   | CADisplayLink（macOS 14+）              | 精确帧率节流，替代错误的 preferredTimescale 方案 |
| 构建工具   | Xcode 26.x + Swift Package Manager     | 无第三方依赖，包体可控            |
| 配置存储   | UserDefaults + Security-Scoped Bookmark | 保存路径与多屏配置                |

---

## 核心技术原理

### 壁纸窗口实现

创建一个 `NSWindow`，将 `windowLevel` 设为 `kCGDesktopWindowLevel`，
使其位于桌面图标层之下、壁纸层之上。通过 `AVPlayerLayer` 在该窗口上循环播放视频，
视觉上即为动态壁纸。

```swift
// WallpaperWindow 需标注 @MainActor（Swift 6 要求，NSWindow 本身已是 MainActor-bound）
@MainActor
final class WallpaperWindow: NSWindow {
    override init(contentRect: NSRect, ...) {
        super.init(...)
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)))
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        isMovableByWindowBackground = false
        ignoresMouseEvents = true
    }
}
```

### 视频循环播放（推荐方案：AVQueuePlayer + AVPlayerLooper）

macOS 官方推荐使用 `AVPlayerLooper` 实现无缝循环，比手动监听
`didPlayToEndTimeNotification` 更稳定，且 API 已标注 `Sendable`：

```swift
// VideoPlayerEngine 内部实现
let asset = AVAsset(url: videoURL)
let playerItem = AVPlayerItem(asset: asset)
let queuePlayer = AVQueuePlayer()
// AVPlayerLooper 自动管理循环，无需手动监听通知
let playerLooper = AVPlayerLooper(player: queuePlayer, templateItem: playerItem)
queuePlayer.isMuted = true
queuePlayer.play()
```

> **注意（macOS 26 已修复）**：`AVPlayerLayer.isReadyForDisplay` 在切换视频时
> 可能短暂变为 false，导致黑屏闪烁。可在切换前保留旧 layer 直到新 layer
> `isReadyForDisplay == true` 再替换。

### 帧率控制（替代原错误方案）

原方案用 `preferredTimescale` 控制帧率是错误的（该属性控制时间精度，非帧率）。
正确方案：

```swift
// 方案 A：限制峰值码率（简单，适合 MVP）
playerItem.preferredPeakBitRate = 2_000_000  // 电池模式限制为 2 Mbps

// 方案 B：CADisplayLink 节流（精确帧率控制，macOS 14+）
// NSScreen/NSWindow/NSView 均可创建 CADisplayLink
let displayLink = screen.displayLink(target: self, selector: #selector(tick))
displayLink.preferredFrameRateRange = CAFrameRateRange(minimum: 15, maximum: 15, preferred: 15)
displayLink.add(to: .main, forMode: .common)
```

### 多显示器管理

遍历 `NSScreen.screens`，为每个屏幕创建独立的 `WallpaperWindow`。
监听 `NSApplicationDidChangeScreenParametersNotification` 处理插拔外接屏。
注意通过 `screen.localizedName` 区分物理显示器与 Sidecar/Universal Control 虚拟屏。

### 一键重置原理

App **首次设置壁纸前**，通过 `NSWorkspace.shared.desktopImageURL(for:)`
快照每个屏幕的当前壁纸路径，持久化到 UserDefaults。
重置时停止视频、销毁 `WallpaperWindow`，
并调用 `NSWorkspace.shared.setDesktopImageURL(originalURL, for:options:)` 还原。

### Swift 6 并发兼容策略（新增）

MVP 阶段使用 **Swift 5 兼容模式**（Xcode 项目设置 Swift Language Version = Swift 5，
Strict Concurrency Checking = Minimal），降低学习门槛。
需要手动标注 `@MainActor` 的关键位置：

| 文件 | 标注位置 |
|------|---------|
| `AppDelegate.swift` | class 级别 `@MainActor` |
| `WallpaperWindow.swift` | class 级别（`NSWindow` 已自动 MainActor-bound） |
| `VideoPlayerEngine.swift` | AVPlayer 回调闭包 + class 级别 `@MainActor` |
| `DisplayManager.swift` | class 级别 `@MainActor`，`NSScreen` 操作主线程 |
| `OriginalWallpaperStore.swift` | `NSWorkspace` 调用需主线程 |
| `EnergyMonitor.swift` | 电源回调用 `Task { @MainActor in ... }` 转发 |

---

## 项目结构

```
VibePaper/
├── App/
│   ├── VibePaperApp.swift              # 入口，MenuBarExtra，生命周期
│   └── AppDelegate.swift               # 休眠/唤醒/屏幕变化事件
│
├── Core/
│   ├── WallpaperWindow.swift           # 桌面级 NSWindow 封装
│   ├── VideoPlayerEngine.swift         # AVPlayer 封装（循环/静音/硬解）
│   └── DisplayManager.swift            # 多屏管理，WallpaperWindow 池
│
├── UI/
│   ├── MenuBarView.swift               # 菜单栏 Popover（快速切换/重置）
│   └── SettingsView.swift              # 完整设置窗口（视频库/多屏/能耗）
│
├── Models/
│   ├── WallpaperConfig.swift           # 每屏壁纸配置（视频路径/播放参数）
│   └── VideoAsset.swift                # 视频文件模型（元数据/缩略图缓存）
│
└── Utilities/
    ├── OriginalWallpaperStore.swift    # 首次快照并还原原始壁纸
    ├── EnergyMonitor.swift             # 电源状态监听，电池/充电策略
    └── ThumbnailGenerator.swift        # AVAssetImageGenerator 生成预览图
```

---

## 功能规划

### Phase 1 — MVP（核心可用）

- [ ] MenuBarExtra 菜单栏图标 + 设置窗口骨架
- [ ] NSOpenPanel 导入视频（mp4 / mov / hevc）
- [ ] 首次启动快照各屏原始壁纸路径（OriginalWallpaperStore）
- [ ] 创建 WallpaperWindow，AVPlayerLayer 静音循环播放（AVQueuePlayer + AVPlayerLooper）
- [ ] 单屏壁纸设置
- [ ] 一键重置按钮（菜单栏 + 设置窗口均可触发）
- [ ] 开机自启（SMAppService / LaunchAgent）
- [ ] Xcode 项目配置：Swift 5 兼容模式 + Minimal 并发检查 + @MainActor 关键位置标注

### Phase 2 — 多屏 + 能耗优化

- [ ] 多显示器独立壁纸选择与管理（`NSScreen.localizedName` 过滤虚拟屏）
- [ ] 监听屏幕插拔，动态增删 WallpaperWindow
- [ ] 电池模式能耗优化：`preferredPeakBitRate` 限制码率（MVP 方案）
- [ ] 精确帧率控制：`CADisplayLink.preferredFrameRateRange` 节流到 15fps（进阶方案）
- [ ] 锁屏 / 休眠自动暂停（NSWorkspace.didSleepNotification）
- [ ] 显示器关闭时暂停（NSApplicationDidResignActiveNotification）
- [ ] 视频库管理界面（添加 / 删除 / 预览缩略图）
- [ ] 切换壁纸时平滑过渡（等待新 AVPlayerLayer.isReadyForDisplay 后再替换旧 layer）

### Phase 3 — 打磨与完善

- [ ] 支持 ProRes / VP9 格式
- [ ] 视频导入选项：拷贝到 App 目录 或 引用原路径
- [ ] 播放速度控制（0.5x ~ 2x）
- [ ] 多屏各自独立配置的持久化
- [ ] 检查系统版本，Sonoma 以下给出提示
- [ ] Swift 6 完整并发模式迁移（Strict Concurrency = Complete）
- [ ] DMG 打包与代码签名（codesign + notarytool）

---

## 能耗优化策略

| 场景           | 策略                                                                    |
|----------------|-------------------------------------------------------------------------|
| 使用电池       | `preferredPeakBitRate = 2_000_000`（MVP）；进阶用 `CADisplayLink` 限 15fps |
| 锁屏 / 休眠    | 监听 `didSleepNotification` → `queuePlayer.pause()`                    |
| 显示器关闭     | 监听 `NSApplicationDidResignActiveNotification` 暂停                    |
| 硬件解码       | AVFoundation 自动调用 Apple Silicon / Intel 硬件解码器（macOS 26 HEVC 高码率解码性能已修复） |
| GPU 渲染       | AVPlayerLayer 直接挂载 CALayer，绕过 CPU 合成                           |
| 内存           | AVQueuePlayer + AVPlayerLooper 流式缓冲，不预加载全帧                  |

---

## 预期性能指标

| 指标         | 目标值                          |
|--------------|---------------------------------|
| 安装包体积   | < 5 MB                          |
| 内存占用     | ~30–60 MB（含视频缓冲）         |
| CPU 占用     | < 3%（4K HEVC，Apple Silicon）  |
| GPU 占用     | < 10%（AVPlayerLayer 渲染）     |
| 启动时间     | < 1 秒                          |

---

## 开发环境

- Xcode 26.x（含 macOS 26 Tahoe SDK）
- Swift 6.3（项目设置为 Swift 5 兼容模式，Phase 3 升级到完整 Swift 6 并发检查）
- 最低部署目标：macOS 14 Sonoma（使用 `@available` 保护 macOS 15+ API）
- 无第三方依赖

**Xcode 项目关键配置**：

| 配置项 | 推荐值 | 说明 |
|--------|--------|------|
| Swift Language Version | Swift 5 | 兼容模式，Phase 3 再迁移到 6 |
| Strict Concurrency Checking | Minimal | 新文件可用 Targeted |
| Optimization Level | -O | Release 构建 |
| Hardened Runtime | 启用 | DMG 分发必需 |
| macOS Deployment Target | 14.0 | 覆盖主流用户 |

---

## 里程碑时间线（参考）

| 里程碑 | 目标                                           |
|--------|------------------------------------------------|
| M0     | 学习 Swift 基础（2 周）：可选类型、ARC、@MainActor |
| M1     | Phase 1 完成，单屏可用                         |
| M2     | Phase 2 完成，多屏 + 能耗                      |
| M3     | Phase 3 完成，Swift 6 迁移 + DMG 打包发布      |

---

## 已知风险与缓解措施

| 风险 | 等级 | 描述 | 缓解措施 |
|------|------|------|---------|
| Swift 6 并发检查 | 🔴 高 | @MainActor 标注繁琐，新手易出错 | MVP 用 Swift 5 兼容模式 |
| 桌面窗口层级 hack | 🟡 中 | `kCGDesktopWindowLevel` 非官方 API，未来 macOS 可能变化 | 目前同类工具（Plash 等）均采用此方案，持续关注 |
| AVPlayerLayer 黑屏闪烁 | 🟡 中 | 切换视频时 `isReadyForDisplay` 短暂为 false（macOS 26 已修复） | 新旧 layer 交替等待就绪再替换 |
| 多显示器复杂场景 | 🟡 中 | Sidecar / Universal Control 虚拟屏干扰 | 用 `NSScreen.localizedName` 过滤 |
| 零 Swift 经验 | 🟡 中 | ARC / 可选类型 / Actor 学习曲线 | 先学基础，Playground 验证再动工 |
