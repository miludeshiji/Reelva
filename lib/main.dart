import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:reelva/app/app.dart';
import 'package:reelva/app/desktop_preferences.dart';
import 'package:reelva/app/desktop_window_controller.dart';
import 'package:reelva/core/errors/error_handling.dart';
import 'package:reelva/core/logging/app_logger.dart';
import 'package:reelva/features/player/application/player_settings_provider.dart';
import 'package:reelva/features/player/domain/player_settings.dart';
import 'package:reelva/features/player/infrastructure/media_kit_player_engine.dart';
import 'package:reelva/features/player/infrastructure/player_settings_store.dart';

void _registerLicenses() {
  LicenseRegistry.addLicense(() async* {
    final license = await rootBundle.loadString('assets/licenses/libsmb2.txt');
    yield LicenseEntryWithLineBreaks(['libsmb2'], license);
    final fontLicense = await rootBundle.loadString(
      'assets/licenses/NotoSansCJK.txt',
    );
    yield LicenseEntryWithLineBreaks(['Noto Sans CJK SC'], fontLicense);
  });
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  _registerLicenses();
  installErrorHandling();
  initializeMediaKit();

  const playerSettingsStore = PlayerSettingsStore();
  var playerSettings = PlayerSettings.defaultsFor(defaultTargetPlatform);
  try {
    playerSettings = await playerSettingsStore.read();
  } catch (e, st) {
    AppLogger.instance.error('读取播放器设置失败，使用默认配置', error: e, stackTrace: st);
  }

  const desktopPreferencesStore = DesktopPreferencesStore();
  DesktopWindowController? desktopWindow;
  var sidebarCollapsed = false;
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.windows) {
    try {
      sidebarCollapsed = await desktopPreferencesStore.readSidebarCollapsed();
    } catch (e, st) {
      AppLogger.instance.error('读取侧栏状态失败，使用默认布局', error: e, stackTrace: st);
    }
    desktopWindow = DesktopWindowController(store: desktopPreferencesStore);
    await desktopWindow.initialize();
  }

  runApp(
    ProviderScope(
      overrides: [
        desktopPreferencesStoreProvider.overrideWithValue(
          desktopPreferencesStore,
        ),
        sidebarCollapsedProvider.overrideWith(
          () => SidebarCollapsedController(initialValue: sidebarCollapsed),
        ),
        if (desktopWindow != null)
          desktopWindowControllerProvider.overrideWithValue(desktopWindow),
        playerSettingsStoreProvider.overrideWithValue(playerSettingsStore),
        playerSettingsProvider.overrideWith(
          () => PlayerSettingsController(initialSettings: playerSettings),
        ),
      ],
      child: const ReelvaApp(),
    ),
  );
}
