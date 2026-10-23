import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/errors/safe_error_widget.dart';
import '../../shared/widgets/empty_state_view.dart';
import '../../shared/widgets/poster_image.dart';
import '../../shared/widgets/reelva_logo.dart';
import '../metadata/application/metadata_providers.dart';
import 'domain/library_work.dart';

/// 影视库页面（M3 海报墙）
///
/// 特性：
/// 1. 逻辑作品（LibraryWork）海报瀑布流，一张海报代表一个逻辑影视作品；
/// 2. 支持初始 100 条分页并在滑到底部时加载更多（+100）；
/// 3. 点击作品卡片导航至作品详情页 `/library/work/:id`；
/// 4. 标题栏仅展示精简进度指示，状态条在内容区紧凑换行展示（包含重试与前往设置）；
/// 5. 错误态提供主动刷新 Invalidating Provider 重试入口；
/// 6. 适配桌面大屏、平板以及 320px 窄屏/高字体缩放场景。
class LibraryPage extends ConsumerStatefulWidget {
  const LibraryPage({super.key});

  @override
  ConsumerState<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends ConsumerState<LibraryPage> {
  int _limit = 100;
  bool _hasInitialRefreshed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _hasInitialRefreshed) return;
      _hasInitialRefreshed = true;
      // 首次加载影视库页面时，安全触发一次未处理候选条目的元数据自动识别与刷新
      ref.read(metadataControllerProvider.notifier).refresh();
    });
  }

  void _triggerRefresh() {
    ref.read(metadataControllerProvider.notifier).refresh();
  }

  @override
  Widget build(BuildContext context) {
    final worksAsync = ref.watch(libraryWorksProvider(_limit));
    final metaTaskState = ref.watch(metadataControllerProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [ReelvaLogo(size: 28), SizedBox(width: 8), Text('影视库')],
        ),
        actions: [
          if (metaTaskState.running)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 14),
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else
            IconButton(
              key: const Key('library_refresh_metadata_button'),
              icon: const Icon(Icons.refresh),
              tooltip: '刷新并识别影视元数据',
              onPressed: _triggerRefresh,
            ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildMetadataStatusBar(context, metaTaskState),
          Expanded(
            child: worksAsync.when(
              loading: () => const Center(
                key: Key('library_loading_indicator'),
                child: CircularProgressIndicator(),
              ),
              error: (error, stack) => Center(
                key: const Key('library_error_widget'),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SafeErrorWidget(),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      key: const Key('library_retry_button'),
                      onPressed: () => ref.invalidate(libraryWorksProvider),
                      icon: const Icon(Icons.refresh, size: 16),
                      label: const Text('重试'),
                    ),
                  ],
                ),
              ),
              data: (works) {
                if (works.isEmpty) {
                  return EmptyStateView(
                    key: const Key('library_empty_view'),
                    icon: Icons.video_library_outlined,
                    title: '影视库为空',
                    message: '配置媒体源并完成扫描后，影视库将呈现影视作品与海报。',
                    actionLabel: '前往媒体源',
                    onAction: () => context.go('/sources'),
                  );
                }

                final hasMore = works.length >= _limit;

                return LayoutBuilder(
                  builder: (context, constraints) {
                    final width = constraints.maxWidth;
                    // 响应式列数：320px 宽度展示 2 列，桌面根据视口宽度最多展示 8 列
                    final crossAxisCount = (width / 160).clamp(2, 8).toInt();

                    return CustomScrollView(
                      key: const Key('library_works_scroll_view'),
                      slivers: [
                        SliverPadding(
                          padding: const EdgeInsets.all(12),
                          sliver: SliverGrid(
                            key: const Key('library_works_grid'),
                            gridDelegate:
                                SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: crossAxisCount,
                                  crossAxisSpacing: 12,
                                  mainAxisSpacing: 12,
                                  childAspectRatio: 0.58,
                                ),
                            delegate: SliverChildBuilderDelegate((
                              context,
                              index,
                            ) {
                              final work = works[index];
                              return _WorkPosterCard(
                                key: Key('library_work_card_${work.id}'),
                                work: work,
                                onTap: () =>
                                    context.go('/library/work/${work.id}'),
                              );
                            }, childCount: works.length),
                          ),
                        ),
                        if (hasMore)
                          SliverToBoxAdapter(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 20),
                              child: Center(
                                child: OutlinedButton(
                                  key: const Key('library_load_more_button'),
                                  onPressed: () {
                                    setState(() {
                                      _limit += 100;
                                    });
                                  },
                                  child: const Text('加载更多作品'),
                                ),
                              ),
                            ),
                          ),
                      ],
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  /// 紧凑且支持换行的元数据后台任务状态横条
  Widget _buildMetadataStatusBar(
    BuildContext context,
    MetadataTaskState state,
  ) {
    final colorScheme = Theme.of(context).colorScheme;

    if (state.running) {
      return Container(
        key: const Key('library_metadata_running_banner'),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
        child: Row(
          children: [
            const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '正在匹配影视元数据与海报...',
                style: TextStyle(
                  fontSize: 12,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      );
    }

    if (state.error != null) {
      return Container(
        key: const Key('library_metadata_error_banner'),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        color: colorScheme.errorContainer.withValues(alpha: 0.8),
        child: Wrap(
          spacing: 12,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.error_outline, size: 16, color: colorScheme.error),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    state.error!,
                    style: TextStyle(
                      fontSize: 12,
                      color: colorScheme.onErrorContainer,
                    ),
                  ),
                ),
              ],
            ),
            Wrap(
              spacing: 4,
              children: [
                TextButton.icon(
                  key: const Key('library_metadata_retry_button'),
                  onPressed: _triggerRefresh,
                  icon: const Icon(Icons.refresh, size: 14),
                  label: const Text('重试', style: TextStyle(fontSize: 12)),
                ),
                TextButton.icon(
                  key: const Key('library_metadata_settings_button'),
                  onPressed: () => context.go('/settings'),
                  icon: const Icon(Icons.settings_outlined, size: 14),
                  label: const Text('设置凭据', style: TextStyle(fontSize: 12)),
                ),
              ],
            ),
          ],
        ),
      );
    }

    final result = state.result;
    if (result != null && result.errors.isNotEmpty) {
      // 提示未配置或网络警告，提供可操作入口
      final hasNoKey = result.errors.any((e) => e.contains('未配置 TMDB API 密钥'));
      return Container(
        key: const Key('library_metadata_result_banner'),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        color: colorScheme.secondaryContainer.withValues(alpha: 0.5),
        child: Wrap(
          spacing: 8,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.info_outline, size: 16, color: colorScheme.primary),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    hasNoKey
                        ? '未配置 TMDB 凭据，仅完成本地识别'
                        : '元数据刷新完成（${result.matched} 匹配，${result.needsReview} 需核对）',
                    style: TextStyle(
                      fontSize: 12,
                      color: colorScheme.onSecondaryContainer,
                    ),
                  ),
                ),
              ],
            ),
            if (hasNoKey)
              TextButton(
                key: const Key('library_metadata_configure_button'),
                onPressed: () => context.go('/settings'),
                child: const Text('配置 TMDB', style: TextStyle(fontSize: 12)),
              ),
          ],
        ),
      );
    }

    return const SizedBox.shrink();
  }
}

