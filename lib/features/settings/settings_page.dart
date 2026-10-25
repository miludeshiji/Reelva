import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../shared/widgets/glass_widgets.dart';
import '../metadata/application/metadata_providers.dart';
import '../sync/application/sync_providers.dart';

class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  final _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _openPage(String location) async {
    final offset = _scrollController.offset;
    await context.push<void>(location);
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      final position = _scrollController.position;
      _scrollController.jumpTo(
        offset.clamp(position.minScrollExtent, position.maxScrollExtent),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final configuredAsync = ref.watch(tmdbCredentialConfiguredProvider);
    final syncConfiguration = ref.watch(syncConfigurationProvider);
    final sectionStyle = theme.textTheme.labelMedium?.copyWith(
      fontSize: 12,
      fontWeight: FontWeight.w400,
      color: ReelvaDesign.muted,
    );
    final mediaSection = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(header: true, child: Text('播放与媒体', style: sectionStyle)),
        const SizedBox(height: ReelvaDesign.space8),
        _SettingsTile(
          key: const Key('settings_player_tile'),
          icon: Icons.tune_rounded,
          title: '播放器',
          subtitle: '硬件解码、画质、缓存、音频与字幕',
          onTap: () => _openPage('/settings/player'),
        ),
        const SizedBox(height: ReelvaDesign.space12),
        _SettingsTile(
          key: const Key('settings_tmdb_tile'),
          icon: Icons.verified_user_outlined,
          title: 'TMDB 识别',
          subtitle: configuredAsync.when(
            data: (configured) =>
                configured ? '已配置 · 管理 API 凭据' : '未配置 · 设置 API 凭据',
            loading: () => '正在读取配置',
            error: (_, _) => '配置状态读取异常',
          ),
          onTap: () => _openPage('/settings/tmdb'),
        ),
      ],
    );
    final storageSection = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(header: true, child: Text('同步与存储', style: sectionStyle)),
        const SizedBox(height: ReelvaDesign.space8),
        _SettingsTile(
          key: const Key('settings_sync_tile'),
          icon: Icons.sync_rounded,
          title: '跨设备同步',
          subtitle: syncConfiguration.when(
            data: (configuration) => configuration == null
                ? '未配置 · WebDAV 手动同步'
                : '已配置 · WebDAV 手动同步',
            loading: () => '正在读取配置',
            error: (_, _) => '配置状态读取异常',
          ),
          onTap: () => _openPage('/settings/sync'),
        ),
        const SizedBox(height: ReelvaDesign.space12),
        _SettingsTile(
          key: const Key('settings_cache_tile'),
          icon: Icons.folder_outlined,
          title: '海报缓存',
          subtitle: '管理本机海报与图片缓存',
          onTap: () => _openPage('/settings/cache'),
        ),
      ],
    );
    final otherSection = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(header: true, child: Text('其他', style: sectionStyle)),
        const SizedBox(height: ReelvaDesign.space8),
        _SettingsTile(
          key: const Key('settings_about_tile'),
          icon: Icons.language_rounded,
          title: '关于 Reelva',
          subtitle: '版本、开源许可与致谢',
          onTap: () => _openPage('/settings/about'),
        ),
      ],
    );

    return Scaffold(
      backgroundColor: ReelvaDesign.background,
      body: SafeArea(
        bottom: false,
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: ReelvaDesign.contentMaxWidth,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const GlassPageHeader(title: '设置'),
                Expanded(
                  child: SingleChildScrollView(
                    controller: _scrollController,
                    padding: EdgeInsets.only(
                      bottom: MediaQuery.paddingOf(context).bottom,
                    ),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(
                        ReelvaDesign.space24,
                        ReelvaDesign.space4,
                        ReelvaDesign.space24,
                        ReelvaDesign.space32,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          mediaSection,
                          const SizedBox(height: ReelvaDesign.space32),
                          storageSection,
                          const SizedBox(height: ReelvaDesign.space32),
                          otherSection,
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  const _SettingsTile({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      child: GlassCard(
        padding: const EdgeInsets.all(14),
        borderRadius: BorderRadius.circular(22),
        color: Colors.white.withValues(alpha: 0.88),
        onTap: onTap,
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: ReelvaDesign.accent.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: ReelvaDesign.accent, size: 22),
            ),
            const SizedBox(width: ReelvaDesign.space12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      height: 1.35,
                      color: ReelvaDesign.ink,
                    ),
                  ),
                  const SizedBox(height: ReelvaDesign.space4),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 11,
                      height: 1.4,
                      color: ReelvaDesign.muted,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: ReelvaDesign.space8),
            const Icon(
              Icons.arrow_forward_rounded,
              color: ReelvaDesign.muted,
              size: 18,
            ),
          ],
        ),
      ),
    );
  }
}
