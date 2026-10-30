import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/widgets/glass_widgets.dart';
import '../../shared/widgets/reelva_logo.dart';
import '../update/application/app_update_providers.dart';
import '../update/presentation/update_settings_card.dart';
import 'reelva_license_page.dart';
import 'settings_subpages.dart';

/// 关于页面
///
/// 展示 Reelva 应用版本、官方 TMDB 归属声明（包含官方 unmodified 矢量 Logo 与强制条款）、
/// 播放器底层 FFmpeg / libmpv 原生组件许可与合规说明，以及完整的第三方开源软件许可入口。
/// 布局与文本换行适配桌面窗口与 320px 窄屏高文字缩放环境。
class AboutPage extends ConsumerWidget {
  const AboutPage({super.key});

  /// TMDB 官方强制要求声明文案（严格保持原英文）
  static const String tmdbRequiredNotice =
      'This product uses the TMDB API but is not endorsed or certified by TMDB.';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final packageInfo = ref.watch(packageInfoProvider);

    return SettingsSubpage(
      title: '关于 Reelva',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Column(
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
                packageInfo.when(
                  data: (info) =>
                      '版本 ${info.version} (Build ${info.buildNumber})',
                  loading: () => '正在读取版本…',
                  error: (_, _) => '版本信息读取失败',
                ),
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
            ],
          ),
          const SizedBox(height: ReelvaDesign.space24),

          const UpdateSettingsCard(),
          const SizedBox(height: ReelvaDesign.space16),

          // 2. TMDB 官方元数据归属说明卡片
          GlassCard(
            padding: const EdgeInsets.all(ReelvaDesign.space16),
            borderRadius: BorderRadius.circular(22),
            color: Colors.white.withValues(alpha: 0.88),
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
          const SizedBox(height: ReelvaDesign.space16),

          // 3. 播放器内核资质与组件许可说明卡片
          GlassCard(
            padding: const EdgeInsets.all(ReelvaDesign.space16),
            borderRadius: BorderRadius.circular(22),
            color: Colors.white.withValues(alpha: 0.88),
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
                        style: theme.textTheme.titleMedium,
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
                  'SMB 局域网协议说明：\n'
                  '应用通过 dart_smb2 (BSD-3-Clause) 调用 libsmb2 (LGPL-2.1+) 原生动态库以实现 SMB2/3 协议安全访问，'
                  '原生库基于构建钩子校验使用固定版本 libsmb2-r9，源码开放于 https://github.com/sahlberg/libsmb2 。\n\n'
                  '网盘内核说明：\n'
                  '百度、夸克、115 和 123 网盘通过 Venera OpenList Core 提供访问，内核使用 AGPL-3.0 许可。'
                  '固定版本 core-v0.1.0-beta.6 的对应源码见 https://github.com/Venera-Works/Venera-OpenList-Core/tree/core-v0.1.0-beta.6 ，完整许可证见下方入口。\n\n'
                  'Dart 与 Flutter 第三方依赖包的开源许可证详情可通过下方入口查看。',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: ReelvaDesign.space24),

          // 4. 查看系统聚合许可证入口
          Align(
            alignment: Alignment.center,
            child: OutlinedButton.icon(
              onPressed: () {
                Navigator.of(context).push<void>(
                  MaterialPageRoute<void>(
                    builder: (context) => ReelvaLicensePage(
                      applicationName: 'Reelva',
                      applicationVersion: packageInfo.asData == null
                          ? '未知版本'
                          : '${packageInfo.asData!.value.version}+${packageInfo.asData!.value.buildNumber}',
                      applicationIcon: const Padding(
                        padding: EdgeInsets.all(8),
                        child: ReelvaLogo(size: 48),
                      ),
                      applicationLegalese:
                          '© 2026 Reelva Contributors.\n'
                          '$tmdbRequiredNotice\n'
                          'Native playback engines incorporate FFmpeg and libmpv under LGPL/GPL licenses.\n'
                          'SMB functionality incorporates dart_smb2 (BSD-3-Clause) and libsmb2 (LGPL-2.1+, https://github.com/sahlberg/libsmb2).\n'
                          'Cloud drive functionality incorporates Venera OpenList Core (AGPL-3.0, https://github.com/Venera-Works/Venera-OpenList-Core/tree/core-v0.1.0-beta.6).',
                    ),
                  ),
                );
              },
              icon: const Icon(Icons.description_outlined, size: 18),
              label: const Text('查看第三方开源许可证'),
            ),
          ),
        ],
      ),
    );
  }
}
