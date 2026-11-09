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
  <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
  <key>CFBundleName</key><string>$APP_NAME</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0.0</string>
  <key>CFBundleVersion</key><string>1</string>
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
