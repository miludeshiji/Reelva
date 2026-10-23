import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/sync_providers.dart';
import '../domain/sync_models.dart';
import '../infrastructure/sync_configuration_store.dart';

/// 跨设备同步设置卡片
///
/// 遵循 M6 规范：
/// - 默认禁用，手动点击「立即同步」执行增量同步；
/// - 密码绝不预填回显；仅当端点与用户名均保持不变时，留空密码才沿用原有密码；
/// - 错误信息白名单脱敏，严禁暴露认证头或远程敏感数据；
/// - 响应式排版：兼容 320px 小屏及 1.5x 文字缩放无溢出；
/// - 同步或配置写入进行中禁用表单与所有操作按钮；
/// - 进入页面时绝不触发自动网络请求或自动刷新。
class SyncSettingsCard extends ConsumerStatefulWidget {
  const SyncSettingsCard({super.key});

  @override
  ConsumerState<SyncSettingsCard> createState() => _SyncSettingsCardState();
}

class _SyncSettingsCardState extends ConsumerState<SyncSettingsCard> {
  final TextEditingController _endpointController = TextEditingController();
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  bool _obscurePassword = true;
  String? _localValidationError;

  @override
  void initState() {
    super.initState();
    final config = ref.read(syncConfigurationProvider).value;
    if (config != null) {
      _endpointController.text = config.endpoint.toString();
      _usernameController.text = config.username;
      // 密码从不预填充，确保凭据安全
      _passwordController.clear();
    }
  }

