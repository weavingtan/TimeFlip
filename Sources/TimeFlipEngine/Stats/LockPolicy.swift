import Foundation

/// 阶段结束时该做什么：要不要铺休息遮罩、要不要锁屏、锁屏前等几秒。
public struct LockAction: Equatable, Sendable {
    public var overlay: Bool
    public var lock: LockStyle?
    public var delaySeconds: Int

    public init(overlay: Bool, lock: LockStyle?, delaySeconds: Int) {
        self.overlay = overlay
        self.lock = lock
        self.delaySeconds = delaySeconds
    }

    public static let none = LockAction(overlay: false, lock: nil, delaySeconds: 0)

    public var doesNothing: Bool { lock == nil && !overlay }
}

/// 锁屏决策：全部是纯逻辑，方便对着边界情况写断言。
public enum LockPolicy {
    /// tick 间隔超过这个秒数就认为刚从睡眠/休眠回来。
    public static let wakeGapThreshold: TimeInterval = 20

    public static func action(
        settings: LockSettings,
        finishedPhase: TimerPhase,
        isCustom: Bool,
        wokeFromSleep: Bool,
        hasFullScreenApp: Bool
    ) -> LockAction {
        // 休息结束不锁屏：睡着/开会时把屏幕锁掉只会让人以为 App 疯了。
        guard finishedPhase == .focus else {
            return LockAction(overlay: settings.overlayEnabled, lock: nil, delaySeconds: 0)
        }

        // 自定义倒计时常用于会议、演讲、煮东西，锁屏是灾难，只铺遮罩。
        if isCustom {
            return LockAction(overlay: settings.overlayEnabled, lock: nil, delaySeconds: 0)
        }

        // 刚从睡眠醒来：用户根本不知道计时已经结束，不能直接黑屏。
        if wokeFromSleep {
            return LockAction(overlay: settings.overlayEnabled, lock: nil, delaySeconds: 0)
        }

        // 前台是全屏应用（演示 / 录屏 / 视频）时不打扰。
        if hasFullScreenApp, settings.skipWhenFullScreenApp {
            return LockAction(overlay: settings.overlayEnabled, lock: nil, delaySeconds: 0)
        }

        guard settings.isEnabled else {
            return LockAction(overlay: settings.overlayEnabled, lock: nil, delaySeconds: 0)
        }

        return LockAction(
            overlay: settings.overlayEnabled,
            lock: settings.style,
            delaySeconds: min(60, max(0, settings.graceSeconds))
        )
    }
}
