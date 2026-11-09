#!/usr/bin/env bash
# 编译并运行引擎测试。本机只有 Command Line Tools，没有 XCTest / SwiftPM，因此用自写 runner。
set -euo pipefail
cd "$(dirname "$0")/.."

if grep -rEn '^[[:space:]]*import (SwiftUI|AppKit)' Sources/TimeFlipEngine --include='*.swift'; then
  echo "ERROR: Sources/TimeFlipEngine 不允许依赖 SwiftUI/AppKit" >&2
  exit 1
fi

mkdir -p .build
ENGINE_SOURCES=$(find Sources/TimeFlipEngine -name '*.swift' | sort)

# shellcheck disable=SC2086
xcrun --sdk macosx swiftc \
  -swift-version 6 \
  -O \
  -o .build/engine-tests \
  $ENGINE_SOURCES \
  Tests/EngineTests/main.swift

./.build/engine-tests