  @override
  void dispose() {
    _endpointController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleSave(SyncConfiguration? existingConfig) async {
    setState(() {
      _localValidationError = null;
    });

    final endpointRaw = _endpointController.text.trim();
    if (endpointRaw.isEmpty) {
      setState(() {
        _localValidationError = '请输入 WebDAV 端点地址';
      });
      return;
    }

    Uri endpoint;
    try {
      endpoint = SyncConfiguration.parseEndpoint(endpointRaw);
    } on SyncException catch (e) {
      setState(() {
        _localValidationError = e.message;
      });
      return;
    } catch (_) {
      setState(() {
        _localValidationError = '无法解析端点地址，请输入正确的 URL';
      });
      return;
    }

    final username = _usernameController.text.trim();
    final passwordInput = _passwordController.text;

    // 严格安全限制：仅当端点与用户名均未改变时，留空密码才表示沿用原有密码；
    // 若修改了端点或用户名，留空密码视为使用空密码，绝不向新主机或新账户泄露旧服务密码！
    final isSameIdentity =
        existingConfig != null &&
        existingConfig.endpoint == endpoint &&
        existingConfig.username == username;

    final finalPassword = passwordInput.isNotEmpty
        ? passwordInput
        : (isSameIdentity ? existingConfig.password : '');

    try {
      final newConfig = SyncConfiguration(
        endpoint: endpoint,
        username: username,
        password: finalPassword,
      );
      await ref
          .read(syncControllerProvider.notifier)
          .saveConfiguration(newConfig);

      // 保存成功后清空密码输入框，避免遗留在明文内存中
      _passwordController.clear();

      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('同步配置已保存')));
      }
    } catch (_) {
      // 错误由 syncController 写入 syncState.error
    }
  }

  Future<void> _handleSyncNow() async {
    setState(() {
      _localValidationError = null;
    });

    try {
      await ref.read(syncControllerProvider.notifier).synchronize();
    } catch (_) {
      // 错误由 syncController 写入 syncState.error
    }
  }

  Future<void> _handleDisable() async {
    setState(() {
      _localValidationError = null;
    });

    try {
      await ref.read(syncControllerProvider.notifier).disable();
      _endpointController.clear();
      _usernameController.clear();
      _passwordController.clear();

      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('已禁用并清除同步配置')));
      }
    } catch (_) {
      // 错误由 syncController 写入 syncState.error
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final configAsync = ref.watch(syncConfigurationProvider);
    final syncState = ref.watch(syncControllerProvider);
    final isBusy = syncState.isBusy;

    // 仅在 AsyncData 完成更新时填充非机密字段，防止瞬态加载时清空用户正在输入的表单
    ref.listen<AsyncValue<SyncConfiguration?>>(syncConfigurationProvider, (
      previous,
      next,
    ) {
      if (next is! AsyncData<SyncConfiguration?>) return;
      final prevConfig = previous?.value;
      final nextConfig = next.value;
      if (prevConfig != nextConfig) {
        if (nextConfig != null) {
          _endpointController.text = nextConfig.endpoint.toString();
          _usernameController.text = nextConfig.username;
          _passwordController.clear();
        } else {
          _endpointController.clear();
          _usernameController.clear();
          _passwordController.clear();
        }
      }
    });

    final currentConfig = configAsync.value;
    final isConfigured = currentConfig != null;
    final displayedError = _localValidationError ?? syncState.error;

    // 判断当前输入框内容是否与已有配置的标识相同
    final isSameIdentity =
        currentConfig != null &&
        _endpointController.text.trim() == currentConfig.endpoint.toString() &&
        _usernameController.text.trim() == currentConfig.username;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 头部：图标、产品名称「跨设备同步」、配置状态 Chip
            Row(
              children: [
                Icon(Icons.cloud_sync_outlined, color: colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '跨设备同步',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                configAsync.when(
                  data: (config) {
                    final configured = config != null;
                    return Container(
                      key: const Key('sync_status_chip'),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: configured
                            ? colorScheme.primaryContainer
                            : colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            configured
                                ? Icons.cloud_done_outlined
                                : Icons.cloud_off_outlined,
                            size: 14,
                            color: configured
                                ? colorScheme.onPrimaryContainer
                                : colorScheme.onSurfaceVariant,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            configured ? '已配置' : '未配置',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: configured
                                  ? colorScheme.onPrimaryContainer
                                  : colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                  loading: () => const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  error: (_, _) => Container(
                    key: const Key('sync_status_chip'),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: colorScheme.errorContainer,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      '读取异常',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: colorScheme.onErrorContainer,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '多台设备配置相同 WebDAV 目录，可同步播放进度与影视条目手动修正。同步仅传输进度与元数据变更，绝不上传媒体视频文件。',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),

            // 配置加载异常时的可恢复操作提示
            if (configAsync.hasError) ...[
              const SizedBox(height: 12),
              Container(
                key: const Key('sync_config_error_banner'),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.warning_amber_rounded,
                          size: 18,
                          color: colorScheme.onErrorContainer,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '读取同步安全配置失败，配置可能损坏',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: colorScheme.onErrorContainer,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        OutlinedButton(
                          key: const Key('sync_retry_config_read'),
                          onPressed: isBusy
                              ? null
                              : () => ref.refresh(syncConfigurationProvider),
                          child: const Text('重试读取'),
                        ),
                        OutlinedButton(
                          key: const Key('sync_clear_damaged_config'),
                          onPressed: isBusy ? null : _handleDisable,
                          child: const Text('清除损坏配置'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 16),

            // 表单输入项：端点地址
            TextField(
              key: const Key('sync_endpoint'),
              controller: _endpointController,
              enabled: !isBusy,
              keyboardType: TextInputType.url,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                labelText: 'WebDAV 端点地址',
                hintText: 'https://dav.example.com/sync/',
                prefixIcon: Icon(Icons.link_outlined),
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 12),

            // 表单输入项：用户名
            TextField(
              key: const Key('sync_username'),
              controller: _usernameController,
              enabled: !isBusy,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                labelText: '用户名（可选）',
                hintText: '留空表示匿名或由端点指定',
                prefixIcon: Icon(Icons.person_outline),
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 12),

            // 表单输入项：密码（绝不预填）
            TextField(
              key: const Key('sync_password'),
              controller: _passwordController,
              enabled: !isBusy,
              obscureText: _obscurePassword,
              decoration: InputDecoration(
                labelText: '密码（可选）',
                hintText: isSameIdentity ? '留空保留现有密码' : 'WebDAV 密码（可选）',
                helperText: '仅在端点与用户名未改变时留空保留旧密码；修改端点或用户名时留空使用空密码。',
                helperMaxLines: 2,
                prefixIcon: const Icon(Icons.lock_outline),
                border: const OutlineInputBorder(),
                isDense: true,
                suffixIcon: IconButton(
                  key: const Key('sync_password_visibility_button'),
                  icon: Icon(
                    _obscurePassword ? Icons.visibility_off : Icons.visibility,
                  ),
                  onPressed: () {
                    setState(() {
                      _obscurePassword = !_obscurePassword;
                    });
                  },
                ),
              ),
            ),

            // 错误信息展示
            if (displayedError != null) ...[
              const SizedBox(height: 12),
              Container(
                key: const Key('sync_error_container'),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.error_outline,
                      size: 18,
                      color: colorScheme.onErrorContainer,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        displayedError,
                        key: const Key('sync_error_text'),
                        style: TextStyle(
                          fontSize: 13,
                          color: colorScheme.onErrorContainer,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            // 结果汇报展示
            if (syncState.report != null) ...[
              const SizedBox(height: 12),
              Container(
                key: const Key('sync_report_container'),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.check_circle_outline,
                      size: 18,
                      color: colorScheme.onPrimaryContainer,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '同步完成：上传 ${syncState.report!.uploaded} 条，'
                        '下载 ${syncState.report!.downloaded} 条，'
                        '应用 ${syncState.report!.applied} 条'
                        '${syncState.report!.pending > 0 ? "，待匹配 ${syncState.report!.pending} 条" : ""}'
                        '${syncState.report!.localOnly > 0 ? "，仅本地 ${syncState.report!.localOnly} 条" : ""}',
                        key: const Key('sync_report_text'),
                        style: TextStyle(
                          fontSize: 13,
                          color: colorScheme.onPrimaryContainer,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 16),

            // 底部操作按钮区（Wrap 确保在 320px/390px 移动屏上不溢出）
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (isConfigured)
                  FilledButton.icon(
                    key: const Key('sync_now'),
                    onPressed: isBusy ? null : _handleSyncNow,
                    icon: syncState.running
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.sync, size: 18),
                    label: Text(syncState.running ? '正在同步...' : '立即同步'),
                  ),
                OutlinedButton.icon(
                  key: const Key('sync_save'),
                  onPressed: isBusy || configAsync.isLoading
                      ? null
                      : () => _handleSave(currentConfig),
                  icon: const Icon(Icons.save_outlined, size: 18),
                  label: const Text('保存配置'),
                ),
                if (isConfigured)
                  OutlinedButton.icon(
                    key: const Key('sync_disable'),
                    onPressed: isBusy ? null : _handleDisable,
                    icon: Icon(
                      Icons.delete_outline,
                      size: 18,
                      color: colorScheme.error,
                    ),
                    label: Text(
                      '禁用同步',
                      style: TextStyle(color: colorScheme.error),
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
