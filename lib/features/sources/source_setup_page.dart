import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:reelva/shared/widgets/glass_widgets.dart';

import 'application/source_providers.dart';
import 'cloud_source_setup_page.dart';
import 'domain/source_models.dart';
import 'infrastructure/remote_credentials_store.dart';

enum SourceSetupKind {
  local('本地目录', '添加设备上的视频文件夹', Icons.folder_outlined),
  webdav('WebDAV', '连接 NAS 或 WebDAV 服务', Icons.cloud_outlined),
  smb('SMB', '访问局域网共享文件夹', Icons.lan_outlined),
  baidu(
    '百度网盘',
    '连接百度网盘中的影视目录',
    Icons.cloud_outlined,
    openListDriver: 'BaiduNetdisk',
  ),
  quark('夸克网盘', '连接夸克网盘中的影视目录', Icons.cloud_outlined, openListDriver: 'Quark'),
  pan115(
    '115 网盘',
    '连接 115 网盘中的影视目录',
    Icons.cloud_outlined,
    openListDriver: '115 Open',
  ),
  pan123(
    '123 云盘',
    '连接 123 云盘中的影视目录',
    Icons.cloud_outlined,
    openListDriver: '123 Open',
  );

  const SourceSetupKind(
    this.label,
    this.description,
    this.icon, {
    this.openListDriver,
  });

  final String label;
  final String description;
  final IconData icon;
  final String? openListDriver;
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
  final _domainController = TextEditingController();
  final _extensionsController = TextEditingController(
    text: defaultVideoExtensions.join(', '),
  );
  final _excludedController = TextEditingController(
    text: defaultExcludedDirectories.join(', '),
  );

  bool _isSubmitting = false;
  bool _obscurePassword = true;
  String? _errorMessage;

  bool get _isLocal => widget.kind == SourceSetupKind.local;

  @override
  void dispose() {
    _nameController.dispose();
    _urlController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _domainController.dispose();
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
        await controller.addRemoteSource(
          kind: widget.kind.name,
          rootUrl: _urlController.text.trim(),
          name: name,
          credentials: RemoteCredentials(
            username: _usernameController.text.trim(),
            password: _passwordController.text,
            domain: _domainController.text.trim(),
          ),
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
            content: Text('媒体源已保存，扫描后可在影视库点击刷新进行匹配'),
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
    final openListDriver = widget.kind.openListDriver;
    if (openListDriver != null) {
      return CloudSourceSetupPage(driver: openListDriver);
    }
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
              _ => 'SMB 共享路径',
            },
            hintText: switch (widget.kind) {
              SourceSetupKind.webdav => 'https://example.com/dav/',
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
      if (!_isLocal)
        TextFormField(
          key: const Key('remote_source_password_field'),
          controller: _passwordController,
          enabled: !_isSubmitting,
          obscureText: _obscurePassword,
          decoration: InputDecoration(
            labelText: '密码（可选）',
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
