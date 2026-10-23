import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/errors/safe_error_widget.dart';
import '../../core/logging/app_logger.dart';
import '../../shared/widgets/empty_state_view.dart';
import '../../shared/widgets/reelva_logo.dart';
import '../sources/application/source_providers.dart';
import '../sources/domain/source_models.dart';

/// 影视库页面
///
/// 展示已扫描索引的视频条目列表；
/// 支持初始 100 条分页并在滑到底部时加载更多；
/// 点击视频条目时通过 SourceController 解析为 PlaybackResource 并跳转播放器；
/// 具备防重复点击、解析中提示与失败恢复能力。
class LibraryPage extends ConsumerStatefulWidget {
  const LibraryPage({super.key});

  @override
  ConsumerState<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends ConsumerState<LibraryPage> {
  int _limit = 100;
  int? _resolvingFileId;

  Future<void> _playVideo(LibraryVideo video) async {
    if (_resolvingFileId != null) return;

    setState(() {
      _resolvingFileId = video.fileId;
    });

    try {
      final resource = await ref
          .read(sourceControllerProvider.notifier)
          .resolvePlayback(video.fileId);

      if (!mounted) return;
      context.go('/player', extra: resource);
    } catch (e, st) {
      if (!mounted) return;
      AppLogger.instance.error('解析视频播放地址失败', error: e, stackTrace: st);
      final message = e is MediaSourceException ? e.message : '无法解析视频播放地址，请重试';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          action: SnackBarAction(
            label: '重试',
            onPressed: () => _playVideo(video),
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

  @override
  Widget build(BuildContext context) {
    final videosAsync = ref.watch(libraryVideosProvider(_limit));

    return Scaffold(
      appBar: AppBar(
        title: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [ReelvaLogo(size: 28), SizedBox(width: 8), Text('影视库')],
        ),
      ),
      body: videosAsync.when(
        loading: () => const Center(
          key: Key('library_loading_indicator'),
          child: CircularProgressIndicator(),
        ),
        error: (error, stack) => const Center(
          key: Key('library_error_widget'),
          child: SafeErrorWidget(),
        ),
        data: (videos) {
          if (videos.isEmpty) {
            return EmptyStateView(
              key: const Key('library_empty_view'),
              icon: Icons.video_library_outlined,
              title: '影视库为空',
              message: '配置媒体源并完成扫描后，影视库将呈现视频内容。',
              actionLabel: '前往媒体源',
              onAction: () => context.go('/sources'),
            );
          }

          final hasMore = videos.length >= _limit;

          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 800),
              child: ListView.separated(
                key: const Key('library_videos_list'),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                itemCount: videos.length + (hasMore ? 1 : 0),
                separatorBuilder: (context, index) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  if (index == videos.length) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16.0),
                      child: Center(
                        child: OutlinedButton.icon(
                          key: const Key('library_load_more_button'),
                          icon: const Icon(Icons.expand_more),
                          label: const Text('加载更多 (+100)'),
                          onPressed: () {
                            setState(() {
                              _limit += 100;
                            });
                          },
                        ),
                      ),
                    );
                  }

                  final video = videos[index];
                  final isResolving = _resolvingFileId == video.fileId;
                  final theme = Theme.of(context);
                  final colorScheme = theme.colorScheme;
                  final title = video.title.isNotEmpty
                      ? video.title
                      : video.fileName;

                  return ListTile(
                    key: Key('library_video_item_${video.fileId}'),
                    leading: Icon(
                      Icons.movie_outlined,
                      size: 32,
                      color: video.available
                          ? colorScheme.primary
                          : colorScheme.outline,
                    ),
                    title: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w500,
                        color: video.available
                            ? colorScheme.onSurface
                            : colorScheme.onSurface.withValues(alpha: 0.6),
                      ),
                    ),
                    subtitle: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: colorScheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            video.sourceName,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        if (!video.available)
                          Expanded(
                            child: Text(
                              video.sourceError != null
                                  ? '文件缺失 (${video.sourceError})'
                                  : '文件缺失',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: colorScheme.error,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          )
                        else
                          Expanded(
                            child: Text(
                              video.fileName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                      ],
                    ),
                    trailing: isResolving
                        ? SizedBox(
                            key: Key(
                              'library_resolving_indicator_${video.fileId}',
                            ),
                            width: 24,
                            height: 24,
                            child: const CircularProgressIndicator(
                              strokeWidth: 2.5,
                            ),
                          )
                        : Icon(
                            Icons.play_circle_outline,
                            color: video.available
                                ? colorScheme.primary
                                : colorScheme.outline,
                          ),
                    onTap: isResolving || _resolvingFileId != null
                        ? null
                        : () => _playVideo(video),
                  );
                },
              ),
            ),
          );
        },
      ),
    );
  }
}
