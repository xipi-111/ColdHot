#!/bin/bash

set -euo pipefail

project_root="$(cd "$(dirname "$0")/.." && pwd)"
dmg_path="${1:?用法: $0 <dmg-path> <release-notes-path> <tag>}"
release_notes_path="${2:?用法: $0 <dmg-path> <release-notes-path> <tag>}"
release_tag="${3:?用法: $0 <dmg-path> <release-notes-path> <tag>}"
key_account="${SPARKLE_KEY_ACCOUNT:-com.xipiyoung.ColdHot}"
sparkle_root="$project_root/.build/SourcePackages/artifacts/sparkle/Sparkle"
generate_appcast="$sparkle_root/bin/generate_appcast"

if [[ ! -f "$dmg_path" || ! -f "$release_notes_path" ]]; then
    echo "缺少 DMG 或发行说明。" >&2
    exit 66
fi
if [[ ! -x "$generate_appcast" ]]; then
    xcodebuild -resolvePackageDependencies \
        -project "$project_root/ColdHot.xcodeproj" \
        -scheme "ColdHot Direct" \
        -clonedSourcePackagesDirPath "$project_root/.build/SourcePackages"
fi

feed_workspace="$(mktemp -d /tmp/coldhot-update-feed.XXXXXX)"
cleanup() {
    case "$feed_workspace" in
        /tmp/coldhot-update-feed.*) rm -rf "$feed_workspace" ;;
    esac
}
trap cleanup EXIT
dmg_name="$(basename "$dmg_path")"
notes_name="${dmg_name%.dmg}.md"
cp "$dmg_path" "$feed_workspace/$dmg_name"
cp "$release_notes_path" "$feed_workspace/$notes_name"
cp "$project_root/docs/appcast.xml" "$feed_workspace/appcast.xml"

"$generate_appcast" \
    --account "$key_account" \
    --download-url-prefix "https://github.com/xipi-111/ColdHot/releases/download/$release_tag/" \
    --embed-release-notes \
    --link "https://github.com/xipi-111/ColdHot" \
    --maximum-versions 3 \
    -o "$project_root/docs/appcast.xml" \
    "$feed_workspace"

echo "已更新：$project_root/docs/appcast.xml"
echo "发布 GitHub Release 后，还需要提交并推送该文件。"
