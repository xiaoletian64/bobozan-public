# Android OTA 更新

更新服务器为用户指定的 `updates.example.invalid`，使用现有 SSH 配置 `bobozan-release`。只新增 `/bobozan/ota/` 静态路径，原 Nginx 配置备份后通过 `nginx -t` 才重载；没有改动其他应用的目录、数据库或容器。

## 使用

首次需要手动覆盖安装支持 OTA 的 APK。之后在「声音与设置 → 检查应用更新」手动检查：展示版本、说明和大小，确认后下载，校验通过才交给 Android 系统安装。Android 8+ 首次需允许该应用安装未知应用，并仍需系统安装确认。支持取消、超时、失败重试，不静默安装、不自动强更，不在对局期间弹更新。

当前是整个 APK 更新，非资源热更新。iOS 不使用此通道。保留原包名 `com.prototype.bobozan` 与签名，更新正常保留原应用存档。

## 发布与信任

- 清单：`http://updates.example.invalid/bobozan/ota/latest.json`
- 服务端公开目录：`/srv/bobozan-ota/public/`，只放签名清单与 APK。
- APK 文件不可修改同版本内容；发布脚本拒绝版本回退，并先上传 APK、校验服务器上的文件，再原子替换清单。
- IP 通过 HTTP 提供下载，仅该 IP 在 Android 网络配置中允许明文；客户端拒绝重定向及更换下载来源。
- 清单由 RSA-3072/SHA-256 签名，内置公钥验证。下载时流式检查大小与 SHA-256，再核对 APK 包名、实际 versionCode 和安装签名，最后仍由系统包安装器验证安装。不同内容、不同签名、旧版本均不会主动交给系统安装。
- 发布签名私钥仅在本机 `~/.config/bobozan-ota/manifest-private.pem`，目录权限 700、文件权限 600，不在仓库、APK 或服务器内。需妥善备份，丢失后不能继续为已安装客户端签发新清单。
- 内置公钥在 `native/android/ota-public-key.txt`，构建准备脚本同步到 Java。HTTP 签名保护内容真实性与完整性，不提供传输保密，也不能保证网络可用性；已有 HTTPS 域名后可迁移通道。

## 后续发布

1. 修改 `export_presets.cfg` 的 Android versionCode（必须递增）、versionName 和输出 APK 路径。
2. 如改动原生代码，先运行 `python3 tools/prepare_android_native.py`。
3. 导出 Android APK 并运行对应测试。
4. 发布：

```sh
python3 tools/publish_ota.py --apk builds/bobozan-v0.6.1.apk --notes '更新说明' --deploy
```

默认使用现有 SSH 别名。省略 `--deploy` 只在 `release/ota/` 生成清单和安装包。发布工具会校验 APK 的实际包名、版本和原签名，再使用本机私钥签名。Nginx 只允许下载，不提供 Web 上传接口。

## 验证（2026-10-01）

- Android 14 独立模拟器从 0.6.0（versionCode 11）完整升级到 0.6.1（versionCode 12）：应用检查线上清单、下载线上约 93 MB APK、校验、授权安装来源、系统确认更新均成功。没有使用 adb 安装替代升级步骤。
- 升级前写入应用私有 files 目录的数据标记，升级后仍可读取；包名与安装签名保持一致。真机厂商安装器差异尚待用户设备验证。
- RSA 签名测试覆盖正常清单、内容篡改和错误公钥；无限闯关、街机、双人同步流程与音色相关回归测试通过。
- 发布目录与桌面交付包 SHA-256：`d550c30399026b12ac834f35b6df9d304fd37cd6bea824e5e4202109fe6af397`。
- 验证截图：[发现新版](ota-update-offer.png)、[系统安装确认](ota-system-install.png)、[升级后检查最新版](ota-latest.png)。

## 参考

系统安装来源授权：[Android PackageManager](https://developer.android.com/reference/android/content/pm/PackageManager#canRequestPackageInstalls())。
文件授权使用独立的非导出 FileProvider，仅暴露私有缓存内的 OTA 子目录：[Android FileProvider](https://developer.android.com/reference/androidx/core/content/FileProvider)。
