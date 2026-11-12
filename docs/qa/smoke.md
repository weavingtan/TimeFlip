# TimeFlip 冒烟记录

日期：2026-11-09
环境：macOS 15.6.1 (24G90)、Apple Silicon、Swift 6.1.2、仅 Command Line Tools（无 Xcode）
主屏：1728×1117 pt（Retina 3456×2234）

## 自动化结果

| 项目 | 命令 | 结果 |
|---|---|---|
| 引擎断言 | `./scripts/test.sh` | ALL 97 CHECKS PASSED |
| 离屏渲染 | `--render-preview` / `--render-settings` | 8 张 PNG 全部产出 |
| 贴桌面 + 浮动 | `./scripts/smoke.sh` | level=-2147483602，575×219，onscreen=true，菜单栏窗口 4 个，hotkey registered=true |
| 贴桌面 + 铺满 | `./scripts/smoke.sh` | level=-2147483602，1728×1117（= 主屏），onscreen=true |
| 拖拽层命中 | `TimeFlip --selftest-hit` | `hit=DragCatcherView`、`catcherHidden=false` |
| 翻页几何 | `--render-preview` 的 `5-flip-angles.png` | 0° / -45° / -90° / -135° / -180° 定格检查通过（旧上半翻下、新下半翻起、阴影随角度加深） |
| 设置还原 | smoke cleanup | settings.json 已还原，App 已退出 |

`--window-check` 的判定：窗口层级、是否在屏、alpha、尺寸、菜单栏状态项窗口存在；铺满模式尺寸与主屏一致（误差 ≤2pt）。

## 关键结论

1. **贴桌面层级必须是 `kCGDesktopIconWindowLevel + 1`（-2147483602）**。
   实测 Finder 的桌面窗口在 -2147483603，而 `kCGDesktopWindowLevel` 是 -2147483623，
   直接用后者会被 Finder 完整遮住；改用 `desktopIcon + 1` 后 `occlusionState` 报告未被遮挡，
   且仍远低于普通窗口（0），不会挡住任何 App。
2. **本机 `screencapture` 只输出壁纸**（屏幕录制权限未授予），因此视觉核对全部走 App 自带的
   `ImageRenderer` 离屏渲染，不依赖系统权限。
3. 菜单栏状态项在运行中为「圆环进度 + mm:ss」，阶段结束未重置时数字变红。
4. 全局快捷键 `⌃⌥⌘T` 注册成功（Carbon，不需要辅助功能权限）。
5. **拖拽改成随时可用**：窗口用 `NSPanel + .nonactivatingPanel`（点击不抢前台），内容之上盖 `DragCatcherView`（`acceptsFirstMouse` + `performDrag`），不再需要「调整桌面时钟位置」模式。
6. **位置只在首次布局 / 尺寸变化 / 形态切换时应用**。此前每秒刷新都会按配置重设 frame，会把拖动中的窗口拽回原处；现在用 `lastAppliedFrame` 过滤程序化移动，拖动结束 0.35s 后再夹回屏幕并持久化。
7. 翻页动画改为 `KeyframeAnimator` 单条角度曲线（0 → -90 → -180，280ms），替换掉原来两段 `DispatchQueue` 拼接（中缝错位、角度跳变）。

## 仍未覆盖（需要人工点一遍）

- 菜单栏左键弹窗 / 右键菜单的实际点击（脚本无法定位状态项按钮）
- 真实鼠标拖动与位置记忆（自动合成鼠标事件会被前台窗口截获，且当前可能处于全屏 Space；已用 `hitTest` 断言拖拽层在最上层）
- 阶段结束的提示音、系统通知（ad-hoc 签名下授权可能被拒，走降级路径）
- 登录时自动启动（`SMAppService` 需要真实 App 路径，冒烟运行的是 bundle 内二进制，未切换）
- 多显示器拖动与跨空间表现
- 翻转动画的观感（静态图无法验证，需肉眼）

## 人工验收步骤

