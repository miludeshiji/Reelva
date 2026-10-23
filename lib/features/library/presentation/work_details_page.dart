import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/errors/safe_error_widget.dart';
import '../../../core/logging/app_logger.dart';
import '../../../shared/widgets/empty_state_view.dart';
import '../../../shared/widgets/poster_image.dart';
import '../../metadata/application/metadata_providers.dart';
import '../../sources/application/source_providers.dart';
import '../../sources/domain/source_models.dart';
import '../domain/library_work.dart';
import 'local_edit_dialog.dart';
import 'manual_match_dialog.dart';

/// 作品详情页面
///
/// 展示作品的海报、元数据（标题、年代、简介、TMDB/本地来源状态、锁定标记）、
/// 多清晰度/多来源版本列表或剧集的分季分集列表；
/// 支持手动匹配（自动处理多条合并后的规范化 ID 路由更新）、本地信息编辑（保存自动锁定），
/// 并通过已有 SourceController.resolvePlayback 解析文件地址后无缝跳转播放器。
class WorkDetailsPage extends ConsumerStatefulWidget {
  const WorkDetailsPage({super.key, required this.workId});

  final int workId;

  @override
  ConsumerState<WorkDetailsPage> createState() => _WorkDetailsPageState();
}

class _WorkDetailsPageState extends ConsumerState<WorkDetailsPage> {
  int? _resolvingFileId;

