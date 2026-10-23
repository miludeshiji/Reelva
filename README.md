# Reelva

Reelva 是一个客户端优先的跨平台影视库与播放器项目，首批目标平台为 Windows 和 Android。

M0 工程基线与 M1 播放器最小闭环已由用户验收。当前实现止于 M4：在既有媒体源、SQLite/Drift 索引、影视识别与海报墙之上，加入观看进度保存与恢复、首页继续观看和最近添加、字幕音轨选择及基础快捷键。Windows / Android 的本轮实机验收尚未完成，因此尚不标记为首个可用 MVP；M4 成果等待用户审查，未经审查不进入 M5。

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

需要应用格式化修改时，运行 `fvm dart format lib test`。静态检查使用 `flutter_lints`，并启用严格类型转换、类型推断和泛型检查。应用依赖版本由 `pubspec.lock` 锁定。CI 在 Ubuntu 24.04 上运行；本地文件系统测试使用实际大小写路径，externalId 仅 Windows 转小写，其他平台保留大小写。

### 本地启动

以下命令会构建并启动应用，需获得明确授权后执行。

```sh
# Windows
fvm flutter run -d windows

# 查看连接的 Android 设备，再将下一行的设备 ID 替换为实际值
fvm flutter devices
fvm flutter run -d <android-device-id>
```

Windows 需要 Visual Studio 的桌面 C++ 工具链；新增的 `flutter_secure_storage_windows` 还要求安装 C++ ATL 组件。Android 需要 Android SDK、JDK 和已接受的 SDK 许可证；可通过 `fvm flutter doctor -v` 查看环境状态。许可证需由开发者自行审阅并接受。

## 目录与依赖

| 目录 | 职责 |
| --- | --- |
| `lib/main.dart` | 绑定、错误处理、media_kit 与 Windows 窗口初始化，Riverpod 入口 |
| `lib/app/` | 根应用、路由和自适应导航 |
| `lib/core/database/` | SQLite / Drift 数据库结构定义与迁移管理（Schema v2，保留 v1 数据） |
| `lib/core/errors/`、`lib/core/logging/` | 错误处理与日志脱敏 |
| `lib/features/sources/` | 媒体源管理、扫描调度、进度状态与跨平台适配器（Windows 本地文件系统 / Android SAF 目录授权） |
| `lib/features/library/` | 作品分页海报墙、电影/季集详情、多版本选择与解析播放 |
| `lib/features/metadata/` | 文件名解析、TMDB 请求与缓存、匹配评分、自动/手动匹配及安全凭据 |
| `lib/features/player/` | 播放器领域、应用、基础设施与播放界面分层 |
| `lib/features/home/`、`lib/features/progress/` | 首页继续观看与最近添加、按作品/剧集保存进度、节流与播放生命周期管理 |
| `lib/features/settings/` | TMDB 凭据、缓存管理与关于界面 |
| `lib/shared/widgets/` | 共用空状态、品牌标识与有回收策略的海报图片缓存 |
| `test/` | 导航、数据库迁移、文件名识别、匹配与锁定、缓存/限流、扫描及播放流程测试 |
| `android/`、`windows/` | 原生平台工程 |

UI 界面通过 `SourceController` 驱动媒体源操作与扫描调度，通过 `MediaSourceAdapter` 跨平台统一抽象访问本地文件系统与 SAF 树状授权目录，通过 `MediaLibraryRepository` 读写 SQLite 数据库，并统一将条目解析为播放资源后跳转 `/player`。播放器边界保持独立，通过 `PlayerEngine` 及 `PlaybackSession` 管理播放生命周期。

数据库沿用 Drift Schema v2，在原有 8 张表上增加的 `external_ids` 与 `metadata_cache` 及 v1 增表、增列迁移保持不变。M4 直接使用已有 `playback_progress` 表，按电影作品或具体剧集保存进度及最近播放文件 ID；同一目标切换文件版本时共享进度。保存事务会重新确认文件当前关联，以兼容后台元数据合并；移除媒体源仍保留观看历史。

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
| `flutter_secure_storage` | 11.2.0 |
| `cached_network_image` / `flutter_cache_manager` | 3.4.1 / 3.4.5 |

## 平台兼容性与验证边界

| 平台 | 配置与依赖事实 | 既有原生验证记录 |
| --- | --- | --- |
| Windows | Flutter 支持 Windows 10/11；锁定的 `media_kit_libs_windows_video` 1.0.11 使用 x86_64 原生库，目标为 Windows x64 | M1 已获用户验收。M2 阶段调试构建成功并走到系统目录选择；完整导入与真实播放仍待手工验收。本轮 M4 仅使用测试环境，未构建或启动原生应用 |
| Android | 固定 SDK 默认 minSdk 24、compileSdk/targetSdk 36、NDK 28.2.13676358；安全存储插件要求 minSdk 23，项目满足版本条件 | M1 已获用户验收。M2 SAF 目录真机验收未通过；本轮只读检查可见 Android 12 / API 32 设备，未安装或启动应用，SAF、字幕音轨和生命周期仍待实机验收 |
| Linux / macOS / iOS / Web | 本次未创建这些平台的工程 | 未验证 |

