# 架构总览

Reelva 是客户端优先的跨平台影视库与播放器，首批目标平台为 Windows 和 Android。可选的跨设备增量同步基于 WebDAV，不影响离线使用，也不上传视频文件。

## 目录结构

| 目录 | 职责 |
| --- | --- |
| `lib/main.dart` | 绑定、错误处理、media_kit 与 Windows 窗口初始化，Riverpod 入口 |
| `lib/app/` | 根应用、路由和自适应导航 |
| `lib/core/database/` | SQLite / Drift 数据库结构定义与迁移管理（Schema v4，保留 v1/v2/v3 数据） |
| `lib/core/errors/`、`lib/core/logging/` | 错误处理与日志脱敏 |
| `lib/features/sources/` | 本地/SAF、WebDAV、SMB 与 OpenList 网盘媒体源管理、登录和扫描，凭据快照、内核运行时、远程播放解析及按需读取桥接 |
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

- UI 通过 `SourceController` 驱动媒体源操作与扫描，通过 `MediaSourceAdapter` 访问本地文件系统、SAF、WebDAV、SMB 或内置 OpenList 网盘，通过 `MediaLibraryRepository` 持久化索引和作品关联。
- 百度、夸克、115、123 四个入口共用 `kind = openlist` 适配器。根定位符为 `openlist://<账号标识>/<目录>/`，条目标识为根内相对路径；账号标识与逻辑路径参与索引和同步，临时下载链接不作为文件身份。Windows 在后台 isolate 中通过 C ABI 调用 DLL，Android 通过 MethodChannel 在原生线程池调用 AAR，两端共用 JSON RPC。
- 百度、115、123 的内置网页登录及百度、123 默认在线续期使用 `api.oplist.org`；夸克网页登录后从原生 Cookie 存储读取授权。也可手填驱动所需 Token / Cookie；网页登录使用 `flutter_inappwebview`，Windows 需要 WebView2 Runtime。
- 播放使用 `PlaybackResource`：网络源在真正打开或重试时准备播放租约，退出、停止或切换时释放；SMB 随机读通过 libsmb2 在 worker isolate 中执行，读取分片最大 256 KiB，避免预先复制整部视频。网盘在准备租约时解析直链及其 Cookie、Referer、User-Agent 等请求头，交由现有 HTTP 桥接按需转发；401/403 后单次重新解析并重试，同目录字幕复用源的授权和播放准备流程。
- 播放器通过 `PlayerEngine` 和 `PlaybackSession` 管理生命周期，不依赖具体网络源协议。网络播放桥接仅监听随机端口的 IPv4 回环地址；HTTP 起播先探测 `Range: bytes=0-0` 并校验 `206`、`Content-Range` 与长度，仅返回 `200` 的服务器可顺序起播。

## 数据库与观看进度

数据库使用 Drift Schema v4（SQLite），保留 v1/v2/v3 的升级路径、媒体索引、元数据缓存、人工锁定与观看历史，并新增同步状态，不重建既有数据库。Windows 数据库默认保存在 `%APPDATA%\com.github.miludeshiji\Reelva\reelva.sqlite`，播放器设置与加密凭据也保存在该目录，不自动迁移旧目录数据。Android 数据库位于应用内部文档目录。

- 观看进度按电影作品或具体剧集保存，不依赖文件路径；同一目标切换文件版本时共享进度。保存事务重新确认文件当前关联，兼容后台元数据合并；移除媒体源仍保留历史。
- 播放中约每 10 秒异步保存一次；暂停、定位、停止、切换视频、退出页面及进入后台时保存变化。重开后，未完成且至少 5 秒的进度自动续播，不足 5 秒或达到总时长 90% 的记录从头播放。

## 凭据与安全边界

