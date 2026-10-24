import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/logging/app_logger.dart';
import '../../shared/widgets/glass_widgets.dart';
import '../../shared/widgets/poster_image.dart';
import '../metadata/application/metadata_providers.dart';
import '../metadata/domain/tmdb_models.dart';
import '../metadata/infrastructure/tmdb_token_store.dart';
import '../sync/presentation/sync_settings_card.dart';

/// 设置页面
///
/// 包含：
/// 1. TMDB 凭据配置（支持 API Key 与 Bearer Token，输入框受控遮蔽防泄漏，从不回显旧凭据）；
/// 2. WebDAV 跨设备同步配置（手动触发、凭据不回显、断点续传）；
/// 3. 磁盘海报图片缓存清理；
/// 4. 关于 Reelva、TMDB 官方归属与许可证入口。
class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  final TextEditingController _tokenController = TextEditingController();
  bool _obscureToken = true;
  bool _isSaving = false;
  bool _isDeleting = false;
  bool _isClearingCache = false;
  bool _tmdbExpanded = false;
  bool _syncExpanded = false;
  bool _cacheExpanded = false;
  String? _tokenError;

  @override
  void dispose() {
    _tokenController.dispose();
    super.dispose();
  }

  Future<void> _saveToken() async {
    final rawInput = _tokenController.text;
    final token = TmdbTokenStore.sanitizeToken(rawInput);

    if (token.isEmpty) {
      setState(() {
        _tokenError = '请输入有效的 TMDB API Key 或 Bearer Token';
      });
      return;
    }

    if (!TmdbTokenStore.isValidToken(token)) {
      setState(() {
        _tokenError = '凭据格式无效：需为 32 位十六进制 Key 或有效的 JWT Bearer Token';
      });
      return;
    }

    setState(() {
      _isSaving = true;
      _tokenError = null;
    });

    try {
      final store = ref.read(tmdbTokenStoreProvider);
      await store.save(token);

      if (!mounted) return;
      _tokenController.clear();
      ref.invalidate(tmdbCredentialConfiguredProvider);

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('TMDB 凭据保存成功，正在触发元数据自动刷新...')),
      );

      // 保存成功后触发一次元数据刷新
      ref.read(metadataControllerProvider.notifier).refresh();
    } catch (e, st) {
      AppLogger.instance.error('保存 TMDB 凭据失败', error: e, stackTrace: st);
      if (!mounted) return;
      final msg = e is MetadataException ? e.message : '保存凭据失败，请重试';
      setState(() {
        _tokenError = msg;
      });
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  Future<void> _deleteToken() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('移除 TMDB 凭据'),
        content: const Text('移除后将无法获取新的在线元数据与海报，已有本地缓存不受影响。确认移除吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('确认移除'),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) return;

    setState(() {
      _isDeleting = true;
    });

    try {
      final store = ref.read(tmdbTokenStoreProvider);
      await store.delete();

      if (!mounted) return;
      _tokenController.clear();
      ref.invalidate(tmdbCredentialConfiguredProvider);

      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('TMDB 凭据已安全清除')));
    } catch (e, st) {
      AppLogger.instance.error('删除 TMDB 凭据失败', error: e, stackTrace: st);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('清除凭据失败，请重试')));
    } finally {
      if (mounted) {
        setState(() {
          _isDeleting = false;
        });
      }
    }
  }

  Future<void> _clearPosterCache() async {
    setState(() {
      _isClearingCache = true;
    });

    try {
      await PosterCacheManager.clearCache();
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('本地海报图片缓存已清空')));
    } catch (e, st) {
      AppLogger.instance.error('清空海报缓存失败', error: e, stackTrace: st);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('清空海报缓存失败，请重试')));
    } finally {
      if (mounted) {
        setState(() {
          _isClearingCache = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final configuredAsync = ref.watch(tmdbCredentialConfiguredProvider);
    final sectionStyle = theme.textTheme.labelMedium?.copyWith(
      fontSize: 12,
      fontWeight: FontWeight.w400,
      color: ReelvaDesign.muted,
    );
    final tmdbConfiguration = GlassCard(
      padding: const EdgeInsets.all(ReelvaDesign.space16),
      borderRadius: BorderRadius.circular(22),
      color: Colors.white.withValues(alpha: 0.88),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Icon(Icons.vpn_key_outlined, color: colorScheme.primary),
              Text(
                'TMDB 凭据配置',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              configuredAsync.when(
                data: (configured) => Container(
                  key: const Key('tmdb_configured_chip'),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: configured
                        ? colorScheme.primaryContainer
                        : colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        configured
                            ? Icons.check_circle_outline
                            : Icons.help_outline,
                        size: 14,
                        color: configured
                            ? colorScheme.onPrimaryContainer
                            : colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        configured ? '已配置' : '未配置',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: configured
                              ? colorScheme.onPrimaryContainer
                              : colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                loading: () => const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                error: (_, _) => Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.error_outline,
                      size: 14,
                      color: colorScheme.error,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '状态读取异常',
                      style: TextStyle(fontSize: 12, color: colorScheme.error),
                    ),
                    const SizedBox(width: 4),
                    IconButton(
                      key: const Key('tmdb_configured_retry_button'),
                      icon: const Icon(Icons.refresh, size: 14),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 20,
                        minHeight: 20,
                      ),
                      tooltip: '重试读取凭据状态',
                      onPressed: () =>
                          ref.invalidate(tmdbCredentialConfiguredProvider),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '支持 TMDB API Key (v3 32位 Hex) 或 Read Access Token (v4 Bearer)。凭据通过系统安全存储加密保管，绝不向输入框回显。',
            style: theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            key: const Key('tmdb_token_input'),
            controller: _tokenController,
            obscureText: _obscureToken,
            autocorrect: false,
            enableSuggestions: false,
            decoration: InputDecoration(
              labelText: '新凭据输入',
              hintText: '输入或粘贴 TMDB API Key / Token',
              errorText: _tokenError,
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                icon: Icon(
                  _obscureToken
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                ),
                tooltip: _obscureToken ? '显示文本' : '隐藏文本',
                onPressed: () {
                  setState(() {
                    _obscureToken = !_obscureToken;
                  });
                },
              ),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                key: const Key('tmdb_save_button'),
                onPressed: _isSaving ? null : _saveToken,
                icon: _isSaving
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save_outlined, size: 18),
                label: const Text('保存凭据'),
              ),
              if (configuredAsync.asData?.value == true)
                OutlinedButton.icon(
                  key: const Key('tmdb_delete_button'),
                  onPressed: _isDeleting ? null : _deleteToken,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: colorScheme.error,
                  ),
                  icon: _isDeleting
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.delete_outline, size: 18),
                  label: const Text('清除凭据'),
                ),
            ],
          ),
        ],
      ),
    );
    final cacheManagement = GlassCard(
      padding: const EdgeInsets.all(ReelvaDesign.space16),
      borderRadius: BorderRadius.circular(22),
      color: Colors.white.withValues(alpha: 0.88),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.storage_outlined, color: colorScheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '本地缓存管理',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '海报图片缓存在本地限制最多 300 张。若海报展示异常或需节省空间，可一键清空海报图片缓存。',
            style: theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            key: const Key('clear_poster_cache_button'),
            onPressed: _isClearingCache ? null : _clearPosterCache,
            icon: _isClearingCache
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.cleaning_services_outlined, size: 18),
            label: const Text('清空海报图片缓存'),
          ),
        ],
      ),
    );

    final mediaSection = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(header: true, child: Text('媒体信息', style: sectionStyle)),
        const SizedBox(height: ReelvaDesign.space8),
        _SettingsTile(
          key: const Key('settings_tmdb_tile'),
          icon: Icons.verified_user_outlined,
          title: 'TMDB 识别',
          subtitle: '配置 API 凭据与自动匹配',
          expanded: _tmdbExpanded,
          onTap: () => setState(() => _tmdbExpanded = !_tmdbExpanded),
        ),
        Visibility(
          visible: _tmdbExpanded,
          maintainState: true,
          child: Padding(
            padding: const EdgeInsets.only(top: ReelvaDesign.space12),
            child: tmdbConfiguration,
          ),
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
          subtitle: 'WebDAV · 手动同步',
          expanded: _syncExpanded,
          onTap: () => setState(() => _syncExpanded = !_syncExpanded),
        ),
        Visibility(
          visible: _syncExpanded,
          maintainState: true,
          child: const Padding(
            padding: EdgeInsets.only(top: ReelvaDesign.space12),
            child: SyncSettingsCard(),
          ),
        ),
        const SizedBox(height: ReelvaDesign.space12),
        _SettingsTile(
          key: const Key('settings_cache_tile'),
          icon: Icons.folder_outlined,
          title: '海报缓存',
          subtitle: '管理本机海报与图片缓存',
          expanded: _cacheExpanded,
          onTap: () => setState(() => _cacheExpanded = !_cacheExpanded),
        ),
        Visibility(
          visible: _cacheExpanded,
          maintainState: true,
          child: Padding(
            padding: const EdgeInsets.only(top: ReelvaDesign.space12),
            child: cacheManagement,
          ),
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
          onTap: () => context.go('/settings/about'),
        ),
      ],
    );
    final privacyCard = GlassCard(
      padding: const EdgeInsets.all(ReelvaDesign.space16),
      borderRadius: BorderRadius.circular(22),
      color: Colors.white.withValues(alpha: 0.55),
      blur: true,
      child: Row(
        children: [
          const Icon(
            Icons.verified_user_outlined,
            color: ReelvaDesign.accent,
            size: 22,
          ),
          const SizedBox(width: ReelvaDesign.space12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '你的影视，始终属于你',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: ReelvaDesign.ink,
                  ),
                ),
                const SizedBox(height: ReelvaDesign.space4),
                Text(
                  '视频文件保留在原存储中；仅手动通过 WebDAV 同步观看进度与元数据修正。',
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontSize: 11,
                    color: ReelvaDesign.muted,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );

    return Scaffold(
      backgroundColor: ReelvaDesign.background,
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: ReelvaDesign.contentMaxWidth,
            ),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const GlassPageHeader(title: '设置'),
                  Padding(
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
                        const SizedBox(height: ReelvaDesign.space32),
                        privacyCard,
                      ],
                    ),
                  ),
                ],
              ),
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
    this.expanded,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool? expanded;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      expanded: expanded,
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
            Icon(
              expanded == true
                  ? Icons.keyboard_arrow_up_rounded
                  : Icons.arrow_forward_rounded,
              color: ReelvaDesign.muted,
              size: 18,
            ),
          ],
        ),
      ),
    );
  }
}
