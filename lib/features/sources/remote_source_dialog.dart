import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'application/source_providers.dart';
import 'domain/source_models.dart';
import 'infrastructure/remote_credentials_store.dart';

/// 远程媒体源凭据编辑弹窗
///
/// 遵循 M5 安全规范：
/// - 保持稳定的媒体源根目录（只读显示，禁止修改）；
/// - 密码 默认清空，绝不预填已存储机密；
/// - 保存时先行优雅取消正在运行的扫描，更新完成后安全持久化。
class EditCredentialsDialog extends ConsumerStatefulWidget {
  const EditCredentialsDialog({super.key, required this.source});

  final MediaSourceConfig source;

  static Future<bool?> show(
    BuildContext context, {
    required MediaSourceConfig source,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (_) => EditCredentialsDialog(source: source),
    );
  }

  @override
  ConsumerState<EditCredentialsDialog> createState() =>
      _EditCredentialsDialogState();
}

class _EditCredentialsDialogState extends ConsumerState<EditCredentialsDialog> {
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _domainController = TextEditingController();

  bool _isSubmitting = false;
  String? _errorMessage;

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    _domainController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    final credentials = RemoteCredentials(
      username: _usernameController.text.trim(),
      password: _passwordController.text,
      domain: _domainController.text.trim(),
    );

    try {
      await ref
          .read(sourceControllerProvider.notifier)
          .updateCredentials(widget.source.id, credentials);
      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
        _errorMessage = e is MediaSourceException ? e.message : '更新凭据失败，请重试';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final kind = widget.source.kind;
    return AlertDialog(
      title: Text('修改凭据 - ${widget.source.name}'),
      content: SingleChildScrollView(
        child: SizedBox(
          width: 440,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              InputDecorator(
                decoration: const InputDecoration(labelText: '根目录地址（保持稳定不可修改）'),
                child: Text(
                  widget.source.rootLocator,
                  style: Theme.of(context).textTheme.bodyMedium
                      ?.copyWith(color: Theme.of(context).colorScheme.outline),
                ),
              ),
              const SizedBox(height: 16),
              if (kind == 'webdav') ...[
                TextField(
                  controller: _usernameController,
                  key: const Key('edit_credentials_username_field'),
                  decoration: const InputDecoration(
                    labelText: '用户名',
                    hintText: '留空表示匿名或未更改',
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _passwordController,
                  key: const Key('edit_credentials_password_field'),
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: '新密码',
                    hintText: '出于安全考虑不预填，留空表示不设置',
                  ),
                ),
              ] else if (kind == 'smb') ...[
                TextField(
                  controller: _usernameController,
                  key: const Key('edit_credentials_username_field'),
                  decoration: const InputDecoration(
                    labelText: '用户名',
                    hintText: '留空表示匿名',
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _passwordController,
                  key: const Key('edit_credentials_password_field'),
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: '新密码',
                    hintText: '出于安全考虑不预填',
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _domainController,
                  key: const Key('edit_credentials_domain_field'),
                  decoration: const InputDecoration(
                    labelText: '工作组 / 域名（可选）',
                    hintText: 'WORKGROUP',
                  ),
                ),
              ],
              if (_errorMessage != null) ...[
                const SizedBox(height: 16),
                Text(
                  _errorMessage!,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                    fontSize: 13,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSubmitting
              ? null
              : () => Navigator.of(context).pop(false),
          child: const Text('取消'),
        ),
        FilledButton(
          key: const Key('edit_credentials_confirm_button'),
          onPressed: _isSubmitting ? null : _submit,
          child: _isSubmitting
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('保存'),
        ),
      ],
    );
  }
}
