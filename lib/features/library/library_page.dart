import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/errors/safe_error_widget.dart';
import '../../shared/widgets/empty_state_view.dart';
import '../../shared/widgets/glass_widgets.dart';
import '../../shared/widgets/poster_image.dart';
import '../metadata/application/metadata_providers.dart';
import '../metadata/presentation/metadata_status_card.dart';
import '../sources/application/source_providers.dart';
import 'domain/library_work.dart';
import 'presentation/manual_match_page.dart';

/// 以逻辑作品组织海报，搜索与类型筛选在数据库分页之前执行。
class LibraryPage extends ConsumerStatefulWidget {
  const LibraryPage({super.key, this.unmatchedOnly = false});

  final bool unmatchedOnly;

  @override
  ConsumerState<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends ConsumerState<LibraryPage> {
  final _searchController = TextEditingController();
  final _scrollController = ScrollController();
  int _limit = 100;
  List<LibraryWork>? _worksBeforeLoadMore;
  String _search = '';
  String? _type;
  bool _recentlyAdded = false;
  bool _hasInitialRefreshed = false;

  bool get _hasFilters => _search.isNotEmpty || _type != null;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _hasInitialRefreshed || widget.unmatchedOnly) return;
      final router = GoRouter.maybeOf(context);
      if (router != null &&
          router.routeInformationProvider.value.uri.path != '/library') {
        return;
      }
      _hasInitialRefreshed = true;
      ref.read(metadataControllerProvider.notifier).refresh();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _triggerRefresh() {
    ref.read(metadataControllerProvider.notifier).refresh();
  }

  Future<void> _reviewWork(LibraryWork work) async {
    final details = await ref
        .read(mediaLibraryRepositoryProvider)
        .getWorkDetails(work.id);
    if (!mounted || details == null) return;
    final files = await ref
        .read(mediaLibraryRepositoryProvider)
        .matchingFilesForWork(work.id);
    if (!mounted) return;
    await ManualMatchPage.showForWork(context, details, files: files);
  }

  void _updateSearch(String value) {
    final search = value.trim();
    if (_search == search) return;
    setState(() {
      _search = search;
      _limit = 100;
      _worksBeforeLoadMore = null;
    });
    if (_scrollController.hasClients) _scrollController.jumpTo(0);
  }

  void _selectType(String? type) {
    if (_type == type) return;
    setState(() {
      _type = type;
      _limit = 100;
      _worksBeforeLoadMore = null;
    });
    if (_scrollController.hasClients) _scrollController.jumpTo(0);
  }

  void _toggleRecent() {
    setState(() {
      _recentlyAdded = !_recentlyAdded;
      _limit = 100;
      _worksBeforeLoadMore = null;
    });
    if (_scrollController.hasClients) _scrollController.jumpTo(0);
  }

  void _clearFilters() {
    _searchController.clear();
    setState(() {
      _search = '';
      _type = null;
      _recentlyAdded = false;
      _limit = 100;
      _worksBeforeLoadMore = null;
    });
    if (_scrollController.hasClients) _scrollController.jumpTo(0);
  }

