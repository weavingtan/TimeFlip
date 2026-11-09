# TimeFlip 设计文档

日期：2026-11-09
状态：已确认（设计评审通过）
参考产品：TomatoBar（菜单栏番茄钟）、Desktop Flip Clock（桌面翻转时钟）

## 1. 一句话定位

一个常驻菜单栏的计时器 App，同时能把「剩余倒计时 / 当前时间」以可自由定制的翻转时钟形式挂在 macOS 桌面上。

## 2. 目标与非目标

### 目标（v1）
1. 菜单栏完成一套完整番茄钟：专注/短休/长休、自定义倒计时、跳过/重置、自动接续、结束提示音与通知、全局快捷键、开机自启。
2. 桌面翻转时钟：显示模式可选、形态可选（铺满 / 浮动可拖）、层级可选（贴桌面 / 置顶）、外观可调（样式、字号、背景色与透明度、字体、字体色、阴影）、显示秒/日期/12-24 小时制。
3. 改任何外观设置都实时生效并实时预览，重启后恢复。
4. 在只有 Command Line Tools（无 Xcode）的机器上可构建、可运行。

### 非目标（v1 明确不做）
节假日显示、纪念日/倒数日、屏保接管、iCloud 同步、历史统计报表、主题市场、多语言（v1 仅简体中文，文案集中管理）、App Store 分发与 Developer ID 公证。

## 3. 使用场景

- S1：用户打开 App → 菜单栏出现图标 → 点「开始专注」→ 桌面翻转时钟从当前时间切为 `24:59` 倒计时 → 到点提示音 + 通知 → 自动进入 5 分钟短休。
- S2：用户只想把桌面当时钟看 → 显示内容设为「仅时钟」，桌面挂件显示 `HH:mm:ss` + 日期。
- S3：用户觉得挡视线 → 菜单栏右键 → 层级切「贴桌面」，鼠标穿透，桌面图标与右键菜单照常可用。
- S4：用户想挪位置/改大小 → 「调整桌面时钟位置」→ 窗口进入可拖拽态 → 拖完自动保存。
- S5：用户想要更大更透明 → 设置面板拖动滑杆，桌面上的挂件同步变化。

## 4. 架构总览

单个可执行程序（`swiftc` 直接编译，不用 SwiftPM）+ 打包脚本产出 `.app`。

```
TimeFlipEngine (纯逻辑，无 AppKit)   ←─ swift test 覆盖
    TimerEngine / TimerPhase / Durations / SettingsStore(纯 Codable + 文件读写)
                │ 状态变化通知
                ▼
        AppCoordinator (@MainActor)
   ┌────────────┼─────────────────────┬────────────────┐
   ▼            ▼                     ▼                ▼
StatusItem   FloatingClock      SettingsWindow    SystemIntegration
Controller   WindowController    Controller        (HotKey/Chime/
(NSStatusItem)(NSWindow+SwiftUI) (SwiftUI Form)     Notification/LoginItem)
                     │
                     ▼
              FlipClockView (纯展示，输入 = 数字串 + 外观参数)
```

设计原则：
- **计时与 UI 零耦合**：`TimerEngine` 只依赖注入的 `now: () -> Date`，不 import SwiftUI/AppKit，可在测试里快进时间。
- **展示与窗口零耦合**：`FlipClockView` 只接收 `ClockRenderModel`（字符数组 + 外观），同一份视图在桌面挂件和设置页预览里复用。
- **外观是值类型**：`ClockAppearance` 是 `Codable` 结构体，改一个字段即触发重新渲染，不散落在各视图里。

## 5. 模块规格

### 5.1 TimerEngine（纯逻辑）
状态：`idle` / `focus` / `shortBreak` / `longBreak` / `paused(phase)`。

- 内部只存 `deadline: Date` 与 `pausedRemaining: TimeInterval`，剩余时间每次用 `deadline - now()` 计算，**不做 tick 累加**，睡眠/唤醒后天然正确。
- 对外发布：`remaining`（秒，向上取整）、`phase`、`isRunning`、`completedSessions`、`progress`（0...1）。
- 阶段完成时发出 `PhaseEvent.completed(phase, next: phase?)`，由 AppCoordinator 决定播声音、发通知、按 `autoStart` 决定是否立刻开始。

转换表：

