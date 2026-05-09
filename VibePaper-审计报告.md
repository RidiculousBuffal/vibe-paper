# VibePaper 技术方案审计报告

> **审计日期**：2026-05-09  
> **当前最新 Swift 版本**：Swift 6.3（2026-03-24 发布）  
> **当前最新 Xcode 版本**：Xcode 26.x（26.2/26.3）  
> **当前最新 macOS 版本**：macOS 26 Tahoe（26.5 RC）  
> **方案原始目标**：Swift 5.9+ / Xcode 15+ / macOS 14 Sonoma

---

## 一、总体评估

### 🟡 结论：方案核心思路稳健，但存在 **3 个关键风险** 和若干需要更新的地方

PLAN 的技术选型（SwiftUI + AppKit + AVFoundation）在 2026 年依然是最佳路线。窗口层级方案（`kCGDesktopWindowLevel`）和 `NSWorkspace` 壁纸 API 均未变化。但 Swift 已从 5.9 跨越到 6.3，**并发模型的重大变更** 对你这样的 Swift 新手来说是需要特别关注的风险点。

---

## 二、版本更新对照

| 项目 | PLAN 目标 | 当前最新 | 差距 | 风险等级 |
|------|----------|---------|------|---------|
| Swift 语言 | 5.9+ | **6.3** | 3 个大版本 | 🔴 高 |
| Xcode IDE | 15+ | **26.x** | 跨越多个大版本 | 🟡 中 |
| macOS 最低系统 | 14 Sonoma | **26 Tahoe** | 2 个大版本 | 🟡 中 |

---

## 三、关键 API 审计

### 3.1 ✅ 无变化的 API（可直接使用）

| API | 用途 | 状态 |
|-----|------|------|
| `NSWorkspace.shared.desktopImageURL(for:)` | 获取当前壁纸路径 | ✅ 未变，主线程调用即可 |
| `NSWorkspace.shared.setDesktopImageURL(_:for:options:)` | 设置壁纸 | ✅ 未变，支持 throws |
| `CGWindowLevelForKey(.desktopWindow)` | 获取桌面层级常量 | ✅ 未变，返回 `CGWindowLevel` |
| `NSWindow.Level` | 窗口层级封装 | ✅ 未变 |
| `NSScreen.screens` | 获取所有屏幕 | ✅ 未变 |
| `AVPlayer` / `AVPlayerLayer` | 视频播放与渲染 | ✅ 核心 API 未变 |
| `AVAsset` / `AVAssetImageGenerator` | 视频元数据/缩略图 | ✅ 未变 |
| `NotificationCenter` 相关通知 | 屏幕/休眠监听 | ✅ 通知名称未变 |
| `SMAppService` | 开机自启 (macOS 13+) | ✅ 推荐方案，成熟稳定 |
| `UserDefaults` | 配置持久化 | ✅ 未变 |
| `Security-Scoped Bookmark` | 文件访问权限（DMG 分发） | ✅ 未变 |

### 3.2 ⚠️ `preferredTimescale` 帧率限制方案 — **需要修正**

**你的方案中写道**：
> 电池模式：通过 `preferredTimescale` 限制帧率（30fps → 15fps）

**问题**：`preferredTimescale` 是 `AVAsset` 的属性，它控制的是**时间精度**（每秒的刻度数），不是帧率。将其设为 15 意味着时间以 1/15 秒为最小单位，但**不会限制播放帧率**。

**正确的能耗优化方案**：

```swift
// 方案一：降低播放速率（最简单）
player.rate = 0.5  // 半速播放，仅适用于特定场景

// 方案二：限制 AVPlayerItem 的峰值码率（更实用）
let item = AVPlayerItem(asset: asset)
item.preferredPeakBitRate = 2_000_000  // 限制为 2Mbps

// 方案三：使用 AVAssetReader + 自定义帧率（复杂但精确）
// 按需解码、跳过帧，适合深度能耗优化
```

**建议**：MVP 阶段先用 `preferredPeakBitRate` 控制码率降低解码负载，Phase 2 再考虑自定义帧率渲染。这对性能目标影响有限，但文档需要修正以免误导。

### 3.3 🔴 Swift 6 严格并发检查 — **最大风险点**

这是对你（零 Swift 经验者）最大的挑战。

**背景**：Swift 6.0（2024-09-17 发布）开始**默认启用完整的数据竞争安全检查（Swift 6 Language Mode）**。此前的 Swift 5.x 只在 Debug 模式做部分检查，Release 不做。现在所有构建模式都强制检查。

**对你的项目影响**：

你的方案大量使用 AppKit（actor-bound to MainActor）和 SwiftUI，这意味着：

```swift
// ❌ 在 Swift 6 中，以下代码可能编译失败
class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Swift 6 需要明确标记哪些代码在主线程执行
    }
}

// ✅ 需要显式添加 @MainActor
@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // 现在编译器知道这一定在主线程
    }
}
```

**具体影响清单**：

