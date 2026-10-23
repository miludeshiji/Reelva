# Reelva

Reelva 是一个客户端优先的跨平台影视库与播放器项目，首批目标平台为 Windows 和 Android。

M0 工程基线与 M1 播放器最小闭环已由用户验收。当前实现已推进并止于 M2：实现了媒体源管理、基于 SQLite/Drift 的本地影视库、目录扫描与解析播放链路，等待用户手工验收。
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
| `lib/core/database/` | SQLite / Drift 数据库结构定义与迁移管理（Schema v1） |
| `lib/core/errors/`、`lib/core/logging/` | 错误处理与日志脱敏 |
| `lib/features/sources/` | 媒体源管理、扫描调度、进度状态与跨平台适配器（Windows 本地文件系统 / Android SAF 目录授权） |
| `lib/features/library/` | 本地影视库仓储、列表分页展示与解析跳转播放 |
| `lib/features/player/` | 播放器领域、应用、基础设施与播放界面分层 |
| `lib/features/home/`、`lib/features/settings/` | 首页与设置界面 |
| `lib/shared/widgets/` | 共用空状态组件与 Reelva SVG 标识 |
| `test/` | 导航外壳、数据库、仓储、扫描控制器、适配器、UI 流程与播放器生命周期测试 |
| `android/`、`windows/` | 原生平台工程 |

UI 界面通过 `SourceController` 驱动媒体源操作与扫描调度，通过 `MediaSourceAdapter` 跨平台统一抽象访问本地文件系统与 SAF 树状授权目录，通过 `MediaLibraryRepository` 读写 SQLite 数据库，并统一将条目解析为播放资源后跳转 `/player`。播放器边界保持独立，通过 `PlayerEngine` 及 `PlaybackSession` 管理播放生命周期。

数据库基于 Drift 实现 Schema v1，包含 8 张核心表：`media_sources`、`media_entries`、`media_files`、`works`、`seasons`、`episodes`、`media_assignments`、`playback_progress`。M2 阶段将扫描到的视频文件自动创建为未刮削的本地作品候选，标题采用无后缀文件名，不引入任何模拟海报或伪造数据；库中已定义的季、集、关联及播放进度表结构仅作为基础 schema 准备，不代表已实现 M3 元数据刮削与 M4 进度同步功能。
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
| Windows | Flutter 支持 Windows 10/11；锁定的 `media_kit_libs_windows_video` 1.0.11 使用 x86_64 原生库，目标为 Windows x64 | M1 已获用户验收。本轮 M2 Windows `fvm flutter build windows --debug --no-pub` 构建成功，Debug 应用已正常启动并走到系统目录选择，随后按用户要求停止自动化验证；目录完整导入、应用重启后状态恢复及库内视频真实播放仍待用户手工验收 |
| Android | 固定 SDK 默认 minSdk 24、compileSdk/targetSdk 36、NDK 28.2.13676358；媒体视频插件的 compileSdk 为 36，原生包提供 ARM32、ARM64、x86_64 等 ABI | M1 已获用户验收。当前 `adb devices` 为空，Android SAF 目录真机验收未通过。Android 调试构建曾遇 Kotlin 增量缓存跨盘错误，关闭增量缓存的替代构建在用户要求下已取消，无有效 APK 构建通过结论，不提供预构建 APK |
| Linux / macOS / iOS / Web | 本次未创建这些平台的工程 | 未验证 |

Android 工程使用 Flutter 3.47.7 模板的 AGP 9.1.0、Gradle 9.3.1 和 Kotlin 2.4.0，Java 目标版本为 17；应用 ID 为 `dev.reelva.reelva`。Windows 工程使用 CMake 3.14+ 和 C++17。应用内标识、Windows 多尺寸 ICO 与 Android 普通及自适应启动图标均以既有 `assets/Reelva.svg` 为唯一图形来源，SVG 原稿未改动。

依赖解析和 Widget 测试不能证明原生插件集成或设备播放可用。M1 基础播放与界面已完成用户验收；本轮 M2 聚焦于媒体源管理、文件系统/SAF 遍历与本地影视库索引，在用户明确要求下停止进一步自动化测试与真机操作，未打包发布成品应用。
本机依赖解析沿用了既有腾讯云 Pub 镜像配置，下载源及校验摘要记录于 `pubspec.lock`。未修改全局 SDK、下载镜像、Android 许可证或 adb 配置。

## M2 媒体源与本地影视库使用

1. **添加媒体源**：进入「媒体源」页面，点击「添加媒体源」，可填写可选显示名称、视频扩展名白名单（默认 `mkv, mp4, avi, mov, m4v, ts, webm`）与排除目录名称（默认 `.cache, $RECYCLE.BIN, System Volume Information`）；随后通过 Windows 系统目录选择器或 Android SAF 授权选择目标文件夹。
2. **扫描与源管理**：添加成功后自动开启首次广度优先扫描，可在媒体源卡片中实时查看已访问目录数与发现视频数，支持随时取消扫描。空闲时可通过条目按钮重新扫描，或通过菜单进行重命名、同根目录重新授权与移除源。重复扫描复用已建索引与稳定 ID；扫描失败或取消不会清空数据库，也不会整批将旧条目误标缺失。
3. **影视库与解析播放**：扫描完成后进入「影视库」，视频条目按初始 100 条分页展示，滑至底部可点击「加载更多 (+100)」。点击条目由控制器通过适配器解析出播放资源并自动载入播放器；解析失败保留当前库视图并提供安全重试提示，避免并发重复点击。
4. **存储与视频安全**：扫描仅索引元数据，绝不复制或移动原始视频文件。Windows 数据库默认保存在用户 `Documents/reelva.sqlite`，Android 位于应用内部文档目录。

## M1 播放器使用与历史验收

从首页的「打开播放器」或从影视库条目解析后进入独立播放页。界面提供播放/暂停、停止、进度拖动、倍速、音量、静音与全屏，显示播放进度、总时长、缓冲及安全错误提示。进入后台会暂停；退出页面等待引擎释放。全屏下返回或按 Esc 先退出全屏，再返回首页。Windows 使用系统文件选择器；Android 使用 `ACTION_OPEN_DOCUMENT` 获取单文件临时读取授权并转换为描述符。

## 验证现状说明

已完成数据库仓储、增量扫描、适配器与 UI 界面的针对性逻辑编写与部分测试执行。此前整套测试曾因测试代码编译错误及 Drift 查询流取消的 Timer 导致运行超时，分析器亦报告过测试文件符号与回调参数问题；相关回调参数、TargetPlatform 导入与 `pump(Duration.zero)` 定时器排空已完成代码调整。因用户明确要求停止自动化测试并由用户自行进行手工验收，未再执行静态分析或全套测试复验，不得声称当前静态分析或全套测试已全绿通过。
重新生成启动图标时，在安装 `resvg-py` 与 `Pillow` 后执行 `python tool/generate_icons.py`；应用运行不依赖 Python。Android 自适应图标使用黑色背景和带安全边距的前景。

## 错误与日志

Flutter 框架错误和未处理的平台异步错误统一进入脱敏日志。构建错误显示通用中文提示，未知路由不显示原始请求路径。

日志在输出消息、异常和堆栈前过滤常见认证头、Cookie、令牌、密码及 API 密钥字段，并隐藏网络 URL，避免泄漏 URL 用户凭据和签名参数。日志脱敏不替代凭据管理；不要记录原始请求载荷、无字段标识的秘密或私密文件内容。安全存储将在实际接入凭据时引入。
