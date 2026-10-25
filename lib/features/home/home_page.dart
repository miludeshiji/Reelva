import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/errors/safe_error_widget.dart';
import '../../core/logging/app_logger.dart';
import '../../shared/widgets/empty_state_view.dart';
import '../../shared/widgets/glass_widgets.dart';
import '../../shared/widgets/poster_image.dart';
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
/// 7. 有内容时在页头提供播放器入口。
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
      await context.push<void>('/player', extra: resource);
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
      backgroundColor: ReelvaDesign.background,
      body: GlassBackground(
        child: SafeArea(
          bottom: false,
          child: _buildBody(context, continueWatchingAsync, recentWorksAsync),
        ),
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

    if (isCwLoading && isRwLoading) {
      return const Center(
        child: CircularProgressIndicator(key: Key('home_loading_indicator')),
      );
    }

    if (continueWatchingAsync.hasError &&
        recentWorksAsync.hasError &&
        !continueWatchingAsync.hasValue &&
        !recentWorksAsync.hasValue) {
      return _buildErrorView();
    }

    final continueWatching =
        continueWatchingAsync.value ?? const <ContinueWatchingEntry>[];
    final recentWorks = recentWorksAsync.value ?? const <LibraryWork>[];

    if ((isCwLoading && recentWorks.isEmpty) ||
        (isRwLoading && continueWatching.isEmpty)) {
      return const Center(
        child: CircularProgressIndicator(key: Key('home_loading_indicator')),
      );
    }

    if (continueWatching.isEmpty && recentWorks.isEmpty) {
      if (continueWatchingAsync.hasError || recentWorksAsync.hasError) {
        return _buildErrorView();
      }
      return EmptyStateView(
        key: const Key('home_empty_library_view'),
        icon: Icons.movie_outlined,
        title: '暂无影视内容',
        message: '添加媒体源后将在此展示继续观看与最近添加的作品。',
        actionLabel: '前往媒体源',
        onAction: () => context.go('/sources'),
      );
    }

    final heroEntry = continueWatching.isEmpty ? null : continueWatching.first;
    final worksById = {for (final work in recentWorks) work.id: work};
    final heroWork = heroEntry == null
        ? recentWorks.first
        : worksById[heroEntry.workId];
    final isDesktop =
        MediaQuery.sizeOf(context).width >= ReelvaDesign.desktopBreakpoint;
    final textScaler = MediaQuery.textScalerOf(context);
    final textScale = textScaler.scale(14) / 14;

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxHeight < 600;
        final pagePadding = isDesktop
            ? ReelvaDesign.space32
            : ReelvaDesign.space24;
        final contentWidth = (constraints.maxWidth - pagePadding * 2).clamp(
          0.0,
          ReelvaDesign.contentMaxWidth,
        );
        final inset = (constraints.maxWidth - contentWidth) / 2;
        final sectionGap = compact
            ? ReelvaDesign.space12
            : ReelvaDesign.space24;
        final cardWidth =
            (isDesktop ? 224.0 : 160.0) * textScale.clamp(1.0, 2.0);
        final continueHeight =
            (cardWidth - ReelvaDesign.space8) * 9 / 16 +
            ReelvaDesign.space8 +
            ReelvaDesign.space16 +
            textScaler.scale(14) * 1.3 +
            ReelvaDesign.space4 +
            textScaler.scale(11) * 1.35 +
            3 +
            ReelvaDesign.space4;
        final gridSpacing = isDesktop
            ? ReelvaDesign.space16
            : ReelvaDesign.space12;
        final minPosterWidth =
            (isDesktop ? 160.0 : 96.0) * textScale.clamp(1.0, 2.0);
        final columns =
            ((contentWidth + gridSpacing) / (minPosterWidth + gridSpacing))
                .floor()
                .clamp(1, 6)
                .toInt();
        final posterWidth =
            (contentWidth - gridSpacing * (columns - 1)) / columns;
        final posterHeight = posterWidth / (isDesktop ? 2 / 3 : 1.4);
        final titleLines = compact && textScale <= 1.2 ? 1 : 2;
        final recentTitleSize = isDesktop ? 14.0 : 13.0;
        final recentHeight =
            posterHeight +
            ReelvaDesign.space8 +
            textScaler.scale(recentTitleSize) * 1.3 * titleLines +
            (isDesktop
                ? ReelvaDesign.space4 + textScaler.scale(11) * 1.35
                : 0) +
            ReelvaDesign.space4;

        final content = RefreshIndicator(
          onRefresh: () async {
            _retryAll();
          },
          child: CustomScrollView(
            key: const Key('home_content_scroll_view'),
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverPadding(
                padding: EdgeInsets.symmetric(horizontal: inset),
                sliver: SliverToBoxAdapter(
                  child: _buildHero(
                    context,
                    entry: heroEntry,
                    work: heroWork,
                    isDesktop: isDesktop,
                    compact: compact,
                  ),
                ),
              ),
              SliverPadding(
                padding: EdgeInsets.fromLTRB(
                  inset,
                  sectionGap,
                  inset,
                  ReelvaDesign.space8,
                ),
                sliver: SliverToBoxAdapter(
                  child: _buildSectionTitle(
                    context,
                    title: '继续观看',
                    actionLabel: '查看全部',
                  ),
                ),
              ),
              if (continueWatchingAsync.hasError &&
                  !continueWatchingAsync.hasValue)
                SliverPadding(
                  padding: EdgeInsets.symmetric(horizontal: inset),
                  sliver: SliverToBoxAdapter(
                    child: _buildShelfError(
                      context,
                      bannerKey: const Key(
                        'home_continue_watching_error_banner',
                      ),
                      retryKey: const Key(
                        'home_continue_watching_retry_button',
                      ),
                      message: '继续观看记录加载失败',
                      onRetry: () => ref.invalidate(continueWatchingProvider),
                    ),
                  ),
                )
              else if (continueWatching.isNotEmpty)
                SliverPadding(
                  padding: EdgeInsets.symmetric(horizontal: inset),
                  sliver: SliverToBoxAdapter(
                    child: SizedBox(
                      height: continueHeight,
                      child: ListView.separated(
                        key: const Key('home_continue_watching_list'),
                        scrollDirection: Axis.horizontal,
                        padding: EdgeInsets.zero,
                        itemCount: continueWatching.length,
                        separatorBuilder: (context, index) =>
                            const SizedBox(width: ReelvaDesign.space12),
                        itemBuilder: (context, index) {
                          final entry = continueWatching[index];
                          return _buildContinueWatchingCard(
                            context,
                            entry,
                            width: cardWidth,
                            work: worksById[entry.workId],
                          );
                        },
                      ),
                    ),
                  ),
                )
              else
                SliverPadding(
                  padding: EdgeInsets.symmetric(horizontal: inset),
                  sliver: SliverToBoxAdapter(
                    child: isCwLoading
                        ? const LinearProgressIndicator()
                        : _buildShelfHint('播放作品后，可在这里继续观看'),
                  ),
                ),
              SliverPadding(
                padding: EdgeInsets.fromLTRB(
                  inset,
                  sectionGap,
                  inset,
                  ReelvaDesign.space8,
                ),
                sliver: SliverToBoxAdapter(
                  child: _buildSectionTitle(
                    context,
                    title: '最近添加',
                    actionLabel: '全部作品',
                  ),
                ),
              ),
              if (recentWorksAsync.hasError && !recentWorksAsync.hasValue)
                SliverPadding(
                  padding: EdgeInsets.symmetric(horizontal: inset),
                  sliver: SliverToBoxAdapter(
                    child: _buildShelfError(
                      context,
                      bannerKey: const Key('home_recent_works_error_banner'),
                      retryKey: const Key('home_recent_works_retry_button'),
                      message: '最近添加作品加载失败',
                      onRetry: () => ref.invalidate(recentWorksProvider),
                    ),
                  ),
                )
              else if (recentWorks.isNotEmpty)
                SliverPadding(
                  padding: EdgeInsets.symmetric(horizontal: inset),
                  sliver: SliverGrid(
                    key: const Key('home_recent_works_grid'),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: columns,
                      mainAxisSpacing: ReelvaDesign.space16,
                      crossAxisSpacing: gridSpacing,
                      mainAxisExtent: recentHeight,
                    ),
                    delegate: SliverChildBuilderDelegate((context, index) {
                      return _buildRecentWorkCard(
                        context,
                        recentWorks[index],
                        isDesktop: isDesktop,
                        posterHeight: posterHeight,
                        titleLines: titleLines,
                      );
                    }, childCount: recentWorks.length),
                  ),
                )
              else
                SliverPadding(
                  padding: EdgeInsets.symmetric(horizontal: inset),
                  sliver: SliverToBoxAdapter(
                    child: isRwLoading
                        ? const LinearProgressIndicator()
                        : _buildShelfHint('新添加的作品会显示在这里'),
                  ),
                ),
              SliverToBoxAdapter(
                child: SizedBox(
                  height: isDesktop
                      ? 112
                      : ReelvaDesign.space32 +
                            MediaQuery.paddingOf(context).bottom,
                ),
              ),
            ],
          ),
        );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(
                inset,
                ReelvaDesign.space12,
                inset,
                ReelvaDesign.space12,
              ),
              child: _buildHeader(context, isDesktop: isDesktop),
            ),
            Expanded(child: content),
          ],
        );
      },
    );
  }

  Widget _buildErrorView() {
    return Center(
      key: const Key('home_error_view'),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(ReelvaDesign.space24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SafeErrorWidget(),
            const SizedBox(height: ReelvaDesign.space12),
            OutlinedButton.icon(
              key: const Key('home_retry_button'),
              onPressed: _retryAll,
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text('重试'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, {required bool isDesktop}) {
    return SizedBox(
      width: double.infinity,
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 12,
        runSpacing: 8,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(
              minHeight: ReelvaDesign.pageHeaderMinHeight,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Semantics(
                    header: true,
                    child: Text(
                      '首页',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.headlineLarge
                          ?.copyWith(
                            fontSize: ReelvaDesign.pageHeaderTitleSize,
                            fontWeight: FontWeight.w700,
                            color: ReelvaDesign.ink,
                          ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Wrap(
            spacing: 4,
            runSpacing: 8,
            children: [
              GlassIconButton(
                key: const Key('home_open_player_fab'),
                tooltip: '打开播放器',
                icon: Icons.play_arrow_rounded,
                size: ReelvaDesign.pageHeaderButtonSize,
                onPressed: () {
                  final router = GoRouter.of(context);
                  if (router.routeInformationProvider.value.uri.path !=
                      '/player') {
                    router.push<void>('/player');
                  }
                },
              ),
              if (isDesktop)
                GlassButton(
                  icon: Icons.search_rounded,
                  tooltip: '前往影视库搜索作品',
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(
                      ReelvaDesign.pageHeaderButtonSize,
                      ReelvaDesign.pageHeaderButtonSize,
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    iconSize: 20,
                    textStyle: Theme.of(context).textTheme.labelLarge
                        ?.copyWith(fontSize: 12),
                  ),
                  onPressed: () => context.go('/library'),
                  child: const Text('搜索影视作品'),
                )
              else
                GlassIconButton(
                  icon: Icons.search_rounded,
                  size: ReelvaDesign.pageHeaderButtonSize,
                  onPressed: () => context.go('/library'),
                  tooltip: '前往影视库搜索作品',
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildHero(
    BuildContext context, {
    required ContinueWatchingEntry? entry,
    required LibraryWork? work,
    required bool isDesktop,
    required bool compact,
  }) {
    final title = entry?.title ?? work!.title;
    final workId = entry?.workId ?? work!.id;
    final hasEpisode =
        entry?.seasonNumber != null || entry?.episodeNumber != null;
    final typeLabel = hasEpisode || work?.type == 'series'
        ? '剧集'
        : work?.type == 'movie'
        ? '电影'
        : '影视作品';
    final eyebrow = [
      typeLabel,
      if (work != null && work.year != null) '${work.year}',
      if (entry != null) '接着上次的故事',
    ].join(' · ');
    final episodeLabel = [
      if (entry != null && entry.seasonNumber != null)
        '第 ${entry.seasonNumber} 季',
      if (entry != null && entry.episodeNumber != null)
        '第 ${entry.episodeNumber} 集',
    ].join(' · ');
    final subtitle = entry == null
        ? null
        : hasEpisode
        ? episodeLabel
        : '上次看到 ${_formatDuration(entry.position)}';
    final overview = work?.overview?.trim();
    final canResume = entry != null && entry.available && entry.fileId != null;
    final isResolving =
        entry != null &&
        entry.fileId != null &&
        _resolvingFileId == entry.fileId;
    final heroPadding = compact
        ? ReelvaDesign.space16
        : isDesktop
        ? ReelvaDesign.space32
        : ReelvaDesign.space20;
    final theme = Theme.of(context);

    return GlassCard(
      padding: EdgeInsets.zero,
      borderRadius: BorderRadius.circular(ReelvaDesign.radius),
      color: const Color(0xFF152C3B),
      child: Stack(
        children: [
          Positioned.fill(
            child: Align(
              alignment: Alignment.centerRight,
              child: FractionallySizedBox(
                widthFactor: isDesktop ? 0.76 : 1,
                heightFactor: 1,
                child: PosterImage(
                  posterPath:
                      work?.backdropPath ??
                      entry?.posterPath ??
                      work?.posterPath,
                  fit: BoxFit.cover,
                  borderRadius: BorderRadius.zero,
                  size: 'w780',
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    const Color(0xFF102432).withValues(alpha: 0.97),
                    const Color(0xFF102432).withValues(alpha: 0.72),
                    const Color(0xFF102432).withValues(alpha: 0.08),
                  ],
                  stops: const [0, 0.46, 1],
                ),
              ),
            ),
          ),
          ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: compact ? 156 : (isDesktop ? 300 : 195),
            ),
            child: Padding(
              padding: EdgeInsets.all(heroPadding),
              child: Align(
                alignment: Alignment.centerLeft,
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: isDesktop ? 560 : 600),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        eyebrow,
                        style: const TextStyle(
                          fontSize: 10,
                          height: 1.35,
                          color: Colors.white70,
                        ),
                      ),
                      SizedBox(
                        height: compact
                            ? ReelvaDesign.space8
                            : ReelvaDesign.space20,
                      ),
                      Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: compact ? 24 : (isDesktop ? 36 : 28),
                          height: 1.15,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: ReelvaDesign.space4),
                        Text(
                          subtitle,
                          style: const TextStyle(
                            fontSize: 12,
                            height: 1.35,
                            color: Colors.white,
                          ),
                        ),
                      ],
                      if (isDesktop &&
                          !compact &&
                          overview != null &&
                          overview.isNotEmpty) ...[
                        const SizedBox(height: ReelvaDesign.space8),
                        Text(
                          overview,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 13,
                            height: 1.4,
                            color: Colors.white70,
                          ),
                        ),
                      ],
                      const SizedBox(height: ReelvaDesign.space12),
                      Theme(
                        data: theme.copyWith(
                          outlinedButtonTheme: OutlinedButtonThemeData(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: ReelvaDesign.ink,
                              backgroundColor: Colors.white.withValues(
                                alpha: 0.9,
                              ),
                              side: const BorderSide(color: Colors.white70),
                              shape: const StadiumBorder(),
                              minimumSize: const Size(0, 40),
                              padding: const EdgeInsets.symmetric(
                                horizontal: ReelvaDesign.space20,
                                vertical: ReelvaDesign.space8,
                              ),
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              textStyle: theme.textTheme.labelLarge?.copyWith(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                        child: GlassButton(
                          key: const Key('home_hero_action'),
                          icon: isResolving
                              ? null
                              : canResume
                              ? Icons.play_arrow_rounded
                              : Icons.arrow_forward_rounded,
                          tooltip: canResume ? '继续播放$title' : '查看$title的作品详情',
                          onPressed: _resolvingFileId != null
                              ? null
                              : () {
                                  if (entry != null && canResume) {
                                    _playEntry(entry);
                                  } else {
                                    _openWorkDetails(workId);
                                  }
                                },
                          child: isResolving
                              ? const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    SizedBox(
                                      width: 14,
                                      height: 14,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    ),
                                    SizedBox(width: ReelvaDesign.space8),
                                    Text('准备播放'),
                                  ],
                                )
                              : Text(canResume ? '继续播放' : '查看详情'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(
    BuildContext context, {
    required String title,
    required String actionLabel,
  }) {
    final action = TextButton(
      onPressed: () => context.go('/library'),
      style: TextButton.styleFrom(
        foregroundColor: ReelvaDesign.accent,
        padding: const EdgeInsets.symmetric(horizontal: ReelvaDesign.space4),
        minimumSize: const Size(0, 32),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        textStyle: Theme.of(context).textTheme.labelLarge
            ?.copyWith(fontSize: 12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(actionLabel),
          const SizedBox(width: ReelvaDesign.space4),
          const Icon(Icons.arrow_forward_rounded, size: 14),
        ],
      ),
    );
    if (MediaQuery.textScalerOf(context).scale(19) > 28) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          GlassSectionTitle(title: title),
          action,
        ],
      );
    }
    return Row(
      children: [
        Expanded(child: GlassSectionTitle(title: title)),
        const SizedBox(width: ReelvaDesign.space8),
        action,
      ],
    );
  }

  Widget _buildShelfHint(String message) {
    return GlassCard(
      padding: const EdgeInsets.all(ReelvaDesign.space12),
      child: Text(
        message,
        style: const TextStyle(
          fontSize: 12,
          height: 1.4,
          color: ReelvaDesign.muted,
        ),
      ),
    );
  }

  Widget _buildShelfError(
    BuildContext context, {
    required Key bannerKey,
    required Key retryKey,
    required String message,
    required VoidCallback onRetry,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return GlassCard(
      key: bannerKey,
      color: scheme.errorContainer.withValues(alpha: 0.7),
      padding: const EdgeInsets.symmetric(
        horizontal: ReelvaDesign.space12,
        vertical: ReelvaDesign.space8,
      ),
      child: Row(
        children: [
          Icon(Icons.warning_amber_rounded, size: 18, color: scheme.error),
          const SizedBox(width: ReelvaDesign.space8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(fontSize: 12, color: scheme.onErrorContainer),
            ),
          ),
          TextButton.icon(
            key: retryKey,
            onPressed: onRetry,
            icon: const Icon(Icons.refresh, size: 14),
            label: const Text('重试', style: TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
  }

  Widget _buildContinueWatchingCard(
    BuildContext context,
    ContinueWatchingEntry entry, {
    required double width,
    LibraryWork? work,
  }) {
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

    return SizedBox(
      width: width,
      child: GlassCard(
        key: Key('continue_watching_card_${entry.workId}'),
        padding: const EdgeInsets.all(ReelvaDesign.space4),
        onTap: () => _playEntry(entry),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AspectRatio(
              aspectRatio: 16 / 9,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(ReelvaDesign.radiusSmall),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    PosterImage(
                      posterPath:
                          work?.backdropPath ??
                          entry.posterPath ??
                          work?.posterPath,
                      title: entry.title,
                      borderRadius: BorderRadius.zero,
                    ),
                    if (!entry.available)
                      ColoredBox(color: Colors.black.withValues(alpha: 0.45)),
                    Center(
                      child: Tooltip(
                        message: entry.available
                            ? '继续播放${entry.title}'
                            : '打开作品详情以恢复媒体文件',
                        child: Material(
                          color: Colors.white.withValues(alpha: 0.9),
                          shape: const CircleBorder(),
                          child: InkWell(
                            key: Key('continue_watching_play_${entry.workId}'),
                            customBorder: const CircleBorder(),
                            onTap: () => _playEntry(entry),
                            child: SizedBox(
                              width: 40,
                              height: 40,
                              child: Center(
                                child: isResolving
                                    ? const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : Icon(
                                        entry.available
                                            ? Icons.play_arrow_rounded
                                            : Icons.info_outline_rounded,
                                        size: 22,
                                        color: ReelvaDesign.ink,
                                      ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    if (!entry.available)
                      Align(
                        alignment: Alignment.topLeft,
                        child: Container(
                          margin: const EdgeInsets.all(ReelvaDesign.space4),
                          padding: const EdgeInsets.symmetric(
                            horizontal: ReelvaDesign.space8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.7),
                            borderRadius: BorderRadius.circular(
                              ReelvaDesign.radiusSmall,
                            ),
                          ),
                          child: const Text(
                            '文件离线',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 10, color: Colors.white),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: ReelvaDesign.space4,
                vertical: ReelvaDesign.space8,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    entry.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
                      height: 1.3,
                      fontWeight: FontWeight.w600,
                      color: ReelvaDesign.ink,
                    ),
                  ),
                  const SizedBox(height: ReelvaDesign.space4),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          episodeSubtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 11,
                            height: 1.35,
                            color: ReelvaDesign.muted,
                          ),
                        ),
                      ),
                      if (entry.duration > Duration.zero) ...[
                        const SizedBox(width: ReelvaDesign.space4),
                        Text(
                          '${(entry.progressFraction * 100).round()}%',
                          style: const TextStyle(
                            fontSize: 10,
                            height: 1.35,
                            color: ReelvaDesign.accent,
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            ClipRRect(
              borderRadius: BorderRadius.circular(ReelvaDesign.radiusSmall),
              child: LinearProgressIndicator(
                value: entry.progressFraction,
                minHeight: 3,
                backgroundColor: ReelvaDesign.accent.withValues(alpha: 0.12),
                valueColor: const AlwaysStoppedAnimation(ReelvaDesign.accent),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRecentWorkCard(
    BuildContext context,
    LibraryWork work, {
    required bool isDesktop,
    required double posterHeight,
    required int titleLines,
  }) {
    final radius = BorderRadius.circular(ReelvaDesign.radiusSmall);
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        key: Key('recent_work_card_${work.id}'),
        borderRadius: radius,
        onTap: () => _openWorkDetails(work.id),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: posterHeight,
              child: ClipRRect(
                borderRadius: radius,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    PosterImage(
                      posterPath: isDesktop
                          ? work.posterPath
                          : work.backdropPath ?? work.posterPath,
                      title: work.title,
                      borderRadius: BorderRadius.zero,
                    ),
                    if (work.versionCount > 1)
                      Align(
                        alignment: Alignment.topRight,
                        child: Container(
                          margin: const EdgeInsets.all(ReelvaDesign.space4),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 5,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.7),
                            borderRadius: BorderRadius.circular(
                              ReelvaDesign.space4,
                            ),
                          ),
                          child: Text(
                            '${work.versionCount} 版本',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    if (!work.available)
                      const Align(
                        alignment: Alignment.bottomLeft,
                        child: Padding(
                          padding: EdgeInsets.all(ReelvaDesign.space8),
                          child: Tooltip(
                            message: '媒体文件当前不可用，可前往详情恢复',
                            child: Icon(
                              Icons.cloud_off_rounded,
                              color: Colors.white,
                              size: 20,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: ReelvaDesign.space8),
            Text(
              work.title,
              maxLines: titleLines,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: isDesktop ? 14 : 13,
                height: 1.3,
                fontWeight: FontWeight.w600,
                color: ReelvaDesign.ink,
              ),
            ),
            if (isDesktop) ...[
              const SizedBox(height: ReelvaDesign.space4),
              Text(
                [
                  if (work.type == 'series') '剧集',
                  if (work.type == 'movie') '电影',
                  if (work.year != null) '${work.year}',
                ].join(' · '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 11,
                  height: 1.35,
                  color: ReelvaDesign.muted,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
