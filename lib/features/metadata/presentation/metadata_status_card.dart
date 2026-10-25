import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../shared/widgets/glass_widgets.dart';
import '../application/metadata_providers.dart';

class MetadataStatusCard extends StatelessWidget {
  const MetadataStatusCard({
    super.key,
    required this.state,
    required this.onRetry,
    this.margin,
  });

  final MetadataTaskState state;
  final VoidCallback onRetry;
  final EdgeInsetsGeometry? margin;

  @override
  Widget build(BuildContext context) {
    final result = state.result;
    if (!state.running && state.error == null && result == null) {
      return const SizedBox.shrink();
    }

    final scheme = Theme.of(context).colorScheme;
    final hasError = !state.running && state.error != null;
    final localOnly = result?.localOnly ?? false;
    final title = state.running
        ? state.phase == MetadataPhase.recognizing
              ? '正在整理影片与剧集'
              : '正在补充海报与简介'
        : hasError
        ? '媒体库整理未完成'
        : localOnly
        ? '已完成本地识别'
        : '媒体库整理完成';
    final total = state.total;

    return GlassCard(
      key: Key(
        state.running
            ? 'metadata_running_banner'
            : hasError
            ? 'metadata_error_banner'
            : 'metadata_result_banner',
      ),
      margin: margin,
      padding: const EdgeInsets.all(ReelvaDesign.space12),
      color: hasError ? scheme.errorContainer.withValues(alpha: 0.65) : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                state.running
                    ? Icons.auto_awesome_outlined
                    : hasError
                    ? Icons.error_outline
                    : Icons.check_circle_outline,
                size: 20,
                color: hasError ? scheme.error : ReelvaDesign.accent,
              ),
              const SizedBox(width: ReelvaDesign.space8),
              Expanded(child: Text(title)),
            ],
          ),
          const SizedBox(height: ReelvaDesign.space8),
          if (state.running) ...[
            LinearProgressIndicator(
              value: total != null && total > 0
                  ? state.processed / total
                  : null,
            ),
            const SizedBox(height: ReelvaDesign.space8),
            if (total != null) Text('已处理 ${state.processed} / $total 个条目'),
            const Text('可切换页面，处理完成后会自动更新'),
          ] else if (hasError) ...[
            Text(state.error!),
            const Text('已建立的媒体库仍可浏览，可稍后重试'),
            TextButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('重试'),
            ),
          ] else if (localOnly)
            const Text('配置 TMDB 后可补充海报与简介')
          else ...[
            Text(
              '本次整理：已匹配 ${result!.matched} 个条目 · ${result.needsReview} 个未自动匹配',
            ),
            if (result.needsReview > 0)
              const Text(
                '标题、年份或季集信息不足，或未找到可靠的 TMDB 结果。可查看待匹配条目，或在媒体源按文件夹批量匹配。',
              ),
          ],
          if (!state.running && (result?.needsReview ?? 0) > 0)
            TextButton.icon(
              key: const Key('metadata_review_button'),
              onPressed: () => context.push('/library/unmatched'),
              icon: const Icon(Icons.manage_search_outlined, size: 18),
              label: const Text('查看待匹配条目'),
            ),
          if (!state.running && (localOnly || hasError))
            TextButton.icon(
              onPressed: () => context.push('/settings/tmdb'),
              icon: const Icon(Icons.settings_outlined, size: 18),
              label: const Text('配置 TMDB'),
            ),
        ],
      ),
    );
  }
}
