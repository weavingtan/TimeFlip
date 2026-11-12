#!/usr/bin/env bash
# 一键发版：改版本号 → 跑断言（可选冒烟）→ 打包校验 → 提交打标签 → 建 GitHub Release。
#
#   ./scripts/release.sh 1.2.3              指定版本
#   ./scripts/release.sh                    自动把 patch +1
#   ./scripts/release.sh 1.2.3 --dry-run    只改版本号 + 打包校验，不提交/不推送/不发布
#   ./scripts/release.sh 1.2.3 --skip-smoke 跳过端到端冒烟（仍跑引擎断言）
#   ./scripts/release.sh 1.2.3 --install    发布后顺便覆盖安装到 /Applications
#
# 发布说明：若存在 docs/releases/v<版本>.md 就直接用，并随本次提交入库；
# 否则按「上一个 tag..HEAD」的提交标题临时生成。
set -euo pipefail
cd "$(dirname "$0")/.."

APP_NAME="TimeFlip"
DIST="dist"
GH="$(command -v gh || true)"
if [ -z "$GH" ] && [ -x /usr/local/bin/gh ]; then GH=/usr/local/bin/gh; fi

DRY_RUN=0
SKIP_SMOKE=0
INSTALL=0
VERSION=""

usage() {
  sed -n '2,11p' "$0" | sed 's/^# \{0,1\}//'
}

for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=1 ;;
    --skip-smoke) SKIP_SMOKE=1 ;;
    --install) INSTALL=1 ;;
    -h|--help) usage; exit 0 ;;
    -*) echo "未知参数：$arg" >&2; usage >&2; exit 2 ;;
    *) VERSION="${arg#v}" ;;
  esac
done

fail() { echo "FAIL: $*" >&2; exit 1; }

# MARK: - 版本号

CURRENT_VERSION=$(sed -n 's|.*<key>CFBundleShortVersionString</key><string>\([^<]*\)</string>.*|\1|p' scripts/build-app.sh)
CURRENT_BUILD=$(sed -n 's|.*<key>CFBundleVersion</key><string>\([0-9]*\)</string>.*|\1|p' scripts/build-app.sh)
[ -n "$CURRENT_VERSION" ] && [ -n "$CURRENT_BUILD" ] || fail "读不出 scripts/build-app.sh 里的当前版本号"

if [ -z "$VERSION" ]; then
  IFS=. read -r V_MAJOR V_MINOR V_PATCH <<< "$CURRENT_VERSION"
  VERSION="$V_MAJOR.$V_MINOR.$((V_PATCH + 1))"
fi

