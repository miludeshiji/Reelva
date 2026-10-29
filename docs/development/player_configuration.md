# 播放器配置

Reelva 参考独立 mpv 配置中的画质、缓存、音频与字幕偏好，通过现有 media_kit 接入 libmpv。用户入口为「设置 → 播放器」。

## 默认值与参数

| 设置 | Windows 默认值 | Android 默认值 | libmpv 对应选项 |
| --- | --- | --- | --- |
| 硬件解码 | 自动 | 沿用 media_kit 平台自动选择 | `VideoControllerConfiguration.hwdec`；关闭时 `no` |
| 高质量缩放 | 开启 | 关闭 | 高质量使用 `scale=ewa_lanczossharp`、`dscale=mitchell`、`cscale=catmull_rom`，并开启正确降采样、线性降采样和 sigmoid 放大；关闭时使用 bilinear |
| 去色带 | 开启 | 关闭 | `deband` |
| 抖动目标色深 | 自动 | 自动 | `dither=fruit`、`dither-depth=auto`；支持 8/10 位及关闭；这不是 10 位端到端输出保证 |
| 预读缓存 | 开启，1024 MiB | 开启，128 MiB | `cache=yes`、`cache-on-disk=no`、`demuxer-max-bytes`；回退缓存为前向上限的四分之一，最多 64 MiB |
| 倍速音调修正 | 开启 | 开启 | `audio-pitch-correction=yes`，保留 `PlayerConfiguration.pitch=false`，避免启用独立音调控制 |
| 最大音量 | 200% | 200% | `volume-max`；控制栏滑块、键盘及引擎遵循同一会话上限 |
| 同目录音频 | 模糊匹配 | 仅对可访问目录有效 | `audio-file-auto=fuzzy`，可改为 exact/no |
| 字幕语言 | 中文优先，英文其次 | 相同 | `slang=zh,chi,chs,sc,zh-hans,en,eng`；可修改顺序或留空 |
| 同目录字幕 | 模糊匹配 | 授权目录同样支持，单文件可手动选择字幕 | 本地目录使用 `sub-auto`；媒体源目录由应用发现，均可改为精确匹配或关闭 |
| 字体 | Microsoft YaHei | Noto Sans CJK SC | `sub-font` |
| 字幕字号 / 描边 / 柔化 / 垂直边距 | 60 / 8 / 1 / 40 | 相同 | `sub-font-size`、`sub-border-size`、`sub-blur`、`sub-margin-y`，白字黑边 |
| ASS 样式 | 保留原始样式并允许兼容调整 | 相同 | `sub-ass-override=yes`，可选 no/force；yes 不强制覆盖 ASS 字体和字号 |
| 字幕随视频处理 | 开启 | 开启 | `blend-subtitles=video` |

通过显式设置受支持的缩放参数实现高质量选项，而非整套加载随 mpv 版本变化的 `profile=high-quality`。`vd-lavc-dr=yes` 保留直接渲染支持。没有强制 `hwdec-codecs=all`，让各平台选择兼容的解码路径。

## 生命周期与存储

- `PlayerSettings` 保存类型化配置并验证缓存、音量、字幕参数及语言格式；`PlayerSettingsStore` 复用既有 `FlutterSecureStorage` 依赖，以独立 JSON 项保存本机偏好；配置同步按平台合并，密码加密可选，快捷键跨平台同步，不修改数据库结构。
- 启动时读取配置，失败记录脱敏日志并使用平台默认值。播放器与快捷键页修改后立即更新本机配置并自动保存，连续修改按顺序写入；保存失败时回退到已保存的配置并提示重试。文本输入只保存格式有效的值，不阻塞其他选项；右上角恢复默认图标会重置本页配置并自动保存。
- 携带视频进入播放页时，首帧直接显示沉浸式播放布局，读取续播进度、解析与缓冲均在其中显示加载状态；单独打开播放器时保留文件选择界面。
- 创建播放会话时固定配置；视频控制器继续由 media_kit 创建。加载媒体前等待控制器就绪，再应用原生参数，避免 Android 初始化覆盖字体边距等设置。保存配置不会重建当前会话，下次进入播放器生效。
- 开启 `PlayerConfiguration.libass`，由 libmpv 绘制普通文本和 ASS 字幕，避免同时绘制 Flutter 文本字幕。Android 通过 `libassAndroidFont` 加载随应用提供的字体，无需枚举整个系统字体目录。
- WebDAV、SMB 和 SAF 媒体源通过源适配器枚举同目录字幕，起播后异步加载，不阻塞视频资源解析。匹配使用 `PlaybackResource.fileName` 保留的原始文件名，不受刮削后片名、集名等显示标题影响。精确模式匹配视频同名文件；模糊模式另接受带语言等分隔后缀的字幕，避免把相近集号混配。按语言偏好优先选择，用户手动切换后，迟到的自动字幕只加入可选轨道。
- 播放页字幕菜单可选择本地字幕或浏览已启用媒体源中的字幕目录。远程字幕复用原有认证和回环播放桥接，Android 复用只读 FD；停止、切换和销毁后释放字幕租约及句柄，字幕加载失败不将视频置为播放失败。
- 左上角返回与系统返回共用退出流程：先捕获当前进度并启动会话释放，再放行路由返回；不让原生播放器或远程租约的异步释放阻塞页面退出。退出中停止按视频尺寸重设方向，路由返回后恢复系统方向和窗口亮度，进度写入与资源释放继续完成。

