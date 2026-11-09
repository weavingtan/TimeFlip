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

## 仍未覆盖（需要人工点一遍）

- 菜单栏左键弹窗 / 右键菜单的实际点击（脚本无法定位状态项按钮）
- 「调整桌面时钟位置」8 秒拖拽态的真实拖动与位置记忆
- 阶段结束的提示音、系统通知（ad-hoc 签名下授权可能被拒，走降级路径）
- 登录时自动启动（`SMAppService` 需要真实 App 路径，冒烟运行的是 bundle 内二进制，未切换）
- 多显示器拖动与跨空间表现
- 翻转动画的观感（静态图无法验证，需肉眼）

## 人工验收步骤

1. `open dist/TimeFlip.app`，确认菜单栏出现圆环 + `25:00`。
2. 左键点图标 → 面板点「开始」→ 菜单栏开始倒计时，桌面右下角出现翻转时钟。
3. 设置 → 桌面时钟：拖字号、改透明度/颜色/字体、切「纯数字」、切「始终置顶」，观察实时变化。
4. 切「铺满屏幕」，确认整屏翻转时钟且不挡其他窗口（切到别的 App 看它是否被盖住）。
5. 切回「浮动窗口」→ 菜单栏右键「调整桌面时钟位置」→ 8 秒内拖动到别处 → 重启 App 确认位置保留。
6. 选 5 分钟快捷倒计时等结束，确认提示音、菜单栏变红、通知（若授权）。
