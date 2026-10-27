import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reelva/features/player/application/player_providers.dart';
import 'package:reelva/features/player/domain/playback_snapshot.dart';
import 'package:reelva/features/player/presentation/player_page.dart';

import 'fake_player_engine.dart';

void main() {
  testWidgets('Windows 按视频比例调整客户区，保留标题栏与边框且不随进度重复缩放', (tester) async {
    tester.view.devicePixelRatio = 2;
    tester.view.physicalSize = const Size(2560, 1440);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final resized = <Map<dynamic, dynamic>>[];
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('reelva/player_input'),
      (_) async => null,
    );
    addTearDown(
      () => messenger.setMockMethodCallHandler(
        const MethodChannel('reelva/player_input'),
        null,
      ),
    );
    messenger.setMockMethodCallHandler(const MethodChannel('window_manager'), (
      call,
    ) async {
      switch (call.method) {
        case 'isFullScreen':
        case 'isMaximized':
          return false;
        case 'getBounds':
          return {'x': 100.0, 'y': 80.0, 'width': 1296.0, 'height': 759.0};
        case 'setBounds':
          resized.add(call.arguments as Map<dynamic, dynamic>);
      }
      return true;
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(
        const MethodChannel('window_manager'),
        null,
      ),
    );
    final engine = FakePlayerEngine(
      initialSnapshot: const PlaybackSnapshot(status: PlaybackStatus.opening),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          playerSessionProvider.overrideWithValue(
            createFakeSession(engine: engine),
          ),
        ],
        child: const MaterialApp(home: PlayerPage()),
      ),
    );
    await tester.pump();
    expect(resized, isEmpty);
    engine.emit(
      const PlaybackSnapshot(
        status: PlaybackStatus.playing,
        videoWidth: 1440,
        videoHeight: 1080,
      ),
    );
    await tester.pumpAndSettle();
    expect(resized, hasLength(1));
    expect(resized.single['width'], 976);
    expect(resized.single['height'], 759);
    expect(resized.single['x'], 260);
    expect(resized.single['y'], 80);
    engine.emit(engine.snapshot.copyWith(position: const Duration(seconds: 1)));
    await tester.pumpAndSettle();
    expect(resized, hasLength(1));
    engine.emit(engine.snapshot.copyWith(videoWidth: 1080, videoHeight: 1920));
    await tester.pumpAndSettle();
    expect(resized, hasLength(2));
    expect(resized.last['width'], 421);
    expect(resized.last['height'], 759);
    await tester.tap(find.byKey(const Key('player_fullscreen_button')));
    await tester.pumpAndSettle();
    engine.emit(engine.snapshot.copyWith(videoWidth: 1920, videoHeight: 1080));
    await tester.pumpAndSettle();
    expect(resized, hasLength(2));
    await tester.tap(find.byKey(const Key('fullscreen_exit_back_button')));
    await tester.pumpAndSettle();
    expect(resized, hasLength(3));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    await engine.dispose();
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));
}
