# media_kit 原生库提供插件

保留 `media_kit_libs_video` 的平台依赖，通过根目录 `dependency_overrides` 固定以下两个提供插件。Java/C++ 桥接代码与 MIT 许可证沿用上游，仅调整原生库资源与下载校验；不修改本机 Pub 缓存。

- `media_kit_libs_android_video` 基于上游 1.3.8，改用 [libmpv-android-video-build v1.1.11 的 full 包](https://github.com/media-kit/libmpv-android-video-build/releases/tag/v1.1.11)，四个 ABI 分别固定 SHA-256，保留 Android helper。原有 default 包未启用 `pgssub`。
- `media_kit_libs_windows_video` 基于上游 1.0.11，改用 [mpv-winbuild-cmake 20261021 的完整 x86-64 开发包](https://github.com/shinchiro/mpv-winbuild-cmake/releases/tag/20261021)，固定 SHA-256；保留原有 ANGLE 与插件接口。解压标记随摘要变化，已有构建目录也会更新 DLL、头文件和导入库。

PGS 回归样例为本项目生成的黑色视频和白色位图矩形，位于 `test/fixtures/player/pgs.mkv`。Windows 构建后运行 `.github/scripts/verify_mpv_subtitles.py`，通过无界面渲染检查内封 PGS 的解码与合成。
