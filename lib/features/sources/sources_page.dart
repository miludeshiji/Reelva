import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:reelva/shared/widgets/glass_widgets.dart'
    show
        GlassBackground,
        GlassCard,
        GlassIconButton,
        GlassPageHeader,
        GlassPopupMenuItem,
        GlassSectionTitle,
        ReelvaDesign;

import '../../shared/widgets/empty_state_view.dart';
import '../metadata/application/metadata_providers.dart';
import '../metadata/presentation/metadata_status_card.dart';
import 'application/source_providers.dart';
import 'domain/source_models.dart';
import 'remote_source_dialog.dart';

/// 媒体源管理页面
///
/// 展示已配置的媒体源列表、实时扫描进度与错误信息；
/// 支持通过独立页面添加新源，以及重命名、重新扫描、取消扫描、重新授权与移除。
class SourcesPage extends ConsumerWidget {
  const SourcesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sourcesAsync = ref.watch(mediaSourcesProvider);
    final scanProgressMap = ref.watch(sourceControllerProvider);
    final metadataState = ref.watch(metadataControllerProvider);

    return Scaffold(
      backgroundColor: ReelvaDesign.background,
      body: GlassBackground(
        child: SafeArea(
          bottom: false,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final isDesktop =
                  constraints.maxWidth >= ReelvaDesign.desktopBreakpoint;
              final addCard = _AddSourceCard(
                key: const Key('sources_add_card'),
                onTap: () => context.push('/sources/add'),
              );

              final content = ListView(
                key: const Key('sources_list_view'),
                padding: EdgeInsets.fromLTRB(
                  0,
                  0,
                  0,
                  ReelvaDesign.space32 + MediaQuery.paddingOf(context).bottom,
                ),
                children: [
                  const SizedBox(height: ReelvaDesign.space8),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: ReelvaDesign.space24,
                    ),
                    child: sourcesAsync.when(
                      loading: () => Column(
                        children: [
                          addCard,
                          const Padding(
                            padding: EdgeInsets.all(ReelvaDesign.space32),
                            child: Center(
                              key: Key('sources_loading_indicator'),
                              child: CircularProgressIndicator(),
                            ),
                          ),
                        ],
                      ),
                      error: (error, stack) => Column(
                        children: [
                          addCard,
                          const SizedBox(height: ReelvaDesign.space24),
                          GlassCard(
                            key: const Key('sources_error_widget'),
                            child: EmptyStateView(
                              icon: Icons.cloud_off_outlined,
                              title: '暂时无法加载媒体源',
                              message: '请稍后重试。',
                              actionLabel: '重试',
                              onAction: () =>
                                  ref.invalidate(mediaSourcesProvider),
                            ),
                          ),
                        ],
                      ),
                      data: (sources) {
                        final connectedHeader = Row(
                          children: [
                            const Expanded(
                              child: GlassSectionTitle(title: '已连接'),
                            ),
                            const SizedBox(width: ReelvaDesign.space12),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: ReelvaDesign.space12,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFFEFF4FB),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                '共 ${sources.length} 个',
                                style: const TextStyle(
                                  color: ReelvaDesign.muted,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        );
                        final sourceList = Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (metadataState.running ||
                                metadataState.result != null ||
                                metadataState.error != null) ...[
                              MetadataStatusCard(
                                state: metadataState,
                                onRetry: () => ref
                                    .read(metadataControllerProvider.notifier)
                                    .refresh(),
                              ),
                              const SizedBox(height: ReelvaDesign.space12),
                            ],
                            if (sources.isEmpty)
                              EmptyStateView(
                                key: const Key('sources_empty_view'),
                                icon: Icons.folder_outlined,
                                title: '暂无媒体源',
                                message: '添加本地文件夹或存储目录，自动扫描视频并建立影视库。',
                                actionLabel: '添加媒体源',
                                onAction: () => context.push('/sources/add'),
                              )
                            else
                              for (
                                var index = 0;
                                index < sources.length;
                                index++
                              ) ...[
                                if (index > 0)
                                  const SizedBox(height: ReelvaDesign.space12),
                                _SourceCard(
                                  source: sources[index],
                                  progress: scanProgressMap[sources[index].id],
                                ),
                              ],
                          ],
                        );
                        final summary = _ScanSummary(
                          sources: sources,
                          progressMap: scanProgressMap,
                        );

                        if (isDesktop) {
                          const managementWidth = 300.0;
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Padding(
                                padding: const EdgeInsets.only(
                                  left: managementWidth + ReelvaDesign.space32,
                                ),
                                child: connectedHeader,
                              ),
                              const SizedBox(height: ReelvaDesign.space20),
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  SizedBox(
                                    width: managementWidth,
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                        addCard,
                                        const SizedBox(
                                          height: ReelvaDesign.space20,
                                        ),
                                        summary,
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: ReelvaDesign.space32),
                                  Expanded(child: sourceList),
                                ],
                              ),
                            ],
                          );
                        }

                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            addCard,
                            const SizedBox(height: ReelvaDesign.space32),
                            connectedHeader,
                            const SizedBox(height: ReelvaDesign.space20),
                            sourceList,
                            const SizedBox(height: ReelvaDesign.space24),
                            summary,
                          ],
                        );
                      },
                    ),
                  ),
                ],
              );

              return Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: ReelvaDesign.contentMaxWidth,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          const Expanded(child: GlassPageHeader(title: '媒体源')),
                          Padding(
                            padding: const EdgeInsets.only(
                              right: ReelvaDesign.space24,
                            ),
                            child: GlassIconButton(
                              key: const Key('sources_add_appbar_button'),
                              icon: Icons.add,
                              size: ReelvaDesign.pageHeaderButtonSize,
                              tooltip: '添加媒体源',
                              onPressed: () => context.push('/sources/add'),
                            ),
                          ),
                        ],
                      ),
                      Expanded(child: content),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _AddSourceCard extends StatelessWidget {
  const _AddSourceCard({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      onTap: onTap,
      color: Colors.white.withValues(alpha: 0.94),
      borderRadius: BorderRadius.circular(ReelvaDesign.radius),
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: ReelvaDesign.accent,
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(Icons.add, size: 20, color: Colors.white),
          ),
          const SizedBox(width: ReelvaDesign.space12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '添加媒体源',
                  style: TextStyle(
                    color: ReelvaDesign.ink,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                SizedBox(height: ReelvaDesign.space4),
                Text(
                  '本地文件夹 · NAS · 网盘',
                  style: TextStyle(color: ReelvaDesign.muted, fontSize: 11),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ScanSummary extends StatelessWidget {
  const _ScanSummary({required this.sources, required this.progressMap});

  final List<MediaSourceConfig> sources;
  final Map<int, ScanProgress> progressMap;

  @override
  Widget build(BuildContext context) {
    var running = 0;
    var visited = 0;
    var videos = 0;
    var errors = 0;
    var cancelled = 0;
    var unscanned = 0;
    var disabled = 0;
    DateTime? latestScanAt;
    for (final source in sources) {
      final progress = progressMap[source.id];
      if (progress != null && progress.running) {
        running++;
        visited += progress.visited;
        videos += progress.videos;
      } else {
        if ((progress?.error ?? source.errorMessage) != null) errors++;
        if (progress?.cancelled ?? false) cancelled++;
      }
      if (!source.enabled) disabled++;
      final lastScanAt = source.lastScanAt;
      if (lastScanAt == null) {
        unscanned++;
      } else if (latestScanAt == null || lastScanAt.isAfter(latestScanAt)) {
        latestScanAt = lastScanAt;
      }
    }

    final title = running > 0
        ? '正在扫描 $running 个媒体源'
        : errors > 0
        ? '扫描异常'
        : cancelled > 0
        ? '扫描已取消'
        : latestScanAt == null
        ? '尚未扫描'
        : '扫描记录';
    final states = [
      if (errors > 0) '$errors 个源扫描异常',
      if (cancelled > 0) '$cancelled 个源已取消扫描',
      if (unscanned > 0) '$unscanned 个源尚未扫描',
      if (disabled > 0) '$disabled 个源已停用',
    ];

    return GlassCard(
      color: Colors.white.withValues(alpha: 0.66),
      borderRadius: BorderRadius.circular(ReelvaDesign.radius),
      padding: const EdgeInsets.all(ReelvaDesign.space20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            running > 0
                ? Icons.sync_rounded
                : errors > 0
                ? Icons.warning_amber_rounded
                : cancelled > 0
                ? Icons.stop_circle_outlined
                : Icons.history_rounded,
            color: errors > 0
                ? Theme.of(context).colorScheme.error
                : ReelvaDesign.accent,
            size: 22,
          ),
          const SizedBox(width: ReelvaDesign.space12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: ReelvaDesign.ink,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: ReelvaDesign.space8),
                Text(
                  running > 0
                      ? '已访问 $visited 个目录 · 发现 $videos 个视频'
                      : states.isNotEmpty
                      ? states.join(' · ')
                      : '当前没有运行中的扫描',
                  style: const TextStyle(
                    color: ReelvaDesign.muted,
                    fontSize: 11,
                  ),
                ),
                if (running == 0) ...[
                  const SizedBox(height: ReelvaDesign.space4),
                  Text(
                    latestScanAt == null
                        ? '尚无扫描记录'
                        : '最近一次扫描 · ${_formatDateTime(latestScanAt)}',
                    style: const TextStyle(
                      color: ReelvaDesign.muted,
                      fontSize: 11,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

String _formatDateTime(DateTime dt) {
  final local = dt.toLocal();
  final year = local.year.toString().padLeft(4, '0');
  final month = local.month.toString().padLeft(2, '0');
  final day = local.day.toString().padLeft(2, '0');
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  return '$year-$month-$day $hour:$minute';
}

class _SourceCard extends ConsumerWidget {
  const _SourceCard({required this.source, this.progress});

  final MediaSourceConfig source;
  final ScanProgress? progress;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isScanning = progress?.running ?? false;
    final activeError = progress?.error ?? source.errorMessage;
    final (kindLabel, kindColor) = switch (source.kind) {
      'androidSaf' => ('Android 存储目录', const Color(0xFFC38A28)),
      'smb' => ('SMB', const Color(0xFF159B77)),
      'webdav' => ('WebDAV', const Color(0xFF637ACC)),
      _ => ('本地目录', ReelvaDesign.accent),
    };
    final status = isScanning
        ? '正在扫描'
        : !source.enabled
        ? '已停用'
        : activeError != null
        ? '扫描异常'
        : (progress?.cancelled ?? false)
        ? '扫描已取消'
        : source.lastScanAt != null
        ? '已完成扫描'
        : '尚未扫描';
    final statusColor = isScanning
        ? ReelvaDesign.accent
        : activeError != null
        ? colorScheme.error
        : !source.enabled ||
              (progress?.cancelled ?? false) ||
              source.lastScanAt == null
        ? ReelvaDesign.muted
        : kindColor;

    return GlassCard(
      key: Key('source_card_${source.id}'),
      onTap: () => context.push('/sources/${source.id}/files'),
      color: Colors.white.withValues(alpha: 0.88),
      borderRadius: BorderRadius.circular(22),
      padding: const EdgeInsets.all(ReelvaDesign.space16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: kindColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(_kindIcon(source.kind), color: kindColor, size: 24),
              ),
              const SizedBox(width: ReelvaDesign.space12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      source.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: ReelvaDesign.ink,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: ReelvaDesign.space4),
                    Tooltip(
                      message: source.rootLocator,
                      child: Text(
                        '$kindLabel · ${source.rootLocator}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: ReelvaDesign.muted,
                          fontSize: 11,
                        ),
                      ),
                    ),
                    const SizedBox(height: ReelvaDesign.space8),
                    Text(
                      status,
                      style: TextStyle(
                        color: statusColor,
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: ReelvaDesign.space4),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  PopupMenuButton<String>(
                    key: Key('source_menu_button_${source.id}'),
                    icon: const Icon(Icons.more_horiz, size: 20),
                    padding: EdgeInsets.zero,
                    tooltip: '更多操作',
                    color: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(ReelvaDesign.space16),
                    ),
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
                          source.kind == 'webdav' || source.kind == 'smb';
                      return [
                        const GlassPopupMenuItem(
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
                          const GlassPopupMenuItem(
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
                          const GlassPopupMenuItem(
                            value: 'edit_credentials',
                            child: Row(
                              children: [
                                Icon(Icons.key_outlined, size: 20),
                                SizedBox(width: 8),
                                Text('修改凭据'),
                              ],
                            ),
                          ),
                        GlassPopupMenuItem(
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
                  if (isScanning)
                    GlassIconButton(
                      key: Key('source_cancel_button_${source.id}'),
                      icon: Icons.stop_circle_outlined,
                      tooltip: '取消扫描',
                      onPressed: () {
                        ref
                            .read(sourceControllerProvider.notifier)
                            .cancelScan(source.id);
                      },
                    )
                  else
                    GlassIconButton(
                      key: Key('source_refresh_button_${source.id}'),
                      icon: Icons.refresh,
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
                ],
              ),
            ],
          ),
          if (isScanning) ...[
            const SizedBox(height: ReelvaDesign.space12),
            LinearProgressIndicator(
              key: Key('source_progress_bar_${source.id}'),
              color: ReelvaDesign.accent,
              backgroundColor: ReelvaDesign.accent.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(ReelvaDesign.radiusSmall),
            ),
            const SizedBox(height: ReelvaDesign.space8),
            Text(
              '正在扫描：已访问 ${progress?.visited ?? 0} 个目录，发现 ${progress?.videos ?? 0} 个视频',
              key: Key('source_progress_text_${source.id}'),
              style: const TextStyle(color: ReelvaDesign.accent, fontSize: 11),
            ),
          ] else if (source.lastScanAt != null) ...[
            const SizedBox(height: ReelvaDesign.space8),
            Text(
              '上次扫描：${_formatDateTime(source.lastScanAt!)}',
              key: Key('source_last_scan_text_${source.id}'),
              style: const TextStyle(color: ReelvaDesign.muted, fontSize: 11),
            ),
          ],
          if (activeError != null) ...[
            const SizedBox(height: ReelvaDesign.space8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: colorScheme.error.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(ReelvaDesign.radiusSmall),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.warning_amber_rounded,
                    size: 16,
                    color: colorScheme.error,
                  ),
                  const SizedBox(width: ReelvaDesign.space8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '媒体源已保存，扫描未完成',
                          style: TextStyle(
                            color: colorScheme.error,
                            fontSize: 11,
                          ),
                        ),
                        Text(
                          activeError,
                          key: Key('source_error_text_${source.id}'),
                          style: TextStyle(
                            color: colorScheme.error,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
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
      case 'smb':
        return Icons.lan_outlined;
      default:
        return Icons.folder_outlined;
    }
  }
}