| 文件 | 涉及组件 | 需要处理 |
|------|---------|---------|
| `VibePaperApp.swift` | `MenuBarExtra`, `@main` | `@MainActor` 标注（SwiftUI 自动处理大部分） |
| `AppDelegate.swift` | `NSApplicationDelegate` | 显式 `@MainActor` |
| `WallpaperWindow.swift` | `NSWindow` 子类 | `NSWindow` 本身已 main-actor-bound |
| `VideoPlayerEngine.swift` | `AVPlayer` 回调 | `@MainActor` + `Sendable` 适配 |
| `DisplayManager.swift` | `NSScreen` 遍历 | 线程安全检查 |
| `OriginalWallpaperStore.swift` | `NSWorkspace` 调用 | 强制主线程 |
| `EnergyMonitor.swift` | 电源状态监听 | 回调需标注 actor |
| `ThumbnailGenerator.swift` | `AVAssetImageGenerator` | `generateCGImagesAsynchronously` 是异步的 |

**应对建议**：
- Swift 6 提供向后兼容模式：可在 Xcode 中将 **Swift Language Version** 设为 **Swift 5**，这会保留 Swift 5 的宽松并发检查，让你渐进式迁移。
- 考虑到你是 Swift 新手，**强烈建议 MVP 阶段使用 Swift 5 兼容模式**，Phase 3 再迁移到 Swift 6 完整并发检查。

---

## 四、macOS 版本与分发策略

### 4.1 最低系统版本建议

| 选项 | 版本 | 用户覆盖率 | 优势 |
|------|------|-----------|------|
| 原方案 | macOS 14 Sonoma | ~高 | 兼容面广 |
| 建议 | **macOS 15 Sequoia** | ~较高 | API 更稳定，Xcode 26 调试友好 |
| 激进 | macOS 26 Tahoe | ~低 | 可使用 Liquid Glass 新设计 |

**建议**：保持 **macOS 14 Sonoma** 作为最低版本是合理的，能覆盖绝大多数用户。但开发时应使用 **Xcode 26 + macOS 26 SDK** 编译，通过 `@available` 做 API 可用性检查。

### 4.2 DMG 分发注意事项

你的方案走 DMG 直接分发（无 App Store 沙箱），这个路线在 2026 年依然有效。但需要注意：

- **代码签名**：`codesign` + `notarytool` 是必需的，否则 macOS Gatekeeper 会阻止运行
- **Hardened Runtime**：需要启用并配置正确的 entitlements
- **Security-Scoped Bookmark**：由于不走沙箱，文件访问权限相对宽松，但 Bookmark 仍是保证跨启动访问的好实践

---

## 五、方案架构审计

### 5.1 ✅ 架构亮点

1. **零第三方依赖**：非常正确的决策，Swift 标准库 + 系统框架完全够用
2. **AppKit 桥接思路**：SwiftUI 写 UI + AppKit 管底层窗口是最佳实践
3. **AVPlayerLayer 直接挂 CALayer**：避免了 CPU → GPU 的数据拷贝，能耗最优
4. **Security-Scoped Bookmark**：考虑周全，DMG 分发场景下保证文件路径稳定性
5. **模块分层清晰**：App / Core / UI / Models / Utilities 职责分明

### 5.2 ⚠️ 架构需要关注的点

1. **WallpaperWindow 层级方案的风险**
   - `kCGDesktopWindowLevel` 设置窗口到桌面图标层之下，这个技巧在 macOS 14~26 均有效
   - 但它是 **非官方支持的行为**（Apple 从未文档化"在桌面下放置视频窗口"），未来 macOS 更新可能改变窗口层级行为
   - 已知的替代方案：macOS 原生 `.heic 动态壁纸` 格式，但它不支持视频
   - **结论**：当前无更好替代方案，这是同类软件（如 Plash、Dynamic Wallpaper Engine）的通用做法

2. **多显示器管理**
   - `NSScreen.screens` 在 Sidecar / Universal Control 场景下行为复杂
   - 需要区分物理显示器和虚拟显示器
   - 建议增加 `NSScreen` 的 `localizedName` 过滤

### 5.3 功能优先级调整建议

根据 2026 年 macOS 生态现状，建议微调优先级：

```
Phase 1 — 建议保持原样
  ✅ MenuBarExtra + 设置窗口
  ✅ 导入视频 + 桌面窗口播放
  ✅ 原始壁纸快照 + 一键重置
  ✅ 开机自启

Phase 2 — 建议增加
  ⬆️ 多显示器管理
  ⬆️ 能耗策略（修正 preferredTimescale 方案）
  ➕ macOS 15+ 动态壁纸格式兼容（读取系统原生的 .heic 动态壁纸）

Phase 3 — 原样保持
  ✅ ProRes / VP9 支持
  ✅ 播放速度控制
  ✅ DMG 打包
```

---

## 六、对你（Swift 新手）的特别建议