Android 工程使用 Flutter 3.47.7 模板的 AGP 9.1.0、Gradle 9.3.1 和 Kotlin 2.4.0，Java 目标版本为 17；应用 ID 为 `dev.reelva.reelva`。Windows 工程使用 CMake 3.14+ 和 C++17。应用内标识、Windows 多尺寸 ICO 与 Android 普通及自适应启动图标均以既有 `assets/Reelva.svg` 为唯一图形来源，SVG 原稿未改动。

依赖解析与 Widget 测试不能证明原生插件集成或设备播放可用。M4 仅运行获准的静态分析、单元/Widget 测试及测试环境运行时验证，没有执行 `flutter build`、`flutter run`、签名、推送或发布。Android 备份规则仅排除安全存储使用的 SharedPreferences，保留普通数据库备份规则；平台实际备份恢复行为仍需设备验收。
本机依赖解析沿用了既有腾讯云 Pub 镜像配置，下载源及校验摘要记录于 `pubspec.lock`。未修改全局 SDK、下载镜像、Android 许可证或 adb 配置。

## M4 观看进度与首页使用

1. **保存与续播**：从影视库详情或首页「继续观看」播放已索引文件，进度归属于电影作品或具体剧集，不依赖文件路径。播放中约每 10 秒异步保存一次；暂停、定位、停止、切换视频、退出页面及进入后台时保存变化，重复状态不重复写库。Windows 播放页拦截标题栏关闭，等待保存与引擎释放后关闭窗口。
2. **恢复规则**：重开后，未完成且至少 5 秒的进度自动续播；不足 5 秒或达到总时长 90% 的记录从头播放。换版本时读取同一作品/剧集的进度，并在新媒体实际时长到达后处理越界。停止保留停下前的位置，主动拖回零秒会保存为零。直接在播放器选择未入库文件或输入 URL 不会创建作品历史。
3. **首页**：「继续观看」按最近观看时间排列，同一电视剧显示最近未完成的一集；优先使用上次的文件版本，文件不可用时尝试同一目标的其他可用版本。「最近添加」按作品首次入库时间排列，同一作品多个版本只显示一张卡片。两组均最多展示 20 部；离线条目保留并可进入详情重新选择来源，加载失败可单独重试。
4. **字幕与音轨**：播放器底部菜单列出内嵌音轨和字幕，可选自动、具体轨道或关闭。轨道实际可用性取决于媒体文件与原生解码能力；本轮未增加外置字幕文件选择。
5. **键盘**：空格播放/暂停，左右方向键后退/前进 10 秒，上下方向键调节 5% 音量，Esc 退出全屏。定位和音量限制在有效范围；输入框、对话框和菜单获得焦点时避让其操作。
6. **错误与退出**：播放错误显示安全提示与重试/换文件入口；进度读写失败单独提示，不中断视频，后续保存成功后清除提示。系统强杀、崩溃或突然断电无法等待最后一次异步保存，可能丢失尚未落盘的进度。

测试证据、全部变更文件及 Windows / Android 待验收场景见 [M4 验收记录](docs/M4-Acceptance.md)。原生播放、窗口关闭和 Android SAF 权限跨重启仍需设备验证，不能由 Widget 测试替代。

## M3 影视识别、匹配与海报墙

