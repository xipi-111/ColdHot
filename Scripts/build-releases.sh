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

output_dir="$dist_root/$mode"
if [[ -e "$output_dir" ]]; then
    case "$output_dir" in
        "$project_root"/dist/local-test|"$project_root"/dist/release)
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

scan_store_binary() {
    local binary="$1"
    if strings "$binary" | grep -Eq 'AppleSMC|IOHIDEventSystemClientCreate|IOHIDServiceClientCopyEvent|com\.apple\.dock|proc_listpids|AGXAccelerator|IOBlockStorageDriver'; then
        echo "App Store 二进制仍包含不允许的实现标记。" >&2
        exit 65
    fi
}

if [[ "$mode" == "local-test" ]]; then
    direct_data="$temporary_root/direct"
    store_data="$temporary_root/store"
    build_unsigned_app "ColdHot Direct" "DirectRelease" "$direct_data"
    build_unsigned_app "ColdHot App Store" "AppStoreRelease" "$store_data"

    direct_app="$direct_data/Build/Products/DirectRelease/ColdHot.app"
    store_app="$store_data/Build/Products/AppStoreRelease/ColdHot.app"
    xattr -cr "$direct_app" "$store_app"
    codesign --force --deep --sign - --options runtime "$direct_app"
    codesign --force --deep --sign - --options runtime \
        --entitlements "$project_root/ColdHot/Resources/ColdHot-AppStore.entitlements" \
        "$store_app"

    codesign --verify --deep --strict "$direct_app"
    codesign --verify --deep --strict "$store_app"
    scan_store_binary "$store_app/Contents/MacOS/ColdHot"

    direct_dmg="$output_dir/ColdHot-Direct-$version-$build_number-local-test.dmg"
    store_pkg="$output_dir/ColdHot-AppStore-$version-$build_number-local-test.pkg"
    create_dmg "$direct_app" "$direct_dmg"
    COPYFILE_DISABLE=1 productbuild --component "$store_app" /Applications "$store_pkg" >/dev/null
    (cd "$output_dir" && shasum -a 256 "$(basename "$direct_dmg")" "$(basename "$store_pkg")" > SHA256SUMS.txt)

    echo "已生成本机测试包：$output_dir"
    echo "这些包使用临时签名，不能作为公开发行或 App Store 上传包。"
    exit 0
fi

: "${DEVELOPMENT_TEAM:?release 模式需要 DEVELOPMENT_TEAM}"
: "${NOTARYTOOL_PROFILE:?release 模式需要 NOTARYTOOL_PROFILE}"

if ! security find-identity -v -p codesigning | grep -q 'Developer ID Application'; then
    echo "缺少 Developer ID Application 证书。" >&2
    exit 66
fi
if ! security find-identity -v -p codesigning | grep -Eq 'Apple Distribution|3rd Party Mac Developer Application'; then
    echo "缺少 Apple Distribution 证书。" >&2
    exit 66
fi
if ! security find-identity -v | grep -q '3rd Party Mac Developer Installer'; then
    echo "缺少 3rd Party Mac Developer Installer 证书。" >&2
    exit 66
fi

direct_archive="$temporary_root/ColdHot-Direct.xcarchive"
store_archive="$temporary_root/ColdHot-AppStore.xcarchive"

xcodebuild -quiet \
    -project "$project_root/ColdHot.xcodeproj" \
    -scheme "ColdHot Direct" \
    -configuration DirectRelease \
    -destination "generic/platform=macOS" \
    -archivePath "$direct_archive" \
    DEVELOPMENT_TEAM="$DEVELOPMENT_TEAM" \
    -allowProvisioningUpdates archive

xcodebuild -quiet \
    -project "$project_root/ColdHot.xcodeproj" \
    -scheme "ColdHot App Store" \
    -configuration AppStoreRelease \
    -destination "generic/platform=macOS" \
    -archivePath "$store_archive" \
    DEVELOPMENT_TEAM="$DEVELOPMENT_TEAM" \
    -allowProvisioningUpdates archive

direct_options="$temporary_root/ExportOptions-Direct.plist"
store_options="$temporary_root/ExportOptions-AppStore.plist"
cp "$project_root/Configurations/ExportOptions-Direct.plist" "$direct_options"
cp "$project_root/Configurations/ExportOptions-AppStore.plist" "$store_options"
plutil -replace teamID -string "$DEVELOPMENT_TEAM" "$direct_options"
plutil -replace teamID -string "$DEVELOPMENT_TEAM" "$store_options"

direct_export="$temporary_root/direct-export"
store_export="$temporary_root/store-export"
xcodebuild -quiet -exportArchive \
    -archivePath "$direct_archive" \
    -exportPath "$direct_export" \
    -exportOptionsPlist "$direct_options" \
    -allowProvisioningUpdates
xcodebuild -quiet -exportArchive \
    -archivePath "$store_archive" \
    -exportPath "$store_export" \
    -exportOptionsPlist "$store_options" \
    -allowProvisioningUpdates

direct_app="$(find "$direct_export" -maxdepth 1 -type d -name '*.app' -print -quit)"
store_pkg="$(find "$store_export" -maxdepth 1 -type f -name '*.pkg' -print -quit)"
if [[ -z "$direct_app" || -z "$store_pkg" ]]; then
    echo "Xcode 未生成预期的 .app 或 .pkg。" >&2
    exit 65
fi

direct_dmg="$output_dir/ColdHot-Direct-$version-$build_number.dmg"
create_dmg "$direct_app" "$direct_dmg"
codesign --force --sign "$(security find-identity -v -p codesigning | sed -n 's/.*"\(Developer ID Application:[^"]*\)".*/\1/p' | head -n 1)" "$direct_dmg"
xcrun notarytool submit "$direct_dmg" --keychain-profile "$NOTARYTOOL_PROFILE" --wait
xcrun stapler staple "$direct_dmg"
xcrun stapler validate "$direct_dmg"
spctl --assess --type open --context context:primary-signature --verbose=4 "$direct_dmg"

ditto "$store_pkg" "$output_dir/$(basename "$store_pkg")"
(cd "$output_dir" && shasum -a 256 "$(basename "$direct_dmg")" "$(basename "$store_pkg")" > SHA256SUMS.txt)
echo "已生成生产发行包：$output_dir"