  Future<void> _playVersion(LibraryVersion version) async {
    if (_resolvingFileId != null) return;
    if (!version.available) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(version.sourceError ?? '该媒体源文件暂不可用（可能处于离线或不可读状态）'),
        ),
      );
      return;
    }

    setState(() {
      _resolvingFileId = version.fileId;
    });

    try {
      final resource = await ref
          .read(sourceControllerProvider.notifier)
          .resolvePlayback(version.fileId);

      if (!mounted) return;
      context.go('/player', extra: resource);
    } catch (e, st) {
      AppLogger.instance.error('解析播放地址失败', error: e, stackTrace: st);
      if (!mounted) return;
      final message = e is MediaSourceException ? e.message : '无法解析视频播放地址，请重试';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          action: SnackBarAction(
            label: '重试',
            onPressed: () => _playVersion(version),
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _resolvingFileId = null;
        });
      }
    }
  }

  Future<void> _openManualMatch(LibraryWork work) async {
    final canonicalId = await ManualMatchDialog.show(
      context,
      workId: work.id,
      currentTitle: work.title,
      currentType: work.type,
      currentYear: work.year,
    );

    if (!mounted || canonicalId == null) return;

    if (canonicalId != widget.workId) {
      // 合并导致工作 ID 迁移，路由自动切换至主作品
      context.go('/library/work/$canonicalId');
    }
  }

  Future<void> _openLocalEdit(LibraryWork work) async {
    await LocalEditDialog.show(
      context,
      workId: work.id,
      initialTitle: work.title,
      initialYear: work.year,
      initialOverview: work.overview,
      initialPosterPath: work.posterPath,
    );
  }

  @override
  Widget build(BuildContext context) {
    final detailsAsync = ref.watch(workDetailsProvider(widget.workId));

    return Scaffold(
      appBar: AppBar(title: const Text('作品详情')),
      body: detailsAsync.when(
        loading: () => const Center(
          key: Key('work_details_loading'),
          child: CircularProgressIndicator(),
        ),
        error: (error, stack) => Center(
          key: const Key('work_details_error'),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SafeErrorWidget(),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                key: const Key('work_details_retry_button'),
                onPressed: () =>
                    ref.invalidate(workDetailsProvider(widget.workId)),
                icon: const Icon(Icons.refresh, size: 16),
                label: const Text('重试'),
              ),
            ],
          ),
        ),
        data: (details) {
          if (details == null) {
            return EmptyStateView(
              key: const Key('work_not_found_view'),
              icon: Icons.movie_filter_outlined,
              title: '作品不存在或已被合并',
              message: '该条目可能已被更新、合并到其他作品或被移除。',
              actionLabel: '返回影视库',
              onAction: () => context.go('/library'),
            );
          }

          final work = details.work;
          final versions = details.versions;

          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 960),
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 20,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildHeader(context, work, versions.length),
                    const SizedBox(height: 24),
                    _buildVersionsSection(context, work, versions),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildHeader(
    BuildContext context,
    LibraryWork work,
    int versionCount,
  ) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isSeries = work.type == 'series';

    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 520;

        final poster = Hero(
          tag: 'work_poster_${work.id}',
          child: PosterImage(
            posterPath: work.posterPath,
            title: work.title,
            width: isNarrow ? 120 : 160,
            height: isNarrow ? 180 : 240,
            size: 'w500',
            borderRadius: BorderRadius.circular(10),
          ),
        );

        final details = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              work.title.isNotEmpty ? work.title : '未命名条目',
              key: const Key('work_details_title'),
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            if (work.originalTitle != null &&
                work.originalTitle != work.title) ...[
              const SizedBox(height: 4),
              Text(
                work.originalTitle!,
                style: theme.textTheme.titleMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                if (work.year != null)
                  _buildChip(
                    context,
                    label: '${work.year}',
                    icon: Icons.calendar_today_outlined,
                  ),
                _buildChip(
                  context,
                  label: isSeries
                      ? '剧集'
                      : (work.type == 'movie' ? '电影' : '未定类型'),
                  icon: isSeries ? Icons.tv : Icons.movie,
                ),
                _buildChip(
                  context,
                  label: work.metadataSource == 'tmdb' ? 'TMDB 匹配' : '本地识别',
                  icon: work.metadataSource == 'tmdb'
                      ? Icons.cloud_done_outlined
                      : Icons.folder_outlined,
                ),
                if (work.metadataLocked)
                  Container(
                    key: const Key('work_locked_badge'),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.lock,
                          size: 14,
                          color: colorScheme.onPrimaryContainer,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '已锁定',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: colorScheme.onPrimaryContainer,
                          ),
                        ),
                      ],
                    ),
                  )
                else if (work.metadataSource == 'local')
                  Container(
                    key: const Key('work_unmatched_badge'),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.help_outline,
                          size: 14,
                          color: colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '待匹配',
                          style: TextStyle(
                            fontSize: 12,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                _buildChip(
                  context,
                  label: '$versionCount 个版本文件',
                  icon: Icons.filter_none_outlined,
                ),
              ],
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 10,
              runSpacing: 8,
              children: [
                FilledButton.tonalIcon(
                  key: const Key('work_manual_match_button'),
                  onPressed: () => _openManualMatch(work),
                  icon: const Icon(Icons.search, size: 18),
                  label: const Text('手动匹配'),
                ),
                OutlinedButton.icon(
                  key: const Key('work_local_edit_button'),
                  onPressed: () => _openLocalEdit(work),
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  label: const Text('本地编辑'),
                ),
              ],
            ),
            if (work.overview != null && work.overview!.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text(
                '剧情简介',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                work.overview!,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  height: 1.4,
                ),
              ),
            ],
          ],
        );

        if (isNarrow) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(child: poster),
              const SizedBox(height: 16),
              details,
            ],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            poster,
            const SizedBox(width: 20),
            Expanded(child: details),
          ],
        );
      },
    );
  }

  Widget _buildChip(
    BuildContext context, {
    required String label,
    required IconData icon,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: colorScheme.onSurfaceVariant),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  Widget _buildVersionsSection(
    BuildContext context,
    LibraryWork work,
    List<LibraryVersion> versions,
  ) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isSeries = work.type == 'series';

    if (versions.isEmpty) {
      return Card(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: colorScheme.outlineVariant),
        ),
        child: const Padding(
          padding: EdgeInsets.all(24),
          child: Center(child: Text('当前条目暂无可播放的文件版本')),
        ),
      );
    }

    if (isSeries) {
      // 剧集：按季与集组织展示
      final Map<int, List<LibraryVersion>> seasonMap = {};
      for (final v in versions) {
        final s = v.seasonNumber ?? 1;
        seasonMap.putIfAbsent(s, () => []).add(v);
      }

      final sortedSeasons = seasonMap.keys.toList()..sort();

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '分季与剧集列表',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          for (final season in sortedSeasons) ...[
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                season > 0 ? '第 $season 季' : '特别篇 / 未归类',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: colorScheme.primary,
                ),
              ),
            ),
            _buildVersionsList(context, seasonMap[season]!),
            const SizedBox(height: 12),
          ],
        ],
      );
    }

    // 电影或单条多版本
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '可用版本列表',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
        _buildVersionsList(context, versions),
      ],
    );
  }

  Widget _buildVersionsList(
    BuildContext context,
    List<LibraryVersion> versions,
  ) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: colorScheme.outlineVariant),
      ),
      child: ListView.separated(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: versions.length,
        separatorBuilder: (_, _) => const Divider(height: 1),
        itemBuilder: (context, index) {
          final version = versions[index];
          final isResolving = _resolvingFileId == version.fileId;

          // 标题逻辑：剧集带集号/分集名，电影展示文件名
          String title = version.fileName;
          if (version.episodeNumber != null) {
            final epPrefix =
                '第 ${version.episodeNumber} 集${version.seasonNumber != null ? ' (S${version.seasonNumber?.toString().padLeft(2, '0')}E${version.episodeNumber?.toString().padLeft(2, '0')})' : ''}';
            title = version.episodeTitle != null
                ? '$epPrefix · ${version.episodeTitle}'
                : '$epPrefix · ${version.fileName}';
          }

          return ListTile(
            key: Key('work_version_item_${version.fileId}'),
            leading: Icon(
              version.available
                  ? Icons.play_circle_outline
                  : Icons.cloud_off_outlined,
              size: 28,
              color: version.available
                  ? colorScheme.primary
                  : colorScheme.onSurfaceVariant,
            ),
            title: Text(
              title,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: version.available
                    ? colorScheme.onSurface
                    : colorScheme.onSurfaceVariant,
              ),
            ),
            subtitle: Wrap(
              spacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text('来源: ${version.sourceName}'),
                if (version.editionLabel != null &&
                    version.editionLabel!.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 1,
                    ),
                    decoration: BoxDecoration(
                      color: colorScheme.secondaryContainer,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      version.editionLabel!,
                      style: TextStyle(
                        fontSize: 11,
                        color: colorScheme.onSecondaryContainer,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                if (!version.available)
                  Text(
                    version.sourceError ?? '不可用',
                    style: TextStyle(fontSize: 12, color: colorScheme.error),
                  ),
              ],
            ),
            trailing: FilledButton.tonal(
              key: Key('work_play_version_button_${version.fileId}'),
              onPressed: (!version.available || _resolvingFileId != null)
                  ? null
                  : () => _playVersion(version),
              child: isResolving
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('播放'),
            ),
          );
        },
      ),
    );
  }
}
