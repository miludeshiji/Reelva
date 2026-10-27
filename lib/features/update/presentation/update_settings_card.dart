import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/widgets/glass_widgets.dart';
import '../application/app_update_providers.dart';
import '../infrastructure/github_release_client.dart';

class UpdateSettingsCard extends ConsumerWidget {
  const UpdateSettingsCard({super.key});

  void _message(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _check(BuildContext context, WidgetRef ref) async {
    try {
      final release = await ref.read(updateCheckProvider.notifier).check();
      if (context.mounted && release == null) _message(context, '暂无新版本');
    } catch (_) {
      if (context.mounted) _message(context, '检查更新失败，请稍后重试');
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final checking = ref.watch(updateCheckProvider).isLoading;
    final preferences = ref.watch(updatePreferencesProvider);
    return GlassCard(
      padding: const EdgeInsets.all(12),
      borderRadius: BorderRadius.circular(22),
      color: Colors.white.withValues(alpha: 0.88),
      child: Material(
        type: MaterialType.transparency,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            GlassSwitchTile(
              key: const Key('automatic_update_switch'),
              contentPadding: const EdgeInsets.symmetric(horizontal: 4),
              title: const Text('自动检查更新'),
              subtitle: Text(
                preferences.hasError ? '读取设置失败，点击右侧开关重试' : '启动时检查，每天最多一次',
              ),
              value: preferences.asData?.value.automatic ?? false,
              onChanged: preferences.hasError
                  ? (_) => ref.invalidate(updatePreferencesProvider)
                  : preferences.hasValue
                  ? (value) async {
                      try {
                        await ref
                            .read(updatePreferencesProvider.notifier)
                            .setAutomatic(value);
                      } catch (_) {
                        if (context.mounted) _message(context, '保存更新设置失败，请重试');
                      }
                    }
                  : null,
            ),
            const SizedBox(height: ReelvaDesign.space8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    key: const Key('github_repository_button'),
                    onPressed: () async {
                      try {
                        await ref.read(openUpdateUrlProvider)(
                          GithubReleaseClient.repositoryUrl,
                        );
                      } catch (_) {
                        if (context.mounted) {
                          _message(context, '无法打开 GitHub，请稍后重试');
                        }
                      }
                    },
                    icon: const Icon(Icons.open_in_new_rounded),
                    label: const Text('GitHub'),
                  ),
                ),
                const SizedBox(width: ReelvaDesign.space12),
                Expanded(
                  child: OutlinedButton.icon(
                    key: const Key('check_update_button'),
                    onPressed: checking ? null : () => _check(context, ref),
                    icon: checking
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.system_update_alt_rounded),
                    label: Text(checking ? '正在检查更新…' : '检查更新'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