1. `open dist/TimeFlip.app`，确认菜单栏出现圆环 + `25:00`。
2. 左键点图标 → 面板点「开始」→ 菜单栏开始倒计时，桌面右下角出现翻转时钟。
3. 设置 → 桌面时钟：拖字号、改透明度/颜色/字体、切「纯数字」、切「始终置顶」，观察实时变化。
4. 切「铺满屏幕」，确认整屏翻转时钟且不挡其他窗口（切到别的 App 看它是否被盖住）。
5. 切回「浮动窗口」→ 直接按住时钟拖到别处（不需要任何按钮）→ 松手后确认菜单栏 App 没有被切走 → 重启 App 确认位置保留。
6. 选 5 分钟快捷倒计时等结束，确认提示音、菜单栏变红、通知（若授权）。

## 2026-11-12 UI 优化回归

改动范围：新增 `Sources/TimeFlip/Design/Theme.swift`（阶段配色与按钮/卡片样式），重做菜单栏弹窗与设置面板，
翻转卡片加卡面渐变与中缝；顺带修了每秒重复刷新菜单栏/挂件、铺满字号按主屏而非挂件所在屏、字号滑杆不吸附、
设置面板每次重绘都枚举字族与系统音效目录等问题。

| 项目 | 命令 | 结果 |
|---|---|---|
| 引擎断言 | `./scripts/test.sh` | ALL 97 CHECKS PASSED |
| 端到端冒烟 | `./scripts/smoke.sh` | SMOKE PASSED（floating 575×219、full 1728×1117、设置窗口 1 个、HITTEST=DragCatcherView、DRAGTEST stayed/resized/saved 全 true）|
| 弹窗渲染 | `--render-settings` | menu-panel / -idle / -break / -finished 四种状态都排版完整、无截断 |
| 设置面板渲染 | `--render-settings` | 三页整页渲染（860×1000），卡片齐全（Picker/Slider/Toggle/TextField 显示为黄色占位块属正常）|
| 真实配置渲染 | `--render-preview` | `6-current-settings.png` 读本机 settings.json 出图，用于核对实际观感 |

已知观感问题（本轮未动动画几何）：翻页动画在 90°–180° 段，卡片底部约 12–16% 会短暂偏亮。
原因：`rotation3DEffect(perspective:)` 让翻页面靠观察者的一边被放大，实际投影高度大于 `cos θ`，
而"揭开"的裁剪量按 `1 - cos θ` 算，两者对不齐。静态图在 -120° 可复现；要修需要按真实投影重算裁剪，
风险高于收益（会牵动已修好的"翻页面与卡面互补、不重影"逻辑），暂记在此。

## 2026-11-12 代码评审回归（引擎健壮性 + 挂件交互）

改动范围：设置解码逐字段兜底、时长/轮次夹取（杜绝 `% 0` 崩溃与 0 分钟死循环）、暂停后跳过的时长口径、
自定义倒计时不计轮次/连续天数、换自定义倒计时不再静默丢阶段、主题导入保留用户字号、
保存统计图取消不再报错、铺满模式鼠标穿透且按挂件所在屏算字号、休息遮罩不抢焦点、
恢复默认设置先确认并复位轮次与位置、12 小时制空格不再画成空白卡、去掉每秒重复刷新与热键重复注册、
统计改为按天建桶（原为 O(天数 × 记录数)）。

| 项目 | 命令 | 结果 |
|---|---|---|
| 引擎断言 | `./scripts/test.sh` | ALL 244 CHECKS PASSED（新增 7 组 / 35 项：非法时长夹取、暂停跳过时长、换自定义收尾、段内字段缺失、无提示音往返、自定义不计轮次、非法窗口坐标）|
| 端到端冒烟 | `./scripts/smoke.sh` | SMOKE PASSED（floating 550×190、full 1728×1117、设置窗口 1 个、HITTEST=DragCatcherView、DRAGTEST stayed/resized/saved 全 true）|
| 12 小时制样图 | `--render-preview` | 新增 `4b-clock-12h.png`，冒烟脚本断言其产出；空格是间隙，不再出现空白卡 |

仍需人工确认（脚本覆盖不到）：

- 铺满模式下桌面图标点击 / 桌面右键是否真的穿透（窗口已设 `ignoresMouseEvents`，但只有真人点击能证）
- 休息遮罩改成 `.nonactivatingPanel` 且不再 `activate` 后，「提前结束休息」是否一次点中就生效
- 恢复默认设置的确认框与随之发生的窗口归位
