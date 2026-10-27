import 'dart:async';
import 'dart:convert';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../core/logging/app_logger.dart';

typedef DesktopWindowState = ({Size size, bool maximized});

class DesktopPreferencesStore {
  const DesktopPreferencesStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  static const sidebarKey = 'reelva_sidebar_collapsed';
  static const windowKey = 'reelva_window_state';
  final FlutterSecureStorage _storage;

  Future<bool> readSidebarCollapsed() async =>
      await _storage.read(key: sidebarKey) == 'true';

  Future<void> saveSidebarCollapsed(bool value) =>
      _storage.write(key: sidebarKey, value: '$value');

  Future<DesktopWindowState?> readWindowState() async {
    final raw = await _storage.read(key: windowKey);
    if (raw == null) return null;
    final data = jsonDecode(raw);
    if (data is! Map<String, dynamic>) {
      throw const FormatException('窗口设置格式损坏');
    }
    final width = data['width'];
    final height = data['height'];
    if (width is! num ||
        height is! num ||
        !width.isFinite ||
        !height.isFinite ||
        width <= 0 ||
        height <= 0) {
      throw const FormatException('窗口尺寸无效');
    }
    return (
      size: Size(width.toDouble(), height.toDouble()),
      maximized: data['maximized'] == true,
    );
  }

  Future<void> saveWindowState(DesktopWindowState value) => _storage.write(
    key: windowKey,
    value: jsonEncode({
      'width': value.size.width,
      'height': value.size.height,
      'maximized': value.maximized,
    }),
  );
}

final desktopPreferencesStoreProvider = Provider<DesktopPreferencesStore>(
  (ref) => const DesktopPreferencesStore(),
);

final sidebarCollapsedProvider =
    NotifierProvider<SidebarCollapsedController, bool>(
      SidebarCollapsedController.new,
    );

class SidebarCollapsedController extends Notifier<bool> {
  SidebarCollapsedController({this.initialValue = false});

  final bool initialValue;
  Future<void> _save = Future<void>.value();

  @override
  bool build() => initialValue;

  void toggle() {
    state = !state;
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.windows) return;
    final value = state;
    final store = ref.read(desktopPreferencesStoreProvider);
    _save = _save.then((_) => store.saveSidebarCollapsed(value)).catchError((
      Object error,
      StackTrace stack,
    ) {
      AppLogger.instance.error('保存侧栏状态失败', error: error, stackTrace: stack);
    });
    unawaited(_save);
  }
}
