# 架构总览

Reelva 是客户端优先的跨平台影视库与播放器，首批目标平台为 Windows 和 Android。可选的跨设备增量同步基于 WebDAV，不影响离线使用，也不上传视频文件。

## 目录结构

| 目录 | 职责 |
| --- | --- |
| `lib/main.dart` | 绑定、错误处理、media_kit 与 Windows 窗口初始化，Riverpod 入口 |
| `lib/app/` | 根应用、路由和自适应导航 |
| `lib/core/database/` | SQLite / Drift 数据库结构定义与迁移管理（Schema v4，保留 v1/v2/v3 数据） |
| `lib/core/errors/`、`lib/core/logging/` | 错误处理与日志脱敏 |
| `lib/features/sources/` | 本地/SAF、WebDAV、SMB 媒体源管理与扫描，安全凭据、远程播放解析及按需读取桥接 |
| `lib/features/library/` | 作品分页海报墙、电影/季集详情、多版本选择与解析播放 |
| `lib/features/metadata/` | 文件名解析、TMDB 请求与缓存、匹配评分、自动/手动匹配及安全凭据 |
| `lib/features/player/` | 播放器领域、应用、基础设施与播放界面分层 |
| `lib/features/home/`、`lib/features/progress/` | 首页继续观看与最近添加、按作品/剧集保存进度、节流与播放生命周期管理 |
| `lib/features/settings/` | 播放器偏好、TMDB 凭据、缓存管理、同步设置入口与关于界面 |
| `lib/features/sync/` | 稳定作品身份、增量批次、冲突合并、同步状态与可选 WebDAV 传输 |
| `lib/shared/widgets/` | 共用空状态、品牌标识与有回收策略的海报图片缓存 |
| `test/` | 导航、数据库迁移、识别与匹配、扫描与播放、同步合并及协议测试 |
| `android/`、`windows/` | 原生平台工程 |

## 核心数据流

- UI 通过 `SourceController` 驱动媒体源操作与扫描，通过 `MediaSourceAdapter` 访问本地文件系统、SAF 或网络协议（WebDAV、SMB），通过 `MediaLibraryRepository` 持久化索引和作品关联。
- 播放使用 `PlaybackResource`：网络源在真正打开或重试时准备播放租约，退出、停止或切换时释放；SMB 随机读通过 libsmb2 在 worker isolate 中执行，读取分片最大 256 KiB，避免预先复制整部视频。
- 播放器通过 `PlayerEngine` 和 `PlaybackSession` 管理生命周期，不依赖具体网络源协议。网络播放桥接仅监听随机端口的 IPv4 回环地址；HTTP 起播先探测 `Range: bytes=0-0` 并校验 `206`、`Content-Range` 与长度，仅返回 `200` 的服务器可顺序起播。

## 数据库与观看进度

数据库使用 Drift Schema v4（SQLite），保留 v1/v2/v3 的升级路径、媒体索引、元数据缓存、人工锁定与观看历史，并新增同步状态，不重建既有数据库。Windows 数据库默认保存在 `%APPDATA%\com.github.miludeshiji\Reelva\reelva.sqlite`，播放器设置与加密凭据也保存在该目录，不自动迁移旧目录数据。Android 数据库位于应用内部文档目录。

- 观看进度按电影作品或具体剧集保存，不依赖文件路径；同一目标切换文件版本时共享进度。保存事务重新确认文件当前关联，兼容后台元数据合并；移除媒体源仍保留历史。
- 播放中约每 10 秒异步保存一次；暂停、定位、停止、切换视频、退出页面及进入后台时保存变化。重开后，未完成且至少 5 秒的进度自动续播，不足 5 秒或达到总时长 90% 的记录从头播放。

## 凭据与安全边界

- 网络媒体源凭据复用 `media_sources.credential_ref`，SQLite 只保存安全存储引用与稳定文件身份；密码、令牌和播放请求头保存在系统安全存储，数据库不保存临时签名直链。
- TMDB 与网络源凭据仅存于系统安全存储，输入框不回显旧秘密；同步配置单独保存在系统安全存储，不纳入同步载荷；密码、API Token 和临时签名直链不会写入同步批次。
- 日志在输出消息、异常和堆栈前过滤常见认证头、Cookie、令牌、密码及 API 密钥字段，并隐藏网络 URL；不记录原始请求载荷、无字段标识的秘密或私密文件内容。网络源错误不会回显服务端原始消息。
- TMDB 请求不跟随重定向；网络源对重定向执行来源与认证边界检查，不跨来源传播认证头或请求体。根目录 URL 不允许嵌入帐号密码、查询参数或相对跳转段，TLS 证书校验保持启用。