1. **识别与浏览**：扫描完成或首次进入影视库后，对未处理文件提取标题、年份、画质及季集信息。电影和电视剧采用不同关联结构；明确的 `S01E05`、`01x05` 和 `S00E02` 可以建立季集记录，没有年份也能浏览和选择文件播放。
2. **多版本作品**：影视库按作品分页，一部作品只显示一张卡片。点击进入详情，在电影版本列表或剧集季/集列表中选择文件，沿用既有媒体源解析与播放器。来源离线或文件缺失时保留记录并提供错误反馈。
3. **配置 TMDB**：在「设置」输入 TMDB v3 API Key 或 API Read Access Token，可粘贴带 `Bearer` 前缀的令牌。凭据使用系统安全存储，保存后清空输入框，不回显旧凭据；可移除凭据。保存失败会明确提示，不回退到明文存储。
4. **自动与手动匹配**：扫描成功、首次打开影视库或点击刷新后，后台按标题、年份、类型匹配；年份未知、结果相近或结构不确定时保留本地条目。在详情页打开手动匹配，修改关键词与年份、选择电影/剧集结果并确认；未确定季集的单集文件选定剧集后需明确填写季号/集号，TMDB确认该集存在后才迁移关联并锁定，取消不改变原候选。匹配到同一 TMDB 身份的作品会合并版本，详情页转到合并后的作品。
5. **本地纠错与锁定**：无密钥也可编辑本地标题、年份、简介和 TMDB 海报相对路径（如 `/image_name.jpg`，留空可清除）。手动匹配及编辑会设置 `metadata_locked`；后续扫描和自动匹配不会覆盖锁定内容。需要更正时可再次手动编辑或匹配。
6. **离线与缓存**：未配置密钥仍可浏览、播放本地索引。搜索和详情持久缓存分别保留 7 天与 14 天的新鲜期；无密钥或网络不可用时允许读取已有缓存，已保存的作品元数据不受网络状态影响。网络请求串行节流，并遵守 429 冷却时间；失败在影视库显示，可重试或进入设置。
7. **海报与署名**：海报使用 TMDB 缩略图及磁盘缓存，按 300 个缓存对象、30 天闲置策略回收，可在设置清空；这不是磁盘字节硬上限。关于页包含保持[官方图形、渐变和宽高比的 TMDB Logo](https://www.themoviedb.org/about/logos-attribution)、[官方要求的署名声明](https://developer.themoviedb.org/docs/faq)及第三方许可证入口。SVG 样式等价转为内联填充，以兼容 Flutter 渲染。libmpv/FFmpeg 的分发许可仍需结合实际原生构建核对。

多集范围、未知集号等文件保留为待确认候选，不自动展开成虚构的单集；完整的跨集关联编辑尚未提供。M3 阶段未使用真实 TMDB 凭据，在线服务与海报下载未验证；Windows / Android 的原生安全存储和平台集成亦未验证，这些限制仍然保留。

## M2 媒体源与本地影视库使用

1. **添加媒体源**：进入「媒体源」页面，点击「添加媒体源」，可填写可选显示名称、视频扩展名白名单（默认 `mkv, mp4, avi, mov, m4v, ts, webm`）与排除目录名称（默认 `.cache, $RECYCLE.BIN, System Volume Information`）；随后通过 Windows 系统目录选择器或 Android SAF 授权选择目标文件夹。
2. **扫描与源管理**：添加成功后自动开启首次广度优先扫描，可在媒体源卡片中实时查看已访问目录数与发现视频数，支持随时取消扫描。空闲时可通过条目按钮重新扫描，或通过菜单进行重命名、同根目录重新授权与移除源。重复扫描复用已建索引与稳定 ID；扫描失败或取消不会清空数据库，也不会整批将旧条目误标缺失。
3. **影视库与解析播放**：进入「影视库」按初始 100 部作品浏览海报墙，底部可加载更多。点击作品查看电影版本或季集列表，再选择文件解析播放；失败保留详情视图并提供安全重试提示，避免并发重复点击。
4. **存储与视频安全**：扫描仅索引元数据，绝不复制或移动原始视频文件。Windows 数据库默认保存在用户 `Documents/reelva.sqlite`，Android 位于应用内部文档目录。

## M1 播放器使用与历史验收

从首页的「打开播放器」或从影视库条目解析后进入独立播放页。界面提供播放/暂停、停止、进度拖动、倍速、音量、静音、全屏，以及 M4 增加的字幕/音轨选择与快捷键，显示播放进度、总时长、缓冲及安全错误提示。进入后台会暂停并保存进度；退出页面等待保存与引擎释放。全屏下返回或按 Esc 先退出全屏，再返回首页。Windows 使用系统文件选择器；Android 使用 `ACTION_OPEN_DOCUMENT` 获取单文件临时读取授权并转换为描述符。

## 验证现状说明

M4 本轮静态分析、单元/Widget 测试、真实本地文件与磁盘 SQLite 恢复验证的最终结果见 [M4 验收记录](docs/M4-Acceptance.md)。此前 M3 首次交付为 198 项测试通过，后续手动匹配回归及 Loopback HTTP / Dio / SQLite 链路亦有通过记录。各阶段测试替身和 Widget 渲染均不等同于 Windows / Android 真机验收。

重新生成启动图标时，在安装 `resvg-py` 与 `Pillow` 后执行 `python tool/generate_icons.py`；应用运行不依赖 Python。Android 自适应图标使用黑色背景和带安全边距的前景。

## 错误与日志

Flutter 框架错误和未处理的平台异步错误统一进入脱敏日志。构建错误显示通用中文提示，未知路由不显示原始请求路径。

日志在输出消息、异常和堆栈前过滤常见认证头、Cookie、令牌、密码及 API 密钥字段，并隐藏网络 URL。TMDB 凭据仅存于系统安全存储；数据库缓存键不包含凭据，请求不跟随重定向，界面仅显示安全错误。不要记录原始请求载荷、无字段标识的秘密或私密文件内容。