| 当前 | 事件 | 结果 |
|---|---|---|
| idle | start | focus，sessionIndex = 1 |
| focus | 完成 | 若 `sessionIndex % sessionsPerLong == 0` → longBreak，否则 shortBreak；autoStart 开启则立即开始，否则停在 idle 等用户 |
| shortBreak / longBreak | 完成 | 下一轮 focus（sessionIndex + 1）；autoStart 决定是否立即开始 |
| 任意运行中 | pause | paused(phase)，记录剩余秒 |
| paused | resume | 回到原 phase，deadline = now + 剩余 |
| 任意 | skip | 直接完成当前阶段，但**不**播完成音、不计入完成轮次 |
| 任意 | reset | idle，剩余回到 focus 时长，sessionIndex 归零 |
| 任意 | start(custom: minutes) | focus，时长临时替换为自定义值，完成后回 idle 不接续 |

续跑边界：`remaining` 小于 0 时按 0 处理并只触发一次完成事件；连续跨越多个阶段不会自动连环跳（一次 tick 最多推进一个阶段）。

### 5.2 菜单栏 StatusItemController
- `NSStatusItem(variableLength)`；图标为自绘 `NSImage`（模板图），运行中绘制圆环进度 + 右侧等宽数字文本。
- 文本：运行中 `mm:ss`（超过 1 小时用 `h:mm:ss`）；空闲显示当前预设时长；已结束且未重置显示红色。
- 左键点击：`NSPopover`（SwiftUI `MenuPanelView`），内容为阶段名、剩余时间、开始/暂停、跳过、重置、时长快捷切换、自定义分钟输入。
- 右键点击（或长按）：`NSMenu`：设置…、调整桌面时钟位置、显示/隐藏桌面时钟、开机自启（勾选）、退出。
- popover 使用 `.transient` 行为，失焦自动关闭；菜单栏在浅色/深色下都用模板图，避免配色问题。

### 5.3 FloatingClockWindowController
一个 `NSWindow`，`.borderless`、`backgroundColor = .clear`、`isOpaque = false`、`hasShadow = false`（阴影由 SwiftUI 画，便于关掉）。

窗口行为矩阵：

| 维度 | 贴桌面（desktop） | 置顶（floating） |
|---|---|---|
| `level` | `NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)))`（实测 -2147483623，壁纸之上、桌面图标之下） | `.floating` |
| `collectionBehavior` | `[.canJoinAllSpaces, .stationary, .ignoresCycle]` | `[.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]` |
| `ignoresMouseEvents` | `true`（默认穿透，不挡桌面右键与图标） | `false` |
| 拖动 | 仅「调整位置」临时态下允许 | 随时可拖（`isMovableByWindowBackground = true`） |
| 全屏 App 下 | 不可见 | 可见（`fullScreenAuxiliary`） |

- 形态：`fullScreen` = 窗口 frame 取 `NSScreen.frame`，字号按屏宽反算；`floating` = 用户尺寸（宽高由字号推导），位置可拖。
- 默认形态：浮动 + 贴桌面 + 字号 96 + 显示内容 `auto`。
- 多屏：位置按 `CGDisplayCreateUUIDFromDisplayID` 得到的 UUID 存字典；屏幕拔插、分辨率变化时对超出屏幕的坐标做夹取修正。
- 「调整位置」临时态：8 秒可拖 + 虚线描边提示；期间 `ignoresMouseEvents = false`，结束或点击别处后恢复穿透并持久化位置。
- 空间切换、睡眠唤醒后重新 `orderFrontRegardless()`，避免窗口被系统收掉。

### 5.4 FlipClockView / FlipDigitView（展示层）
输入 `ClockRenderModel`：`digits: [Character]`（含 `:`）、`appearance: ClockAppearance`、`isFinished: Bool`。

布局（对应参考截图）：
```
[日期行]  Nov 09 2026                                  Mon        ← 可选
[卡片行]  [1][5] : [3][9] : [2][1]
           每格 = 一张卡片，数字上下两半 + 中间 1px 缝
[底行]    Week 45, Day 9   或   Focus 3/4                        ← 可选
```

- 每个**数字**是一张卡片：上半 + 下半两块，中间一条 1px 分隔缝，卡片圆角 8~12%（随字号）。
- 翻页动画（仅当数字变化时触发，两段式）：
  1. 0→90ms：旧上半绕底边 `rotation3DEffect` 0°→-90°，`perspective 0.55`，渐隐到 0.6；
  2. 90→180ms：新下半 90°→0°，同时新上半立即就位（先显示新上半，避免闪白）。
  - 非动画位直接换字，避免整排跳动。
  - 减少动态效果（系统 `accessibilityReduceMotion`）开启时退化为 120ms 交叉淡入。
- 冒号：默认每 1 秒闪烁（可关），不参与翻转。
- 样式二选一：`flip`（卡片 + 分隔缝）与 `digital`（无卡片、纯文字，背景色不生效）。

