import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/errors/safe_error_widget.dart';
import '../../shared/widgets/empty_state_view.dart';
import '../../shared/widgets/glass_widgets.dart';
import '../../shared/widgets/poster_image.dart';
import '../metadata/application/metadata_providers.dart';
import 'domain/library_work.dart';

/// 以逻辑作品组织海报，搜索与类型筛选在数据库分页之前执行。
class LibraryPage extends ConsumerStatefulWidget {
  const LibraryPage({super.key});

  @override
  ConsumerState<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends ConsumerState<LibraryPage> {
  final _searchController = TextEditingController();
  final _scrollController = ScrollController();
  int _limit = 100;
  String _search = '';
  String? _type;
  bool _recentlyAdded = false;
  bool _hasInitialRefreshed = false;

  bool get _hasFilters => _search.isNotEmpty || _type != null;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _hasInitialRefreshed) return;
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

  void _updateSearch(String value) {
    final search = value.trim();
    if (_search == search) return;
    setState(() {
      _search = search;
      _limit = 100;
    });
    if (_scrollController.hasClients) _scrollController.jumpTo(0);
  }

  void _selectType(String? type) {
    if (_type == type) return;
    setState(() {
      _type = type;
      _limit = 100;
    });
    if (_scrollController.hasClients) _scrollController.jumpTo(0);
  }

  void _toggleRecent() {
    setState(() {
      _recentlyAdded = !_recentlyAdded;
      _limit = 100;
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
    );
    final usesFilteredProvider = _hasFilters || _recentlyAdded;
    final worksAsync = usesFilteredProvider
        ? ref.watch(filteredLibraryWorksProvider(query))
        : ref.watch(libraryWorksProvider(_limit));
    final metaTaskState = ref.watch(metadataControllerProvider);

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

                  return CustomScrollView(
                    key: const Key('library_works_scroll_view'),
                    controller: _scrollController,
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    slivers: [
                      SliverToBoxAdapter(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Expanded(
                                  child: GlassPageHeader(
                                    title: '影视库',
                                    subtitle: '在这里，所有故事都井然有序。',
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.only(
                                    top: ReelvaDesign.space20,
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
                                          tooltip: '刷新并识别影视元数据',
                                          onPressed: _triggerRefresh,
                                        ),
                                ),
                              ],
                            ),
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
                            _buildMetadataStatusBar(context, metaTaskState),
                          ],
                        ),
                      ),
                      worksAsync.when(
                        loading: () => const SliverFillRemaining(
                          hasScrollBody: false,
                          child: Center(
                            key: Key('library_loading_indicator'),
                            child: CircularProgressIndicator(),
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
                                    onPressed: () {
                                      if (usesFilteredProvider) {
                                        ref.invalidate(
                                          filteredLibraryWorksProvider(query),
                                        );
                                      } else {
                                        ref.invalidate(
                                          libraryWorksProvider(_limit),
                                        );
                                      }
                                    },
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
                                      onTap: () => context.go(
                                        '/library/work/${work.id}',
                                      ),
                                    );
                                  }, childCount: works.length),
                                ),
                              ),
                              if (works.length >= _limit)
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
                                        onPressed: () => setState(() {
                                          _limit += 100;
                                        }),
                                        child: const Text('加载更多作品'),
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          );
                        },
                      ),
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

  Widget _buildMetadataStatusBar(
    BuildContext context,
    MetadataTaskState state,
  ) {
    final scheme = Theme.of(context).colorScheme;
    const margin = EdgeInsets.fromLTRB(24, 0, 24, 20);

    if (state.running) {
      return const GlassCard(
        key: Key('library_metadata_running_banner'),
        margin: margin,
        padding: EdgeInsets.all(ReelvaDesign.space12),
        child: Row(
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: ReelvaDesign.space12),
            Expanded(child: Text('正在匹配影视元数据与海报...')),
          ],
        ),
      );
    }

    if (state.error != null) {
      return GlassCard(
        key: const Key('library_metadata_error_banner'),
        margin: margin,
        padding: const EdgeInsets.all(ReelvaDesign.space12),
        color: scheme.errorContainer.withValues(alpha: 0.65),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.error_outline, size: 20, color: scheme.error),
                const SizedBox(width: ReelvaDesign.space8),
                Expanded(
                  child: Text(
                    state.error!,
                    style: TextStyle(color: scheme.onErrorContainer),
                  ),
                ),
              ],
            ),
            Wrap(
              spacing: ReelvaDesign.space8,
              runSpacing: ReelvaDesign.space4,
              children: [
                TextButton.icon(
                  key: const Key('library_metadata_retry_button'),
                  onPressed: _triggerRefresh,
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: const Text('重试'),
                ),
                TextButton.icon(
                  key: const Key('library_metadata_settings_button'),
                  onPressed: () => context.go('/settings'),
                  icon: const Icon(Icons.settings_outlined, size: 18),
                  label: const Text('设置凭据'),
                ),
              ],
            ),
          ],
        ),
      );
    }

    final result = state.result;
    if (result != null && result.errors.isNotEmpty) {
      final hasNoKey = result.errors.any((e) => e.contains('未配置 TMDB API 密钥'));
      return GlassCard(
        key: const Key('library_metadata_result_banner'),
        margin: margin,
        padding: const EdgeInsets.all(ReelvaDesign.space12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline, size: 20, color: scheme.primary),
                const SizedBox(width: ReelvaDesign.space8),
                Expanded(
                  child: Text(
                    hasNoKey
                        ? '未配置 TMDB 凭据，仅完成本地识别'
                        : '元数据刷新完成（${result.matched} 匹配，${result.needsReview} 需核对）',
                  ),
                ),
              ],
            ),
            if (hasNoKey)
              TextButton(
                key: const Key('library_metadata_configure_button'),
                onPressed: () => context.go('/settings'),
                child: const Text('配置 TMDB'),
              ),
          ],
        ),
      );
    }

    return const SizedBox.shrink();
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
