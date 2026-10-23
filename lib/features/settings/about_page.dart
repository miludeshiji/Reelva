import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../shared/widgets/reelva_logo.dart';

/// 关于页面
///
/// 展示 Reelva 应用版本、官方 TMDB 归属声明（包含官方 unmodified 矢量 Logo 与强制条款）、
/// 播放器底层 FFmpeg / libmpv 原生组件许可与合规说明，以及完整的第三方开源软件许可入口。
/// 布局与文本换行适配桌面窗口与 320px 窄屏高文字缩放环境。
class AboutPage extends StatelessWidget {
  const AboutPage({super.key});

  /// TMDB 官方强制要求声明文案（严格保持原英文）
  static const String tmdbRequiredNotice =
      'This product uses the TMDB API but is not endorsed or certified by TMDB.';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('关于 Reelva')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // 1. Reelva 主 Logo（显著展示，尺寸与视觉层级明显高于 TMDB Logo）
                const ReelvaLogo(size: 72),
                const SizedBox(height: 12),
                Text(
                  'Reelva',
                  style: theme.textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '版本 0.1.0 (Build 1)',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '现代跨平台媒体库与播放器',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 32),

                // 2. TMDB 官方元数据归属说明卡片
                Card(
                  elevation: 0,
                  color: colorScheme.surfaceContainerHighest.withValues(
                    alpha: 0.5,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(
                      color: colorScheme.outlineVariant.withValues(alpha: 0.5),
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          spacing: 8,
                          runSpacing: 6,
                          alignment: WrapAlignment.spaceBetween,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            // 官方 unmodified TMDB 矢量 Logo（保持原生蓝绿色渐变与宽高比）
                            SvgPicture.asset(
                              'assets/tmdb.svg',
                              height: 20,
                              fit: BoxFit.contain,
                              semanticsLabel: 'The Movie Database (TMDB) Logo',
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: colorScheme.primaryContainer,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                '元数据提供方',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: colorScheme.onPrimaryContainer,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        SelectableText(
                          tmdbRequiredNotice,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: colorScheme.onSurface,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Reelva 的影视详情及海报数据由 The Movie Database (TMDB) API 提供。本软件非 TMDB 官方产品，亦未获得 TMDB 的直接认证或认可。',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                // 3. 播放器内核资质与组件许可说明卡片
                Card(
                  elevation: 0,
                  color: colorScheme.surfaceContainerHighest.withValues(
                    alpha: 0.5,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(
                      color: colorScheme.outlineVariant.withValues(alpha: 0.5),
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.gavel_outlined,
                              size: 20,
                              color: colorScheme.primary,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                '组件许可与合规说明',
                                style: theme.textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Text(
                          '多媒体播放资质说明：\n'
                          '应用底层通过 media_kit 调度 libmpv 与 FFmpeg 原生共享库进行音频与视频解码。'
                          '由于 libmpv 与 FFmpeg 的原生二进制分发许可证取决于实际的编译开关、编解码器配置及动态链接方式（通常受 LGPL v2.1+ 或 GPL 许可证约束），'
                          '因此在构建并正式发布分发包前，必须根据最终打包环境核对并明确各原生组件的适用许可证，并按相应许可证履行资质声明及对应源码提供义务。\n\n'
                          'Dart 与 Flutter 第三方依赖包的开源许可证详情可通过下方入口查看。',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 28),

                // 4. 查看系统聚合许可证入口
                OutlinedButton.icon(
                  onPressed: () {
                    showLicensePage(
                      context: context,
                      applicationName: 'Reelva',
                      applicationVersion: '0.1.0+1',
                      applicationIcon: const Padding(
                        padding: EdgeInsets.all(8.0),
                        child: ReelvaLogo(size: 48),
                      ),
                      applicationLegalese:
                          '© 2026 Reelva Contributors.\n'
                          '$tmdbRequiredNotice\n'
                          'Native playback engines incorporate FFmpeg and libmpv under LGPL/GPL licenses.',
                    );
                  },
                  icon: const Icon(Icons.description_outlined, size: 18),
                  label: const Text('查看第三方开源许可证'),
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
