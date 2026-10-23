import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/errors/safe_error_widget.dart';
import '../../core/logging/app_logger.dart';
import '../../shared/widgets/empty_state_view.dart';
import '../../shared/widgets/poster_image.dart';
import '../../shared/widgets/reelva_logo.dart';
import '../library/domain/library_work.dart';
import '../progress/application/progress_providers.dart';
import '../sources/application/source_providers.dart';
import '../sources/domain/source_models.dart';
import 'application/home_providers.dart';

/// 首页展示组件（M4）
///
/// 特性：
/// 1. 展示「继续观看 (Continue Watching)」与「最近添加 (Recently Added)」两大展架；
/// 2. 继续观看卡片支持显示播放进度、季集信息、断点秒数，并提供一键续播；
/// 3. 具备防重复点击与播放地址解析失败的安全重试能力；若文件离线或不可用，安全导向作品详情恢复；
/// 4. 最近添加展示创建时间倒序的作品（去重多版本，一作品一卡片），点击跳转作品详情；
/// 5. 媒体库全空时保留前往媒体源的 CTA 引导；
/// 6. 单项展架失败时内联展示安全可重试状态，不遮挡已有有效展架；
/// 7. 保留右下角快速打开播放器 FAB。
class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> {
  int? _resolvingFileId;

  void _retryAll() {
    ref.invalidate(continueWatchingProvider);
    ref.invalidate(recentWorksProvider);
  }

