import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reelva/features/player/application/playback_session.dart';
import 'package:reelva/features/player/application/player_providers.dart';
import 'package:reelva/features/player/domain/playback_snapshot.dart';
import 'package:reelva/features/player/infrastructure/android_screen_brightness.dart';
import 'package:reelva/features/player/presentation/player_page.dart';

import 'fake_player_engine.dart';

void main() {
  late FakePlayerEngine engine;
  late List<MethodCall> brightnessCalls;
  var brightness = 0.5;

  setUp(() {
    engine = FakePlayerEngine(
      initialSnapshot: const PlaybackSnapshot(
        status: PlaybackStatus.playing,
        volume: 80,
        duration: Duration(minutes: 20),
      ),
    );
    brightness = 0.5;
    brightnessCalls = [];
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (_) async => null,
    );
    messenger.setMockMethodCallHandler(AndroidScreenBrightness.channel, (
      call,
    ) async {
      brightnessCalls.add(call);
      if (call.method == 'get') return brightness;
      if (call.method == 'set') {
        brightness =
            (call.arguments as Map<dynamic, dynamic>)['brightness'] as double;
      }
      return null;
    });
  });

  tearDown(() async {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, null);
    messenger.setMockMethodCallHandler(AndroidScreenBrightness.channel, null);
    await engine.dispose();
  });

  Future<void> mount(
    WidgetTester tester, {
    Size size = const Size(390, 844),
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final session = createFakeSession(engine: engine);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          playerSessionProvider.overrideWithValue(
            PlaybackSession(
              engine: engine,
              videoBuilder: session.videoBuilder,
              maxVolume: 200,
            ),
          ),
        ],
        child: const MaterialApp(home: PlayerPage()),
      ),
    );
    await tester.pumpAndSettle();
  }

  for (final size in [const Size(390, 844), const Size(844, 390)]) {
    testWidgets('左右滑动调亮度和音量，方向与起点锁定，浮窗居中且不触发倍速 $size', (tester) async {
      await mount(tester, size: size);
      final video = tester.getRect(
        find.byKey(const Key('player_video_region')),
      );
      final indicator = find.byKey(const Key('player_gesture_indicator'));
      expect(find.byKey(const Key('player_volume_button')), findsNothing);
      final left = Offset(video.width * 0.2, video.height * 0.5);
      final gesture = await tester.startGesture(left);
      await gesture.moveBy(const Offset(0, -30));
      await tester.pump();
      await gesture.moveBy(const Offset(0, -35));
      await tester.pump();
      expect(brightness, greaterThan(0.5));
      expect(engine.setVolumeCount, 0);
      expect(indicator, findsOneWidget);
      expect(tester.getCenter(indicator), video.center);
      expect(find.text('亮度 ${(brightness * 100).round()}%'), findsOneWidget);
      await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
      expect(engine.setRateCount, 0);
      await gesture.moveBy(Offset(video.width * 0.6, -20));
      await tester.pump();
      expect(engine.setVolumeCount, 0);
      await gesture.up();
      await tester.pump(const Duration(milliseconds: 900));
      expect(indicator, findsNothing);
      final oldBrightness = brightness;
      await tester.dragFrom(left, const Offset(0, 60));
      await tester.pump();
      expect(brightness, lessThan(oldBrightness));
      final right = Offset(video.width * 0.8, video.height * 0.5);
      await tester.dragFrom(right, const Offset(0, -60));
      await tester.pump();
      expect(engine.lastVolume, greaterThan(80));
      expect(find.text('音量 ${engine.lastVolume!.round()}%'), findsOneWidget);
      final volume = engine.lastVolume!;
      await tester.dragFrom(right, const Offset(0, 50));
      await tester.pump();
      expect(engine.lastVolume, lessThan(volume));
      await tester.dragFrom(right, const Offset(0, -2000));
      await tester.pump();
      expect(engine.lastVolume, 200);
      await tester.dragFrom(right, const Offset(0, 2000));
      await tester.pump();
      expect(engine.lastVolume, 0);
      expect(find.byIcon(Icons.volume_off_rounded), findsOneWidget);
      expect(engine.pauseCount, 0);
      expect(engine.playCount, 0);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(kDoubleTapTimeout);
      expect(
        brightnessCalls.where((call) => call.method == 'reset'),
        hasLength(1),
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('移动端单击切换控件，双击暂停和继续，按钮操作不触发画面手势', (tester) async {
    await mount(tester);
    final point = tester.getCenter(
      find.byKey(const Key('player_video_region')),
    );
    await tester.tapAt(point);
    await tester.pump(kDoubleTapTimeout);
    await tester.pumpAndSettle();
    expect(engine.pauseCount, 0);
    await tester.tapAt(point);
    await tester.pump(const Duration(milliseconds: 70));
    await tester.tapAt(point);
    await tester.pumpAndSettle();
    expect(engine.pauseCount, 1);
    await tester.tapAt(point);
    await tester.pump(const Duration(milliseconds: 70));
    await tester.tapAt(point);
    await tester.pumpAndSettle();
    expect(engine.playCount, 1);
    await tester.drag(
      find.byKey(const Key('player_seek_slider')),
      const Offset(0, -50),
    );
    await tester.pumpAndSettle();
    expect(engine.setVolumeCount, 0);
    expect(brightnessCalls, isEmpty);
    expect(find.byKey(const Key('player_gesture_indicator')), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('亮度读取尚未返回时松手，不应用迟到的亮度变更', (tester) async {
    final read = Completer<double>();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(AndroidScreenBrightness.channel, (
          call,
        ) async {
          brightnessCalls.add(call);
          return call.method == 'get' ? read.future : null;
        });
    await mount(tester);
    final gesture = await tester.startGesture(const Offset(80, 400));
    await gesture.moveBy(const Offset(0, -60));
    await tester.pump();
    await gesture.up();
    read.complete(0.5);
    await tester.pumpAndSettle();
    expect(brightnessCalls.map((call) => call.method), ['get']);
    expect(find.byKey(const Key('player_gesture_indicator')), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('亮度调节失败时提示错误，释放手势后仍可调节音量', (tester) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(AndroidScreenBrightness.channel, (
          call,
        ) async {
          brightnessCalls.add(call);
          if (call.method == 'get') return 0.5;
          if (call.method == 'set') throw PlatformException(code: 'FAILED');
          return null;
        });
    await mount(tester);
    await tester.dragFrom(const Offset(80, 400), const Offset(0, -60));
    await tester.pump(kDoubleTapTimeout);
    expect(find.text('无法调节亮度，请重试'), findsOneWidget);
    expect(find.byKey(const Key('player_gesture_indicator')), findsNothing);
    await tester.dragFrom(const Offset(310, 400), const Offset(0, -60));
    await tester.pump(kDoubleTapTimeout);
    expect(engine.lastVolume, greaterThan(80));
    expect(find.text('音量 ${engine.lastVolume!.round()}%'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(kDoubleTapTimeout);
    expect(tester.takeException(), isNull);
  });
}
