#!/usr/bin/env bash
# 端到端冒烟：单元测试 → 构建 → 离屏渲染 → 真实窗口层级/尺寸断言 → 还原用户设置。
# 注意：本机 screencapture 受 TCC 限制只能拍到壁纸，所以视觉核对走 --render-preview。
set -euo pipefail
cd "$(dirname "$0")/.."

APP="dist/TimeFlip.app"
BIN="$APP/Contents/MacOS/TimeFlip"
OUT="/tmp/timeflip-smoke"
LEVEL=$(( -2147483603 + 1 ))   # kCGDesktopIconWindowLevel + 1
SETTINGS="$HOME/Library/Application Support/TimeFlip/settings.json"

cleanup() {
  osascript -e 'quit app "TimeFlip"' >/dev/null 2>&1 || true
  pkill -f "$APP/Contents/MacOS/TimeFlip" >/dev/null 2>&1 || true
  python3 - "$SETTINGS" <<'PY'
import json, os, sys
target = sys.argv[1]
backup = "/tmp/timeflip-smoke-backup.json"
if os.path.exists(backup):
    with open(backup) as f:
        data = f.read()
    with open(target, "w") as f:
        f.write(data)
    os.remove(backup)
PY
}
trap cleanup EXIT

echo "== 1/5 引擎测试"
./scripts/test.sh | tail -3

echo "== 2/5 构建"
./scripts/build-app.sh | tail -1

echo "== 3/5 离屏渲染（无需屏幕录制权限）"
"$BIN" --render-preview "$OUT/preview" | tail -4
"$BIN" --render-settings "$OUT/settings" | tail -4
test -f "$OUT/preview/1-flip-light.png"
test -f "$OUT/preview/6-themes.png"
test -f "$OUT/preview/7-share-card.png"
test -f "$OUT/settings/menu-panel.png"
test -f "$OUT/settings/settings-统计.png"
test -f "$OUT/settings/settings-桌面时钟.png"

echo "== 4/5 窗口断言"
xcrun --sdk macosx swiftc -O scripts/window-check.swift -o .build/window-check
CHECK=".build/window-check"

mkdir -p "$(dirname "$SETTINGS")"
if [ -f "$SETTINGS" ]; then
  cp "$SETTINGS" /tmp/timeflip-smoke-backup.json
fi

run_case() {
  local mode="$1"; local form="$2"; local layer="$3"
  osascript -e 'quit app "TimeFlip"' >/dev/null 2>&1 || true
  pkill -f "$APP/Contents/MacOS/TimeFlip" >/dev/null 2>&1 || true
  sleep 1
  python3 - "$SETTINGS" "$form" "$layer" <<'PY'
import json, os, sys
path, form, layer = sys.argv[1], sys.argv[2], sys.argv[3]
os.makedirs(os.path.dirname(path), exist_ok=True)
json.dump({
    "version": 1,
    "behavior": {"showMode": "auto", "form": form, "layer": layer, "visible": True},
}, open(path, "w"), ensure_ascii=False, indent=2)
PY
  env TIMEFLIP_DEBUG=1 "$BIN" > "/tmp/timeflip-smoke-$mode.log" 2>&1 &
  sleep 3
  echo "-- 模式: $mode"
  "$CHECK" "$LEVEL" "$mode"
  grep -o "hotkey registered=[a-z]*" "/tmp/timeflip-smoke-$mode.log" | head -1 || true
}

run_case floating floating desktop
run_case full fullScreen desktop

echo "-- 模式: settings（真实打开设置窗口，验证 SwiftUI 面板不崩）"
osascript -e 'quit app "TimeFlip"' >/dev/null 2>&1 || true
pkill -f "$APP/Contents/MacOS/TimeFlip" >/dev/null 2>&1 || true
sleep 1
python3 - "$SETTINGS" <<'PY'
import json, os, sys
path = sys.argv[1]
json.dump({
    "version": 1,
    "behavior": {"showMode": "auto", "form": "floating", "layer": "desktop", "visible": True},
}, open(path, "w"), ensure_ascii=False, indent=2)
PY
env TIMEFLIP_DEBUG=1 "$BIN" --open-settings > /tmp/timeflip-smoke-settings.log 2>&1 &
sleep 3
"$CHECK" "$LEVEL" floating --require-settings-window

echo "-- 拖拽层自检（命中测试必须落到 DragCatcherView）"
osascript -e 'quit app "TimeFlip"' >/dev/null 2>&1 || true
pkill -f "$APP/Contents/MacOS/TimeFlip" >/dev/null 2>&1 || true
sleep 1
HIT=$(env TIMEFLIP_DEBUG=1 "$BIN" --selftest-hit 2>&1 | grep HITTEST || true)
echo "$HIT"
case "$HIT" in
  *"hit=DragCatcherView"*) ;;
  *) echo "FAIL: 拖拽层未命中"; exit 1 ;;
esac

echo "-- 拖拽位置回归（拖动后紧接着尺寸变化，窗口不能弹回旧位置）"
osascript -e 'quit app "TimeFlip"' >/dev/null 2>&1 || true
pkill -f "$APP/Contents/MacOS/TimeFlip" >/dev/null 2>&1 || true
sleep 1
DRAG=$(env TIMEFLIP_DEBUG=1 "$BIN" --selftest-drag 2>&1 | grep DRAGTEST || true)
echo "$DRAG"
case "$DRAG" in
  *"stayed=true resized=true saved=true"*) ;;
  *) echo "FAIL: 拖动后窗口被弹回记忆位置 / 位置没记住"; exit 1 ;;
esac

echo "-- 强制休息决策链（不真的锁屏，只打印策略与系统前提）"
osascript -e 'quit app "TimeFlip"' >/dev/null 2>&1 || true
pkill -f "$APP/Contents/MacOS/TimeFlip" >/dev/null 2>&1 || true
sleep 1
REST=$(env TIMEFLIP_DEBUG=1 "$BIN" --selftest-rest 2>&1 | grep RESTTEST || true)
echo "$REST"
case "$REST" in
  *"lock=displaySleep delay=7 overlay=true"*) ;;
  *) echo "FAIL: 锁屏策略没有按设置生效"; exit 1 ;;
esac

echo "== 5/5 还原设置并退出"
cleanup
trap - EXIT

echo "SMOKE PASSED"
