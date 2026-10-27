import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import '../core/logging/app_logger.dart';
import 'desktop_preferences.dart';

final desktopWindowControllerProvider = Provider<DesktopWindowController>((
  ref,
) {
  final controller = DesktopWindowController(
    store: ref.read(desktopPreferencesStoreProvider),
  );
  ref.onDispose(controller.dispose);
  return controller;
});

class DesktopWindowController with WindowListener {
  DesktopWindowController({this.store = const DesktopPreferencesStore()});

  final DesktopPreferencesStore store;
  Rect? _normalBounds;
  bool _playing = false;
  Future<({Rect bounds, bool maximized})?>? _beforePlayback;
  Future<void> _save = Future<void>.value();

  Future<void> initialize() async {
    await windowManager.ensureInitialized();
    DesktopWindowState? saved;
    try {
      saved = await store.readWindowState();
    } catch (error, stack) {
      AppLogger.instance.error('读取窗口设置失败', error: error, stackTrace: stack);
    }
    if (saved != null) await windowManager.setSize(saved.size);
    _normalBounds = await windowManager.getBounds();
    if (saved?.maximized == true) await windowManager.maximize();
    windowManager.addListener(this);
  }

  void _saveState(DesktopWindowState value) {
    _save = _save.then((_) => store.saveWindowState(value)).catchError((
      Object error,
      StackTrace stack,
    ) {
      AppLogger.instance.error('保存窗口设置失败', error: error, stackTrace: stack);
    });
    unawaited(_save);
  }

  Future<void> _rememberWindow() async {
    if (_playing) return;
    try {
      if (await windowManager.isFullScreen() ||
          await windowManager.isMinimized()) {
        return;
      }
      final maximized = await windowManager.isMaximized();
      final bounds = maximized
          ? _normalBounds
          : await windowManager.getBounds();
      if (_playing || bounds == null) return;
      _normalBounds = bounds;
      _saveState((size: bounds.size, maximized: maximized));
    } catch (error, stack) {
      AppLogger.instance.error('读取当前窗口尺寸失败', error: error, stackTrace: stack);
    }
  }

  @override
  void onWindowResized() => unawaited(_rememberWindow());

  @override
  void onWindowMoved() => unawaited(_rememberWindow());

  @override
  void onWindowMaximize() => unawaited(_rememberWindow());

  @override
  void onWindowUnmaximize() => unawaited(_rememberWindow());

  Future<void> beginPlayback() {
    _playing = true;
    _beforePlayback = _captureWindow();
    return _beforePlayback!.then((_) {});
  }

  Future<({Rect bounds, bool maximized})?> _captureWindow() async {
    try {
      final maximized = await windowManager.isMaximized();
      final bounds = await windowManager.getBounds();
      if (!maximized) _normalBounds = bounds;
      if (_normalBounds != null) {
        _saveState((size: _normalBounds!.size, maximized: maximized));
      }
      return (bounds: _normalBounds ?? bounds, maximized: maximized);
    } catch (error, stack) {
      AppLogger.instance.error('保存播放前窗口状态失败', error: error, stackTrace: stack);
      return null;
    }
  }

  Future<void> endPlayback() async {
    if (!_playing) return;
    try {
      final saved = await _beforePlayback;
      if (saved == null) return;
      if (await windowManager.isFullScreen()) {
        await windowManager.setFullScreen(false);
      }
      if (await windowManager.isMaximized()) {
        await windowManager.unmaximize();
        await WidgetsBinding.instance.endOfFrame;
      }
      await windowManager.setBounds(saved.bounds);
      if (saved.maximized) await windowManager.maximize();
    } catch (error, stack) {
      AppLogger.instance.error('还原播放前窗口状态失败', error: error, stackTrace: stack);
    } finally {
      _beforePlayback = null;
      _playing = false;
    }
  }

  void dispose() => windowManager.removeListener(this);
}
