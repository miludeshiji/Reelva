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
| 同目录字幕 | 模糊匹配 | 授权单文件无法枚举同目录 | `sub-auto=fuzzy`，可改为 exact/no |
| 字体 | Microsoft YaHei | Noto Sans CJK SC | `sub-font` |
| 字幕字号 / 描边 / 柔化 / 垂直边距 | 60 / 8 / 1 / 40 | 相同 | `sub-font-size`、`sub-border-size`、`sub-blur`、`sub-margin-y`，白字黑边 |
| ASS 样式 | 保留原始样式并允许兼容调整 | 相同 | `sub-ass-override=yes`，可选 no/force；yes 不强制覆盖 ASS 字体和字号 |
| 字幕随视频处理 | 开启 | 开启 | `blend-subtitles=video` |

通过显式设置受支持的缩放参数实现高质量选项，而非整套加载随 mpv 版本变化的 `profile=high-quality`。`vd-lavc-dr=yes` 保留直接渲染支持。没有强制 `hwdec-codecs=all`，让各平台选择兼容的解码路径。

## 生命周期与存储

- `PlayerSettings` 保存类型化配置并验证缓存、音量、字幕参数及语言格式；`PlayerSettingsStore` 复用既有 `FlutterSecureStorage` 依赖，以独立 JSON 项保存本机偏好，不修改数据库或同步载荷。
- 启动时读取配置，失败记录脱敏日志并使用平台默认值。设置页保存成功后才更新内存配置，失败保留原值并提示重试。
- 创建播放会话时固定配置；视频控制器继续由 media_kit 创建。加载媒体前等待控制器就绪，再应用原生参数，避免 Android 初始化覆盖字体边距等设置。保存配置不会重建当前会话，下次进入播放器生效。
- 开启 `PlayerConfiguration.libass`，由 libmpv 绘制普通文本和 ASS 字幕，避免同时绘制 Flutter 文本字幕。Android 通过 `libassAndroidFont` 加载随应用提供的字体，无需枚举整个系统字体目录。

## 独立 mpv 配置的适配边界

- **渲染后端**：Windows 使用 media_kit 的 `vo=libmpv` 纹理输出，Android 保留插件管理的 GPU/Surface 初始化。独立窗口的 `vo=gpu-next`、`gpu-api=d3d11`、`gpu-context=d3d11`、独占全屏及窗口外观不能直接套用。
- **显示同步与 ICC**：显示同步插帧依赖显示时序；libmpv Render API 的 ICC 自动管理要求宿主提供 ICC 数据。当前 Flutter 嵌入未接入这些能力，因此不暴露无法保证生效的开关，也不强制 `vf=format=gamma=gamma2.2` 改写视频色彩标记。相关说明见 [mpv 官方手册](https://mpv.io/manual/stable/#options-icc-profile-auto)。
- **字幕黑边**：黑边由 Flutter 视频布局处理，不能保证 `sub-ass-force-margins` 把原生字幕放入该区域，故未提供该选项。
- **外围功能**：窗口、快捷键、播放结束和观看进度由应用管理，不套用 `keep-open`、播放列表循环、mpv OSC/OSD、`watch-later`、个人日志和截图目录。未接入的截图、SVP IPC、VapourSynth 和外部 shader 保持独立，不执行个人配置中的脚本或路径。
- **外挂轨道**：自动加载仅适用于 libmpv 能枚举的本地目录。SAF 单文件的 fd、网络播放代理都不能枚举源目录；没有新增这些来源的字幕发现或手动外挂选择功能。

## 字体来源与许可

`assets/fonts/NotoSansCJKsc-Regular.otf` 来自 [Noto CJK 官方仓库](https://github.com/notofonts/noto-cjk/blob/main/Sans/OTF/SimplifiedChinese/NotoSansCJKsc-Regular.otf)，字体文件约 16 MB，采用 SIL Open Font License 1.1。完整许可位于 `assets/licenses/NotoSansCJK.txt`，并登记到应用的第三方许可证页面。

原生画质、硬件解码回退及 Android 字体加载仍需 Windows / Android 实机播放确认；静态分析和测试不替代设备验收。