## 跨设备同步机制

- 同步内容为观看进度、已看状态和人工修正的标题、年份、简介、海报路径。电影使用包含类型的 TMDB ID，剧集再使用真实季号与集号；两端数据库编号、文件路径和媒体源可以不同。视频、目录索引、账号密码和 TMDB 凭据均不上传。
- 增量批次不可变：首次同步发送已有可同步记录，随后仅发送变化记录；未完成的上传保存在本地可重试，已接收批次不重复应用。进度与人工元数据分别按版本自动合并，同一条记录同时修改时按修改时间及设备标识确定唯一结果。
- 无 TMDB 身份的本地候选不参与跨设备身份匹配；收到但本机尚无对应作品的记录保留为待应用记录，完成扫描与匹配后再次同步即可应用。同步默认关闭，仅提供手动同步；远端历史批次不会自动压缩或清理，服务端管理员可读取同步目录内容，没有额外的端到端加密。

## 核心依赖（锁定版本）

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
| `xml` | 7.0.1 |
| `dart_smb2` | 0.2.3 |

## 平台与原生工程

| 平台 | 配置与依赖事实 |
| --- | --- |
| Windows | Flutter 支持 Windows 10/11；锁定的 `media_kit_libs_windows_video` 1.0.11 使用 x86_64 原生库，目标为 Windows x64；工程使用 CMake 3.14+ 和 C++17 |
| Android | Flutter 模板默认 minSdk 24、compileSdk/targetSdk 36、NDK 28.2.13676358；安全存储插件要求 minSdk 23，项目满足版本条件；AGP 9.1.0、Gradle 9.3.1、Kotlin 2.4.0，Java 目标版本 17，应用 ID `com.github.miludeshiji.reelva` |
| Linux / macOS / iOS / Web | 未创建这些平台的工程 |

Android 备份规则仅排除安全存储使用的 SharedPreferences，保留普通数据库备份规则。应用内标识、Windows 多尺寸 ICO 与 Android 普通/自适应启动图标均以 `assets/Reelva.svg` 为唯一图形来源；图标重新生成见 [开发检查](../development/build.md)。

## 许可

- `dart_smb2` 使用 worker isolate 和 libsmb2 原生共享库；首次执行对应平台的测试/构建时，其 hook 从固定的 `libsmb2-r9` 下载原生库并核对 SHA-256，Android 最低 API 24 与项目设置一致。原生库采用 LGPL-2.1+，关于页及第三方许可证入口登记了完整许可文本与[上游源码](https://github.com/sahlberg/libsmb2)、[对应二进制构建来源](https://github.com/ales-drnz/dart_smb2/releases/tag/libsmb2-r9)，应用内附带 `assets/licenses/libsmb2.txt`。
- 关于页包含保持[官方图形、渐变和宽高比的 TMDB Logo](https://www.themoviedb.org/about/logos-attribution)与[官方要求的署名声明](https://developer.themoviedb.org/docs/faq)；海报缓存按 300 个缓存对象、30 天闲置策略回收（非磁盘字节硬上限）。
- libmpv/FFmpeg 的分发许可仍需结合实际原生构建核对。

## 验证边界（既有记录，保留待验证事实）

以下为既有的手工/真机验收边界，静态分析、单元与 Widget 测试、协议 smoke 不能替代：

- **Windows**：调试构建成功并走到系统目录选择；完整导入与真实播放仍待手工验收。
- **Android**：SAF 目录真机验收未通过；原生播放、字幕音轨和生命周期仍待实机验收。平台实际备份恢复行为需设备验收。
- **TMDB 在线**：未使用真实凭据，在线服务与海报下载未验证；Windows / Android 的原生安全存储和平台集成亦未验证。
- **未验证平台**：Linux / macOS / iOS / Web 未验证。

## 目录元数据

`NfoService` 通过现有媒体源的 `MediaSidecarAdapter` 读写 NFO 和图片，数据库保留快速查询索引。扫描按目录导入 NFO，电视剧上下文沿扫描队列传给季目录；匹配及人工编辑在数据库事务完成后导出，保存失败单独反馈。图片定位符保存在独立索引字段，设备内定位符不进入跨设备同步载荷。Schema v4 新增作品完整上映日期、目录图片定位符和分集 TMDB ID；打开数据库时清理已移除源的配置及凭据，保留观看历史。