  @override
  Widget build(BuildContext context) {
    final query = (
      limit: _limit,
      search: _search,
      type: _type,
      recentlyAdded: _recentlyAdded,
      unmatchedOnly: widget.unmatchedOnly,
    );
    final usesFilteredProvider =
        _hasFilters || _recentlyAdded || widget.unmatchedOnly;
    final worksProvider = usesFilteredProvider
        ? filteredLibraryWorksProvider(query)
        : libraryWorksProvider(_limit);
    final worksAsync = ref.watch(worksProvider);
    ref.listen(worksProvider, (_, next) {
      if (_worksBeforeLoadMore != null &&
          next.hasValue &&
          !next.isLoading &&
          !next.hasError) {
        setState(() => _worksBeforeLoadMore = null);
      }
    });
    final worksBeforeLoadMore = _worksBeforeLoadMore;
    final visibleWorksAsync =
        worksBeforeLoadMore != null && !worksAsync.hasValue
        ? AsyncData(worksBeforeLoadMore)
        : worksAsync;
    final isLoadingMore = worksBeforeLoadMore != null && worksAsync.isLoading;
    final loadMoreFailed =
        worksBeforeLoadMore != null &&
        worksAsync.hasError &&
        !worksAsync.isLoading;
    final metaTaskState = ref.watch(metadataControllerProvider);
    final isScanning = ref.watch(
      sourceControllerProvider.select(
        (progress) => progress.values.any((scan) => scan.running),
      ),
    );
    final isBuildingLibrary = isScanning || metaTaskState.running;

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
              child: LayoutBuilder(
                builder: (context, constraints) {
                  const padding = ReelvaDesign.space24;
                  const gap = ReelvaDesign.space16;
                  final gridWidth = constraints.maxWidth - padding * 2;
                  final columns = (gridWidth / 168).floor().clamp(2, 8).toInt();
                  final posterWidth =
                      (gridWidth - gap * (columns - 1)) / columns;
                  final scaler = MediaQuery.textScalerOf(context);
                  final cardHeight =
                      posterWidth * 1.2 +
                      ReelvaDesign.space8 +
                      scaler.scale(14) * 1.3 * 2 +
                      ReelvaDesign.space4 +
                      scaler.scale(11) * 1.4 +
                      ReelvaDesign.space4;

                  final content = CustomScrollView(
                    key: const Key('library_works_scroll_view'),
                    controller: _scrollController,
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    slivers: [
                      SliverToBoxAdapter(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: padding,
                              ),
                              child: GlassSearchField(
                                key: const Key('library_search_field'),
                                controller: _searchController,
                                hintText: '搜索电影、剧集和关键词',
                                onChanged: _updateSearch,
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.fromLTRB(
                                padding,
                                ReelvaDesign.space12,
                                padding,
                                ReelvaDesign.space20,
                              ),
                              child: Wrap(
                                spacing: ReelvaDesign.space8,
                                runSpacing: ReelvaDesign.space8,
                                children: [
                                  ChoiceChip(
                                    key: const Key('library_filter_all'),
                                    label: const Text(
                                      '全部',
                                      style: TextStyle(fontSize: 12),
                                    ),
                                    selected: _type == null,
                                    showCheckmark: false,
                                    onSelected: (_) => _selectType(null),
                                  ),
                                  ChoiceChip(
                                    key: const Key('library_filter_movie'),
                                    label: const Text(
                                      '电影',
                                      style: TextStyle(fontSize: 12),
                                    ),
                                    selected: _type == 'movie',
                                    showCheckmark: false,
                                    onSelected: (_) => _selectType('movie'),
                                  ),
                                  ChoiceChip(
                                    key: const Key('library_filter_series'),
                                    label: const Text(
                                      '电视剧',
                                      style: TextStyle(fontSize: 12),
                                    ),
                                    selected: _type == 'series',
                                    showCheckmark: false,
                                    onSelected: (_) => _selectType('series'),
                                  ),
                                  FilterChip(
                                    key: const Key('library_filter_unmatched'),
                                    label: const Text(
                                      '待匹配',
                                      style: TextStyle(fontSize: 12),
                                    ),
                                    selected: widget.unmatchedOnly,
                                    showCheckmark: false,
                                    onSelected: (_) {
                                      if (widget.unmatchedOnly) {
                                        context.go('/library');
                                      } else {
                                        context.push('/library/unmatched');
                                      }
                                    },
                                  ),
                                  FilterChip(
                                    key: const Key('library_sort_recent'),
                                    label: const Text(
                                      '最近添加',
                                      style: TextStyle(fontSize: 12),
                                    ),
                                    selected: _recentlyAdded,
                                    showCheckmark: false,
                                    onSelected: (_) => _toggleRecent(),
                                  ),
                                ],
                              ),
                            ),
                            if (widget.unmatchedOnly)
                              GlassCard(
                                key: const Key('library_unmatched_help'),
                                margin: const EdgeInsets.fromLTRB(
                                  24,
                                  0,
                                  24,
                                  20,
                                ),
                                padding: const EdgeInsets.all(12),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      '这些条目尚未自动关联 TMDB。点击条目进行手动匹配，确认后会自动移出列表。',
                                    ),
                                    TextButton.icon(
                                      onPressed: () => context.go('/sources'),
                                      icon: const Icon(
                                        Icons.folder_outlined,
                                        size: 18,
                                      ),
                                      label: const Text('前往媒体源按文件夹批量匹配'),
                                    ),
                                  ],
                                ),
                              )
                            else
                              MetadataStatusCard(
                                state: metaTaskState,
                                onRetry: _triggerRefresh,
                                margin: const EdgeInsets.fromLTRB(
                                  24,
                                  0,
                                  24,
                                  20,
                                ),
                              ),
                          ],
                        ),
                      ),
                      visibleWorksAsync.when(
                        loading: () => SliverFillRemaining(
                          hasScrollBody: false,
                          child: Center(
                            key: const Key('library_loading_indicator'),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const CircularProgressIndicator(),
                                const SizedBox(height: ReelvaDesign.space12),
                                Text(
                                  isBuildingLibrary ? '正在建立影视库…' : '正在加载影视库…',
                                ),
                                const Text('可切换页面，处理完成后会自动更新'),
                              ],
                            ),
                          ),
                        ),
                        error: (error, stack) => SliverFillRemaining(
                          hasScrollBody: false,
                          child: Center(
                            key: const Key('library_error_widget'),
                            child: Padding(
                              padding: const EdgeInsets.all(padding),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const SafeErrorWidget(),
                                  const SizedBox(height: ReelvaDesign.space12),
                                  GlassButton(
                                    key: const Key('library_retry_button'),
                                    onPressed: () =>
                                        ref.invalidate(worksProvider),
                                    icon: Icons.refresh_rounded,
                                    child: const Text('重试'),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        data: (works) {
                          if (works.isEmpty) {
                            return SliverFillRemaining(
                              hasScrollBody: false,
                              child: _hasFilters
                                  ? EmptyStateView(
                                      key: const Key(
                                        'library_search_empty_view',
                                      ),
                                      icon: Icons.search_off_rounded,
                                      title: '未找到匹配的作品',
                                      message: '试试其他关键词，或清空搜索和筛选后查看全部作品。',
                                      actionLabel: '清空搜索和筛选',
                                      onAction: _clearFilters,
                                    )
                                  : isBuildingLibrary
                                  ? EmptyStateView(
                                      key: const Key('library_building_view'),
                                      icon: Icons.manage_search_outlined,
                                      title: '正在建立影视库',
                                      message: isScanning
                                          ? '正在扫描媒体源中的视频，可切换页面继续使用。'
                                          : '正在整理影片与剧集，完成后会自动显示。',
                                      actionLabel: '查看媒体源',
                                      onAction: () => context.go('/sources'),
                                    )
                                  : widget.unmatchedOnly
                                  ? EmptyStateView(
                                      key: const Key(
                                        'library_unmatched_empty_view',
                                      ),
                                      icon: Icons.task_alt,
                                      title: '暂无待匹配条目',
                                      message: '当前条目已完成匹配或人工确认，可返回影视库查看。',
                                      actionLabel: '查看全部',
                                      onAction: () => context.go('/library'),
                                    )
                                  : EmptyStateView(
                                      key: const Key('library_empty_view'),
                                      icon: Icons.video_library_outlined,
                                      title: '影视库为空',
                                      message: '配置媒体源并完成扫描后，影视库将呈现影视作品与海报。',
                                      actionLabel: '前往媒体源',
                                      onAction: () => context.go('/sources'),
                                    ),
                            );
                          }

                          return SliverMainAxisGroup(
                            slivers: [
                              SliverPadding(
                                padding: const EdgeInsets.fromLTRB(
                                  padding,
                                  0,
                                  padding,
                                  ReelvaDesign.space24,
                                ),
                                sliver: SliverGrid(
                                  key: const Key('library_works_grid'),
                                  gridDelegate:
                                      SliverGridDelegateWithFixedCrossAxisCount(
                                        crossAxisCount: columns,
                                        crossAxisSpacing: gap,
                                        mainAxisSpacing: gap,
                                        mainAxisExtent: cardHeight,
                                      ),
                                  delegate: SliverChildBuilderDelegate((
                                    context,
                                    index,
                                  ) {
                                    final work = works[index];
                                    return _WorkPosterCard(
                                      key: Key('library_work_card_${work.id}'),
                                      work: work,
                                      onTap: () {
                                        if (widget.unmatchedOnly) {
                                          _reviewWork(work);
                                        } else {
                                          context.go(
                                            '/library/work/${work.id}',
                                          );
                                        }
                                      },
                                    );
                                  }, childCount: works.length),
                                ),
                              ),
                              if (worksBeforeLoadMore != null ||
                                  works.length >= _limit)
                                SliverToBoxAdapter(
                                  child: Padding(
                                    padding: const EdgeInsets.only(
                                      bottom: ReelvaDesign.space32,
                                    ),
                                    child: Center(
                                      child: GlassButton(
                                        key: const Key(
                                          'library_load_more_button',
                                        ),
                                        onPressed: isLoadingMore
                                            ? null
                                            : () {
                                                if (loadMoreFailed) {
                                                  ref.invalidate(worksProvider);
                                                } else if (_worksBeforeLoadMore ==
                                                    null) {
                                                  setState(() {
                                                    _worksBeforeLoadMore =
                                                        works;
                                                    _limit += 100;
                                                  });
                                                }
                                              },
                                        child: isLoadingMore
                                            ? const Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  SizedBox.square(
                                                    dimension: 20,
                                                    child:
                                                        CircularProgressIndicator(
                                                          key: Key(
                                                            'library_load_more_indicator',
                                                          ),
                                                          strokeWidth: 2,
                                                        ),
                                                  ),
                                                  SizedBox(width: 8),
                                                  Text('正在加载…'),
                                                ],
                                              )
                                            : Text(
                                                loadMoreFailed
                                                    ? '加载失败，点击重试'
                                                    : '加载更多作品',
                                              ),
                                      ),
                                    ),
                                  ),
                                ),
                              SliverToBoxAdapter(
                                child: SizedBox(
                                  height: MediaQuery.paddingOf(context).bottom,
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ],
                  );
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: GlassPageHeader(
                              title: widget.unmatchedOnly ? '待匹配' : '影视库',
                              leading: widget.unmatchedOnly
                                  ? GlassIconButton(
                                      icon: Icons.arrow_back,
                                      tooltip: '返回',
                                      size: ReelvaDesign.pageHeaderButtonSize,
                                      onPressed: () => context.pop(),
                                    )
                                  : null,
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.only(
                              top: ReelvaDesign.space12,
                              right: ReelvaDesign.space24,
                            ),
                            child: metaTaskState.running
                                ? const SizedBox(
                                    width: 48,
                                    height: 48,
                                    child: Center(
                                      child: SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      ),
                                    ),
                                  )
                                : GlassIconButton(
                                    key: const Key(
                                      'library_refresh_metadata_button',
                                    ),
                                    icon: Icons.refresh_rounded,
                                    size: ReelvaDesign.pageHeaderButtonSize,
                                    tooltip: '刷新并识别影视元数据',
                                    onPressed: _triggerRefresh,
                                  ),
                          ),
                        ],
                      ),
                      Expanded(child: content),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _WorkPosterCard extends StatelessWidget {
  const _WorkPosterCard({super.key, required this.work, required this.onTap});

  final LibraryWork work;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final displayTitle = work.title.trim().isNotEmpty ? work.title : '未识别作品';
    final metadata = [
      if (work.type == 'series') '剧集' else if (work.type == 'movie') '电影',
      if (work.year != null) '${work.year}',
    ].join(' · ');

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(ReelvaDesign.radius),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AspectRatio(
              aspectRatio: 5 / 6,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Hero(
                    tag: 'work_poster_${work.id}',
                    child: PosterImage(
                      posterPath: work.posterPath,
                      title: displayTitle,
                      borderRadius: BorderRadius.circular(ReelvaDesign.radius),
                    ),
                  ),
                  if (work.metadataLocked ||
                      work.metadataSource == 'local' ||
                      work.versionCount > 1)
                    Positioned(
                      top: ReelvaDesign.space8,
                      left: ReelvaDesign.space8,
                      right: ReelvaDesign.space8,
                      child: Wrap(
                        spacing: ReelvaDesign.space4,
                        runSpacing: ReelvaDesign.space4,
                        children: [
                          if (work.metadataLocked)
                            const _PosterBadge(
                              text: '已锁定',
                              icon: Icons.lock_outline,
                            )
                          else if (work.metadataSource == 'local')
                            const _PosterBadge(text: '待匹配'),
                          if (work.versionCount > 1)
                            _PosterBadge(text: '${work.versionCount} 版本'),
                        ],
                      ),
                    ),
                  if (!work.available)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(ReelvaDesign.radius),
                      child: ColoredBox(
                        color: Colors.black.withValues(alpha: 0.35),
                        child: const Center(
                          child: Padding(
                            padding: EdgeInsets.all(ReelvaDesign.space8),
                            child: _PosterBadge(
                              text: '文件离线',
                              icon: Icons.cloud_off_outlined,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: ReelvaDesign.space8),
            Text(
              displayTitle,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontSize: 14,
                height: 1.3,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: ReelvaDesign.space4),
            Text(
              metadata,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                fontSize: 11,
                height: 1.4,
                color: ReelvaDesign.muted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PosterBadge extends StatelessWidget {
  const _PosterBadge({required this.text, this.icon});

  final String text;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(ReelvaDesign.radiusSmall),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: ReelvaDesign.ink),
            const SizedBox(width: ReelvaDesign.space4),
          ],
          Flexible(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: ReelvaDesign.ink,
                fontSize: 10,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
