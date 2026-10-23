# Reelva

Reelva 是一个客户端优先的跨平台影视库与播放器项目，首批目标平台为 Windows 和 Android。

当前交付范围为 M0 工程基线与 M1 播放器最小闭环。播放器代码、单元与 Widget 行为、Windows 无窗口 libmpv 播放已验证；M1 原生应用与 Android SAF 播放仍待设备验收，尚未进入 M2。

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

以下命令会构建并启动应用，需获得明确授权后执行。

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
| `lib/main.dart` | 绑定、错误处理、media_kit 与 Windows 窗口初始化，Riverpod 入口 |
| `lib/app/` | 根应用、路由和自适应导航 |
| `lib/features/` | 四个基础页面与播放器的领域、应用、基础设施、界面分层 |
| `lib/core/errors/`、`lib/core/logging/` | 错误处理与日志脱敏 |
| `lib/shared/widgets/` | 共用空状态组件与 Reelva SVG 标识 |
| `test/` | 导航、播放器状态与生命周期、文件选择、交互、错误处理与日志测试 |
| `android/`、`windows/` | 原生平台工程 |

播放器界面通过 `PlayerEngine` 控制播放，由 `MediaKitPlayerEngine` 适配 media_kit；视频视图与引擎通过 `PlaybackSession` 组合。Android 文档描述符仅由适配层管理。尚未实现媒体库、数据库读写或媒体源服务。

| 核心依赖 | 锁定版本 |
| --- | --- |
| `flutter_riverpod` | 3.4.3 |
| `go_router` | 18.1.1 |
| `drift` / `drift_flutter` | 2.35.2 / 0.3.1 |
| `dio` | 5.11.1 |
| `media_kit` / `media_kit_video` / `media_kit_libs_video` | 1.2.6 / 2.0.1 / 1.0.7 |
| `file_selector` | 1.1.0 |
| `flutter_svg` | 2.3.0 |
| `window_manager` | 0.5.2 |

## 平台兼容性与验证边界

| 平台 | 配置与依赖事实 | 当前验证范围 |
| --- | --- | --- |
| Windows | Flutter 支持 Windows 10/11；锁定的 `media_kit_libs_windows_video` 1.0.11 使用 x86_64 原生库，因此当前目标为 Windows x64 | 在本机 Windows 11 x64 使用真实 libmpv DLL 无窗口验证 MP4、MKV、公开 HTTP/HTTPS 视频；M1 原生窗口、视频纹理、系统文件对话框和窗口全屏尚未验收 |
| Android | 固定 SDK 默认 minSdk 24、compileSdk/targetSdk 36、NDK 28.2.13676358；媒体视频插件的 compileSdk 为 36，原生包提供 ARM32、ARM64、x86_64 等 ABI | SAF 通道契约、权限错误映射与描述符释放时序已有 Dart 测试；本次未编译或运行 Android 应用，系统选取器、实际文档读取、播放与沉浸式全屏尚未在设备上验收 |
| Linux / macOS / iOS / Web | 本次未创建这些平台的工程 | 未验证 |

Android 工程使用 Flutter 3.47.7 模板的 AGP 9.1.0、Gradle 9.3.1 和 Kotlin 2.4.0，Java 目标版本为 17；应用 ID 为 `dev.reelva.reelva`。Windows 工程使用 CMake 3.14+ 和 C++17。应用内标识、Windows 多尺寸 ICO 与 Android 普通及自适应启动图标均以既有 `assets/Reelva.svg` 为唯一图形来源，SVG 原稿未改动。

依赖解析和 Widget 测试不能证明原生插件集成或设备播放可用。Windows 无窗口验证直接加载真实 libmpv DLL，覆盖开播、暂停与恢复、中段及近结尾 Seek、倍速与音量属性、停止和释放，不包含原生窗口显示或声音输出验收。本轮没有构建、打包或启动 M1 应用，也未签名、推送或发布。

本机依赖解析沿用了既有腾讯云 Pub 镜像配置，下载源及校验摘要记录于 `pubspec.lock`。未修改全局 SDK、下载镜像、Android 许可证或 adb 配置。

## M1 播放器使用与验收

从首页的「打开播放器」进入独立播放页，可选择本地单个视频，或输入带主机名的 HTTP/HTTPS 地址。界面提供播放/暂停、停止、进度拖动、倍速、音量、静音与全屏，显示播放进度、总时长、缓冲及安全错误提示。进入后台会暂停；退出页面等待引擎释放。全屏下返回或按 Esc 先退出全屏，再返回首页。

Windows 使用系统文件选择器。Android 使用 `ACTION_OPEN_DOCUMENT` 获取单文件临时读取授权，通过 `ContentResolver.openFileDescriptor` 将 `content://` 转为供 libmpv 使用的文件描述符；取消选择不改变播放，切换或退出时先停止底层读取再释放描述符。M1 不持久化 URI 授权，不做目录扫描；云文档提供方的读取和 Seek 能力仍需实际验证。

已完成的原生播放验证使用 [W3C Sintel MP4](https://media.w3.org/2010/05/sintel/trailer.mp4)、其本地 MP4 样本与 MKV 重封装样本，以及公开 HTTP 地址的重定向访问。Seek 结果仅适用于这些样本；没有验证任意服务端的 Range 支持。测试保持静音，不能作为实际音频设备输出的验收依据。

单元与 Widget 测试覆盖播放状态、缓冲/暂停语义、错误保留进度、并发打开/关闭、描述符关闭顺序、路径与权限处理、重复进入、延迟选择回传、全屏返回和 Esc。另以 1200×800、390×844 的 Widget 渲染检查了布局和品牌标识；其视频区域是测试静态画面，不代表真实视频纹理或 Android 设备截图。依赖本机 DLL、样本和系统字体的临时验收脚本不纳入常规测试集。

重新生成启动图标时，在安装 `resvg-py` 与 `Pillow` 后执行 `python tool/generate_icons.py`；应用运行不依赖 Python。Android 自适应图标使用黑色背景和带安全边距的前景。

## 错误与日志

Flutter 框架错误和未处理的平台异步错误统一进入脱敏日志。构建错误显示通用中文提示，未知路由不显示原始请求路径。

日志在输出消息、异常和堆栈前过滤常见认证头、Cookie、令牌、密码及 API 密钥字段，并隐藏网络 URL，避免泄漏 URL 用户凭据和签名参数。日志脱敏不替代凭据管理；不要记录原始请求载荷、无字段标识的秘密或私密文件内容。安全存储将在实际接入凭据时引入。
