# 发布与 CI 工作流

Reelva 通过 GitHub Actions 提供 3 个工作流，覆盖质量分析、跨平台构建与正式发布。日常开发检查见 [build.md](./build.md)。

## 工作流总览

| 工作流 | 文件 | 触发条件 | 产物（保留期） |
| --- | --- | --- | --- |
| 代码分析 | `.github/workflows/analyze.yml` | Pull Request、`main` 分支推送、被发布工作流调用（`workflow_call`） | `dart-coverage` 覆盖率（14 天） |
| 跨平台构建 | `.github/workflows/build.yml` | Pull Request（覆盖源码、资源、配置及脚本等关键路径）、手动触发（`workflow_dispatch`）、被发布工作流调用（`workflow_call`） | `android-arm64-v8a`、`android-armeabi-v7a`、`android-x86_64`、`windows-x64`（各 7 天） |
| 版本发布 | `.github/workflows/release.yml` | 仅推送版本标签 `v*` | `release-notes` 发布日志（1 天）与 GitHub Release 附件 |

- **代码分析**：检查锁定依赖（`flutter pub get --enforce-lockfile`）、全项目 Dart 格式、静态分析、单元与部件测试及覆盖率，并运行发布元数据校验脚本的标准单元测试。PR 与常规推送可取消旧运行；被发布流程调用时禁止取消。
- **跨平台构建**：输入参数 `build_android`（布尔，默认 `true`）、`build_windows`（布尔，默认 `true`）、`release`（布尔，手动默认 `false`）。构建平台不可全部关闭。PR 冒烟构建无条件执行 Debug 模式，严禁注入或读取正式签名 Secrets。

### 构建产物命名（`{version}` 为 `pubspec.yaml` 去除 `+build` 后的版本名）

正式构建（`release: true`）生成 5 个文件：

- `Reelva-{version}-android-arm64-v8a.apk`
- `Reelva-{version}-android-armeabi-v7a.apk`
- `Reelva-{version}-android-x86_64.apk`
- `Reelva-{version}-windows-x64.zip`（便携包，附带 MSVC CRT 运行库）
- `Reelva-{version}-windows-x64-installer.exe`（Inno Setup 安装程序）

Debug 构建（`release: false`，含 PR 与手动调试）只生成 3 个 `-debug.apk` 与 1 个 `Reelva-{version}-windows-x64-debug.zip`，不生成 Debug 安装包；Debug 包仅供编译与开发测试用途，不附带且不分发不可再分发的调试 CRT。

- Windows 安装程序基于 `windows/installer.iss`，使用 Inno Setup 内置默认语言编译，无代码签名；支持系统标准安装目录与可选当前用户安装模式，创建开始菜单快捷方式、可选桌面快捷方式及系统标准卸载入口（卸载不删除用户应用数据），支持 `/VERYSILENT` 静默安装；静默安装后不自动启动应用，交互安装可选择完成后启动。
- Android APK 按分架构拆分（`--split-per-abi`），目标平台为 arm、arm64、x64。Actions 产物按架构独立上传，每个下载项只包含对应架构的 APK；正式发布时收集这三个产物，并分别上传为 Release 附件。

## Android 签名

### 本地签名

正式构建使用本地密钥签名，密钥库文件位于 `android/reelva-release.jks`，别名为 `reelva`。构建配置通过 `android/key.properties` 读取，`storeFile` 相对于 `android` 目录解析：

```properties
storeFile=reelva-release.jks
keyAlias=reelva
storePassword=<本地填写真实值>
keyPassword=<本地填写真实值>
```

在本地打包 Release 前，需在该文件中追加真实的 `storePassword` 和 `keyPassword`。密钥文件与 `key.properties` 均已配置为 Git 忽略，切勿提交到版本库。正式构建缺失凭据时直接失败，不会回退到调试证书；Debug 构建无需正式凭据。更换为正式签名后，生成的安装包无法覆盖此前安装的调试签名版本，需先卸载旧包（卸载会清除应用本地数据）。

