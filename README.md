# Reelva

Reelva 是一个客户端优先的跨平台影视库与播放器项目，首批目标平台为 Windows 和 Android。

当前实现范围为 **M0：项目初始化与工程基线**：Reelva 应用标题、Material 3 暗色主题、首页 / 影视库 / 媒体源 / 设置导航、统一错误处理和脱敏日志。宽屏使用侧栏，窄屏使用底部导航；未知路由可返回首页。

这些页面目前展示空状态。播放器初始化与播放、媒体源添加、扫描、数据库表和 TMDB 接入尚未实现；M1 需要在 M0 审查通过后另行授权。

## 开发环境与检查

使用 FVM 和仓库的 `.fvmrc` 固定 **Flutter 3.47.7 / Dart 3.13.5**，不要使用可能指向其他 SDK 的裸 `flutter` / `dart` 命令。

```sh
fvm install
fvm flutter --version
fvm flutter pub get
fvm dart format --output=none --set-exit-if-changed lib test
fvm flutter analyze --no-pub
fvm flutter test --no-pub
```

需要应用格式化修改时，运行 `fvm dart format lib test`。静态检查使用 `flutter_lints`，并启用严格类型转换、类型推断和泛型检查。应用依赖版本由 `pubspec.lock` 锁定。

### 本地启动

以下命令会构建并运行应用，**须获用户授权后执行**；本次 M0 工作没有执行原生构建或启动。

```sh
# Windows
fvm flutter run -d windows

# 查看连接的 Android 设备，再将下一行的设备 ID 替换为实际值
fvm flutter devices
fvm flutter run -d <android-device-id>
```

Windows 需要 Visual Studio 的桌面 C++ 工具链。Android 需要 Android SDK、JDK 和已接受的 SDK 许可证；可通过 `fvm flutter doctor -v` 查看环境状态。许可证需由开发者自行审阅并接受。

## 目录与依赖

| 目录 | 职责 |
| --- | --- |
| `lib/main.dart` | 绑定初始化、统一错误处理和 Riverpod 入口 |
| `lib/app/` | 根应用、路由和自适应导航 |
| `lib/features/` | 四个基础页面 |
| `lib/core/errors/`、`lib/core/logging/` | 错误处理与日志脱敏 |
| `lib/shared/widgets/` | 页面共用空状态组件 |
| `test/` | 导航 Widget 测试、错误处理与日志单元测试 |
| `android/`、`windows/` | 原生平台工程 |

只创建已有实现需要的目录，尚未引入数据库、播放器或媒体源服务的空接口。

| 核心依赖 | 锁定版本 | M0 用途 |
| --- | --- | --- |
| `flutter_riverpod` | 3.4.3 | 根作用域与路由生命周期 |
| `go_router` | 18.1.1 | 四个页面与错误路由恢复 |
| `drift` / `drift_flutter` | 2.35.2 / 0.3.1 | 工程依赖基线，未创建数据库 |
| `dio` | 5.11.1 | 工程依赖基线，未发起业务请求 |
| `media_kit` / `media_kit_video` / `media_kit_libs_video` | 1.2.6 / 2.0.1 / 1.0.7 | 工程依赖基线，未初始化播放器 |

## 平台兼容性与验证边界

| 平台 | 配置与依赖事实 | 当前验证范围 |
| --- | --- | --- |
| Windows | Flutter 支持 Windows 10/11；锁定的 `media_kit_libs_windows_video` 1.0.11 使用 x86_64 原生库，因此当前目标为 Windows x64 | 本机 Windows 11 x64 的 Visual Studio 工具链已识别；原生编译、启动和播放未验证 |
| Android | 固定 SDK 默认 minSdk 24、compileSdk/targetSdk 36、NDK 28.2.13676358；媒体视频插件的 compileSdk 为 36，原生包提供 ARM32、ARM64、x86_64 等 ABI | 本机 SDK 36、JDK 17 已识别；部分 SDK 许可证未接受且存在多个 adb；真机、模拟器及原生插件集成未验证 |
| Linux / macOS / iOS / Web | 本次未创建这些平台的工程 | 未验证；不承诺 Web 原生 libmpv |

Android 工程使用 Flutter 3.47.7 模板的 AGP 9.1.0、Gradle 9.3.1 和 Kotlin 2.4.0，Java 目标版本为 17；应用 ID 为 `dev.reelva.reelva`。Windows 工程使用 CMake 3.14+ 和 C++17。保留模板启动图标，既有 `assets/Reelva.svg` 未改动。

依赖解析和 Widget 测试不能证明原生插件已兼容或视频可播放。media_kit 的平台构建脚本会在后续原生构建时下载 libmpv 等二进制；M0 未触发这些平台构建。正式签名和发布配置不在本阶段范围内。

本机依赖解析沿用了既有腾讯云 Pub 镜像配置，下载源及校验摘要记录于 `pubspec.lock`。未修改全局 SDK、下载镜像、Android 许可证或 adb 配置。

## 错误与日志

Flutter 框架错误和未处理的平台异步错误统一进入脱敏日志。构建错误显示通用中文提示，未知路由不显示原始请求路径。

日志在输出消息、异常和堆栈前过滤常见认证头、Cookie、令牌、密码及 API 密钥字段，并隐藏网络 URL，避免泄漏 URL 用户凭据和签名参数。日志脱敏不替代凭据管理；不要记录原始请求载荷、无字段标识的秘密或私密文件内容。安全存储将在实际接入凭据时引入。

## 参考

- [Flutter 支持平台](https://docs.flutter.dev/reference/supported-platforms)
- [go_router API](https://pub.dev/documentation/go_router/latest/go_router/GoRouter-class.html)
- [Riverpod ProviderScope](https://pub.dev/documentation/flutter_riverpod/latest/flutter_riverpod/ProviderScope-class.html)
- [Drift 平台支持](https://drift.simonbinder.eu/platforms/)
- [media_kit 官方安装与平台说明](https://github.com/media-kit/media-kit)

本地开发任务书位于 `docs/Reelva-Development-Plan.md`；保留仓库既有规则，该目录仍被 Git 忽略。

## M0 验证记录

- `fvm flutter pub get`：成功，使用锁定依赖。
- `fvm dart format lib test`：完成。
- `fvm flutter analyze --no-pub`：通过，0 个问题。
- `fvm flutter test --no-pub --reporter expanded`：19 项通过，包含 17 项常驻测试和 2 项临时截图检查。临时截图脚本已删除，常驻测试覆盖四页导航、直接路由、未知路由恢复、小视口与大字体、错误处理和凭据脱敏。
- Widget 视觉检查：已查看 1200×800 桌面布局和 390×844 手机布局的中文文字、Material 图标与空状态；截图保留于被忽略的 `build/m0-smoke/`，不作为原生运行证明。
- Windows / Android 原生构建、启动与插件运行：未验证；本次未执行 `flutter build`、`flutter run`、提交、推送或发布。

M0 工程实现及获准的自动化检查已完成，原生启动验收保留上述限制；等待用户审查后再决定进入 M1。
