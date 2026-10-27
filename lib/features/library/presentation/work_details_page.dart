import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/errors/safe_error_widget.dart';
import '../../../core/logging/app_logger.dart';
import '../../../shared/widgets/empty_state_view.dart';
import '../../../shared/widgets/glass_widgets.dart';
import '../../../shared/widgets/poster_image.dart';
import '../../metadata/application/metadata_providers.dart';
import '../../metadata/presentation/nfo_status_card.dart';
import '../../sources/application/source_providers.dart';
import '../../sources/domain/source_models.dart';
import '../domain/library_work.dart';
import 'local_edit_dialog.dart';
import 'manual_match_page.dart';

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
  int? _selectedSeason;

  @override
  void didUpdateWidget(covariant WorkDetailsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.workId != widget.workId) _selectedSeason = null;
  }

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
    final details = await ref
        .read(mediaLibraryRepositoryProvider)
        .getWorkDetails(work.id);
    if (!mounted || details == null) return;
    final files = await ref
        .read(mediaLibraryRepositoryProvider)
        .matchingFilesForWork(work.id);
    if (!mounted) return;
    final canonicalId = await ManualMatchPage.showForWork(
      context,
      details,
      files: files,
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
      initialPosterPath:
          work.tmdbPosterPath ??
          (work.posterPath?.contains('://') == false ? work.posterPath : null),
    );
  }

  @override
  Widget build(BuildContext context) {
    final detailsAsync = ref.watch(workDetailsProvider(widget.workId));

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: GlassBackground(
        child: SafeArea(
          top: false,
          bottom: false,
          child: detailsAsync.when(
            loading: () => _buildStateBody(
              const Center(
                key: Key('work_details_loading'),
                child: CircularProgressIndicator(),
              ),
            ),
            error: (error, stack) => _buildStateBody(
              Center(
                key: const Key('work_details_error'),
                child: Padding(
                  padding: const EdgeInsets.all(ReelvaDesign.space24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SafeErrorWidget(),
                      const SizedBox(height: ReelvaDesign.space12),
                      GlassButton(
                        key: const Key('work_details_retry_button'),
                        onPressed: () =>
                            ref.invalidate(workDetailsProvider(widget.workId)),
                        icon: Icons.refresh_rounded,
                        child: const Text('重试'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            data: (details) {
              if (details == null) {
                return _buildStateBody(
                  EmptyStateView(
                    key: const Key('work_not_found_view'),
                    icon: Icons.movie_filter_outlined,
                    title: '作品不存在或已被合并',
                    message: '该条目可能已被更新、合并到其他作品或被移除。',
                    actionLabel: '返回影视库',
                    onAction: () => context.go('/library'),
                  ),
                );
              }

              return Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: ReelvaDesign.contentMaxWidth,
                  ),
                  child: LayoutBuilder(
                    builder: (context, constraints) => CustomScrollView(
                      key: const Key('work_details_scroll_view'),
                      slivers: [
                        _buildAppBar(
                          context,
                          work: details.work,
                          expandedHeight: (constraints.maxWidth * 0.78).clamp(
                            220.0,
                            360.0,
                          ),
                        ),
                        SliverPadding(
                          padding: EdgeInsets.fromLTRB(
                            ReelvaDesign.space24,
                            ReelvaDesign.space24,
                            ReelvaDesign.space24,
                            ReelvaDesign.space24 +
                                MediaQuery.paddingOf(context).bottom,
                          ),
                          sliver: SliverToBoxAdapter(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                const NfoStatusCard(
                                  margin: EdgeInsets.only(
                                    bottom: ReelvaDesign.space24,
                                  ),
                                ),
                                _buildHeader(context, details),
                                if (details.work.type == 'series') ...[
                                  const SizedBox(height: ReelvaDesign.space24),
                                  _buildVersionsSection(context, details),
                                ],
                                if (details.work.overview?.trim().isNotEmpty ??
                                    false) ...[
                                  const SizedBox(height: ReelvaDesign.space24),
                                  const GlassSectionTitle(title: '剧情简介'),
                                  const SizedBox(height: ReelvaDesign.space8),
                                  Text(
                                    details.work.overview!,
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodyMedium
                                        ?.copyWith(
                                          height: 1.65,
                                          color: ReelvaDesign.muted,
                                        ),
                                  ),
                                ],
                                if (details.work.type != 'series') ...[
                                  const SizedBox(height: ReelvaDesign.space24),
                                  _buildVersionsSection(context, details),
                                ],
                                const SizedBox(height: ReelvaDesign.space8),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildStateBody(Widget child) {
    return CustomScrollView(
      slivers: [
        _buildAppBar(context),
        SliverFillRemaining(hasScrollBody: false, child: child),
      ],
    );
  }

  Widget _buildAppBar(
    BuildContext context, {
    LibraryWork? work,
    double? expandedHeight,
  }) {
    return SliverAppBar(
      pinned: true,
      automaticallyImplyLeading: false,
      backgroundColor: ReelvaDesign.background,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      toolbarHeight: ReelvaDesign.pageHeaderMinHeight + ReelvaDesign.space32,
      titleSpacing: 0,
      expandedHeight: expandedHeight,
      systemOverlayStyle: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        statusBarBrightness: Brightness.light,
        systemStatusBarContrastEnforced: false,
      ),
      flexibleSpace: work == null
          ? null
          : FlexibleSpaceBar(background: _buildCover(work)),
      title: Padding(
        padding: const EdgeInsets.all(ReelvaDesign.space16),
        child: Row(
          children: [
            ClipOval(
              child: GlassIconButton(
                key: const Key('work_details_back_button'),
                icon: Icons.arrow_back_rounded,
                size: ReelvaDesign.pageHeaderButtonSize,
                tooltip: '返回影视库',
                onPressed: () => context.go('/library'),
              ),
            ),
            const SizedBox(width: ReelvaDesign.space12),
            Expanded(
              child: Align(
                alignment: Alignment.centerLeft,
                heightFactor: 1,
                child: GlassCard(
                  padding: const EdgeInsets.symmetric(
                    horizontal: ReelvaDesign.space12,
                    vertical: ReelvaDesign.space8,
                  ),
                  borderRadius: BorderRadius.circular(24),
                  child: Text(
                    '作品详情',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelMedium,
                  ),
                ),
              ),
            ),
            if (work != null) ...[
              const SizedBox(width: ReelvaDesign.space8),
              PopupMenuButton<_WorkAction>(
                key: const Key('work_more_button'),
                tooltip: '更多操作',
                onSelected: (action) {
                  switch (action) {
                    case _WorkAction.manualMatch:
                      _openManualMatch(work);
                    case _WorkAction.localEdit:
                      _openLocalEdit(work);
                  }
                },
                itemBuilder: (context) => const [
                  GlassPopupMenuItem(
                    value: _WorkAction.manualMatch,
                    child: Text('手动匹配'),
                  ),
                  GlassPopupMenuItem(
                    value: _WorkAction.localEdit,
                    child: Text('本地编辑'),
                  ),
                ],
                child: GlassCard(
                  padding: const EdgeInsets.all(ReelvaDesign.space12),
                  borderRadius: BorderRadius.circular(24),
                  child: const Icon(Icons.more_horiz_rounded),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildCover(LibraryWork work) {
    final backdrop = work.backdropPath?.trim();
    return Stack(
      fit: StackFit.expand,
      children: [
        PosterImage(
          key: const Key('work_details_cover'),
          posterPath: backdrop != null && backdrop.isNotEmpty
              ? backdrop
              : work.posterPath,
          size: 'w780',
          borderRadius: BorderRadius.zero,
        ),
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Color(0x80F8FAFD),
                Color(0x00F8FAFD),
                Color(0x00F8FAFD),
                ReelvaDesign.background,
              ],
              stops: [0, 0.32, 0.72, 1],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildHeader(BuildContext context, WorkDetails details) {
    final theme = Theme.of(context);
    final work = details.work;
    final isSeries = work.type == 'series';
    final selectedSeason = _seasonFor(details.versions);
    final playable = details.versions.where(
      (version) =>
          version.available &&
          (!isSeries || (version.seasonNumber ?? 1) == selectedSeason),
    );
    final firstAvailable = playable.isEmpty ? null : playable.first;

    final information = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          work.title.trim().isNotEmpty ? work.title : '未命名条目',
          key: const Key('work_details_title'),
          style: theme.textTheme.headlineLarge?.copyWith(
            fontSize: 30,
            height: 1.2,
            fontWeight: FontWeight.w700,
          ),
        ),
        if (work.originalTitle?.trim().isNotEmpty == true &&
            work.originalTitle != work.title) ...[
          const SizedBox(height: ReelvaDesign.space8),
          Text(
            work.originalTitle!,
            style: theme.textTheme.bodySmall?.copyWith(
              color: ReelvaDesign.muted,
              letterSpacing: 0.8,
            ),
          ),
        ],
        const SizedBox(height: ReelvaDesign.space16),
        Wrap(
          spacing: ReelvaDesign.space8,
          runSpacing: ReelvaDesign.space8,
          children: [
            if (work.year != null) _buildChip(context, label: '${work.year}'),
            _buildChip(
              context,
              label: isSeries ? '剧集' : (work.type == 'movie' ? '电影' : '未定类型'),
            ),
            _buildChip(
              context,
              label: switch (work.metadataSource) {
                'tmdb' => 'TMDB 匹配',
                'nfo' => '目录元数据',
                _ => '本地识别',
              },
              icon: work.metadataSource == 'tmdb'
                  ? Icons.cloud_done_outlined
                  : Icons.folder_outlined,
            ),
            if (work.metadataLocked)
              _buildChip(
                context,
                key: const Key('work_locked_badge'),
                label: '已锁定',
                icon: Icons.lock_outline,
              )
            else if (work.metadataSource == 'local')
              _buildChip(
                context,
                key: const Key('work_unmatched_badge'),
                label: '待匹配',
                icon: Icons.help_outline,
              ),
            _buildChip(
              context,
              key: const Key('work_item_count'),
              label: isSeries
                  ? '库中有 ${details.episodeCount} 集'
                  : '${details.versions.length} 个版本文件',
              icon: Icons.filter_none_outlined,
            ),
          ],
        ),
        const SizedBox(height: ReelvaDesign.space20),
        GlassButton(
          key: const Key('work_start_play_button'),
          primary: true,
          icon: Icons.play_arrow_rounded,
          onPressed: firstAvailable == null || _resolvingFileId != null
              ? null
              : () => _playVersion(firstAvailable),
          child: Text(
            _resolvingFileId != null ? '正在解析播放地址…' : '开始播放',
            textAlign: TextAlign.center,
          ),
        ),
        const SizedBox(height: ReelvaDesign.space12),
        Wrap(
          spacing: ReelvaDesign.space8,
          runSpacing: ReelvaDesign.space8,
          children: [
            GlassButton(
              key: const Key('work_manual_match_button'),
              onPressed: () => _openManualMatch(work),
              icon: Icons.search_rounded,
              child: const Text('手动匹配'),
            ),
            GlassButton(
              key: const Key('work_local_edit_button'),
              onPressed: () => _openLocalEdit(work),
              icon: Icons.edit_outlined,
              child: const Text('本地编辑'),
            ),
          ],
        ),
      ],
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < ReelvaDesign.desktopBreakpoint) {
          return information;
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Hero(
              tag: 'work_poster_${work.id}',
              child: PosterImage(
                posterPath: work.posterPath,
                title: work.title,
                width: 160,
                height: 240,
                size: 'w500',
                borderRadius: BorderRadius.circular(ReelvaDesign.radius),
              ),
            ),
            const SizedBox(width: ReelvaDesign.space24),
            Expanded(child: information),
          ],
        );
      },
    );
  }

  Widget _buildChip(
    BuildContext context, {
    Key? key,
    required String label,
    IconData? icon,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      key: key,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: ReelvaDesign.muted),
            const SizedBox(width: ReelvaDesign.space4),
          ],
          Flexible(
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                height: 1.3,
                color: ReelvaDesign.muted,
              ),
            ),
          ),
        ],
      ),
    );
  }

  int? _seasonFor(List<LibraryVersion> versions) {
    final seasons =
        versions.map((version) => version.seasonNumber ?? 1).toSet().toList()
          ..sort();
    if (seasons.contains(_selectedSeason)) return _selectedSeason;
    return seasons.where((season) => season > 0).firstOrNull ??
        seasons.firstOrNull;
  }

  Widget _buildVersionsSection(BuildContext context, WorkDetails details) {
    final versions = details.versions;
    if (versions.isEmpty) {
      return const GlassCard(child: Center(child: Text('当前条目暂无可播放的文件版本')));
    }

    if (details.work.type != 'series') {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const GlassSectionTitle(title: '可用版本列表'),
          const SizedBox(height: ReelvaDesign.space12),
          GlassCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: _buildVersionRows(context, details, versions),
            ),
          ),
        ],
      );
    }

    final seasonMap = <int, List<LibraryVersion>>{};
    for (final version in versions) {
      seasonMap.putIfAbsent(version.seasonNumber ?? 1, () => []).add(version);
    }
    final seasons = seasonMap.keys.toList()..sort();
    final selectedSeason = _seasonFor(versions)!;
    final episodeMap = <Object, List<LibraryVersion>>{};
    for (final version in seasonMap[selectedSeason]!) {
      final key = version.episodeNumber ?? ('file', version.fileId);
      episodeMap.putIfAbsent(key, () => []).add(version);
    }
    final episodes = episodeMap.values.toList()
      ..sort((a, b) {
        final first = a.first.episodeNumber;
        final second = b.first.episodeNumber;
        if (first == null) {
          return second == null
              ? a.first.fileName.compareTo(b.first.fileName)
              : 1;
        }
        return second == null ? -1 : first.compareTo(second);
      });
    final episodeCount = episodes
        .where((episode) => episode.first.episodeNumber != null)
        .length;
    final unnumberedCount = episodes.length - episodeCount;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const GlassSectionTitle(title: '剧集'),
        const SizedBox(height: ReelvaDesign.space8),
        SingleChildScrollView(
          key: const Key('work_season_tabs'),
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final season in seasons)
                Semantics(
                  selected: season == selectedSeason,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      border: Border(
                        bottom: BorderSide(
                          color: season == selectedSeason
                              ? Theme.of(context).colorScheme.primary
                              : Colors.transparent,
                          width: 3,
                        ),
                      ),
                    ),
                    child: TextButton(
                      key: ValueKey('work_season_tab_$season'),
                      onPressed: () => setState(() {
                        _selectedSeason = season;
                      }),
                      style: TextButton.styleFrom(
                        foregroundColor: season == selectedSeason
                            ? Theme.of(context).colorScheme.primary
                            : ReelvaDesign.muted,
                      ),
                      child: Text(season > 0 ? '第 $season 季' : '特别篇'),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: ReelvaDesign.space12),
        Text(
          '本季库中有 $episodeCount 集'
          '${unnumberedCount > 0 ? ' · $unnumberedCount 个未分集文件' : ''}',
          key: const Key('work_season_episode_count'),
          style: Theme.of(context).textTheme.bodySmall
              ?.copyWith(color: ReelvaDesign.muted),
        ),
        const SizedBox(height: ReelvaDesign.space12),
        LayoutBuilder(
          builder: (context, constraints) {
            final cardWidth = (constraints.maxWidth * 0.46).clamp(156.0, 240.0);
            final scaler = MediaQuery.textScalerOf(context);
            final cardHeight =
                cardWidth * 9 / 16 +
                ReelvaDesign.space12 +
                scaler.scale(14) * 3 +
                scaler.scale(13) * 1.45;
            return SizedBox(
              height: cardHeight,
              child: ListView.separated(
                key: ValueKey(
                  'work_episode_list_${details.work.id}_$selectedSeason',
                ),
                primary: false,
                scrollDirection: Axis.horizontal,
                itemCount: episodes.length,
                separatorBuilder: (context, index) =>
                    const SizedBox(width: ReelvaDesign.space12),
                itemBuilder: (context, index) => SizedBox(
                  width: cardWidth,
                  child: _buildEpisodeCard(context, details, episodes[index]),
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildEpisodeCard(
    BuildContext context,
    WorkDetails details,
    List<LibraryVersion> versions,
  ) {
    final theme = Theme.of(context);
    final first = versions.first;
    final available = versions.any((version) => version.available);
    final resolving = versions.any(
      (version) => version.fileId == _resolvingFileId,
    );
    final title = first.episodeNumber == null
        ? first.fileName
        : '第 ${first.episodeNumber} 集'
              '${first.episodeTitle?.trim().isNotEmpty == true ? ' · ${first.episodeTitle}' : ''}';
    return Material(
      key: ValueKey(
        'work_episode_card_${first.seasonNumber ?? 1}_'
        '${first.episodeNumber ?? 'file_${first.fileId}'}',
      ),
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(ReelvaDesign.radiusSmall),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: _resolvingFileId != null || (!available && versions.length == 1)
            ? null
            : () => _openEpisode(details, versions, title),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AspectRatio(
              aspectRatio: 16 / 9,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  PosterImage(
                    posterPath:
                        details.work.backdropPath ?? details.work.posterPath,
                    borderRadius: BorderRadius.circular(
                      ReelvaDesign.radiusSmall,
                    ),
                  ),
                  Center(
                    child: DecoratedBox(
                      decoration: const BoxDecoration(
                        color: Color(0x80000000),
                        shape: BoxShape.circle,
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(ReelvaDesign.space8),
                        child: resolving
                            ? const SizedBox(
                                width: 28,
                                height: 28,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2,
                                ),
                              )
                            : Icon(
                                available
                                    ? Icons.play_arrow_rounded
                                    : Icons.cloud_off_outlined,
                                color: Colors.white,
                                size: 28,
                              ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: ReelvaDesign.space8),
            Text(
              title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: available ? ReelvaDesign.ink : ReelvaDesign.muted,
              ),
            ),
            const Spacer(),
            Text(
              '${available ? '' : '不可用 · '}'
              '${versions.length > 1 ? '${versions.length} 个版本' : first.sourceName}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: available ? ReelvaDesign.muted : theme.colorScheme.error,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openEpisode(
    WorkDetails details,
    List<LibraryVersion> versions,
    String title,
  ) async {
    if (versions.length == 1) {
      await _playVersion(versions.single);
      return;
    }
    final selected = await showDialog<LibraryVersion>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('$title · 选择版本'),
        contentPadding: EdgeInsets.zero,
        content: SizedBox(
          width: 560,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: _buildVersionRows(
                context,
                details,
                versions,
                onPlay: (version) => Navigator.of(context).pop(version),
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
        ],
      ),
    );
    if (!mounted || selected == null) return;
    await _playVersion(selected);
  }

  List<Widget> _buildVersionRows(
    BuildContext context,
    WorkDetails details,
    List<LibraryVersion> versions, {
    ValueChanged<LibraryVersion>? onPlay,
  }) {
    return [
      for (final (index, version) in versions.indexed) ...[
        if (index > 0) const Divider(height: 1, indent: 16, endIndent: 16),
        _buildVersionRow(context, details.work, version, onPlay: onPlay),
      ],
    ];
  }

  Widget _buildVersionRow(
    BuildContext context,
    LibraryWork work,
    LibraryVersion version, {
    ValueChanged<LibraryVersion>? onPlay,
  }) {
    final theme = Theme.of(context);
    final isResolving = _resolvingFileId == version.fileId;
    var title = version.fileName;
    if (version.episodeNumber != null) {
      final epPrefix =
          '第 ${version.episodeNumber} 集${version.seasonNumber != null ? ' (S${version.seasonNumber.toString().padLeft(2, '0')}E${version.episodeNumber.toString().padLeft(2, '0')})' : ''}';
      title = version.episodeTitle != null
          ? '$epPrefix · ${version.episodeTitle}'
          : '$epPrefix · ${version.fileName}';
    }

    final playButton = GlassButton(
      key: Key('work_play_version_button_${version.fileId}'),
      primary: true,
      onPressed: !version.available || _resolvingFileId != null
          ? null
          : () {
              if (onPlay != null) {
                onPlay(version);
              } else {
                _playVersion(version);
              }
            },
      child: isResolving
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Text('播放'),
    );

    return Padding(
      key: Key('work_version_item_${version.fileId}'),
      padding: const EdgeInsets.all(ReelvaDesign.space16),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final stackAction =
              constraints.maxWidth < 480 ||
              MediaQuery.textScalerOf(context).scale(14) > 20;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (work.type == 'series')
                    PosterImage(
                      posterPath: work.backdropPath ?? work.posterPath,
                      width: 72,
                      height: 56,
                      borderRadius: BorderRadius.circular(
                        ReelvaDesign.radiusSmall,
                      ),
                    )
                  else
                    Icon(
                      version.available
                          ? Icons.play_circle_outline_rounded
                          : Icons.cloud_off_outlined,
                      size: 32,
                      color: version.available
                          ? theme.colorScheme.primary
                          : ReelvaDesign.muted,
                    ),
                  const SizedBox(width: ReelvaDesign.space12),
                  Expanded(
                    child: Text(
                      title,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: version.available
                            ? ReelvaDesign.ink
                            : ReelvaDesign.muted,
                      ),
                    ),
                  ),
                  if (!stackAction) ...[
                    const SizedBox(width: ReelvaDesign.space12),
                    playButton,
                  ],
                ],
              ),
              const SizedBox(height: ReelvaDesign.space8),
              if (version.episodeNumber != null && version.episodeTitle != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: ReelvaDesign.space8),
                  child: Text(
                    version.fileName,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: ReelvaDesign.muted,
                    ),
                  ),
                ),
              Text(
                '来源: ${version.sourceName}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: ReelvaDesign.muted,
                ),
              ),
              if (version.editionLabel?.trim().isNotEmpty ?? false) ...[
                const SizedBox(height: ReelvaDesign.space8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: _buildChip(context, label: version.editionLabel!),
                ),
              ],
              if (!version.available) ...[
                const SizedBox(height: ReelvaDesign.space8),
                Text(
                  version.sourceError ?? '不可用',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
              ],
              if (stackAction) ...[
                const SizedBox(height: ReelvaDesign.space12),
                Align(alignment: Alignment.centerRight, child: playButton),
              ],
            ],
          );
        },
      ),
    );
  }
}

enum _WorkAction { manualMatch, localEdit }