显示内容的取值规则（`ShowMode`）：
- `auto`：`focus` / `paused(focus)` → 倒计时剩余 `mm:ss`；`idle` / 休息阶段结束后的空闲 → 当前时间 `HH:mm:ss`（受 `showSeconds` 与 `use24Hour` 影响）。
- `countdownOnly`：始终显示剩余时间；空闲时显示 focus 预设时长。
- `clockOnly`：始终显示当前时间，与计时器状态无关。

### 5.5 ClockAppearance（外观参数）
| 字段 | 类型 | 默认 | 说明 |
|---|---|---|---|
| style | `.flip / .digital` | flip | 卡片式或纯数字 |
| fontFamily | String | `Helvetica Neue` | 取 `NSFontManager.shared.availableFontFamilies`，找不到回退系统字体 |
| fontWeight | bold / heavy / black | heavy | 数字字重 |
| fontSize | 12...400 pt | 96 | 仅浮动模式生效 |
| textColor | hex + alpha | #1A1A1A | 数字颜色 |
| backgroundColor | hex + alpha | #FFFFFF @ 0.90 | 卡片背景 |
| backgroundOpacity | 0...1 | 0.90 | 与背景色 alpha 合并生效 |
| shadowEnabled | Bool | true | 卡片投影 |
| shadowRadius / shadowOpacity | 0...40 / 0...1 | 12 / 0.25 | 投影强度 |
| showSeconds | Bool | true | 仅作用于时钟模式：`HH:mm:ss` → `HH:mm`；倒计时模式恒为 `mm:ss`（秒不可关） |
| showDate | Bool | true | 顶部日期行 |
| showBottomLine | Bool | true | 底部「周/天」或「Focus N/M」 |
| use24Hour | Bool | true | 时钟模式 |
| colonBlink | Bool | true | 冒号闪烁 |
| showLeadingZero | Bool | true | 小时前导零 |

### 5.6 SettingsWindowController
- 普通可缩放窗口（不是面板），左侧 rail + 右侧表单的自绘分段布局（不用系统 TabView，避免样式不可控）：
  1. **计时器**：专注/短休/长休分钟数（1...180）、几轮长休（2...8）、自动开始下一阶段、提示音选择（系统音列表 + 试听）、全局快捷键录制。
  2. **桌面时钟**：显示内容（自动/仅倒计时/仅时钟）、形态（铺满/浮动）、层级（贴桌面/置顶）、样式、字号、背景色+不透明度、字体、字体色、阴影开关与强度、显示秒/日期/底行/24 小时制/冒号闪烁、「调整位置」按钮。页面内嵌一个 1:8 比例的实时预览。
  3. **通用**：开机自启、菜单栏显示样式（图标+时间/仅时间/仅图标）、恢复默认设置。
- 所有改动写回 `SettingsStore`，300ms 防抖落盘；滑杆拖动时窗口实时更新。

### 5.7 系统集成
- **HotKey**：Carbon `RegisterEventHotKey`，默认 `⌃⌥⌘T` 切换开始/暂停；录制时禁用冲突检测失败提示（注册失败弹一次提示并回退默认）。
- **ChimePlayer**：`NSSound(named:)` 播放 `/System/Library/Sounds` 中的音源，可选「无」；提前 0.1s 预热避免首次延迟。
- **通知**：`UNUserNotificationCenter`，授权失败或 `bundleIdentifier` 无效时降级为「播放声音 + 菜单栏图标变红 3 秒 + 桌面时钟短暂闪边框」，功能不阻塞。
- **LoginItem**：`SMAppService.mainApp.register()/unregister()`，状态以系统为准，失败时提示并回滚开关。

## 6. 数据与持久化

- 单一 JSON：`~/Library/Application Support/TimeFlip/settings.json`，`JSONEncoder(outputFormatting: [.prettyPrinted, .sortedKeys])`，原子写。
- 顶层结构：`{ version, timer, appearance, behavior, menuBar, windowPlacements }`。
- `windowPlacements`：`{ [屏幕UUID]: { x, y } }`，只存浮动模式的原点；浮动窗口尺寸由字号推导，铺满模式不使用坐标。
- `version` 用于未来迁移；解码失败 → 备份为 `settings.broken-<timestamp>.json` → 使用默认值，不崩溃。


## 7. 构建与运行

本机实测结论（2026-11-09，仅有 Command Line Tools）：
- `swift build` / `swift test` **不可用**：SwiftPM manifest 链接报 `Undefined symbols: PackageDescription.Package.__allocating_init`。
- `XCTest` 模块**不存在**（`no such module 'XCTest'`），无法用 XCTest 写单测。
- `swiftc` + SwiftUI/AppKit 可正常编译链接，`swiftc` 产物可直接运行。

