import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/widgets/glass_widgets.dart';
import '../application/nfo_providers.dart';

class NfoStatusCard extends ConsumerWidget {
  const NfoStatusCard({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(nfoControllerProvider);
    final errors = state.result?.errors ?? [];
    if (!state.running && errors.isEmpty) return const SizedBox.shrink();
    return GlassCard(
      key: const Key('nfo_status_card'),
      padding: const EdgeInsets.all(ReelvaDesign.space12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(state.running ? '正在保存目录元数据' : '部分目录元数据未完成保存'),
          if (state.running) const LinearProgressIndicator(),
          for (final error in errors.take(3)) Text(error),
          if (!state.running)
            TextButton.icon(
              onPressed: () =>
                  ref.read(nfoControllerProvider.notifier).export(),
              icon: const Icon(Icons.refresh),
              label: const Text('重试导出 NFO 与图片'),
            ),
        ],
      ),
    );
  }
}