  Future<void> _playEntry(ContinueWatchingEntry entry) async {
    // 防重复点击保护
    if (_resolvingFileId != null) return;

    if (!entry.available || entry.fileId == null) {
      // 不可用 -> 跳转作品详情页恢复或重新选择版本
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('媒体文件当前不可用，已打开作品详情进行恢复'),
            duration: Duration(seconds: 3),
          ),
        );
      }
      context.go('/library/work/${entry.workId}');
      return;
    }

    setState(() {
      _resolvingFileId = entry.fileId;
    });

    try {
      final resource = await ref
          .read(sourceControllerProvider.notifier)
          .resolvePlayback(entry.fileId!);

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
            onPressed: () => _playEntry(entry),
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

  void _openWorkDetails(int workId) {
    context.go('/library/work/$workId');
  }

  static String _formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);
    if (hours > 0) {
      return '$hours:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final continueWatchingAsync = ref.watch(continueWatchingProvider);
    final recentWorksAsync = ref.watch(recentWorksProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [ReelvaLogo(size: 28), SizedBox(width: 8), Text('首页')],
        ),
      ),
      body: _buildBody(context, continueWatchingAsync, recentWorksAsync),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('home_open_player_fab'),
        onPressed: () => context.go('/player'),
        icon: const Icon(Icons.play_arrow),
        label: const Text('打开播放器'),
      ),
    );
  }

  Widget _buildBody(
    BuildContext context,
    AsyncValue<List<ContinueWatchingEntry>> continueWatchingAsync,
    AsyncValue<List<LibraryWork>> recentWorksAsync,
  ) {
    final isCwLoading =
        continueWatchingAsync.isLoading && !continueWatchingAsync.hasValue;
    final isRwLoading =
        recentWorksAsync.isLoading && !recentWorksAsync.hasValue;

    // 两者均处于初始加载态
    if (isCwLoading && isRwLoading) {
      return const Center(
        child: CircularProgressIndicator(key: Key('home_loading_indicator')),
      );
    }

    // 两者均出错且无缓存数据
    if (continueWatchingAsync.hasError &&
        recentWorksAsync.hasError &&
        !continueWatchingAsync.hasValue &&
        !recentWorksAsync.hasValue) {
      return Center(
        key: const Key('home_error_view'),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SafeErrorWidget(),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              key: const Key('home_retry_button'),
              onPressed: _retryAll,
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text('重试'),
            ),
          ],
        ),
      );
    }

    final continueWatching =
        continueWatchingAsync.value ?? const <ContinueWatchingEntry>[];
    final recentWorks = recentWorksAsync.value ?? const <LibraryWork>[];

    // 若还在等待其中一个流的首次发射且另一个为空，展示加载指示
    if ((isCwLoading && recentWorks.isEmpty) ||
        (isRwLoading && continueWatching.isEmpty)) {
      return const Center(
        child: CircularProgressIndicator(key: Key('home_loading_indicator')),
      );
    }

    // 两者均无数据时
    if (continueWatching.isEmpty && recentWorks.isEmpty) {
      if (continueWatchingAsync.hasError || recentWorksAsync.hasError) {
        return Center(
          key: const Key('home_error_view'),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SafeErrorWidget(),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                key: const Key('home_retry_button'),
                onPressed: _retryAll,
                icon: const Icon(Icons.refresh, size: 16),
                label: const Text('重试'),
              ),
            ],
          ),
        );
      }

      // 媒体库完全为空时，展示空引导与媒体源 CTA
      return EmptyStateView(
        key: const Key('home_empty_library_view'),
        icon: Icons.movie_outlined,
        title: '暂无影视内容',
        message: '添加媒体源后将在此展示推荐与最近播放内容。',
        actionLabel: '前往媒体源',
        onAction: () => context.go('/sources'),
      );
    }

    final theme = Theme.of(context);

    return RefreshIndicator(
      onRefresh: () async {
        _retryAll();
      },
      child: CustomScrollView(
        key: const Key('home_content_scroll_view'),
        slivers: [
          // 若继续观看加载失败但最近添加有数据，呈现安全可重试的错误条
          if (continueWatchingAsync.hasError && !continueWatchingAsync.hasValue)
            SliverToBoxAdapter(
              child: Container(
                key: const Key('home_continue_watching_error_banner'),
                margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: theme.colorScheme.errorContainer.withValues(
                    alpha: 0.7,
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.warning_amber_rounded,
                      size: 18,
                      color: theme.colorScheme.error,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '继续观看记录加载失败',
                        style: TextStyle(
                          fontSize: 12,
                          color: theme.colorScheme.onErrorContainer,
                        ),
                      ),
                    ),
                    TextButton.icon(
                      key: const Key('home_continue_watching_retry_button'),
                      onPressed: () => ref.invalidate(continueWatchingProvider),
                      icon: const Icon(Icons.refresh, size: 14),
                      label: const Text('重试', style: TextStyle(fontSize: 12)),
                    ),
                  ],
                ),
              ),
            ),
          if (continueWatching.isNotEmpty) ...[
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Row(
                  children: [
                    Icon(
                      Icons.play_circle_outline,
                      color: theme.colorScheme.primary,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '继续观看',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '${continueWatching.length} 部',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.outline,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: SizedBox(
                height: 230,
                child: ListView.separated(
                  key: const Key('home_continue_watching_list'),
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 4,
                  ),
                  itemCount: continueWatching.length,
                  separatorBuilder: (context, index) =>
                      const SizedBox(width: 12),
                  itemBuilder: (context, index) {
                    final entry = continueWatching[index];
                    return _buildContinueWatchingCard(context, entry);
                  },
                ),
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 12)),
          ],
          // 若最近添加加载失败但继续观看有数据，呈现安全可重试的错误条
          if (recentWorksAsync.hasError && !recentWorksAsync.hasValue)
            SliverToBoxAdapter(
              child: Container(
                key: const Key('home_recent_works_error_banner'),
                margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: theme.colorScheme.errorContainer.withValues(
                    alpha: 0.7,
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.warning_amber_rounded,
                      size: 18,
                      color: theme.colorScheme.error,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '最近添加作品加载失败',
                        style: TextStyle(
                          fontSize: 12,
                          color: theme.colorScheme.onErrorContainer,
                        ),
                      ),
                    ),
                    TextButton.icon(
                      key: const Key('home_recent_works_retry_button'),
                      onPressed: () => ref.invalidate(recentWorksProvider),
                      icon: const Icon(Icons.refresh, size: 14),
                      label: const Text('重试', style: TextStyle(fontSize: 12)),
                    ),
                  ],
                ),
              ),
            ),
          if (recentWorks.isNotEmpty) ...[
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: Row(
                  children: [
                    Icon(
                      Icons.new_releases_outlined,
                      color: theme.colorScheme.primary,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '最近添加',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '${recentWorks.length} 部',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.outline,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 80),
              sliver: SliverGrid(
                key: const Key('home_recent_works_grid'),
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 160,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: 2 / 3.4,
                ),
                delegate: SliverChildBuilderDelegate((context, index) {
                  final work = recentWorks[index];
                  return _buildRecentWorkCard(context, work);
                }, childCount: recentWorks.length),
              ),
            ),
          ] else ...[
            const SliverToBoxAdapter(child: SizedBox(height: 80)),
          ],
        ],
      ),
    );
  }

  Widget _buildContinueWatchingCard(
    BuildContext context,
    ContinueWatchingEntry entry,
  ) {
    final theme = Theme.of(context);
    final isResolving =
        _resolvingFileId == entry.fileId && entry.fileId != null;

    final String episodeSubtitle;
    if (entry.seasonNumber != null || entry.episodeNumber != null) {
      final s = entry.seasonNumber != null ? 'S${entry.seasonNumber} ' : '';
      final e = entry.episodeNumber != null ? 'E${entry.episodeNumber}' : '';
      episodeSubtitle = '$s$e · ${_formatDuration(entry.position)}';
    } else {
      episodeSubtitle =
          '${_formatDuration(entry.position)} / ${_formatDuration(entry.duration)}';
    }

    return Card(
      key: Key('continue_watching_card_${entry.workId}'),
      clipBehavior: Clip.antiAlias,
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: () => _playEntry(entry),
        child: SizedBox(
          width: 170,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    PosterImage(
                      posterPath: entry.posterPath,
                      title: entry.title,
                      fit: BoxFit.cover,
                    ),
                    if (!entry.available)
                      Container(
                        color: Colors.black.withValues(alpha: 0.55),
                        child: const Center(
                          child: Chip(
                            label: Text('文件离线', style: TextStyle(fontSize: 10)),
                            visualDensity: VisualDensity.compact,
                          ),
                        ),
                      ),
                    Positioned(
                      bottom: 8,
                      right: 8,
                      child: Material(
                        color: theme.colorScheme.primary,
                        shape: const CircleBorder(),
                        elevation: 4,
                        child: InkWell(
                          customBorder: const CircleBorder(),
                          onTap: () => _playEntry(entry),
                          child: Padding(
                            padding: const EdgeInsets.all(8),
                            child: isResolving
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : Icon(
                                    entry.available
                                        ? Icons.play_arrow
                                        : Icons.info_outline,
                                    key: Key(
                                      'continue_watching_play_${entry.workId}',
                                    ),
                                    size: 18,
                                    color: theme.colorScheme.onPrimary,
                                  ),
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: LinearProgressIndicator(
                        value: entry.progressFraction,
                        minHeight: 4,
                        backgroundColor: Colors.black38,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          theme.colorScheme.primary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      entry.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      episodeSubtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.outline,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRecentWorkCard(BuildContext context, LibraryWork work) {
    final theme = Theme.of(context);

    return Card(
      key: Key('recent_work_card_${work.id}'),
      clipBehavior: Clip.antiAlias,
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: () => _openWorkDetails(work.id),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  PosterImage(
                    posterPath: work.posterPath,
                    title: work.title,
                    fit: BoxFit.cover,
                  ),
                  if (work.versionCount > 1)
                    Positioned(
                      top: 6,
                      right: 6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.7),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          '${work.versionCount} 版本',
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  if (!work.available)
                    Positioned.fill(
                      child: Container(
                        color: Colors.black.withValues(alpha: 0.5),
                        child: const Center(
                          child: Chip(
                            label: Text('文件离线', style: TextStyle(fontSize: 10)),
                            visualDensity: VisualDensity.compact,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    work.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    work.year != null
                        ? '${work.year}'
                        : (work.type == 'series' ? '剧集' : '电影'),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.outline,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
