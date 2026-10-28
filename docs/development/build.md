# 开发检查

Reelva 的开发环境、日常检查与本地运行说明。发布签名与 CI 发布流程见 [release.md](./release.md)，代码结构与验证边界见 [../architecture/overview.md](../architecture/overview.md)。

## 工具链

- 使用 FVM 与仓库根目录的 `.fvmrc` 固定 **Flutter 3.47.7 / Dart 3.13.5**，不要使用可能指向其他 SDK 的裸 `flutter` / `dart` 命令。
- 应用依赖版本由 `pubspec.lock` 锁定；依赖解析沿用既有腾讯云 Pub 镜像配置（CI 中为 `PUB_HOSTED_URL`），下载源与校验摘要记录于 `pubspec.lock`。
- 静态检查使用 `flutter_lints`，并启用严格类型转换、类型推断和泛型检查。
- Windows 构建：需要 Visual Studio 桌面 C++ 工具链（MSVC x64）；`flutter_secure_storage_windows` 还要求安装 C++ ATL 组件。
- Android 构建：需要 Android SDK、JDK 17 和已接受的 SDK 许可证；许可证需由开发者自行审阅并接受，可通过 `fvm flutter doctor -v` 查看环境状态。
- Android 工程使用 Flutter 3.47.7 模板的 AGP 9.1.0、Gradle 9.3.1 和 Kotlin 2.4.0，Java 目标版本为 17；Windows 工程使用 CMake 3.14+ 和 C++17。

## 环境初始化

```sh
fvm install
fvm flutter --version
fvm flutter pub get
```

## OpenList 原生内核

内核使用 [Venera-OpenList-Core 的固定 Release](https://github.com/Venera-Works/Venera-OpenList-Core/releases/tag/core-v0.1.0-beta.5)，版本为 `0.1.0-beta.5`、JSON RPC ABI 为 `1`。`native/openlist_core/core.lock.json` 固定源码提交和平台包 SHA-256；`.github/scripts/fetch_openlist_core.py` 校验下载包摘要、版本、源码提交、ABI、目标架构和许可证后安装，不在用户设备运行时下载。

开发者准备对应目标的原生库：

```powershell
python .github/scripts/fetch_openlist_core.py windows-x64
python .github/scripts/fetch_openlist_core.py android
```

Windows 库安装到 `native/openlist_core/artifacts/windows/`，CMake 将 DLL 与许可证复制到应用目录；Android AAR 安装到 `android/app/libs/`，由 Gradle 打包，覆盖 armeabi-v7a、arm64-v8a、x86_64。CI 的构建工作流在构建前执行对应获取步骤，原生包不提交入库。以上命令只获取预编译依赖，不构建或启动 Reelva；应用构建仍遵守下方授权要求。

内置网页登录使用固定的 `flutter_inappwebview 6.2.0-beta.3`，其 Android 实现已改用 `proguard-android-optimize.txt`，兼容项目的 AGP 9.1。Windows 需要 Microsoft Edge WebView2 Runtime，缺失时可使用手动 Token / Cookie 配置；真实登录、原生加载和媒体播放仍需 Windows / Android 设备验证。

## 日常检查

```sh
fvm dart format --output=none --set-exit-if-changed .
fvm flutter analyze --no-pub
fvm flutter test --no-pub
```

开发完成后先运行 `fvm dart format .`，再执行上述格式检查。CI 的 `analyze.yml` 在推送 `main` 或 `feature/**` 分支、提交 PR 及被发布流程调用时运行；备份分支的推送不会触发。该工作流在 Ubuntu 24.04 执行相同的锁定依赖、格式、分析与测试检查，并额外上传覆盖率产物。写文件系统相关测试时注意：本地测试使用实际大小写路径，`externalId` 仅在 Windows 转小写，其他平台保留大小写。

## 本地运行（需明确授权）

以下命令会构建并启动应用，**需获得明确授权后执行；未经授权不得构建应用**。

```sh
# Windows
fvm flutter run -d windows

# 查看连接的 Android 设备，再将下一行的设备 ID 替换为实际值
fvm flutter devices
fvm flutter run -d <android-device-id>
```

Debug 构建无需正式签名凭据；本地 Release 打包的签名要求见 [release.md](./release.md)。

## 图标生成

应用内标识、Windows 多尺寸 ICO 与 Android 普通/自适应启动图标均以既有 `assets/Reelva.svg` 为唯一图形来源，SVG 原稿不要改动。重新生成图标：

```sh
pip install resvg-py pillow
python tool/generate_icons.py
```

应用运行不依赖 Python。Android 自适应图标使用黑色背景和带安全边距的前景。
