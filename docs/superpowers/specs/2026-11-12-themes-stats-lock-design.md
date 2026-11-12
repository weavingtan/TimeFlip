# TimeFlip v1.2 设计：主题包 / 统计分享 / 强制休息

日期：2026-11-12
状态：已确认（用户批准方向：8 套预设 + 主题 JSON 互传 + 统计分享图 + 可配置锁屏）

## 1. 一句话目标

把 TimeFlip 从「能定制的翻转时钟」变成「默认就很好看的桌面专注仪表」：
预设主题降低调参门槛，会话数据沉淀成资产，结束时的强制休息把专注变成可执行的约束。

## 2. 范围

| 模块 | 内容 |
|---|---|
| 视觉重做 | 翻牌机的物理感：数字撑满卡片、卡片 3:4、缝三件套、机身托盘、受光渐变、双层投影、翻转压暗 |
| 主题包 | 8 套预设一键切换；当前外观可选导入/导出为 JSON（文件 + 剪贴板），无服务端 |
| 统计 | 本地会话记录（`sessions.json`）、每日目标、连续天数、14 天柱状/热力、最佳时段、中断率、分享竖图 |
| 强制休息 | 三档：仅提醒 / 全屏休息遮罩 / 结束时锁屏；宽限期可取消；睡眠唤醒与全屏应用下不锁 |

非目标：云同步、账号、主题市场服务端、屏保 bundle、订阅制。

## 3. 数据模型（Engine 层，纯 Foundation）

### 3.1 外观扩展

`ClockAppearance` 新增字段（解码缺失时用默认值，保证旧 settings.json 可用）：

- `material: ClockMaterial`：`paper / glass / metal / wood / pixel`，决定卡面材质与圆角
- `showChassis: Bool`：是否画机身托盘
- `themeID: String?`：当前选中的预设 id（仅用于 UI 高亮，不参与渲染）

### 3.2 主题

```swift
struct ThemePreset { id, name, subtitle, appearance }
ThemePreset.all          // 8 套：cream/neon/film/newsprint/frosted/wood/pixel/minimal
preset.apply(to:)        // 应用时保留用户字号，其余外观整体替换
struct ThemeDocument { schema, name, appearance }
  .encoded()             // 单行 JSON，可直接粘进聊天
  ThemeDocument.decode(_:) // 容忍前后噪音、缺字段、越界（clamp）
```

### 3.3 会话与统计

```swift
struct SessionRecord { id, startedAt, endedAt, phase, plannedSeconds, actualSeconds, completed, isCustom }
final class SessionLog   // 读写 sessions.json；损坏时备份并回退空表；保留 365 天
struct FocusStats.make(records:goal:now:calendar:)
  // todaySessions/todayFocusSeconds/weekFocusSeconds/totalFocusSeconds
  // streakDays（今天无记录则从昨天起算）、last14Days、bestHour、interruptionRate
```

只记录 `focus` 阶段（含自定义倒计时）；`completed=false` 用于统计中断率。

### 3.4 锁屏策略（可测的纯逻辑）

```swift
enum LockStyle { off, displaySleep, lock }
struct LockSettings { style, graceSeconds, overlayEnabled, skipWhenFullScreenApp }
struct LockAction  { overlay: Bool, lock: LockStyle?, delaySeconds: Int }
LockPolicy.action(settings:finishedPhase:isCustom:wokeFromSleep:hasFullScreenApp:)
```

规则（优先级从高到低）：

1. 非专注阶段完成 → 只做休息遮罩，绝不锁屏
2. 刚从睡眠唤醒（tick 间隔 > 20s）→ 只做遮罩，绝不锁屏
3. 前台是全屏应用且开关打开 → 只做遮罩
4. `style == .off` → 只有遮罩
5. 否则 `delaySeconds = graceSeconds`，到点执行 `style`

## 4. 系统实现（App 层）

### 4.1 锁屏

macOS 15 已移除 `CGSession -suspend` 与 `login.framework` 的 `SACLockScreenImmediate`，实测本机：

- `pmset displaysleepnow`：无需权限，关屏（系统设置「需要密码」为立即时即锁屏）
- `CGEvent` 发 `⌃⌘Q`：真锁屏，需一次性「辅助功能」授权

`ScreenLocker`：`.lock` 优先 CGEvent（未授权则 `AXIsProcessTrustedWithOptions` 提示一次后降级），
任一失败降级 `pmset displaysleepnow`，再失败降级为全屏遮罩并在菜单栏标红。

### 4.2 休息遮罩

每个屏幕一个无边框 `NSPanel`（`.statusBar` 层级、`canJoinAllSpaces`、非激活），
显示休息倒计时、呼吸引导圈与「提前结束」按钮；休息阶段结束自动关窗。

### 4.3 宽限期

专注完成后弹出居中置顶小窗：`N 秒后锁屏` + 「再等 5 分钟」（重新开始 5 分钟自定义倒计时）+「立即锁屏」。
`graceSeconds == 0` 时直接执行。

### 4.4 分享图

`ShareCardRenderer` 用 `ImageRenderer` 画 540×675（@2x → 1080×1350）竖图：
品牌行、本周专注时长、连续天数、目标达成、14 天柱状。
可保存到桌面（NSSavePanel）或直接写入剪贴板（`NSPasteboard`）。

## 5. 测试

`scripts/test.sh` 新增断言：

- 8 套预设 id 唯一、外观数值全部在合法区间
- 应用预设保留用户字号
- 主题 JSON 往返、容忍噪音、越界 clamp、非法输入返回 nil
- 会话写入/读回、损坏回退、365 天裁剪
- 今日/本周时长、连续天数（含今天没记录的情况）、中断率、最佳时段
- 锁屏策略 6 种组合（休息不锁、唤醒不锁、全屏不锁、关闭、宽限、立即）

`scripts/smoke.sh` 增加离屏渲染产物断言：主题条、分享卡、休息遮罩。

## 6. 兼容与风险

- `settings.json` 新增字段全部走「缺失即默认」，老文件直接可用；`version` 仍为 1
- 辅助功能未授权时锁屏降级为关屏，设置页显示授权状态与按钮
- 无密码账户锁屏后形同未锁 → 设置页提示
- `pmset` 在少数企业策略下可能被禁用 → 失败提示而非静默
