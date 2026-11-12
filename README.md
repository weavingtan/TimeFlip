# TimeFlip

macOS 菜单栏番茄钟 + 桌面翻转时钟挂件。常驻菜单栏计时，专注状态以翻转卡片的形式挂在桌面上，可拖拽、可铺满、可调透明度与配色。

## 功能

**菜单栏**
- 番茄流程：专注 / 短休 / 长休，轮次可配（默认 25-5-20，4 轮长休）
- 自定义倒计时：快捷 5/10/15/25/45/60 分钟，或任意 1–180 分钟
- 开始 / 暂停 / 跳过 / 重置，自动开始下一阶段（可关）
- 阶段结束提示音（系统音可选）+ 系统通知；通知不可用时改为图标变红
- 全局快捷键 `⌃⌥⌘T` 开始/暂停
- 菜单栏显示：图标+时间 / 仅时间 / 仅图标，运行中显示圆环进度
- 登录时自动启动（SMAppService）

**桌面翻转时钟**
- 显示内容：自动（计时中显示剩余倒计时，空闲显示当前时间）/ 仅倒计时 / 仅时钟
- 形态：浮动窗口（可拖拽、可按屏幕记忆位置）/ 铺满整个屏幕
- 层级：贴桌面（在壁纸之上、所有窗口之下）/ 始终置顶
- 拖拽：任意时刻按住时钟任意位置即可拖动，松手后位置按屏幕记住；拖拽不会把 TimeFlip 变成前台 App
- 外观：翻转卡片或纯数字、字号 12–400pt、背景色与不透明度、字体与字重、字体色、阴影
- 显示项：秒、日期行、底行（周/日或专注进度）、24/12 小时制、冒号闪烁、小时前导零
- 设置面板改任何一项都实时生效，300ms 后落盘

## 下载

[Releases](https://github.com/weavingtan/TimeFlip/releases/latest) 里有打包好的 `TimeFlip-1.1.0-macos.zip`（macOS 14+；ad-hoc 签名、未公证）。
解压后把 `TimeFlip.app` 拖进「应用程序」；首次打开若提示「无法验证开发者」，右键 →「打开」，或先执行：

```bash
xattr -dr com.apple.quarantine /Applications/TimeFlip.app
```

它是纯菜单栏应用：启动后没有 Dock 图标、没有窗口，看屏幕右上角的图标 —— 左键 → 计时面板，右键 → 设置 / 显示隐藏桌面时钟 / 退出。

## 构建与运行

本机只需要 Command Line Tools（不需要 10GB 的 Xcode）：

```bash
./scripts/build-app.sh      # 产出 dist/TimeFlip.app
open dist/TimeFlip.app      # 启动（无 Dock 图标，只在菜单栏）
```

启动后：左键点菜单栏图标 → 计时面板；右键 → 设置 / 显示隐藏桌面时钟 / 退出。

## 测试

```bash
./scripts/test.sh    # 引擎断言（97 项：状态机、设置持久化、文案、字号反算）
./scripts/smoke.sh   # 测试 + 构建 + 离屏渲染 + 窗口层级/尺寸断言 + 还原设置
```

冒烟脚本会把设置文件临时改成测试值，结束后自动还原。

### 开发期离屏渲染

`screencapture` 在本机受屏幕录制权限限制（只能拍到壁纸），因此视觉核对走 App 自带的离屏渲染：

```bash
dist/TimeFlip.app/Contents/MacOS/TimeFlip --render-preview  /tmp/tf-preview
dist/TimeFlip.app/Contents/MacOS/TimeFlip --render-settings /tmp/tf-preview
```

- `--render-preview`：翻转卡片（浅/深）、纯数字、仅时钟、翻页角度展开图，外加一张按本机已保存设置渲染的挂件图
- `--render-settings`：菜单栏弹窗的四种状态（运行中 / 空闲 / 休息 / 刚结束）+ 设置面板三页

设置面板里的 Picker/Slider 是 NS 控件，离屏渲染会显示为黄色占位块，这是正常现象。

## 数据位置

- 设置：`~/Library/Application Support/TimeFlip/settings.json`（JSON，损坏时自动备份为 `settings.broken-*.json` 并回退默认值）

## 已知限制

- ad-hoc 签名下系统通知可能拿不到授权，此时降级为提示音 + 图标变红，功能不受影响。
- 未做 Developer ID 签名与公证，分发给他人需要自行签名。
- 只支持 macOS 14+。
