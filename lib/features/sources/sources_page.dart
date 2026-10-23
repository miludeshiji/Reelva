import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors/safe_error_widget.dart';
import '../../shared/widgets/empty_state_view.dart';
import '../../shared/widgets/reelva_logo.dart';
import 'application/source_providers.dart';
import 'domain/source_models.dart';
import 'infrastructure/remote_credentials_store.dart';
import 'remote_source_dialog.dart';

/// 媒体源管理页面
///
/// 展示已配置的媒体源列表、实时扫描进度与错误信息；
/// 支持通过配置弹窗添加新源、重命名、重新扫描、取消扫描、重新授权以及移除。
class SourcesPage extends ConsumerWidget {
  const SourcesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sourcesAsync = ref.watch(mediaSourcesProvider);
    final scanProgressMap = ref.watch(sourceControllerProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [ReelvaLogo(size: 28), SizedBox(width: 8), Text('媒体源')],
        ),
        actions: [
          IconButton(
            key: const Key('sources_add_appbar_button'),
            icon: const Icon(Icons.add),
            tooltip: '添加媒体源',
            onPressed: () => _showAddSourceDialog(context, ref),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('sources_add_fab'),
        onPressed: () => _showAddSourceDialog(context, ref),
        icon: const Icon(Icons.add),
        label: const Text('添加媒体源'),
      ),
      body: sourcesAsync.when(
        loading: () => const Center(
          key: Key('sources_loading_indicator'),
          child: CircularProgressIndicator(),
        ),
        error: (error, stack) => const Center(
          key: Key('sources_error_widget'),
          child: SafeErrorWidget(),
        ),
        data: (sources) {
          if (sources.isEmpty) {
            return EmptyStateView(
              key: const Key('sources_empty_view'),
              icon: Icons.folder_outlined,
              title: '暂无媒体源',
              message: '添加本地文件夹或存储目录，自动扫描视频并建立影视库。',
              actionLabel: '添加媒体源',
              onAction: () => _showAddSourceDialog(context, ref),
            );
          }

          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 800),
              child: ListView.separated(
                key: const Key('sources_list_view'),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                itemCount: sources.length,
                separatorBuilder: (context, index) =>
                    const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  final source = sources[index];
                  final progress = scanProgressMap[source.id];
                  return _SourceCard(source: source, progress: progress);
                },
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _showAddSourceDialog(BuildContext context, WidgetRef ref) async {
    await showDialog<void>(
      context: context,
      builder: (dialogCtx) => const _AddSourceDialog(),
    );
  }
}

class _AddSourceDialog extends ConsumerStatefulWidget {
  const _AddSourceDialog();

  @override
  ConsumerState<_AddSourceDialog> createState() => _AddSourceDialogState();
}

class _AddSourceDialogState extends ConsumerState<_AddSourceDialog> {
  String _selectedType = 'local';
  final _nameController = TextEditingController();
  final _urlController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _tokenController = TextEditingController();
  final _domainController = TextEditingController();
  final _openListPathController = TextEditingController();
  final _userAgentController = TextEditingController();
  final _refererController = TextEditingController();

  final _extensionsController = TextEditingController(
    text: defaultVideoExtensions.join(', '),
  );
  final _excludedController = TextEditingController(
    text: defaultExcludedDirectories.join(', '),
  );

  bool _isSubmitting = false;
  String? _errorMessage;

  @override
  void dispose() {
    _nameController.dispose();
    _urlController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _tokenController.dispose();
    _domainController.dispose();
    _openListPathController.dispose();
    _userAgentController.dispose();
    _refererController.dispose();
    _extensionsController.dispose();
    _excludedController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final rawName = _nameController.text.trim();
    final name = rawName.isEmpty ? null : rawName;
    final extensions = _extensionsController.text
        .split(',')
        .map((e) => e.trim().toLowerCase())
        .where((e) => e.isNotEmpty)
        .toList();
    final excluded = _excludedController.text
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    try {
      if (_selectedType == 'local') {
        await ref
            .read(sourceControllerProvider.notifier)
            .addDirectory(
              name: name,
              extensions: extensions.isEmpty
                  ? defaultVideoExtensions
                  : extensions,
              excludedDirectories: excluded.isEmpty
                  ? defaultExcludedDirectories
                  : excluded,
            );
      } else {
        final rawUrl = _urlController.text.trim();
        if (rawUrl.isEmpty) {
          setState(() {
            _isSubmitting = false;
            _errorMessage = '请输入根目录地址';
          });
          return;
        }

        final headers = <String, String>{};
        if (_userAgentController.text.trim().isNotEmpty) {
          headers['User-Agent'] = _userAgentController.text.trim();
        }
        if (_refererController.text.trim().isNotEmpty) {
          headers['Referer'] = _refererController.text.trim();
        }

        final credentials = RemoteCredentials(
          username: _usernameController.text.trim(),
          password: _passwordController.text,
          token: _tokenController.text.trim(),
          domain: _domainController.text.trim(),
          playbackHeaders: headers,
        );

        await ref
            .read(sourceControllerProvider.notifier)
            .addRemoteSource(
              kind: _selectedType,
              rootUrl: rawUrl,
              name: name,
              credentials: credentials,
              openListRootPath: _openListPathController.text.trim().isEmpty
                  ? null
                  : _openListPathController.text.trim(),
              extensions: extensions.isEmpty
                  ? defaultVideoExtensions
                  : extensions,
              excludedDirectories: excluded.isEmpty
                  ? defaultExcludedDirectories
                  : excluded,
            );
      }
      if (mounted) {
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (!mounted) return;
      final message = e is MediaSourceException ? e.message : '添加媒体源失败，请重试';
      setState(() {
        _isSubmitting = false;
        _errorMessage = message;
      });
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    }
  }

  String get _urlHint {
    switch (_selectedType) {
      case 'webdav':
        return 'https://example.com/dav/';
      case 'openlist':
        return 'https://example.com/base#/Movies';
      case 'smb':
        return 'smb://192.168.1.100/share/media';
      default:
        return 'https://';
    }
  }

  String get _urlLabel {
    switch (_selectedType) {
      case 'webdav':
        return 'WebDAV URL';
      case 'openlist':
        return 'OpenList 服务器 URL';
      case 'smb':
        return 'SMB 共享路径';
      default:
        return '服务器地址';
    }
  }

  @override
  Widget build(BuildContext context) {
    final isLocal = _selectedType == 'local';
    return AlertDialog(
      title: const Text('添加媒体源'),
      content: SingleChildScrollView(
        child: SizedBox(
          width: 480,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DropdownButtonFormField<String>(
                key: const Key('add_source_type_dropdown'),
                initialValue: _selectedType,
                decoration: const InputDecoration(labelText: '媒体源类型'),
                items: const [
                  DropdownMenuItem(value: 'local', child: Text('本地目录')),
                  DropdownMenuItem(value: 'webdav', child: Text('WebDAV')),
                  DropdownMenuItem(value: 'openlist', child: Text('OpenList')),
                  DropdownMenuItem(value: 'smb', child: Text('SMB (局域网共享)')),
                ],
                onChanged: (val) {
                  if (val != null) {
                    setState(() {
                      _selectedType = val;
                      _errorMessage = null;
                    });
                  }
                },
              ),
              const SizedBox(height: 16),
              if (!isLocal) ...[
                TextField(
                  controller: _urlController,
                  key: const Key('remote_source_url_field'),
                  decoration: InputDecoration(
                    labelText: _urlLabel,
                    hintText: _urlHint,
                  ),
                ),
                const SizedBox(height: 16),
              ],
              TextField(
                controller: _nameController,
                key: const Key('add_source_name_field'),
                decoration: InputDecoration(
                  labelText: '媒体源名称（可选）',
                  hintText: isLocal ? '留空将使用目录名称' : '留空将自动根据地址生成',
                ),
              ),
              if (_selectedType == 'webdav') ...[
                const SizedBox(height: 16),
                TextField(
                  controller: _usernameController,
                  key: const Key('remote_source_username_field'),
                  decoration: const InputDecoration(labelText: '用户名（可选）'),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _passwordController,
                  key: const Key('remote_source_password_field'),
                  obscureText: true,
                  decoration: const InputDecoration(labelText: '密码（可选）'),
                ),
              ] else if (_selectedType == 'openlist') ...[
                const SizedBox(height: 16),
                TextField(
                  controller: _openListPathController,
                  key: const Key('remote_source_openlist_path_field'),
                  decoration: const InputDecoration(
                    labelText: '根目录路径（可选，或在 URL # 中指定）',
                    hintText: '/Movies',
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _tokenController,
                  key: const Key('remote_source_token_field'),
                  obscureText: true,
                  decoration: const InputDecoration(labelText: 'API Token（可选）'),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _passwordController,
                  key: const Key('remote_source_password_field'),
                  obscureText: true,
                  decoration: const InputDecoration(labelText: '目录访问密码（可选）'),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _userAgentController,
                  key: const Key('remote_source_user_agent_field'),
                  decoration: const InputDecoration(
                    labelText: 'User-Agent 请求头（可选）',
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _refererController,
                  key: const Key('remote_source_referer_field'),
                  decoration: const InputDecoration(
                    labelText: 'Referer 请求头（可选）',
                  ),
                ),
              ] else if (_selectedType == 'smb') ...[
                const SizedBox(height: 16),
                TextField(
                  controller: _usernameController,
                  key: const Key('remote_source_username_field'),
                  decoration: const InputDecoration(labelText: '用户名（可选）'),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _passwordController,
                  key: const Key('remote_source_password_field'),
                  obscureText: true,
                  decoration: const InputDecoration(labelText: '密码（可选）'),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _domainController,
                  key: const Key('remote_source_domain_field'),
                  decoration: const InputDecoration(
                    labelText: '工作组 / 域名（可选）',
                    hintText: 'WORKGROUP',
                  ),
                ),
              ],
              const SizedBox(height: 16),
              TextField(
                controller: _extensionsController,
                key: const Key('add_source_extensions_field'),
                decoration: const InputDecoration(
                  labelText: '视频扩展名（逗号分隔）',
                  hintText: 'mkv, mp4, avi, mov, m4v, ts, webm',
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _excludedController,
                key: const Key('add_source_excluded_field'),
                decoration: const InputDecoration(
                  labelText: '排除目录名称（逗号分隔）',
                  hintText: r'.cache, $RECYCLE.BIN, System Volume Information',
                ),
              ),
              if (_errorMessage != null) ...[
                const SizedBox(height: 16),
                Text(
                  _errorMessage!,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                    fontSize: 13,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSubmitting ? null : () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          key: const Key('add_source_confirm_button'),
          onPressed: _isSubmitting ? null : _submit,
          child: _isSubmitting
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(isLocal ? '选择目录' : '添加'),
        ),
      ],
    );
  }
}

class _SourceCard extends ConsumerWidget {
  const _SourceCard({required this.source, this.progress});

  final MediaSourceConfig source;
  final ScanProgress? progress;

  String _formatDateTime(DateTime dt) {
    final local = dt.toLocal();
    final year = local.year.toString().padLeft(4, '0');
    final month = local.month.toString().padLeft(2, '0');
    final day = local.day.toString().padLeft(2, '0');
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return '$year-$month-$day $hour:$minute';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isScanning = progress?.running ?? false;
    final activeError = progress?.error ?? source.errorMessage;
    final kindLabel = source.kind == 'androidSaf' ? 'Android 存储目录' : '本地目录';

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: activeError != null
              ? colorScheme.error.withValues(alpha: 0.5)
              : colorScheme.outlineVariant,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  _kindIcon(source.kind),
                  color: colorScheme.primary,
                  size: 28,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        source.name,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        kindLabel,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                if (isScanning)
                  IconButton(
                    key: Key('source_cancel_button_${source.id}'),
                    icon: const Icon(Icons.stop_circle_outlined),
                    color: colorScheme.error,
                    tooltip: '取消扫描',
                    onPressed: () {
                      ref
                          .read(sourceControllerProvider.notifier)
                          .cancelScan(source.id);
                    },
                  )
                else
                  IconButton(
                    key: Key('source_refresh_button_${source.id}'),
                    icon: const Icon(Icons.refresh),
                    tooltip: '重新扫描',
                    onPressed: () async {
                      try {
                        await ref
                            .read(sourceControllerProvider.notifier)
                            .refreshSource(source.id);
                      } catch (e) {
                        if (!context.mounted) return;
                        final msg = e is MediaSourceException
                            ? e.message
                            : '启动扫描失败，请重试';
                        ScaffoldMessenger.of(context)
                            .showSnackBar(SnackBar(content: Text(msg)));
                      }
                    },
                  ),
                PopupMenuButton<String>(
                  key: Key('source_menu_button_${source.id}'),
                  icon: const Icon(Icons.more_vert),
                  tooltip: '更多操作',
                  onSelected: (action) async {
                    switch (action) {
                      case 'rename':
                        await _showRenameDialog(context, ref);
                        break;
                      case 'reauthorize':
                        await _reauthorize(context, ref);
                        break;
                      case 'edit_credentials':
                        await EditCredentialsDialog.show(
                          context,
                          source: source,
                        );
                        break;
                      case 'remove':
                        await _showRemoveDialog(context, ref);
                        break;
                    }
                  },
                  itemBuilder: (context) {
                    final isRemote =
                        source.kind == 'webdav' ||
                        source.kind == 'openlist' ||
                        source.kind == 'smb';
                    return [
                      const PopupMenuItem(
                        value: 'rename',
                        child: Row(
                          children: [
                            Icon(Icons.edit_outlined, size: 20),
                            SizedBox(width: 8),
                            Text('重命名'),
                          ],
                        ),
                      ),
                      if (!isRemote)
                        const PopupMenuItem(
                          value: 'reauthorize',
                          child: Row(
                            children: [
                              Icon(Icons.lock_reset_outlined, size: 20),
                              SizedBox(width: 8),
                              Text('重新授权'),
                            ],
                          ),
                        )
                      else
                        const PopupMenuItem(
                          value: 'edit_credentials',
                          child: Row(
                            children: [
                              Icon(Icons.key_outlined, size: 20),
                              SizedBox(width: 8),
                              Text('修改凭据'),
                            ],
                          ),
                        ),
                      PopupMenuItem(
                        value: 'remove',
                        child: Row(
                          children: [
                            Icon(
                              Icons.delete_outline,
                              size: 20,
                              color: colorScheme.error,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '移除',
                              style: TextStyle(color: colorScheme.error),
                            ),
                          ],
                        ),
                      ),
                    ];
                  },
                ),
              ],
            ),
            if (isScanning) ...[
              const SizedBox(height: 12),
              LinearProgressIndicator(
                key: Key('source_progress_bar_${source.id}'),
              ),
              const SizedBox(height: 8),
              Text(
                '正在扫描：已访问 ${progress?.visited ?? 0} 个目录，发现 ${progress?.videos ?? 0} 个视频',
                key: Key('source_progress_text_${source.id}'),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.primary,
                ),
              ),
            ] else if (source.lastScanAt != null) ...[
              const SizedBox(height: 8),
              Text(
                '上次扫描：${_formatDateTime(source.lastScanAt!)}',
                key: Key('source_last_scan_text_${source.id}'),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            if (activeError != null) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: colorScheme.errorContainer.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.warning_amber_rounded,
                      size: 16,
                      color: colorScheme.error,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        activeError,
                        key: Key('source_error_text_${source.id}'),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onErrorContainer,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _showRenameDialog(BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController(text: source.name);
    final newName = await showDialog<String>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('重命名媒体源'),
        content: TextField(
          controller: controller,
          key: const Key('rename_source_field'),
          autofocus: true,
          decoration: const InputDecoration(labelText: '新名称'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            key: const Key('rename_source_confirm_button'),
            onPressed: () {
              final text = controller.text.trim();
              if (text.isNotEmpty) Navigator.of(dialogCtx).pop(text);
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );

    if (newName == null || newName.isEmpty || newName == source.name) return;

    try {
      await ref
          .read(sourceControllerProvider.notifier)
          .renameSource(source.id, newName);
    } catch (e) {
      if (!context.mounted) return;
      final msg = e is MediaSourceException ? e.message : '重命名失败，请重试';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  Future<void> _reauthorize(BuildContext context, WidgetRef ref) async {
    try {
      await ref
          .read(sourceControllerProvider.notifier)
          .reauthorizeSource(source.id);
    } catch (e) {
      if (!context.mounted) return;
      final msg = e is MediaSourceException ? e.message : '重新授权失败，请重试';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  Future<void> _showRemoveDialog(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('移除媒体源'),
        content: Text(
          '确定要移除媒体源“${source.name}”吗？\n此操作仅从影视库管理中移除，不会删除磁盘上的任何视频文件。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            key: const Key('remove_source_confirm_button'),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => Navigator.of(dialogCtx).pop(true),
            child: const Text('移除'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await ref.read(sourceControllerProvider.notifier).removeSource(source.id);
    } catch (e) {
      if (!context.mounted) return;
      final msg = e is MediaSourceException ? e.message : '移除媒体源失败，请重试';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  IconData _kindIcon(String kind) {
    switch (kind) {
      case 'androidSaf':
        return Icons.folder_shared_outlined;
      case 'webdav':
        return Icons.cloud_outlined;
      case 'openlist':
        return Icons.dns_outlined;
      case 'smb':
        return Icons.lan_outlined;
      default:
        return Icons.folder_outlined;
    }
  }
}
