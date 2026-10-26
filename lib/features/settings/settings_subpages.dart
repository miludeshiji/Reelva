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

class TmdbSettingsPage extends ConsumerStatefulWidget {
  const TmdbSettingsPage({super.key});

  @override
  ConsumerState<TmdbSettingsPage> createState() => _TmdbSettingsPageState();
}

class _TmdbSettingsPageState extends ConsumerState<TmdbSettingsPage> {
  final TextEditingController _tokenController = TextEditingController();
  bool _obscureToken = true;
  bool _isSaving = false;
  bool _isDeleting = false;
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

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('TMDB 凭据已保存，可在影视库点击刷新进行匹配')));
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final configuredAsync = ref.watch(tmdbCredentialConfiguredProvider);
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
            '支持 TMDB API Key (v3 32位 Hex) 或 Read Access Token (v4 Bearer)。',
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
    return SettingsSubpage(title: 'TMDB 识别', child: tmdbConfiguration);
  }
}

class SyncSettingsPage extends StatelessWidget {
  const SyncSettingsPage({super.key});

  @override
  Widget build(BuildContext context) =>
      const SettingsSubpage(title: '跨设备同步', child: SyncSettingsCard());
}

class PosterCacheSettingsPage extends StatefulWidget {
  const PosterCacheSettingsPage({super.key});

  @override
  State<PosterCacheSettingsPage> createState() =>
      _PosterCacheSettingsPageState();
}

class _PosterCacheSettingsPageState extends State<PosterCacheSettingsPage> {
  bool _isClearingCache = false;

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

    return SettingsSubpage(title: '海报缓存', child: cacheManagement);
  }
}

class SettingsSubpage extends StatelessWidget {
  const SettingsSubpage({super.key, required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ReelvaDesign.background,
      body: GlassBackground(
        child: SafeArea(
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
                  GlassPageHeader(
                    title: title,
                    leading: GlassIconButton(
                      key: const Key('settings_subpage_back_button'),
                      icon: Icons.arrow_back,
                      size: ReelvaDesign.pageHeaderButtonSize,
                      tooltip: '返回设置',
                      onPressed: () => context.pop(),
                    ),
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                      keyboardDismissBehavior:
                          ScrollViewKeyboardDismissBehavior.onDrag,
                      padding: EdgeInsets.fromLTRB(
                        ReelvaDesign.space24,
                        ReelvaDesign.space8,
                        ReelvaDesign.space24,
                        ReelvaDesign.space32 +
                            MediaQuery.paddingOf(context).bottom,
                      ),
                      child: Align(
                        alignment: Alignment.topLeft,
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 960),
                          child: child,
                        ),
                      ),
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
