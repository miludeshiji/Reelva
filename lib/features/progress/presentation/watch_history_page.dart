import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/logging/app_logger.dart';
import '../../../shared/widgets/empty_state_view.dart';
import '../../../shared/widgets/glass_widgets.dart';
import '../../../shared/widgets/poster_image.dart';
import '../../sources/application/source_providers.dart';
import '../../sources/domain/source_models.dart';
import '../application/progress_providers.dart';

class WatchHistoryPage extends ConsumerStatefulWidget {
  const WatchHistoryPage({super.key});

  @override
  ConsumerState<WatchHistoryPage> createState() => _WatchHistoryPageState();
}

class _WatchHistoryPageState extends ConsumerState<WatchHistoryPage> {
  int? _openingEntryId;

  Future<void> _openEntry(WatchHistoryEntry history) async {
    if (_openingEntryId != null) return;
    setState(() => _openingEntryId = history.id);
    final entry = history.entry;
    try {
      if (!entry.available || entry.fileId == null) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('媒体文件当前不可用，已打开作品详情进行恢复')));
        await context.push<void>('/library/work/${entry.workId}');
      } else {
        final resource = await ref
            .read(sourceControllerProvider.notifier)
            .resolvePlayback(entry.fileId!);
        if (!mounted) return;
        await context.push<void>('/player', extra: resource);
      }
    } catch (error, stack) {
      AppLogger.instance.error('打开观看历史失败', error: error, stackTrace: stack);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            error is MediaSourceException ? error.message : '无法解析视频播放地址，请重试',
          ),
          action: SnackBarAction(
            label: '重试',
            onPressed: () => _openEntry(history),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _openingEntryId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final historyAsync = ref.watch(watchHistoryProvider);
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: GlassBackground(
        child: SafeArea(
          bottom: false,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: ReelvaDesign.contentMaxWidth,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  GlassPageHeader(
                    title: '观看历史',
                    leading: GlassIconButton(
                      key: const Key('watch_history_back_button'),
                      icon: Icons.arrow_back,
                      tooltip: '返回首页',
                      size: ReelvaDesign.pageHeaderButtonSize,
                      onPressed: () => context.pop(),
                    ),
                  ),
                  Expanded(
                    child: historyAsync.when(
                      loading: () => const Center(
                        child: CircularProgressIndicator(
                          key: Key('watch_history_loading'),
                        ),
                      ),
                      error: (error, stack) => EmptyStateView(
                        key: const Key('watch_history_error'),
                        icon: Icons.error_outline,
                        title: '观看历史加载失败',
                        message: '请稍后重试。',
                        actionLabel: '重试',
                        onAction: () => ref.invalidate(watchHistoryProvider),
                      ),
                      data: (history) => history.isEmpty
                          ? const EmptyStateView(
                              key: Key('watch_history_empty'),
                              icon: Icons.history_rounded,
                              title: '暂无观看历史',
                              message: '播放影视库中的作品后，会在这里保留观看记录。',
                            )
                          : ListView.separated(
                              key: const Key('watch_history_list'),
                              padding: EdgeInsets.fromLTRB(
                                ReelvaDesign.space24,
                                ReelvaDesign.space8,
                                ReelvaDesign.space24,
                                ReelvaDesign.space32 +
                                    MediaQuery.paddingOf(context).bottom,
                              ),
                              itemCount: history.length,
                              separatorBuilder: (context, index) =>
                                  const SizedBox(height: ReelvaDesign.space12),
                              itemBuilder: (context, index) =>
                                  _buildEntry(context, history[index]),
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

  Widget _buildEntry(BuildContext context, WatchHistoryEntry history) {
    final entry = history.entry;
    final isOpening = _openingEntryId == history.id;
    final available = entry.available && entry.fileId != null;
    final onOpen = _openingEntryId == null ? () => _openEntry(history) : null;
    final theme = Theme.of(context);
    final episode = [
      if (entry.seasonNumber != null) '第 ${entry.seasonNumber} 季',
      if (entry.episodeNumber != null) '第 ${entry.episodeNumber} 集',
    ].join(' · ');
    final updatedAt = history.updatedAt.toLocal();
    final date =
        '${updatedAt.year}/'
        '${updatedAt.month.toString().padLeft(2, '0')}/'
        '${updatedAt.day.toString().padLeft(2, '0')} '
        '${updatedAt.hour.toString().padLeft(2, '0')}:'
        '${updatedAt.minute.toString().padLeft(2, '0')}';

    return GlassCard(
      key: Key('watch_history_entry_${history.id}'),
      padding: const EdgeInsets.all(ReelvaDesign.space12),
      onTap: onOpen,
      child: Row(
        children: [
          PosterImage(
            posterPath: entry.posterPath,
            title: entry.title,
            width: 64,
            height: 96,
            borderRadius: BorderRadius.circular(ReelvaDesign.radiusSmall),
          ),
          const SizedBox(width: ReelvaDesign.space12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (episode.isNotEmpty) Text(episode),
                const SizedBox(height: ReelvaDesign.space4),
                Wrap(
                  spacing: ReelvaDesign.space8,
                  runSpacing: ReelvaDesign.space4,
                  children: [
                    Text(history.completed ? '已看完' : '未看完'),
                    if (!available) const Text('文件离线'),
                  ],
                ),
                Text(
                  '${_formatDuration(entry.position)} / '
                  '${_formatDuration(entry.duration)}',
                  style: theme.textTheme.bodySmall,
                ),
                Text('最近观看 $date', style: theme.textTheme.bodySmall),
                const SizedBox(height: ReelvaDesign.space8),
                LinearProgressIndicator(
                  value: entry.progressFraction,
                  minHeight: 3,
                  borderRadius: BorderRadius.circular(2),
                ),
              ],
            ),
          ),
          const SizedBox(width: ReelvaDesign.space8),
          if (isOpening)
            const SizedBox.square(
              dimension: 40,
              child: Center(
                child: SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          else
            GlassIconButton(
              key: Key('watch_history_play_${history.id}'),
              icon: !available
                  ? Icons.folder_open_rounded
                  : history.completed
                  ? Icons.replay_rounded
                  : Icons.play_arrow_rounded,
              tooltip: !available
                  ? '打开作品详情以恢复媒体文件'
                  : history.completed
                  ? '重新播放${entry.title}'
                  : '继续播放${entry.title}',
              size: 40,
              onPressed: onOpen,
            ),
        ],
      ),
    );
  }

  static String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return duration.inHours > 0
        ? '${duration.inHours}:$minutes:$seconds'
        : '$minutes:$seconds';
  }
}