### CI Secrets

正式构建与发布依赖仓库 Secrets，配置时不要在文档、Issue 或日志中粘贴真实秘密：

- **`ANDROID_KEYSTORE`**：正式签名证书库（JKS 文件）的 Base64 编码字符串。CI 在严格权限（`umask 077`）下解码写入临时文件 `android/keystore.jks`，构建完成后清理。
- **`ANDROID_KEY_PROPERTIES`**：`key.properties` 的原始多行属性配置文本。CI 构建解析路径固定为相对 `android` 目录的 `keystore.jks`：

```properties
storeFile=keystore.jks
keyAlias=<你的别名>
storePassword=<你的 keystore 密码>
keyPassword=<你的 key 密码>
```

PR 与手动调试构建不使用上述 Secrets；正式构建若缺失任一凭据将直接失败。

## 版本发布流程

推送 `v*` 标签（如 `v0.1.0` 或 `v0.1.0-beta1`）触发 `release.yml`，流程不可并发取消：

1. **元数据校验**：调用 `.github/scripts/release_metadata.py` 核验版本规范、Tag 严格匹配、CHANGELOG 对应章节、Beta 警告与正式版 README 下载链接，提取发布日志并上传 `release-notes` 产物。
2. **质量门禁**：调用 `analyze.yml` 执行完整分析与测试。
3. **正式构建**：调用 `build.yml`（双平台、`release: true`），传入仓库 Android 签名 Secrets。
4. **GitHub Release**：下载全部 5 个产物与发布日志；已公开版本严禁修改覆盖，若存在同名草稿则予以恢复；一次性完整上传产物并公开。正式版设为 latest 发布，Beta 版设为 prerelease 且不设为 latest。

### 发布准备清单

1. **版本号规范**（`pubspec.yaml` 的 `version` 字段）：
   - 正式版本：`X.Y.Z+<正整数>`（如 `0.1.0+1`），Git Tag 必须为 `vX.Y.Z`（如 `v0.1.0`）。
   - Beta 版本：`X.Y.Z-beta<N>+<正整数>`（`N ≥ 1`，如 `0.1.0-beta1+1`），Git Tag 必须为 `vX.Y.Z-beta<N>`。
2. **CHANGELOG.md**：必须建立 `## v<版本名>` 章节并包含非空更新日志。
   - **Beta 版本**：发布工具会在 Release 日志正文顶部自动添加两行警告（`## **注意**` 与 `**beta版可能存在大量bug，无必要请勿下载**`），无需在 CHANGELOG 中手动编写。
   - **正式版本严禁**在 CHANGELOG 中带有上述 Beta 警告。
3. **README.md 下载链接（仅正式版要求）**：正式版本发布前，必须在 README.md 中提供当前版本全部 5 个产物的完整 GitHub Release 下载链接，形如：

   - `https://github.com/miludeshiji/Reelva/releases/download/<tag>/Reelva-<version>-android-arm64-v8a.apk`
   - `https://github.com/miludeshiji/Reelva/releases/download/<tag>/Reelva-<version>-android-armeabi-v7a.apk`
   - `https://github.com/miludeshiji/Reelva/releases/download/<tag>/Reelva-<version>-android-x86_64.apk`
   - `https://github.com/miludeshiji/Reelva/releases/download/<tag>/Reelva-<version>-windows-x64.zip`
   - `https://github.com/miludeshiji/Reelva/releases/download/<tag>/Reelva-<version>-windows-x64-installer.exe`

   Beta 版本不强制要求在 README 中配置下载链接。注意：README 校验在推送标签时执行，链接应随标签对应的提交一并提交；当前 0.1.0 尚未发布，请勿提前写入尚不存在的 Release 链接，以上占位符仅说明发布前的更新规则，避免被发布校验器误识别。
