#!/bin/bash

set -euo pipefail

project_root="$(cd "$(dirname "$0")/.." && pwd)"
output_dir="$project_root/AppStore/screenshots/zh-Hans"
build_root="$project_root/AppStore/.screenshot-build"
binary="$build_root/ColdHotScreenshotRenderer"
sources=()

while IFS= read -r source; do
    sources+=("$source")
done < <(find "$project_root/ColdHot" -name '*.swift' ! -path '*/App/ColdHotApp.swift' -print | sort)

mkdir -p "$build_root"

xcrun swiftc \
    -parse-as-library \
    -D APP_STORE \
    -D SCREENSHOT_RENDERER \
    -O \
    -o "$binary" \
    "${sources[@]}" \
    "$project_root/AppStore/ScreenshotHarness.swift" \
    "$project_root/AppStore/ScreenshotRenderer.swift"

"$binary"

mkdir -p "$output_dir"

echo "截图渲染器：$binary"
echo "输出目录：$output_dir"
echo "已输出 overview、CPU 详情和电池隐私三张 1280×800 PNG。"
