# ColdHot 发行说明

## 两个发行渠道

| 渠道 | Scheme | Configuration | Bundle ID | 交付物 |
| --- | --- | --- | --- | --- |
| 官网 / GitHub | ColdHot Direct | DirectRelease | `com.xipiyoung.ColdHot` | Developer ID 签名并公证的 DMG |
| Mac App Store | ColdHot App Store | AppStoreRelease | `com.xipiyoung.ColdHot.AppStore` | App Store Connect PKG |

两个版本的 Bundle ID 不同，因此本地设置相互独立。用户应选择其中一个渠道长期安装，避免 `/Applications` 中同名应用相互覆盖。

## 本机测试包

```sh
./Scripts/build-releases.sh local-test
```

脚本会构建 Universal Binary（arm64 + x86_64），给两个 `.app` 添加临时签名，检查 App Store 二进制不包含被移除的实现标记，然后输出：

- `dist/local-test/ColdHot-Direct-*-local-test.dmg`
- `dist/local-test/ColdHot-AppStore-*-local-test.pkg`
- `dist/local-test/SHA256SUMS.txt`

这些包只用于本机安装验证，不能上传或公开发行。

## 生产发行前置条件

在 Xcode 的 Accounts / Manage Certificates 中准备：

- `Developer ID Application`：官网版签名与公证。
- `Apple Distribution`：App Store 应用签名。
- `3rd Party Mac Developer Installer`：App Store 安装包签名。
- 与两个 Bundle ID 对应的 App ID、Provisioning Profile 和 App Store Connect 记录。

再用 `notarytool` 保存公证凭据，例如：

```sh
xcrun notarytool store-credentials ColdHotNotary \
  --apple-id "你的 Apple ID" \
  --team-id "你的 Team ID" \
  --password "App 专用密码"
```

## 构建生产包

```sh
DEVELOPMENT_TEAM="你的 Team ID" \
NOTARYTOOL_PROFILE="ColdHotNotary" \
./Scripts/build-releases.sh release
```

脚本会：

1. 分别 Archive 两个 Scheme。
2. 用 Developer ID 导出官网版，生成 DMG，提交公证并 staple ticket。
3. 导出 App Store Connect PKG。
4. 生成 SHA-256 校验文件。

官网版 DMG 可作为 GitHub Release Asset 上传。App Store PKG 应使用 Xcode Organizer、Transporter 或 App Store Connect 上传，不应放在 GitHub 供普通用户安装。

## App Store Connect 仍需准备

- App 名称、描述、关键词、支持 URL、营销 URL。
- 可公开访问的隐私政策 URL；可以托管仓库中的 `PRIVACY.md`，但正式提交时建议使用稳定网页地址。
- 至少一张符合 Mac 截图规格的产品截图。
- App Privacy 问卷；当前实现不向开发者收集监控数据。
- 审核备注，说明网络延迟测试只有用户主动启用并展开网络卡片时才运行。