[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "版本号格式应为 X.Y.Z：$VERSION"
NEW_BUILD=$((CURRENT_BUILD + 1))
NEW_TAG="v$VERSION"

# MARK: - 前置检查

[ -z "$(git status --porcelain)" ] || fail "工作区有未提交的改动，先提交或 stash 再发版"
if git rev-parse -q --verify "refs/tags/$NEW_TAG" >/dev/null; then
  fail "标签 $NEW_TAG 已存在"
fi

BRANCH=$(git branch --show-current)
if [ "$DRY_RUN" -eq 0 ]; then
  [ "$BRANCH" = "main" ] || fail "当前在 $BRANCH 分支，发版请在 main 上"
  [ -n "$GH" ] || fail "找不到 gh：先安装 GitHub CLI 或把它放到 /usr/local/bin"
  "$GH" auth status >/dev/null 2>&1 || fail "gh 未登录，先执行 gh auth login"
fi

echo "== 版本：$CURRENT_VERSION (build $CURRENT_BUILD) → $VERSION (build $NEW_BUILD)"
if [ "$DRY_RUN" -eq 1 ]; then echo "== 模式：dry-run（不提交 / 不推送 / 不发布）"; fi

# MARK: - 改版本号

/usr/bin/sed -i '' -E \
  -e "s|<key>CFBundleShortVersionString</key><string>[^<]*</string>|<key>CFBundleShortVersionString</key><string>${VERSION}</string>|" \
  -e "s|<key>CFBundleVersion</key><string>[0-9]*</string>|<key>CFBundleVersion</key><string>${NEW_BUILD}</string>|" \
  scripts/build-app.sh
/usr/bin/sed -i '' -E \
  -e "s|TimeFlip-[0-9]+\.[0-9]+\.[0-9]+-macos\.zip|TimeFlip-${VERSION}-macos.zip|g" \
  README.md

grep -q "<string>${VERSION}</string>" scripts/build-app.sh || fail "build-app.sh 版本号没写进去"
grep -q "TimeFlip-${VERSION}-macos.zip" README.md || fail "README 里的 zip 名没更新"

# MARK: - 测试与构建

echo "== 1/5 引擎断言"
./scripts/test.sh | tail -2

if [ "$SKIP_SMOKE" -eq 1 ]; then
  echo "== 2/5 构建（已跳过冒烟）"
  ./scripts/build-app.sh | tail -1
else
  echo "== 2/5 端到端冒烟（测试 + 构建 + 离屏渲染 + 窗口断言 + 还原设置）"
  ./scripts/smoke.sh | tail -3
fi

# MARK: - 打包校验

echo "== 3/5 打包"
APP="$DIST/$APP_NAME.app"
ZIP="$DIST/${APP_NAME}-${VERSION}-macos.zip"

PLIST_VERSION=$(/usr/bin/plutil -p "$APP/Contents/Info.plist" | sed -n 's|.*"CFBundleShortVersionString" => "\(.*\)"|\1|p')
[ "$PLIST_VERSION" = "$VERSION" ] || fail "产物版本是 $PLIST_VERSION，不是 $VERSION"

# 冒烟脚本跑过 App，文件上会挂 com.apple.provenance；不清干净 zip 里会多出一堆 ._ 冗余项。
xattr -cr "$APP"
/bin/rm -f "$ZIP"
/usr/bin/ditto -c -k --keepParent "$APP" "$ZIP"

codesign --verify --strict "$APP" >/dev/null 2>&1 || fail "签名校验不通过"
if unzip -l "$ZIP" | grep -q '\._'; then fail "zip 里含 ._ 冗余项"; fi

echo "== 4/5 产物自检"
CHECK_DIR=$(mktemp -d)
TEMP_NOTES=""
cleanup() {
  /bin/rm -rf "$CHECK_DIR"
  if [ -n "$TEMP_NOTES" ]; then /bin/rm -f "$TEMP_NOTES"; fi
}
trap cleanup EXIT

unzip -q "$ZIP" -d "$CHECK_DIR"
"$CHECK_DIR/$APP_NAME.app/Contents/MacOS/$APP_NAME" --render-preview "$CHECK_DIR/out" >/dev/null
test -f "$CHECK_DIR/out/1-flip-light.png" || fail "解包后的 App 跑不出离屏渲染"
echo "   zip $(du -h "$ZIP" | cut -f1) · $(unzip -l "$ZIP" | tail -1 | awk '{print $2}') 个文件 · 签名 ad-hoc 通过"

if [ "$DRY_RUN" -eq 1 ]; then
  echo "== 5/5 跳过发布"
  echo "== 完成：$ZIP"
  echo "!! 版本号已写进 scripts/build-app.sh 与 README.md，但未提交。"
  echo "   撤销：git checkout -- scripts/build-app.sh README.md && /bin/rm -f $ZIP"
  exit 0
fi

# MARK: - 发布说明

echo "== 5/5 提交、打标签、建 Release"
NOTES="docs/releases/v${VERSION}.md"
if [ -f "$NOTES" ]; then
  echo "   用仓库里的发布说明：$NOTES"
else
  TEMP_NOTES=$(mktemp)
  NOTES="$TEMP_NOTES"
  PREV_TAG=$(git describe --tags --abbrev=0 2>/dev/null || true)
  {
    echo "## 更新内容"
    echo
    if [ -n "$PREV_TAG" ]; then
      git log "$PREV_TAG"..HEAD --no-merges --pretty='- %s'
    else
      git log --no-merges --pretty='- %s' -15
    fi
    echo
    echo "设置与专注记录完全兼容。"
  } > "$NOTES"
  echo "   按 $PREV_TAG..HEAD 的提交标题临时生成发布说明（想手写就在 docs/releases/v$VERSION.md 放一份）"
fi

git add scripts/build-app.sh README.md
if [ -f "docs/releases/v${VERSION}.md" ]; then
  git add "docs/releases/v${VERSION}.md"
fi
git commit -m "chore(release): v$VERSION" -m "Info.plist 版本 $VERSION / build $NEW_BUILD，README 指向新的 zip 名。"
git tag -a "$NEW_TAG" -m "$APP_NAME $VERSION"
git push origin "$BRANCH"
git push origin "$NEW_TAG"
"$GH" release create "$NEW_TAG" "$ZIP" --title "$APP_NAME $VERSION" --notes-file "$NOTES" --latest

# MARK: - 可选：覆盖安装

if [ "$INSTALL" -eq 1 ]; then
  echo "== 安装到 /Applications"
  osascript -e "quit app \"$APP_NAME\"" >/dev/null 2>&1 || true
  sleep 1
  /bin/rm -rf "/Applications/$APP_NAME.app"
  /usr/bin/ditto "$APP" "/Applications/$APP_NAME.app"
  xattr -dr com.apple.quarantine "/Applications/$APP_NAME.app" 2>/dev/null || true
  open "/Applications/$APP_NAME.app"
  echo "   已替换 /Applications/$APP_NAME.app 并启动"
fi

echo "== 发布完成：$NEW_TAG"