- 主应用 SQLite 的 `media_sources.credential_ref` 只保存凭据引用与稳定文件身份，临时签名直链不入库。WebDAV、SMB、TMDB 及同步服务凭据保存在系统安全存储，输入框不回显旧秘密。
- 网盘内核另在 `getApplicationSupportDirectory()/openlist/openlist.db` 保存账号驱动配置和刷新后的 Token / Cookie，属于明文凭据；系统安全存储同时保存可迁移的授权快照。Windows 对应 `%APPDATA%\com.github.miludeshiji\Reelva\openlist\`，Android 对应应用私有 `files/openlist/`。手工备份整个应用数据目录会包含这些秘密，不能将该数据库当作无凭据索引分发。
- 多个媒体目录可以引用同一网盘账号。移除最后一个启用目录时清理内核账号和安全存储快照；仍有其他启用目录时保留账号。内核首次初始化清理没有启用源引用的内核账号，不删除主应用媒体源记录、作品索引或观看历史。
- 媒体源授权及 TMDB 密钥进入独立的应用配置同步文件，可选密码加密，不设置密码时明文保存，不进入观看进度批次。备份从内核回读最新授权，不复制整个内核数据库，也不导出临时签名直链；恢复优先保留本机已有授权，缺失账号使用同步快照，首次访问文件时再加载。同步服务连接与加密密码仍单独保存在系统安全存储。
- 日志在输出消息、异常和堆栈前过滤常见认证头、Cookie、令牌、密码及 API 密钥字段，并隐藏网络 URL；不记录原始请求载荷、无字段标识的秘密或私密文件内容。网络源错误不会回显服务端原始消息。
- TMDB 请求不跟随重定向；网络源对重定向执行来源与认证边界检查，不跨来源传播认证头或请求体。根目录 URL 不允许嵌入帐号密码、查询参数或相对跳转段，TLS 证书校验保持启用。

## 跨设备同步机制

- 观看进度按 TMDB 作品及季集身份保存至不可变增量批次；旧批次中的 metadata 修正记录仅解析并忽略。首次发送已有可同步记录，随后只发送变化，保留发件箱、接收游标与待应用记录。
- `reelva-sync-v1/` 中的应用配置文件同步媒体源及扫描规则、账号凭据、TMDB 密钥、平台播放器偏好、通用快捷键与按媒体源划分的影视库索引。密码可选：未设置时明文 JSON，设置后使用 AES-256-GCM、随机盐和 PBKDF2-HMAC-SHA256，密钥推导在后台 isolate 执行。已有加密文件必须正确解密后才能合并，错误密码不覆盖远端。读取原有 `application-v1.json` 以及各设备的 `application-<设备标识>.json`，按记录版本合并。原文件提供强 ETag 时继续条件更新；没有强 ETag 或只有弱 ETag 时，每台设备只更新自己的快照，同一设备的同步沿用单飞控制，不要求服务端提供 ETag，也不会覆盖其他设备的并发修改。
- 索引快照包含目录、文件、作品、季集、外部身份和版本关联，数据库编号在恢复时重新映射，图片只传可迁移的源内定位符。索引捕获读取本机 SQLite，不枚举媒体源或下载 NFO；网盘配置快照另外回读内核当前授权，内核尚无该账号时读取安全存储快照，不为备份重新加载该账号。接收后直接恢复浏览、播放与续播所需索引，不触发扫描。已有本机较新的作品字段保留，已移除文件保留不可用记录以保护历史。网盘使用跨设备稳定的网络源身份；同批次先恢复启用目录，再处理停用目录，避免换目录时删除仍需共享的账号。
- 凭据及配置同步基线保存在安全存储；索引快照及其待绑定数据保存在 SQLite，基线只记录内容摘要，避免将整个影视库反复写入安全存储。扫描中的源不生成未完成快照。本地源由各设备选择目录建立绑定，绑定后直接恢复索引；Android 按使用需要定位具体文件，SAF 授权仍由系统获取，不传递设备授权或运行状态。
- 记录按版本合并，同一条记录同时修改时按发现修改的时间与设备标识确定结果。无 TMDB 身份的观看进度继续保留在本机；收到尚无目标的进度在索引恢复或匹配后应用。同步默认关闭，仅由用户手动触发，远端历史批次不自动清理。

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
| `cryptography` | 2.9.0 |
| `dart_smb2` | 0.2.3 |
| `flutter_inappwebview` | 6.2.0-beta.3 |
| Venera OpenList Core / JSON RPC ABI | 0.1.0-beta.5 / 1 |

## 平台与原生工程

| 平台 | 配置与依赖事实 |
| --- | --- |
| Windows | Flutter 支持 Windows 10/11；锁定的 `media_kit_libs_windows_video` 1.0.11 使用 x86_64 原生库，目标为 Windows x64；工程使用 CMake 3.14+ 和 C++17 |
| Android | Flutter 模板默认 minSdk 24、compileSdk/targetSdk 36、NDK 28.2.13676358；安全存储插件要求 minSdk 23，项目满足版本条件；AGP 9.1.0、Gradle 9.3.1、Kotlin 2.4.0，Java 目标版本 17，应用 ID `com.github.miludeshiji.reelva` |
| Linux / macOS / iOS / Web | 未创建这些平台的工程 |

OpenList 原生包由固定 Release 下载并随应用分发：Windows x64 使用 `venera_openlist.dll`，Android 使用含 armeabi-v7a、arm64-v8a、x86_64 的 `openlistcore.aar`。版本、源提交、RPC ABI 与平台 SHA-256 固定在 `native/openlist_core/core.lock.json`；获取流程见[开发检查](../development/build.md)。

Android 云备份与设备迁移规则排除安全存储使用的 SharedPreferences、`files/openlist/` 内核目录和 `app_webview/` 登录会话，保留普通影视库数据库备份。`path_provider_android` 将应用支持目录映射到 `Context.filesDir`，因此内核目录使用备份规则的 `file/openlist/` 路径。应用内标识、Windows 多尺寸 ICO 与 Android 普通/自适应启动图标均以 `assets/Reelva.svg` 为唯一图形来源；图标重新生成见[开发检查](../development/build.md)。

## 许可

- `dart_smb2` 使用 worker isolate 和 libsmb2 原生共享库；首次执行对应平台的测试/构建时，其 hook 从固定的 `libsmb2-r9` 下载原生库并核对 SHA-256，Android 最低 API 24 与项目设置一致。原生库采用 LGPL-2.1+，关于页及第三方许可证入口登记了完整许可文本与[上游源码](https://github.com/sahlberg/libsmb2)、[对应二进制构建来源](https://github.com/ales-drnz/dart_smb2/releases/tag/libsmb2-r9)，应用内附带 `assets/licenses/libsmb2.txt`。
- 关于页包含保持[官方图形、渐变和宽高比的 TMDB Logo](https://www.themoviedb.org/about/logos-attribution)与[官方要求的署名声明](https://developer.themoviedb.org/docs/faq)；海报缓存按 300 个缓存对象、30 天闲置策略回收（非磁盘字节硬上限）。
- 内置 [Venera OpenList Core](https://github.com/Venera-Works/Venera-OpenList-Core/tree/core-v0.1.0-beta.5) 采用 AGPL-3.0，固定 `core-v0.1.0-beta.5` 源码与原生包。关于页及第三方许可入口登记内核与源码链接，应用附带 `assets/licenses/openlist.txt`；下载包中的许可证也随原生库安装。
- libmpv/FFmpeg 的分发许可仍需结合实际原生构建核对。

## 验证边界（既有记录，保留待验证事实）

以下为既有的手工/真机验收边界，静态分析、单元与 Widget 测试、协议 smoke 不能替代：

- **Windows**：调试构建成功并走到系统目录选择；完整导入与真实播放仍待手工验收。
- **Android**：SAF 目录真机验收未通过；原生播放、字幕音轨和生命周期仍待实机验收。平台实际备份恢复行为需设备验收。
- **TMDB 在线**：未使用真实凭据，在线服务与海报下载未验证；Windows / Android 的原生安全存储和平台集成亦未验证。
- **内置网盘**：本次未构建或运行应用；四家真实账号登录、Token / Cookie 续期、大文件播放与拖动跳转、Windows WebView2 和 Android 原生加载及备份恢复均待设备验收。
- **未验证平台**：Linux / macOS / iOS / Web 未验证。

## 目录元数据

`NfoService` 通过现有媒体源的 `MediaSidecarAdapter` 读取 NFO 和图片，并向可写来源保存匹配资料，数据库保留快速查询索引。扫描按目录导入 NFO，电视剧上下文沿扫描队列传给季目录；匹配及人工编辑在数据库事务完成后导出，保存失败单独反馈。图片定位符保存在独立索引字段，设备内源编号不直接进入同步载荷，索引中的图片引用转换为源内路径后恢复。Schema v4 新增作品完整上映日期、目录图片定位符和分集 TMDB ID。

影视库点击刷新时只对已有索引执行 TMDB 匹配；媒体源扫描按钮负责重新枚举目录并导入 NFO，启动、进入影视库及源扫描结束均不主动触发匹配。NFO 成功写回后记录本机字段快照，后续扫描可更新已锁定且没有待写回修改的条目。OpenList 适配器实现 `ReadOnlyMediaSidecarAdapter`，允许读取已有 NFO、图片并遵守小文件大小限制；自动导出跳过只读源，新的匹配及人工修改只保存在本机索引并可同步，不向网盘上传 NFO 或图片。
