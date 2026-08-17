# ColdHot 官网版发行说明

ColdHot 目前仅维护官网 / GitHub 分发版。仓库中的 App Store Scheme 和配置只作为历史内容保留，不再构建、提交或发布。

## 发行目标

| 渠道 | Scheme | Configuration | Bundle ID | 交付物 |
| --- | --- | --- | --- | --- |
| 官网 / GitHub | ColdHot Direct | DirectRelease | `com.xipiyoung.ColdHot` | Developer ID 签名并完成 Apple 公证的 DMG |

## 本机测试包

```sh
./Scripts/build-releases.sh local-test
```

测试包输出到：

```text
dist/local-test/<版本>-<构建号>/
```

其中包含临时签名的 DMG 和 `SHA256SUMS.txt`。该包只用于本机测试，不能公开分发。

## 正式发行前置条件

- 钥匙串中存在有效的 `Developer ID Application` 证书。
- `notarytool` 已保存有效的公证凭据，例如配置名 `ColdHotNotary`。
- `DEVELOPMENT_TEAM` 使用 Developer ID 证书对应的 Team ID。

如需首次保存公证凭据：

```sh
xcrun notarytool store-credentials ColdHotNotary \
  --apple-id "你的 Apple ID" \
  --team-id "你的 Team ID" \
  --password "App 专用密码"
```

## 构建正式包

```sh
DEVELOPMENT_TEAM="你的 Team ID" \
NOTARYTOOL_PROFILE="ColdHotNotary" \
./Scripts/build-releases.sh release
```

脚本会完成：

1. 使用 `ColdHot Direct` Scheme 创建 Archive。
2. 用 Developer ID 导出签名应用。
3. 验证应用签名和 Gatekeeper 状态。
4. 生成并签名 DMG。
5. 提交 Apple 公证，等待 Accepted 后装订公证票据。
6. 再次验证 DMG，并生成 SHA-256 校验文件。

正式包输出到：

```text
dist/release/<版本>-<构建号>/
```

版本目录彼此独立，重新构建只会替换相同版本目录，不会删除旧版本安装包。

## 发布到 GitHub

- 创建与对外版本一致的标签，例如 `v1.1.0`。
- 上传 DMG 和 `SHA256SUMS.txt` 作为 Release Assets。
- 将该 Release 标记为 Latest。
- 官网下载按钮可指向 GitHub 的 Latest Release 页面，或更新为对应 DMG 的固定地址。

用户升级时先退出 ColdHot，再打开新 DMG，将 `ColdHot.app` 拖入“应用程序”并选择替换。由于 Bundle ID 不变，现有偏好设置会继续保留。
