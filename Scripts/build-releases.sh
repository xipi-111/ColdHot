#!/bin/bash

set -euo pipefail

project_root="$(cd "$(dirname "$0")/.." && pwd)"
mode="${1:-local-test}"
dist_root="$project_root/dist"
version="$(xcodebuild -project "$project_root/ColdHot.xcodeproj" -scheme "ColdHot Direct" -configuration DirectRelease -showBuildSettings 2>/dev/null | awk '/MARKETING_VERSION =/{print $3; exit}')"
build_number="$(xcodebuild -project "$project_root/ColdHot.xcodeproj" -scheme "ColdHot Direct" -configuration DirectRelease -showBuildSettings 2>/dev/null | awk '/CURRENT_PROJECT_VERSION =/{print $3; exit}')"

if [[ "$mode" != "local-test" && "$mode" != "release" ]]; then
    echo "用法: $0 [local-test|release]" >&2
    exit 64
fi

output_dir="$dist_root/$mode/$version-$build_number"
if [[ -e "$output_dir" ]]; then
    case "$output_dir" in
        "$project_root"/dist/local-test/*|"$project_root"/dist/release/*)
            rm -rf "$output_dir"
            ;;
        *)
            echo "拒绝清理非预期目录：$output_dir" >&2
            exit 70
            ;;
    esac
fi
mkdir -p "$output_dir"

temporary_root="$(mktemp -d /tmp/coldhot-release.XXXXXX)"
cleanup() {
    rm -rf "$temporary_root"
}
trap cleanup EXIT

build_unsigned_app() {
    local scheme="$1"
    local configuration="$2"
    local derived_data="$3"
    xcodebuild -quiet \
        -project "$project_root/ColdHot.xcodeproj" \
        -scheme "$scheme" \
        -configuration "$configuration" \
        -destination "generic/platform=macOS" \
        -derivedDataPath "$derived_data" \
        build CODE_SIGNING_ALLOWED=NO
}

create_dmg() {
    local app_path="$1"
    local dmg_path="$2"
    local staging="$temporary_root/dmg-staging"
    mkdir -p "$staging"
    ditto --norsrc --noextattr "$app_path" "$staging/ColdHot.app"
    ln -s /Applications "$staging/Applications"
    hdiutil create -quiet -volname "ColdHot" -srcfolder "$staging" -format UDZO "$dmg_path"
}

if [[ "$mode" == "local-test" ]]; then
    direct_data="$temporary_root/direct"
    build_unsigned_app "ColdHot Direct" "DirectRelease" "$direct_data"

    direct_app="$direct_data/Build/Products/DirectRelease/ColdHot.app"
    xattr -cr "$direct_app"
    codesign --force --deep --sign - --options runtime "$direct_app"

    codesign --verify --deep --strict "$direct_app"

    direct_dmg="$output_dir/ColdHot-Direct-$version-$build_number-local-test.dmg"
    create_dmg "$direct_app" "$direct_dmg"
    (cd "$output_dir" && shasum -a 256 "$(basename "$direct_dmg")" > SHA256SUMS.txt)

    echo "已生成本机测试包：$output_dir"
    echo "该安装包使用临时签名，不能公开发行。"
    exit 0
fi

: "${DEVELOPMENT_TEAM:?release 模式需要 DEVELOPMENT_TEAM}"
: "${NOTARYTOOL_PROFILE:?release 模式需要 NOTARYTOOL_PROFILE}"

if ! security find-identity -v -p codesigning | grep -q 'Developer ID Application'; then
    echo "缺少 Developer ID Application 证书。" >&2
    exit 66
fi
direct_archive="$temporary_root/ColdHot-Direct.xcarchive"

xcodebuild -quiet \
    -project "$project_root/ColdHot.xcodeproj" \
    -scheme "ColdHot Direct" \
    -configuration DirectRelease \
    -destination "generic/platform=macOS" \
    -archivePath "$direct_archive" \
    DEVELOPMENT_TEAM="$DEVELOPMENT_TEAM" \
    -allowProvisioningUpdates archive

direct_options="$temporary_root/ExportOptions-Direct.plist"
cp "$project_root/Configurations/ExportOptions-Direct.plist" "$direct_options"
plutil -replace teamID -string "$DEVELOPMENT_TEAM" "$direct_options"

direct_export="$temporary_root/direct-export"
xcodebuild -quiet -exportArchive \
    -archivePath "$direct_archive" \
    -exportPath "$direct_export" \
    -exportOptionsPlist "$direct_options" \
    -allowProvisioningUpdates
direct_app="$(find "$direct_export" -maxdepth 1 -type d -name '*.app' -print -quit)"
if [[ -z "$direct_app" ]]; then
    echo "Xcode 未生成预期的 .app。" >&2
    exit 65
fi

codesign --verify --deep --strict --verbose=2 "$direct_app"

direct_dmg="$output_dir/ColdHot-Direct-$version-$build_number.dmg"
create_dmg "$direct_app" "$direct_dmg"
codesign --force --sign "$(security find-identity -v -p codesigning | sed -n 's/.*"\(Developer ID Application:[^"]*\)".*/\1/p' | head -n 1)" "$direct_dmg"
xcrun notarytool submit "$direct_dmg" --keychain-profile "$NOTARYTOOL_PROFILE" --wait
xcrun stapler staple "$direct_dmg"
xcrun stapler validate "$direct_dmg"
spctl --assess --type open --context context:primary-signature --verbose=4 "$direct_dmg"

(cd "$output_dir" && shasum -a 256 "$(basename "$direct_dmg")" > SHA256SUMS.txt)
echo "已生成生产发行包：$output_dir"
