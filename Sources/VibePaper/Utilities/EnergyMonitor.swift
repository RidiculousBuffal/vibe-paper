import Foundation
import IOKit.ps

/// 电源状态监听 —— 检测是否处于电池供电模式
/// 使用 IOKit Power Source Notifications（轻量级，无需轮询）
@MainActor
final class EnergyMonitor {

    static let shared = EnergyMonitor()

    /// 电源状态变化通知（在主线程 post）
    static let powerStateChangedNotification = Notification.Name("VibePaper.PowerStateChanged")

    private(set) var isOnBattery: Bool = false

    private var runLoopSource: CFRunLoopSource?

    // MARK: - Init

    private init() {
        refreshState()
        startObserving()
    }

    // MARK: - Private

    private func startObserving() {
        // 使用 C 回调 + retained self 指针
        let selfPtr = Unmanaged.passRetained(self).toOpaque()
        let src = IOPSNotificationCreateRunLoopSource(
            { ctx in
                guard let ctx else { return }
                // 在主线程调度，避免 MainActor 隔离问题
                let monitor = Unmanaged<EnergyMonitor>.fromOpaque(ctx).takeUnretainedValue()
                DispatchQueue.main.async {
                    monitor.refreshState()
                    NotificationCenter.default.post(name: EnergyMonitor.powerStateChangedNotification, object: nil)
                }
            },
            selfPtr
        )
        if let src {
            let retained = src.takeRetainedValue()
            CFRunLoopAddSource(CFRunLoopGetMain(), retained, .defaultMode)
            runLoopSource = retained
        }
    }

    private func refreshState() {
        let snapshot = IOPSCopyPowerSourcesInfo().takeRetainedValue()
        let list = IOPSCopyPowerSourcesList(snapshot).takeRetainedValue() as [CFTypeRef]

        var onBattery = false
        for src in list {
            guard let info = IOPSGetPowerSourceDescription(snapshot, src)
                .takeUnretainedValue() as? [String: Any],
                  let transport = info[kIOPSTransportTypeKey] as? String,
                  transport == kIOPSInternalType,
                  let state = info[kIOPSPowerSourceStateKey] as? String
            else { continue }
            onBattery = (state == kIOPSBatteryPowerValue)
            break
        }
        isOnBattery = onBattery
    }

    deinit {
        if let src = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), src, .defaultMode)
        }
    }
}
