# VibePaper

轻量级 macOS 原生动态壁纸应用。导入 4K 视频，设为桌面壁纸，支持多显示器独立壁纸与低能耗策略。

## 功能

- **动态壁纸播放** — AVFoundation 硬件加速（H.264 / HEVC），GPU 渲染，不占 CPU
- **多显示器独立壁纸** — 每块屏幕可设置不同视频
- **无缝循环** — AVQueuePlayer + AVPlayerLooper，零黑屏切换
- **低能耗策略** — 电池模式自动限制码率（≤ 2 Mbps）+ CADisplayLink 节流 15fps
- **自动暂停** — 锁屏 / 休眠 / 屏幕睡眠时自动暂停，唤醒后恢复
- **一键重置** — 恢复设置前的系统原始壁纸
- **配置持久化** — 重启后自动恢复上次壁纸配置（Security-Scoped Bookmark）
- **播放速率控制** — 0.5x ~ 2x 实时调节
- **开机自启** — SMAppService 登录项管理

## 系统要求

- macOS 14 Sonoma 或更高版本
- Apple Silicon / Intel 均支持

## 快速开始

```bash
git clone https://github.com/yourname/vibe-paper.git
cd vibe-paper
swift run
```

## 构建与发布

```bash
# 开发运行
swift run

# Release 构建 + 打包 .app
make bundle

# 创建 DMG
make dmg

# 完整发布（构建 + 签名 + DMG）
SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" make all

# 公证
APPLE_ID=you@example.com TEAM_ID=XXXXXX APP_PASSWORD=xxxx make notarize
```

## 项目结构

```
Sources/VibePaper/
├── App/
│   ├── VibePaperApp.swift          # @main 入口，MenuBarExtra
│   └── AppDelegate.swift           # 生命周期，版本检查，启动恢复
├── Core/
│   ├── WallpaperWindow.swift       # 桌面级 NSWindow（kCGDesktopWindowLevel）
│   ├── VideoPlayerEngine.swift     # AVQueuePlayer + AVPlayerLooper
│   └── DisplayManager.swift        # 多屏窗口池，休眠/唤醒/屏幕插拔监听
├── UI/
│   ├── MenuBarView.swift           # 菜单栏 Popover
│   └── SettingsView.swift          # 设置窗口（壁纸 / 能耗 / 关于）
├── Models/
│   ├── WallpaperConfig.swift       # 每屏配置（Codable）
│   └── VideoAsset.swift            # 视频文件模型
└── Utilities/
    ├── OriginalWallpaperStore.swift # 原始壁纸快照与还原
    ├── EnergyMonitor.swift          # IOKit 电源状态监听
    ├── ThumbnailGenerator.swift     # 异步缩略图生成
    ├── VideoLibraryStore.swift      # 视频库持久化（Security-Scoped Bookmark）
    ├── WallpaperConfigStore.swift   # 多屏配置持久化（JSON + UserDefaults）
    └── LaunchAtLoginManager.swift   # 开机自启（SMAppService）
```

## 技术方案

| 层面 | 选择 |
|------|------|
| 语言 | Swift 5 兼容模式（@MainActor 关键位置标注） |
| UI | SwiftUI + AppKit |
| 视频引擎 | AVFoundation（AVQueuePlayer + AVPlayerLooper） |
| 渲染 | AVPlayerLayer + CALayer（GPU，零 CPU 合成） |
| 帧率控制 | CADisplayLink.preferredFrameRateRange |
| 构建 | Swift Package Manager |
| 依赖 | 零第三方依赖 |

## 预期性能

| 指标 | 目标 |
|------|------|
| 安装包体积 | < 5 MB |
| 内存占用 | ~30–60 MB |
| CPU 占用 | < 3%（4K HEVC，Apple Silicon） |
| GPU 占用 | < 10% |

## 许可证

MIT