## 快捷键

用户入口为「设置 → 快捷键」。默认按键参考个人 `input.conf`，完整列表见[用户指南](../user/guide.md#播放器)。快捷键和鼠标配置作为 `PlayerSettings.input` 保存，旧配置缺少该字段时使用默认值，不迁移数据库，不影响已有画质、字幕和音频偏好。

- Flutter 负责接收按键，按逻辑键与 Ctrl / Shift / Alt / Meta 精确匹配；Enter 和小键盘 Enter 等价。设置页捕获实际按键，允许清除绑定、检测冲突和恢复本页默认值，修改后自动保存。每次进入播放页固定一份输入配置。
- 普通定位默认 2 秒、大幅定位 60 秒，普通音量 2%、大幅音量 5%；滚轮分别为 2% 和 2 秒，可独立调整。速度以 0.1 递增或递减，支持恢复正常倍速和减半 / 加倍，范围 0.1–16 倍。
- 播放、定位、倍速、音量和轨道操作复用 `PlayerEngine`，继续遵循音量上限和观看进度保存；逐帧、章节、字幕 / 音频延迟、字幕位置 / 缩放、硬解、反交错、比例、A-B / 单文件循环、旋转和均衡器调整通过固定操作映射至 libmpv 命令。章节和逐帧操作经过 `ProgressPlayerEngine`，不绕过进度层。
- 控制操作不在输入框或弹窗背后触发。定位、音量、倍速及连续微调接收按键重复事件；播放 / 暂停、全屏、循环等切换操作忽略重复。
- Windows 播放焦点通过原生通道临时解除 Flutter 窗口的 IME 上下文关联，使中文输入法不拦截快捷键；焦点进入文本输入框、离开播放页或销毁窗口时恢复原上下文。使用 [ImmAssociateContext](https://learn.microsoft.com/en-us/windows/win32/api/imm/nf-imm-immassociatecontext)，不切换系统键盘布局。
- 长按视频画面或无修饰键的右方向键约半秒，临时切换为 3 倍速，独立于自动隐藏控件在画面上方中央显示「3倍速中」，不主动唤出进度条与播放按钮；长按时的触屏轻微移动、鼠标移动也不唤出控制栏。松开、触摸取消、失焦或进入后台时恢复长按前的倍速并隐藏提示。右方向键短按在松开时执行原绑定，长按期间不重复定位；禁用键盘快捷键时不启用右方向键长按。
- Tab 切换 Flutter 播放信息面板，通过 `PlayerEngine.getStatistics()` 按需读取 [mpv 播放属性](https://mpv.io/manual/stable/#properties)，包含视频、音频、硬解、丢帧、音画同步和缓存信息。面板每秒刷新一次，关闭后取消刷新，缺失字段显示「—」，查询不修改播放或进度状态；无需 Lua 统计脚本。Tab 可改绑，已有自定义 Tab 配置优先保留。
- 鼠标仅在视频曲面上处理单击、双击、右键菜单和滚轮，不接管控制栏上的鼠标操作；触屏点按继续显示 / 隐藏控件。鼠标菜单使用 Flutter，包含播放、全屏、静音、轨道和单文件循环等已支持操作。
- Android 触屏双击切换播放 / 暂停；纵向手势按起点锁定左侧亮度或右侧音量，不接管控制栏操作。中央浮窗在调节时显示数值，松手后短暂保留；音量复用播放引擎与会话上限，亮度通过原生通道设置当前窗口的 [screenBrightness](https://developer.android.com/reference/android/view/WindowManager.LayoutParams#screenBrightness)，退出时恢复原窗口设置。未修改系统亮度偏好，不申请写系统设置权限。
- Android 播放页在画面左右中间提供锁定与截图按钮，横竖屏共用同一布局。锁定时取消临时倍速及滑动调节，隐藏并禁用普通控件、状态操作和播放快捷键，触屏只切换解锁与截图按钮的显示，3 秒后自动隐藏；播放状态变化不重新唤出普通控件。系统返回先解锁，再沿用退出流程，锁定状态不持久化。
- 截图经 `PlayerEngine.captureFrame()` 与进度层转发，使用 media_kit 抓取包含 libass 字幕的视频帧 PNG，不截取 Flutter 界面，不改变播放与进度状态。Android 原生通道在后台线程写入 `Pictures/Reelva`，Android 10 及以上使用 MediaStore 的待发布图片，写入失败清理未完成记录；Android 9 及以下仅在保存时申请旧版写存储权限，写入后通知媒体扫描。保存期间禁用重复点击，抓帧或写入失败仅提示截图错误，不将视频置为播放失败。
- 所有临时播放调整只影响当前播放会话，不自动写回默认配置。不加载原始 `input.conf`，也不启用 mpv 的窗口输入处理，避免与 Flutter 的全屏、窗口和焦点管理重复。

应用从影视库已有文件关联生成按季集排序的播放列表，使用已保存的集名，同集版本优先保留当前文件及同源可用版本；选集时才通过媒体源解析地址，并沿用同一播放会话与观看进度层。播放列表、字幕和音频复用 `PlayerSelectionPanel`，统一面板样式并对齐到播放列表按钮上方。Windows 在取得视频显示尺寸后，按客户区比例缩放窗口并计入原生标题栏与边框；全屏期间不缩放，返回窗口模式后重新适配。`DesktopWindowController` 在进入播放器时保留原窗口状态，退出时等待尺寸适配结束再恢复窗口位置、尺寸及最大化状态；播放期间不将临时窗口尺寸写入应用偏好。主界面窗口尺寸、最大化状态及侧栏折叠状态通过既有安全存储单独保存在本机，启动时恢复，不参与跨设备同步。右上角菜单中的「视频信息」与 Tab 共用统计面板。

原配置依赖的最近播放 Lua、playlistmanager、OSC、控制台、独立窗口缩放 / 边框 / 置顶、SVP / VapourSynth 和 Anime4K 文件没有对应实现，不提供无效绑定；`#menu` 注释也不作为原生菜单导入。截图通过 Android 播放页按钮提供，不导入独立 mpv 的截图绑定与目录配置。应用选集不使用 mpv 原生播放列表。F9 和反斜杠改用应用信息弹窗与进度提示。原生命令语义以 [mpv 官方手册](https://mpv.io/manual/stable/#list-of-input-commands)为准，真实设备上的逐帧、章节、硬解和画面处理仍需播放验收。

## 独立 mpv 配置的适配边界

- **渲染后端**：Windows 使用 media_kit 的 `vo=libmpv` 纹理输出，Android 保留插件管理的 GPU/Surface 初始化。独立窗口的 `vo=gpu-next`、`gpu-api=d3d11`、`gpu-context=d3d11`、独占全屏及窗口外观不能直接套用。
- **显示同步与 ICC**：显示同步插帧依赖显示时序；libmpv Render API 的 ICC 自动管理要求宿主提供 ICC 数据。当前 Flutter 嵌入未接入这些能力，因此不暴露无法保证生效的开关，也不强制 `vf=format=gamma=gamma2.2` 改写视频色彩标记。相关说明见 [mpv 官方手册](https://mpv.io/manual/stable/#options-icc-profile-auto)。
- **字幕黑边**：黑边由 Flutter 视频布局处理，不能保证 `sub-ass-force-margins` 把原生字幕放入该区域，故未提供该选项。
- **外围功能**：窗口、快捷键、播放结束和观看进度由应用管理，不套用 `keep-open`、播放列表循环、mpv OSC/OSD、`watch-later`、个人日志和截图目录。未接入的 SVP IPC、VapourSynth 和外部 shader 保持独立，不执行个人配置中的脚本或路径。
- **外挂轨道**：自动字幕发现需要可枚举的媒体源目录；单独输入 HTTP/HTTPS 视频地址、Android 单文件授权没有源目录信息，可手动选择字幕。手动和媒体源自动发现支持 SRT、ASS、SSA、VTT、SMI/SAMI、SUP；可直接访问的本地目录保留 libmpv 原有的自动发现。SAF 文档 ID 按不透明标识处理，优先调用 Android 的 [findDocumentPath](https://developer.android.com/reference/android/provider/DocumentsContract#findDocumentPath(android.content.ContentResolver,%20android.net.Uri)) 查询父目录，provider 不支持时遍历授权树。字幕添加使用 [sub-add](https://mpv.io/manual/stable/#track-manipulation)，并核对原生轨道列表确认加载结果。

## 字体来源与许可

`assets/fonts/NotoSansCJKsc-Regular.otf` 来自 [Noto CJK 官方仓库](https://github.com/notofonts/noto-cjk/blob/main/Sans/OTF/SimplifiedChinese/NotoSansCJKsc-Regular.otf)，字体文件约 16 MB，采用 SIL Open Font License 1.1。完整许可位于 `assets/licenses/NotoSansCJK.txt`，并登记到应用的第三方许可证页面。

原生画质、硬件解码回退及 Android 字体加载仍需 Windows / Android 实机播放确认；静态分析和测试不替代设备验收。
