import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/errors/safe_error_widget.dart';
import '../../../core/logging/app_logger.dart';
import '../../../shared/widgets/empty_state_view.dart';
import '../../../shared/widgets/glass_widgets.dart';
import '../../../shared/widgets/poster_image.dart';
import '../../metadata/application/metadata_providers.dart';
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
      initialPosterPath: work.posterPath,
    );
  }

  @override
  Widget build(BuildContext context) {
    final detailsAsync = ref.watch(workDetailsProvider(widget.workId));

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: GlassBackground(
        child: SafeArea(
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
                  child: SingleChildScrollView(
                    key: const Key('work_details_scroll_view'),
                    padding: EdgeInsets.only(
                      bottom: MediaQuery.paddingOf(context).bottom,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _buildCover(context, details.work),
                        Padding(
                          padding: const EdgeInsets.all(ReelvaDesign.space24),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _buildHeader(context, details),
                              if (details.work.overview?.trim().isNotEmpty ??
                                  false) ...[
                                const SizedBox(height: ReelvaDesign.space24),
                                const GlassSectionTitle(title: '剧情简介'),
                                const SizedBox(height: ReelvaDesign.space8),
                                Text(
                                  details.work.overview!,
                                  style: Theme.of(context).textTheme.bodyMedium
                                      ?.copyWith(
                                        height: 1.65,
                                        color: ReelvaDesign.muted,
                                      ),
                                ),
                              ],
                              const SizedBox(height: ReelvaDesign.space24),
                              _buildVersionsSection(context, details),
                              const SizedBox(height: ReelvaDesign.space8),
                            ],
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
        SliverToBoxAdapter(
          child: GlassPageHeader(
            title: '作品详情',
            leading: GlassIconButton(
              icon: Icons.arrow_back_rounded,
              size: ReelvaDesign.pageHeaderButtonSize,
              tooltip: '返回影视库',
              onPressed: () => context.go('/library'),
            ),
          ),
        ),
        SliverFillRemaining(hasScrollBody: false, child: child),
      ],
    );
  }

  Widget _buildCover(BuildContext context, LibraryWork work) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final height = (constraints.maxWidth * 0.78).clamp(220.0, 360.0);
        final backdrop = work.backdropPath?.trim();
        return SizedBox(
          height: height,
          child: Stack(
            fit: StackFit.expand,
            children: [
              PosterImage(
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
                      Color(0x240E1728),
                      Color(0x000E1728),
                      ReelvaDesign.background,
                    ],
                    stops: [0, 0.72, 1],
                  ),
                ),
              ),
              Align(
                alignment: Alignment.topCenter,
                child: Padding(
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
                          PopupMenuItem(
                            value: _WorkAction.manualMatch,
                            child: Text('手动匹配'),
                          ),
                          PopupMenuItem(
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
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildHeader(BuildContext context, WorkDetails details) {
    final theme = Theme.of(context);
    final work = details.work;
    final isSeries = work.type == 'series';
    final playable = details.versions.where((version) => version.available);
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
              label: work.metadataSource == 'tmdb' ? 'TMDB 匹配' : '本地识别',
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
              label: '${details.versions.length} 个版本文件',
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
    final selectedSeason = seasonMap.containsKey(_selectedSeason)
        ? _selectedSeason
        : null;
    final visibleSeasons = selectedSeason == null ? seasons : [selectedSeason];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GlassSectionTitle(
          title: '分季与剧集列表',
          trailing: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 260),
            child: GlassCard(
              padding: const EdgeInsets.symmetric(
                horizontal: ReelvaDesign.space12,
              ),
              borderRadius: BorderRadius.circular(24),
              child: DropdownButton<int>(
                key: const Key('work_season_selector'),
                value: selectedSeason,
                hint: const Text('全部季'),
                isExpanded: true,
                underline: const SizedBox.shrink(),
                borderRadius: BorderRadius.circular(ReelvaDesign.radius),
                onChanged: (season) => setState(() {
                  _selectedSeason = season;
                }),
                items: [
                  const DropdownMenuItem<int>(child: Text('全部季')),
                  for (final season in seasons)
                    DropdownMenuItem(
                      value: season,
                      child: Text(
                        season > 0 ? '第 $season 季' : '特别篇 / 未归类',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: ReelvaDesign.space12),
        for (final season in visibleSeasons)
          GlassCard(
            margin: const EdgeInsets.only(bottom: ReelvaDesign.space12),
            padding: EdgeInsets.zero,
            child: ExpansionTile(
              key: PageStorageKey('work_season_${details.work.id}_$season'),
              initiallyExpanded: true,
              maintainState: true,
              tilePadding: const EdgeInsets.symmetric(
                horizontal: ReelvaDesign.space16,
                vertical: ReelvaDesign.space8,
              ),
              shape: const Border(),
              collapsedShape: const Border(),
              title: Text(
                season > 0 ? '第 $season 季' : '特别篇 / 未归类',
                style: Theme.of(context).textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              subtitle: Text('${seasonMap[season]!.length} 个版本文件'),
              children: [
                const Divider(height: 1),
                ..._buildVersionRows(context, details, seasonMap[season]!),
              ],
            ),
          ),
      ],
    );
  }

  List<Widget> _buildVersionRows(
    BuildContext context,
    WorkDetails details,
    List<LibraryVersion> versions,
  ) {
    return [
      for (final (index, version) in versions.indexed) ...[
        if (index > 0) const Divider(height: 1, indent: 16, endIndent: 16),
        _buildVersionRow(context, details.work, version),
      ],
    ];
  }

  Widget _buildVersionRow(
    BuildContext context,
    LibraryWork work,
    LibraryVersion version,
  ) {
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
          : () => _playVersion(version),
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
