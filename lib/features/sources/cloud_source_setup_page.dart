import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:reelva/shared/widgets/glass_widgets.dart';

import 'application/source_providers.dart';
import 'cloud_login_page.dart';
import 'domain/openlist_models.dart';
import 'domain/source_models.dart';
import 'infrastructure/openlist_service.dart';
import 'openlist_authorization.dart';

class CloudSourceSetupPage extends ConsumerStatefulWidget {
  const CloudSourceSetupPage({super.key, required this.driver, this.source});

  final String driver;
  final MediaSourceConfig? source;

  @override
  ConsumerState<CloudSourceSetupPage> createState() =>
      _CloudSourceSetupPageState();
}

class _CloudSourceSetupPageState extends ConsumerState<CloudSourceSetupPage> {
  final _manualForm = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _accessController = TextEditingController();
  final _refreshController = TextEditingController();
  final _cookieController = TextEditingController();
  final _extensionsController = TextEditingController(
    text: defaultVideoExtensions.join(', '),
  );
  final _excludedController = TextEditingController(
    text: defaultExcludedDirectories.join(', '),
  );
  String? _accountId;
  Map<String, dynamic> _previousAuthorization = const {};
  List<OpenListEntry> _directories = const [];
  String _directory = '/';
  String? _error;
  bool _busy = false;
  bool _saving = false;
  bool _bound = false;
  bool _authorized = false;
  bool _showSecrets = false;

  bool get _reauthorizing => widget.source != null;
  String get _label => openListDrivers[widget.driver] ?? '网盘';
  late final OpenListService _service;

  @override
  void initState() {
    super.initState();
    _service = ref.read(openListServiceProvider);
    final source = widget.source;
    if (source != null) {
      final root = OpenListRoot.parse(source.rootLocator);
      _accountId = root.accountId;
      _directory = root.path;
      _nameController.text = source.name;
      _extensionsController.text = source.extensions.join(', ');
      _excludedController.text = source.excludedDirectories.join(', ');
      unawaited(_loadAccount());
    }
  }