考虑到你只有 Node.js 和 Java 背景，以下是你需要提前了解的关键差异：

| 概念 | Node.js/Java | Swift | 学习要点 |
|------|-------------|-------|---------|
| 内存管理 | GC 自动 | ARC 引用计数 | 理解 strong/weak/unowned 引用 |
| 可选类型 | null / Optional | `?` / `!` | 强制解包是最常见崩溃原因 |
| 并发模型 | Promise/async | `async/await` + Actor | Swift 6 的更严格，编译时检查 |
| 值类型 vs 引用类型 | 类=引用 | struct=值, class=引用 | struct 赋值是拷贝，与 Java 截然不同 |
| 协议 | Interface | Protocol | 类似但更强大，支持关联类型 |
| 错误处理 | try-catch | `do-try-catch` 或 `throws` | `try?` 和 `try!` 的区别 |

**推荐学习路径**（按优先级）：

1. **The Swift Programming Language**（官方书，免费）：至少读完前 15 章
2. **100 Days of SwiftUI**（Paul Hudson）：前 20 天足够开始写这个项目
3. 用 Playground 先写简单的 AVPlayer Demo，别一上来就搭整个架构

---

## 七、修正后的开发环境配置

```yaml
语言:      Swift 6.3（建议 MVP 阶段用 Swift 5 兼容模式）
IDE:       Xcode 26.2+ 
SDK:       macOS 26 SDK
最低部署:  macOS 14 Sonoma
包管理:    Swift Package Manager（无第三方依赖）
构建:      xcodebuild（Release 配置）
分发:      DMG + codesign + notarytool
```

**Xcode 项目配置建议**：
- Swift Language Version：Swift 5（兼容模式，渐进迁移到 6）
- Strict Concurrency Checking：Minimal（Targeted 可用于新文件）
- Optimization Level：-O（Release）

---

## 八、风险总结

| 风险 | 等级 | 描述 | 缓解措施 |
|------|------|------|---------|
| Swift 6 并发检查 | 🔴 高 | 对新手最不友好，大量代码需标注 @MainActor | MVP 阶段使用 Swift 5 兼容模式 |
| preferredTimescale 方案错误 | 🟡 中 | 不会真的限制帧率，文档需修正 | 改用 preferredPeakBitRate |
| 桌面窗口层级 hack | 🟡 中 | 非官方支持行为，未来 macOS 可能变化 | 目前无替代方案，持续关注 Apple 动态 |
| 版本跨度大 | 🟡 中 | SDK 从 14 到 26，API 可能有细微差异 | @available 保护 + 真机测试 |
| 零 Swift 经验 | 🟡 中 | 学习曲线陡峭，ARC/可选类型易踩坑 | 先学基础再动工，MVP 目标保守 |

---

## 九、最终评级

| 维度 | 评分 | 说明 |
|------|------|------|
| 技术选型 | ⭐⭐⭐⭐⭐ | 仍然最优，无更好的替代方案 |
| 架构设计 | ⭐⭐⭐⭐☆ | 分层清晰，细节可优化 |
| API 有效性 | ⭐⭐⭐⭐☆ | 核心 API 未变，帧率方案需修正 |
| 版本时效性 | ⭐⭐☆☆☆ | 版本信息严重过时，需全面更新 |
| Swift 新手友好度 | ⭐⭐☆☆☆ | Swift 6 并发模型对新人不友好 |

**总体评价**：方案的核心技术思路完全可行，但这是一个"2023 年的方案要在 2026 年实施"的情况。版本信息需要全面更新，`preferredTimescale` 方案需要修正，Swift 6 并发是你需要重点学习的部分。**建议先花 2 周学习 Swift 基础，然后用 Swift 5 兼容模式开始 MVP，逐步迁移到 Swift 6 完整并发检查。**

---

> **参考来源**：
> - [Swift 6.3 Released — Swift.org](https://www.swift.org/blog/swift-6.3-released/) (2026-03-24)
> - [Swift 6.2 Released — Swift.org](https://www.swift.org/blog/swift-6.2-released/) (2025-09-15)
> - [WWDC25: What's New in Swift 6.2 — Appcircle](https://appcircle.io/blog/wwdc25-whats-new-in-swift-6-2)
> - [Swift 6.3 New Features — SwiftProgramming.com](https://swiftprogramming.com/whats-new-swift-63/)
> - [Swift 6.3 Stabilizes Android SDK — InfoQ](https://www.infoq.com/news/2026/04/swift-6-3-android-c-interop/)
> - [macOS Wallpaper API 调查 — GitHub](https://github.com/FactrueSolin/Smart-Wallpaper/blob/main/docs/macos-wallpaper-api.md)
> - [Apple Developer — macOS Release Notes](https://developer.apple.com/documentation/macos-release-notes)
> - [Apple Developer — Swift Updates](https://developer.apple.com/documentation/updates/swift)
> - [Apple Developer — macOS Tahoe](https://www.apple.com.cn/macos/big-sur)
