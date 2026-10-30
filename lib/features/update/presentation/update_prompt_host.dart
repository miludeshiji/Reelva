import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/logging/app_logger.dart';
import '../application/app_update_providers.dart';
import '../domain/app_release.dart';
import 'app_update_dialog.dart';

class UpdatePromptHost extends ConsumerStatefulWidget {
  const UpdatePromptHost({
    super.key,
    required this.router,
    required this.child,
  });

  final GoRouter router;
  final Widget child;

  @override
  ConsumerState<UpdatePromptHost> createState() => _UpdatePromptHostState();
}

class _UpdatePromptHostState extends ConsumerState<UpdatePromptHost>
    with WidgetsBindingObserver {
  AppRelease? _pending;
  bool _dialogOpen = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.router.routerDelegate.addListener(_schedulePrompt);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(_removeInstalledApks());
      unawaited(_checkAutomatically());
    });
  }

  Future<void> _removeInstalledApks() async {
    if (defaultTargetPlatform != TargetPlatform.android) return;
    try {
      final info = await ref.read(packageInfoProvider.future);
      if (!mounted) return;
      await ref.read(apkDownloaderProvider).removeInstalledApks(info.version);
    } catch (e, st) {
      AppLogger.instance.warning('清理已安装更新包失败', error: e, stackTrace: st);
    }
  }

  Future<void> _checkAutomatically() async {
    try {
      final preferences = await ref.read(updatePreferencesProvider.future);
      if (!mounted || !preferences.shouldCheck(DateTime.now())) return;
      await ref.read(updateCheckProvider.notifier).check();
    } catch (e, st) {
      AppLogger.instance.error('自动检查更新失败', error: e, stackTrace: st);
    }
  }

  void _schedulePrompt() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_showPending());
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  Future<void> _showPending() async {
    final release = _pending;
    if (release == null ||
        _dialogOpen ||
        widget.router.state.uri.path == '/player' ||
        (WidgetsBinding.instance.lifecycleState != null &&
            WidgetsBinding.instance.lifecycleState !=
                AppLifecycleState.resumed)) {
      return;
    }
    final navigatorContext =
        widget.router.routerDelegate.navigatorKey.currentContext;
    if (navigatorContext == null || !navigatorContext.mounted) return;
    _pending = null;
    _dialogOpen = true;
    try {
      await showDialog<void>(
        context: navigatorContext,
        builder: (context) => AppUpdateDialog(
          release: release,
          currentVersion:
              ref.read(packageInfoProvider).asData?.value.version ?? '',
        ),
      );
    } finally {
      _dialogOpen = false;
      if (mounted && _pending != null) _schedulePrompt();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _schedulePrompt();
  }

  @override
  void dispose() {
    widget.router.routerDelegate.removeListener(_schedulePrompt);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(updateCheckProvider, (previous, next) {
      final release = next.asData?.value;
      if (release != null) {
        _pending = release;
        _schedulePrompt();
      }
    });
    return widget.child;
  }
}