  Future<void> _loadAccount() async {
    setState(() => _busy = true);
    try {
      final credentials = await _service.readAccount(_accountId!);
      _previousAuthorization = credentials.openListAuthorization;
    } catch (_) {
      // Reauthorization remains possible when the old credential is missing.
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    final accountId = _accountId;
    if (!_reauthorizing && !_bound && !_saving && accountId != null) {
      final service = _service;
      unawaited(_deleteTemporaryAccount(service, accountId));
    }
    _nameController.dispose();
    _accessController.dispose();
    _refreshController.dispose();
    _cookieController.dispose();
    _extensionsController.dispose();
    _excludedController.dispose();
    super.dispose();
  }

  Future<void> _deleteTemporaryAccount(
    OpenListService service,
    String accountId,
  ) async {
    try {
      await service.deleteAccount(accountId);
    } catch (_) {
      // The service also reconciles accounts against the saved media sources.
    }
  }

  Future<void> _login() async {
    setState(() => _error = null);
    final authorization = await Navigator.of(context)
        .push<Map<String, dynamic>>(
          MaterialPageRoute(
            builder: (_) => CloudLoginPage(driver: widget.driver),
          ),
        );
    if (authorization != null && mounted) await _authorize(authorization);
  }

  Future<void> _manualAuthorize() async {
    if (!_manualForm.currentState!.validate()) return;
    try {
      final authorization = buildOpenListAuthorization(
        driver: widget.driver,
        accessToken: _accessController.text,
        refreshToken: _refreshController.text,
        cookie: _cookieController.text,
        previous: _previousAuthorization,
      );
      await _authorize(authorization);
    } on FormatException catch (error) {
      setState(() => _error = error.message);
    }
  }

  Future<void> _authorize(Map<String, dynamic> authorization) async {
    if (_busy) return;
    final addition = Map<String, dynamic>.from(_previousAuthorization)
      ..removeWhere(
        (key, _) => const {
          'AccessToken',
          'RefreshToken',
          'access_token',
          'refresh_token',
          'access_token_expires_at',
          'token_updated_at',
          'expires_in',
          'cookie',
          'Cookie',
        }.contains(key),
      )
      ..addAll(authorization);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (_reauthorizing) {
        await ref
            .read(sourceControllerProvider.notifier)
            .reauthorizeOpenListSource(widget.source!.id, addition);
        if (mounted) Navigator.of(context).pop(true);
        return;
      }
      final accountId = await _service.saveAccount(
        accountId: _accountId,
        driver: widget.driver,
        name: _nameController.text.trim().isEmpty
            ? _label
            : _nameController.text.trim(),
        addition: addition,
      );
      _accountId = accountId;
      _previousAuthorization = addition;
      _authorized = true;
      _accessController.clear();
      _refreshController.clear();
      _cookieController.clear();
      if (!mounted) {
        if (!_reauthorizing) await _deleteTemporaryAccount(_service, accountId);
        return;
      }
      final entries = await _service.list(accountId, '/', refresh: true);
      if (!mounted) return;
      setState(() {
        _directory = '/';
        _directories = _sortedDirectories(entries);
      });
    } catch (error) {
      if (mounted) {
        setState(
          () => _error =
              error is MediaSourceException &&
                  const {
                    'unauthorized',
                    'invalid_token',
                    'invalid_grant',
                  }.contains(error.code)
              ? '网盘登录已失效，请重新授权'
              : '连接网盘失败，请检查登录状态和网络后重试',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  List<OpenListEntry> _sortedDirectories(List<OpenListEntry> entries) =>
      entries.where((entry) => entry.isDirectory).toList()
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

  Future<void> _openDirectory(String path) async {
    if (_busy || _accountId == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final entries = await _service.list(_accountId!, path, refresh: true);
      if (!mounted) return;
      setState(() {
        _directory = path;
        _directories = _sortedDirectories(entries);
      });
    } catch (_) {
      if (mounted) setState(() => _error = '读取目录失败，请检查登录状态和网络后重试');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _saveSource() async {
    if (_busy || _saving || !_authorized || _accountId == null) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final extensions = _split(_extensionsController.text);
      final excluded = _split(_excludedController.text);
      await ref
          .read(sourceControllerProvider.notifier)
          .addOpenListSource(
            accountId: _accountId!,
            directory: _directory,
            name: _nameController.text.trim().isEmpty
                ? null
                : _nameController.text.trim(),
            extensions: extensions.isEmpty
                ? defaultVideoExtensions
                : extensions,
            excludedDirectories: excluded.isEmpty
                ? defaultExcludedDirectories
                : excluded,
          );
      _bound = true;
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      context.go('/sources');
      messenger.showSnackBar(
        const SnackBar(content: Text('媒体源已保存，扫描后可在影视库点击刷新进行匹配')),
      );
    } catch (_) {
      if (mounted) {
        setState(() => _error = '保存媒体源失败，请重试');
      } else if (!_bound && _accountId != null) {
        await _deleteTemporaryAccount(_service, _accountId!);
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  List<String> _split(String value) => value
      .split(',')
      .map((item) => item.trim())
      .where((item) => item.isNotEmpty)
      .toList();

  @override
  Widget build(BuildContext context) {
    final disabled = _busy || _saving;
    return PopScope(
      canPop: !_saving,
      child: Scaffold(
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
                      title: _reauthorizing ? '重新授权 $_label' : '添加 $_label',
                      leading: GlassIconButton(
                        key: const Key('cloud_source_back_button'),
                        icon: Icons.arrow_back,
                        tooltip: '返回',
                        onPressed: _saving
                            ? null
                            : () => Navigator.of(context).pop(),
                      ),
                    ),
                    Expanded(
                      child: SingleChildScrollView(
                        padding: EdgeInsets.fromLTRB(
                          24,
                          8,
                          24,
                          32 + MediaQuery.paddingOf(context).bottom,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          spacing: ReelvaDesign.space16,
                          children: [
                            GlassCard(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                spacing: ReelvaDesign.space16,
                                children: [
                                  if (!_reauthorizing)
                                    TextField(
                                      key: const Key('cloud_source_name_field'),
                                      controller: _nameController,
                                      enabled: !disabled,
                                      decoration: const InputDecoration(
                                        labelText: '媒体源名称（可选）',
                                        hintText: '留空将使用网盘及目录名称',
                                      ),
                                    ),
                                  Text(
                                    _reauthorizing
                                        ? '登录后更新此媒体源的授权，所选目录保持不变。'
                                        : '登录网盘后，选择要加入影视库的目录。',
                                  ),
                                  FilledButton.icon(
                                    key: const Key('cloud_login_button'),
                                    onPressed: disabled ? null : _login,
                                    icon: const Icon(Icons.login),
                                    label: Text('网页登录 $_label'),
                                  ),
                                  if (_reauthorizing)
                                    Text(
                                      '当前目录：$_directory',
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall,
                                    ),
                                ],
                              ),
                            ),
                            _manualCard(disabled),
                            if (_busy) const LinearProgressIndicator(),
                            if (_authorized && !_reauthorizing)
                              _directoryCard(disabled),
                            if (!_reauthorizing)
                              GlassExpansionCard(
                                title: const Text('高级选项'),
                                maintainState: true,
                                childrenPadding: const EdgeInsets.all(
                                  ReelvaDesign.space20,
                                ),
                                children: [
                                  TextField(
                                    key: const Key(
                                      'cloud_source_extensions_field',
                                    ),
                                    controller: _extensionsController,
                                    enabled: !disabled,
                                    decoration: const InputDecoration(
                                      labelText: '视频扩展名（逗号分隔）',
                                    ),
                                  ),
                                  const SizedBox(height: ReelvaDesign.space16),
                                  TextField(
                                    key: const Key(
                                      'cloud_source_excluded_field',
                                    ),
                                    controller: _excludedController,
                                    enabled: !disabled,
                                    decoration: const InputDecoration(
                                      labelText: '排除目录名称（逗号分隔）',
                                    ),
                                  ),
                                ],
                              ),
                            if (_error != null)
                              Semantics(
                                liveRegion: true,
                                child: Text(
                                  _error!,
                                  key: const Key('cloud_source_error'),
                                  style: TextStyle(
                                    color: Theme.of(context).colorScheme.error,
                                  ),
                                ),
                              ),
                            if (!_reauthorizing)
                              FilledButton.icon(
                                key: const Key('cloud_source_confirm_button'),
                                onPressed: disabled || !_authorized
                                    ? null
                                    : _saveSource,
                                icon: _saving
                                    ? const SizedBox.square(
                                        dimension: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Icon(Icons.add),
                                label: Text(_saving ? '正在保存…' : '将此目录添加为媒体源'),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _manualCard(bool disabled) {
    return GlassExpansionCard(
      tileKey: const Key('cloud_manual_options'),
      title: Text(widget.driver == 'Quark' ? '手动填写 Cookie' : '手动填写 Token'),
      maintainState: true,
      childrenPadding: const EdgeInsets.all(ReelvaDesign.space20),
      children: [
        Form(
          key: _manualForm,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: ReelvaDesign.space16,
            children: [
              if (widget.driver == 'Quark')
                TextFormField(
                  key: const Key('cloud_cookie_field'),
                  controller: _cookieController,
                  enabled: !disabled,
                  autocorrect: false,
                  enableSuggestions: false,
                  obscureText: !_showSecrets,
                  decoration: const InputDecoration(labelText: 'Cookie'),
                  validator: (value) => value == null || value.trim().isEmpty
                      ? '请填写 Cookie'
                      : null,
                )
              else ...[
                TextFormField(
                  key: const Key('cloud_access_token_field'),
                  controller: _accessController,
                  enabled: !disabled,
                  autocorrect: false,
                  enableSuggestions: false,
                  obscureText: !_showSecrets,
                  decoration: InputDecoration(
                    labelText: widget.driver == '115 Open'
                        ? 'Access Token'
                        : 'Access Token（可选）',
                  ),
                  validator: (value) =>
                      widget.driver == '115 Open' &&
                          (value == null || value.trim().isEmpty)
                      ? '请填写 Access Token'
                      : null,
                ),
                TextFormField(
                  key: const Key('cloud_refresh_token_field'),
                  controller: _refreshController,
                  enabled: !disabled,
                  autocorrect: false,
                  enableSuggestions: false,
                  obscureText: !_showSecrets,
                  decoration: const InputDecoration(labelText: 'Refresh Token'),
                  validator: (value) => value == null || value.trim().isEmpty
                      ? '请填写 Refresh Token'
                      : null,
                ),
              ],
              Row(
                children: [
                  TextButton.icon(
                    onPressed: disabled
                        ? null
                        : () => setState(() => _showSecrets = !_showSecrets),
                    icon: Icon(
                      _showSecrets
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                    ),
                    label: Text(_showSecrets ? '隐藏凭据' : '显示凭据'),
                  ),
                  const Spacer(),
                  FilledButton(
                    key: const Key('cloud_manual_connect_button'),
                    onPressed: disabled ? null : _manualAuthorize,
                    child: Text(_reauthorizing ? '更新授权' : '连接网盘'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _directoryCard(bool disabled) {
    final segments = _directory
        .split('/')
        .where((part) => part.isNotEmpty)
        .toList();
    final parent = segments.length <= 1
        ? '/'
        : '/${segments.take(segments.length - 1).join('/')}';
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '选择影视目录',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              GlassIconButton(
                icon: Icons.home_outlined,
                tooltip: '网盘根目录',
                onPressed: disabled ? null : () => _openDirectory('/'),
              ),
              GlassIconButton(
                icon: Icons.arrow_upward,
                tooltip: '上一级目录',
                onPressed: disabled || segments.isEmpty
                    ? null
                    : () => _openDirectory(parent),
              ),
              GlassIconButton(
                icon: Icons.refresh,
                tooltip: '刷新目录',
                onPressed: disabled ? null : () => _openDirectory(_directory),
              ),
            ],
          ),
          const SizedBox(height: ReelvaDesign.space8),
          Text(
            _directory,
            key: const Key('cloud_current_directory'),
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: ReelvaDesign.space12),
          if (_directories.isEmpty && !_busy)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Text('此目录没有子文件夹，可直接添加当前目录'),
            )
          else
            for (final entry in _directories)
              Material(
                type: MaterialType.transparency,
                child: ListTile(
                  key: ValueKey('cloud_directory_${entry.path}'),
                  enabled: !disabled,
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(
                    Icons.folder_outlined,
                    color: ReelvaDesign.accent,
                  ),
                  title: Text(entry.name),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _openDirectory(entry.path),
                ),
              ),
        ],
      ),
    );
  }
}
