import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reelva/app/desktop_preferences.dart';
import 'package:reelva/app/desktop_window_controller.dart';

void main() {
  for (final initiallyMaximized in [false, true]) {
    testWidgets('窗口重启恢复，播放缩放和全屏不覆盖应用尺寸，原最大化状态为 $initiallyMaximized', (
      tester,
    ) async {
      FlutterSecureStorage.setMockInitialValues({
        DesktopPreferencesStore.windowKey: jsonEncode({
          'width': 1040,
          'height': 740,
          'maximized': initiallyMaximized,
        }),
      });
      var bounds = const Rect.fromLTWH(40, 70, 1280, 720);
      var normalBounds = bounds;
      var maximized = false;
      var fullscreen = false;
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(
        const MethodChannel('window_manager'),
        (call) async {
          switch (call.method) {
            case 'isMaximized':
              return maximized;
            case 'isFullScreen':
              return fullscreen;
            case 'isMinimized':
              return false;
            case 'getBounds':
              return {
                'x': bounds.left,
                'y': bounds.top,
                'width': bounds.width,
                'height': bounds.height,
              };
            case 'setBounds':
              final args = call.arguments as Map<dynamic, dynamic>;
              bounds = Rect.fromLTWH(
                (args['x'] as num?)?.toDouble() ?? bounds.left,
                (args['y'] as num?)?.toDouble() ?? bounds.top,
                (args['width'] as num).toDouble(),
                (args['height'] as num).toDouble(),
              );
              normalBounds = bounds;
            case 'maximize':
              maximized = true;
              bounds = const Rect.fromLTWH(0, 0, 1920, 1080);
            case 'unmaximize':
              WidgetsBinding.instance.addPostFrameCallback((_) {
                maximized = false;
                bounds = normalBounds;
              });
            case 'setFullScreen':
              fullscreen =
                  (call.arguments as Map<dynamic, dynamic>)['isFullScreen']
                      as bool;
          }
          return true;
        },
      );
      addTearDown(
        () => messenger.setMockMethodCallHandler(
          const MethodChannel('window_manager'),
          null,
        ),
      );
      final controller = DesktopWindowController();
      addTearDown(controller.dispose);
      await controller.initialize();
      expect(normalBounds.size, const Size(1040, 740));
      expect(maximized, initiallyMaximized);
      if (!initiallyMaximized) {
        bounds = const Rect.fromLTWH(90, 100, 1150, 800);
        normalBounds = bounds;
        controller.onWindowResized();
        await tester.pumpAndSettle();
      }
      final appBounds = normalBounds;
      await controller.beginPlayback();
      maximized = !initiallyMaximized;
      fullscreen = initiallyMaximized;
      bounds = const Rect.fromLTWH(0, 0, 1920, 1080);
      controller.onWindowResized();
      controller.onWindowMaximize();
      await tester.pumpAndSettle();
      final saved = await const DesktopPreferencesStore().readWindowState();
      expect(saved?.size, appBounds.size);
      expect(saved?.maximized, initiallyMaximized);
      final restoration = controller.endPlayback();
      await tester.pumpAndSettle();
      await restoration;
      expect(fullscreen, isFalse);
      expect(maximized, initiallyMaximized);
      expect(normalBounds, appBounds);
      if (!initiallyMaximized) expect(bounds, appBounds);

      controller.dispose();
      bounds = const Rect.fromLTWH(10, 10, 1280, 720);
      maximized = false;
      final restarted = DesktopWindowController();
      addTearDown(restarted.dispose);
      await restarted.initialize();
      expect(normalBounds.size, appBounds.size);
      expect(maximized, initiallyMaximized);
    });
  }
}