/// 海报墙中的单个作品卡片
class _WorkPosterCard extends StatelessWidget {
  const _WorkPosterCard({super.key, required this.work, required this.onTap});

  final LibraryWork work;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final displayTitle = work.title.trim().isNotEmpty ? work.title : '未识别作品';

    return Card(
      elevation: 1,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(
          color: colorScheme.outlineVariant.withValues(alpha: 0.4),
        ),
      ),
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 1. 海报区域（带锁定/版本角标）
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  PosterImage(
                    posterPath: work.posterPath,
                    title: displayTitle,
                    fit: BoxFit.cover,
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(8),
                    ),
                  ),
                  // 左上角：元数据锁定或待匹配状态标记
                  if (work.metadataLocked)
                    Positioned(
                      top: 6,
                      left: 6,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: colorScheme.primaryContainer.withValues(
                            alpha: 0.9,
                          ),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.lock,
                          size: 12,
                          color: colorScheme.onPrimaryContainer,
                        ),
                      ),
                    )
                  else if (work.metadataSource == 'local')
                    Positioned(
                      top: 6,
                      left: 6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: colorScheme.surfaceContainerHighest.withValues(
                            alpha: 0.85,
                          ),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          '待匹配',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w500,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ),
                  // 右上角：多版本数量角标
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
                  // 下方不可用指示
                  if (!work.available)
                    Positioned.fill(
                      child: Container(
                        color: Colors.black.withValues(alpha: 0.5),
                        child: const Center(
                          child: Chip(
                            label: Text('文件离线', style: TextStyle(fontSize: 11)),
                            visualDensity: VisualDensity.compact,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            // 2. 标题与信息栏
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    displayTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      if (work.year != null) ...[
                        Text(
                          '${work.year}',
                          style: TextStyle(
                            fontSize: 11,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(width: 6),
                      ],
                      if (work.type != null)
                        Text(
                          work.type == 'series' ? '剧集' : '电影',
                          style: TextStyle(
                            fontSize: 11,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                    ],
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