因此构建与测试都不走 SwiftPM：

- 源码分层（目录即模块边界，不产生 module）：
  - `Sources/TimeFlipEngine/`：纯 Foundation，不得 import SwiftUI/AppKit（构建脚本会 grep 校验）。
  - `Sources/TimeFlip/`：AppKit/SwiftUI 应用层。
- `scripts/build-app.sh`：
  1. `xcrun --sdk macosx swiftc -swift-version 6 -O -parse-as-library Sources/TimeFlipEngine/*.swift Sources/TimeFlip/**/*.swift -o dist/TimeFlip.app/Contents/MacOS/TimeFlip`
  2. 组装 `Contents/{MacOS,Resources}`，写入 `Info.plist`（`LSUIElement=true`、`CFBundleIdentifier=com.weaving.timeflip`、`CFBundleExecutable=TimeFlip`、`NSHighResolutionCapable=true`、`LSMinimumSystemVersion=14.0`、`CFBundleShortVersionString`）
  3. `codesign --force --sign - dist/TimeFlip.app`（ad-hoc）
  4. 产物可直接 `open dist/TimeFlip.app`。
- `scripts/test.sh`：把引擎源码 + `Tests/EngineTests/main.swift` 编译成 `.build/engine-tests` 并运行；测试框架是自写的 30 行断言器（`check` / `expectEqual`），失败以非零码退出。test.sh 必须先跑引擎源码的「禁止 import SwiftUI/AppKit」检查。

## 8. 测试策略

### 单元测试（`scripts/test.sh`，自写断言 runner）
1. 状态机全路径：idle→focus→shortBreak→…→第 4 轮→longBreak→focus。
2. 暂停/恢复保持剩余秒；暂停中 sleep 跨越很长时间后 resume 不跳阶段。
3. 睡眠补时：注入 now 前进 2 小时，remaining 归零且只触发一次 completed。
4. skip 不计入完成轮次、不触发完成音事件。
5. reset 归零并恢复 focus 预设时长。
6. 自定义分钟数（含边界 1 与 180）、非法输入被拒。
7. `SettingsStore` 编解码往返、缺失字段用默认值、损坏 JSON 走兜底。
8. 字号自适应：给定屏宽与位数反算卡片尺寸落在合理区间；极端小屏不出现负值。

### 冒烟（脚本，人工看图）
1. `scripts/build-app.sh && open dist/TimeFlip.app`。
2. 用 `CGWindowListCopyWindowInfo` 断言存在 owner=TimeFlip 的窗口，层级等于桌面层（-2147483623），尺寸等于主屏 frame。
3. `screencapture` 抓桌面 → 人工确认翻转卡片、日期行、配色。
4. 切「置顶 + 浮动」后再次断言层级 = 3、尺寸变化，抓图确认。
5. 菜单栏：抓取菜单栏区域截图确认圆环进度与倒计时文本。
6. 清理：退出 App 前恢复默认设置，避免污染用户配置。

### 手动验收清单（写进 README 前不单独建文档）
自动开始、声音、通知降级、快捷键、开机自启、多屏拖动记忆、桌面穿透。

## 9. 风险与对策

| 风险 | 影响 | 对策 |
|---|---|---|
| 桌面层窗口在部分系统版本被 Finder 图标窗口盖住 | 挂件不可见 | 已确认层级常量；若被盖，回退到 `desktopIcon + 1` 并把图标区域让开（顶部/右下留边距） |
| ad-hoc 签名下通知授权失败 | 无系统通知 | 已设计降级：声音 + 图标变红 + 闪边框 |
| 全屏 App / 多空间下窗口丢失 | 挂件消失 | `canJoinAllSpaces` + 空间切换通知里 `orderFrontRegardless` |
| SwiftUI 3D 动画在低端机掉帧 | 翻页卡顿 | 只动画变化位、固定 180ms、必要时降级为淡入 |
| 全局快捷键被占用 | 快捷键无效 | 注册失败提示并提供备选组合 |

## 10. 里程碑（实现顺序）

1. **M1 引擎**：`TimeFlipEngine` + `scripts/test.sh` 全部用例绿灯。
2. **M2 菜单栏**：StatusItem + 弹窗 + 右键菜单，可用键盘驱动。
3. **M3 桌面挂件**：窗口层级/穿透/拖动 + FlipClockView 静态渲染 + 翻页动画。
4. **M4 设置**：三页设置面板 + 实时预览 + 持久化 + 多屏位置。
5. **M5 系统集成**：快捷键、提示音、通知降级、开机自启。
6. **M6 打包与冒烟**：build-app.sh、冒烟脚本、层级与截图核对。
