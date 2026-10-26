import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:reelva/shared/widgets/glass_widgets.dart';

import 'application/source_providers.dart';
import 'domain/source_models.dart';
import 'infrastructure/remote_credentials_store.dart';

enum SourceSetupKind {
  local('本地目录', '添加设备上的视频文件夹', Icons.folder_outlined),
  webdav('WebDAV', '连接 NAS 或 WebDAV 服务', Icons.cloud_outlined),
  openlist('OpenList', '连接 OpenList 中的媒体目录', Icons.layers_outlined),
  smb('SMB', '访问局域网共享文件夹', Icons.lan_outlined);

  const SourceSetupKind(this.label, this.description, this.icon);

  final String label;
  final String description;
  final IconData icon;
}

class SourceSetupPage extends ConsumerStatefulWidget {
  const SourceSetupPage({super.key, required this.kind});

  final SourceSetupKind kind;

  @override
  ConsumerState<SourceSetupPage> createState() => _SourceSetupPageState();
}

class _SourceSetupPageState extends ConsumerState<SourceSetupPage> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _urlController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _tokenController = TextEditingController();
  final _domainController = TextEditingController();
  final _openListPathController = TextEditingController();
  final _userAgentController = TextEditingController();
  final _refererController = TextEditingController();
  final _extensionsController = TextEditingController(
    text: defaultVideoExtensions.join(', '),
  );
  final _excludedController = TextEditingController(
    text: defaultExcludedDirectories.join(', '),
  );

  bool _isSubmitting = false;
  bool _obscurePassword = true;
  bool _obscureToken = true;
  String? _errorMessage;

  bool get _isLocal => widget.kind == SourceSetupKind.local;

  @override
  void dispose() {
    _nameController.dispose();
    _urlController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _tokenController.dispose();
    _domainController.dispose();
    _openListPathController.dispose();
    _userAgentController.dispose();
    _refererController.dispose();
    _extensionsController.dispose();
    _excludedController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_isSubmitting || !_formKey.currentState!.validate()) return;

    final rawName = _nameController.text.trim();
    final name = rawName.isEmpty ? null : rawName;
    final extensions = _extensionsController.text
        .split(',')
        .map((value) => value.trim().toLowerCase())
        .where((value) => value.isNotEmpty)
        .toList();
    final excluded = _excludedController.text
        .split(',')
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toList();

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    try {
      final controller = ref.read(sourceControllerProvider.notifier);
      if (_isLocal) {
        final source = await controller.addDirectory(
          name: name,
          extensions: extensions.isEmpty ? defaultVideoExtensions : extensions,
          excludedDirectories: excluded.isEmpty
              ? defaultExcludedDirectories
              : excluded,
        );
        if (source == null) return;
      } else {
        final headers = <String, String>{};
        if (_userAgentController.text.trim().isNotEmpty) {
          headers['User-Agent'] = _userAgentController.text.trim();
        }
        if (_refererController.text.trim().isNotEmpty) {
          headers['Referer'] = _refererController.text.trim();
        }
        await controller.addRemoteSource(
          kind: widget.kind.name,
          rootUrl: _urlController.text.trim(),
          name: name,
          credentials: RemoteCredentials(
            username: _usernameController.text.trim(),
            password: _passwordController.text,
            token: _tokenController.text.trim(),
            domain: _domainController.text.trim(),
            playbackHeaders: headers,
          ),
          openListRootPath: _openListPathController.text.trim().isEmpty
              ? null
              : _openListPathController.text.trim(),
          extensions: extensions.isEmpty ? defaultVideoExtensions : extensions,
          excludedDirectories: excluded.isEmpty
              ? defaultExcludedDirectories
              : excluded,
        );
      }
      if (mounted) {
        final messenger = ScaffoldMessenger.of(context);
        context.go('/sources');
        messenger.showSnackBar(
          const SnackBar(
            content: Text('媒体源已保存，扫描与识别进度可在列表查看'),
            duration: Duration(seconds: 2),
            showCloseIcon: true,
          ),
        );
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _errorMessage = error is MediaSourceException
            ? error.message
            : '添加媒体源失败，请重试';
      });
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: ReelvaDesign.background,
      body: GlassBackground(
        child: SafeArea(
          bottom: false,
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: ReelvaDesign.contentMaxWidth,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  GlassPageHeader(
                    title: _isLocal ? '添加本地目录' : '添加 ${widget.kind.label}',
                    leading: GlassIconButton(
                      key: const Key('source_setup_back_button'),
                      icon: Icons.arrow_back,
                      size: ReelvaDesign.pageHeaderButtonSize,
                      tooltip: '返回来源选择',
                      onPressed: () => context.pop(),
                    ),
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                      keyboardDismissBehavior:
                          ScrollViewKeyboardDismissBehavior.onDrag,
                      padding: EdgeInsets.fromLTRB(
                        ReelvaDesign.space24,
                        ReelvaDesign.space8,
                        ReelvaDesign.space24,
                        ReelvaDesign.space32 +
                            MediaQuery.paddingOf(context).bottom,
                      ),
                      child: Form(
                        key: _formKey,
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            final twoColumns =
                                constraints.maxWidth >=
                                ReelvaDesign.desktopBreakpoint -
                                    ReelvaDesign.space24 * 2;
                            final mainWidth = twoColumns
                                ? (constraints.maxWidth -
                                          ReelvaDesign.space24) *
                                      0.6
                                : constraints.maxWidth;
                            final advancedWidth = twoColumns
                                ? constraints.maxWidth -
                                      ReelvaDesign.space24 -
                                      mainWidth
                                : constraints.maxWidth;
                            return Wrap(
                              spacing: ReelvaDesign.space24,
                              runSpacing: ReelvaDesign.space16,
                              children: [
                                SizedBox(
                                  width: mainWidth,
                                  child: GlassCard(
                                    key: const Key(
                                      'source_setup_connection_card',
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      spacing: ReelvaDesign.space16,
                                      children: [
                                        Row(
                                          children: [
                                            Container(
                                              width: 40,
                                              height: 40,
                                              decoration: BoxDecoration(
                                                color: theme
                                                    .colorScheme
                                                    .primaryContainer,
                                                borderRadius:
                                                    BorderRadius.circular(
                                                      ReelvaDesign.radiusSmall,
                                                    ),
                                              ),
                                              child: Icon(
                                                widget.kind.icon,
                                                color: ReelvaDesign.accent,
                                                size: 22,
                                              ),
                                            ),
                                            const SizedBox(
                                              width: ReelvaDesign.space12,
                                            ),
                                            Expanded(
                                              child: Text(
                                                _isLocal ? '目录信息' : '连接信息',
                                                style:
                                                    theme.textTheme.titleSmall,
                                              ),
                                            ),
                                          ],
                                        ),
                                        ..._connectionFields(),
                                      ],
                                    ),
                                  ),
                                ),
                                SizedBox(
                                  width: advancedWidth,
                                  child: GlassExpansionCard(
                                    key: const Key(
                                      'source_setup_advanced_card',
                                    ),
                                    tileKey: const Key(
                                      'add_source_advanced_options',
                                    ),
                                    title: const Text('高级选项'),
                                    maintainState: true,
                                    tilePadding: const EdgeInsets.symmetric(
                                      horizontal: ReelvaDesign.space20,
                                      vertical: ReelvaDesign.space4,
                                    ),
                                    childrenPadding: const EdgeInsets.fromLTRB(
                                      ReelvaDesign.space20,
                                      ReelvaDesign.space16,
                                      ReelvaDesign.space20,
                                      ReelvaDesign.space20,
                                    ),
                                    children: [
                                      Column(
                                        spacing: ReelvaDesign.space16,
                                        children: _advancedFields(),
                                      ),
                                    ],
                                  ),
                                ),
                                SizedBox(
                                  width: mainWidth,
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    spacing: ReelvaDesign.space16,
                                    children: [
                                      if (_errorMessage != null)
                                        Semantics(
                                          liveRegion: true,
                                          child: Text(
                                            _errorMessage!,
                                            style: theme.textTheme.bodySmall
                                                ?.copyWith(
                                                  color:
                                                      theme.colorScheme.error,
                                                ),
                                          ),
                                        ),
                                      LayoutBuilder(
                                        builder: (context, constraints) {
                                          final cancel = OutlinedButton(
                                            onPressed: _isSubmitting
                                                ? null
                                                : () => context.pop(),
                                            child: const Text('取消'),
                                          );
                                          final submit = FilledButton.icon(
                                            key: const Key(
                                              'add_source_confirm_button',
                                            ),
                                            onPressed: _isSubmitting
                                                ? null
                                                : _submit,
                                            icon: _isSubmitting
                                                ? const SizedBox.square(
                                                    dimension: 18,
                                                    child:
                                                        CircularProgressIndicator(
                                                          strokeWidth: 2,
                                                          color: ReelvaDesign
                                                              .accentForeground,
                                                        ),
                                                  )
                                                : Icon(
                                                    _isLocal
                                                        ? Icons
                                                              .create_new_folder_outlined
                                                        : Icons.add,
                                                  ),
                                            label: Text(
                                              _isSubmitting
                                                  ? '正在保存…'
                                                  : _isLocal
                                                  ? '选择目录并添加'
                                                  : '添加媒体源',
                                            ),
                                          );
                                          if (constraints.maxWidth < 360 ||
                                              MediaQuery.textScalerOf(context)
                                                      .scale(14) >
                                                  14 * 1.3) {
                                            return Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.stretch,
                                              spacing: ReelvaDesign.space12,
                                              children: [submit, cancel],
                                            );
                                          }
                                          return Row(
                                            children: [
                                              cancel,
                                              const SizedBox(
                                                width: ReelvaDesign.space12,
                                              ),
                                              Expanded(child: submit),
                                            ],
                                          );
                                        },
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _connectionFields() {
    return [
      TextFormField(
        key: const Key('add_source_name_field'),
        controller: _nameController,
        enabled: !_isSubmitting,
        decoration: InputDecoration(
          labelText: '媒体源名称（可选）',
          hintText: _isLocal ? '留空将使用目录名称' : '留空将自动根据地址生成',
        ),
      ),
      if (!_isLocal)
        TextFormField(
          key: const Key('remote_source_url_field'),
          controller: _urlController,
          enabled: !_isSubmitting,
          keyboardType: TextInputType.url,
          autocorrect: false,
          decoration: InputDecoration(
            labelText: switch (widget.kind) {
              SourceSetupKind.webdav => 'WebDAV 地址',
              SourceSetupKind.openlist => 'OpenList 服务器地址',
              _ => 'SMB 共享路径',
            },
            hintText: switch (widget.kind) {
              SourceSetupKind.webdav => 'https://example.com/dav/',
              SourceSetupKind.openlist => 'https://example.com/base#/Movies',
              _ => 'smb://192.168.1.100/share/media',
            },
          ),
          validator: (value) =>
              value == null || value.trim().isEmpty ? '请输入根目录地址' : null,
        ),
      if (widget.kind == SourceSetupKind.webdav ||
          widget.kind == SourceSetupKind.smb)
        TextFormField(
          key: const Key('remote_source_username_field'),
          controller: _usernameController,
          enabled: !_isSubmitting,
          decoration: const InputDecoration(labelText: '用户名（可选）'),
        ),
      if (widget.kind == SourceSetupKind.openlist) ...[
        TextFormField(
          key: const Key('remote_source_openlist_path_field'),
          controller: _openListPathController,
          enabled: !_isSubmitting,
          decoration: const InputDecoration(
            labelText: '根目录路径（可选，或在 URL # 中指定）',
            hintText: '/Movies',
          ),
        ),
        TextFormField(
          key: const Key('remote_source_token_field'),
          controller: _tokenController,
          enabled: !_isSubmitting,
          obscureText: _obscureToken,
          decoration: InputDecoration(
            labelText: 'API Token（可选）',
            suffixIcon: IconButton(
              tooltip: _obscureToken ? '显示令牌' : '隐藏令牌',
              onPressed: _isSubmitting
                  ? null
                  : () => setState(() => _obscureToken = !_obscureToken),
              icon: Icon(
                _obscureToken
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined,
              ),
            ),
          ),
        ),
      ],
      if (!_isLocal)
        TextFormField(
          key: const Key('remote_source_password_field'),
          controller: _passwordController,
          enabled: !_isSubmitting,
          obscureText: _obscurePassword,
          decoration: InputDecoration(
            labelText: widget.kind == SourceSetupKind.openlist
                ? '目录访问密码（可选）'
                : '密码（可选）',
            suffixIcon: IconButton(
              tooltip: _obscurePassword ? '显示密码' : '隐藏密码',
              onPressed: _isSubmitting
                  ? null
                  : () => setState(() => _obscurePassword = !_obscurePassword),
              icon: Icon(
                _obscurePassword
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined,
              ),
            ),
          ),
        ),
      if (_isLocal)
        Text(
          '选择目录后，Reelva 会扫描其中的视频文件。Android 上需要授权访问所选目录。',
          style: Theme.of(context).textTheme.bodySmall
              ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
    ];
  }

  List<Widget> _advancedFields() {
    return [
      if (widget.kind == SourceSetupKind.smb)
        TextFormField(
          key: const Key('remote_source_domain_field'),
          controller: _domainController,
          enabled: !_isSubmitting,
          decoration: const InputDecoration(
            labelText: '工作组 / 域名（可选）',
            hintText: 'WORKGROUP',
          ),
        ),
      if (widget.kind == SourceSetupKind.openlist) ...[
        TextFormField(
          key: const Key('remote_source_user_agent_field'),
          controller: _userAgentController,
          enabled: !_isSubmitting,
          decoration: const InputDecoration(labelText: 'User-Agent 请求头（可选）'),
        ),
        TextFormField(
          key: const Key('remote_source_referer_field'),
          controller: _refererController,
          enabled: !_isSubmitting,
          decoration: const InputDecoration(labelText: 'Referer 请求头（可选）'),
        ),
      ],
      TextFormField(
        key: const Key('add_source_extensions_field'),
        controller: _extensionsController,
        enabled: !_isSubmitting,
        maxLines: null,
        decoration: const InputDecoration(
          labelText: '视频扩展名（逗号分隔）',
          hintText: 'mkv, mp4, avi, mov, m4v, ts, webm',
        ),
      ),
      TextFormField(
        key: const Key('add_source_excluded_field'),
        controller: _excludedController,
        enabled: !_isSubmitting,
        maxLines: null,
        decoration: const InputDecoration(
          labelText: '排除目录名称（逗号分隔）',
          hintText: r'.cache, $RECYCLE.BIN, System Volume Information',
        ),
      ),
    ];
  }
}
