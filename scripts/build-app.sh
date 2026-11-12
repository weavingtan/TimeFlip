#!/usr/bin/env bash
# 用 Command Line Tools 的 swiftc 直接编译并组装 .app（本机没有 Xcode / SwiftPM 不可用）。
set -euo pipefail
cd "$(dirname "$0")/.."

APP_NAME="TimeFlip"
BUNDLE_ID="com.weaving.timeflip"
DIST_DIR="dist"
APP_DIR="$DIST_DIR/$APP_NAME.app"

/bin/rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources" .build

# 图标：由 scripts/make-icon.swift 现画成 .icns（脚本没改动就复用上次产物）
ICNS=".build/AppIcon.icns"
if [ ! -f "$ICNS" ] || [ scripts/make-icon.swift -nt "$ICNS" ]; then
  ICONSET=".build/AppIcon.iconset"
  /bin/rm -rf "$ICONSET" ".build/icon"
  mkdir -p "$ICONSET"
  xcrun --sdk macosx swift scripts/make-icon.swift .build/icon >/dev/null
  MASTER=".build/icon/icon-1024.png"
  scale() { sips -Z "$1" "$MASTER" --out "$ICONSET/icon_$2.png" >/dev/null 2>&1; }
  scale 16   16x16
  scale 32   16x16@2x
  scale 32   32x32
  scale 64   32x32@2x
  scale 128  128x128
  scale 256  128x128@2x
  scale 256  256x256
  scale 512  256x256@2x
  scale 512  512x512
  cp "$MASTER" "$ICONSET/icon_512x512@2x.png"
  iconutil -c icns "$ICONSET" -o "$ICNS"
fi
cp "$ICNS" "$APP_DIR/Contents/Resources/AppIcon.icns"

SOURCES=$(find Sources/TimeFlipEngine Sources/TimeFlip -name '*.swift' | sort)

# 应用层用 Swift 5 语言模式（AppKit/SwiftUI 胶水代码），引擎测试仍用 Swift 6 校验。
# shellcheck disable=SC2086
xcrun --sdk macosx swiftc \
  -swift-version 5 \
  -O \
  -parse-as-library \
  -o "$APP_DIR/Contents/MacOS/$APP_NAME" \
  $SOURCES

cat > "$APP_DIR/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key><string>zh_CN</string>
  <key>CFBundleExecutable</key><string>$APP_NAME</string>
  <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
  <key>CFBundleName</key><string>$APP_NAME</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.1.0</string>
  <key>CFBundleVersion</key><string>2</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSPrincipalClass</key><string>NSApplication</string>
  <key>NSHumanReadableCopyright</key><string>TimeFlip</string>
</dict>
</plist>
PLIST

plutil -lint "$APP_DIR/Contents/Info.plist" >/dev/null
codesign --force --sign - "$APP_DIR" >/dev/null 2>&1 || true

echo "built: $APP_DIR"
