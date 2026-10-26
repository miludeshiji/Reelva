import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reelva/features/player/application/playback_session.dart';
import 'package:reelva/features/player/application/player_providers.dart';
import 'package:reelva/features/player/application/player_settings_provider.dart';
import 'package:reelva/features/player/domain/playback_snapshot.dart';
import 'package:reelva/features/player/domain/player_settings.dart';
import 'package:reelva/features/player/domain/player_shortcuts.dart';
import 'package:reelva/features/player/presentation/player_page.dart';

import 'fake_player_engine.dart';

void main() {
  late FakePlayerEngine engine;

  setUp(() {
    engine = FakePlayerEngine(
      initialSnapshot: const PlaybackSnapshot(
        status: PlaybackStatus.paused,
        position: Duration(seconds: 70),
        duration: Duration(minutes: 5),
        volume: 50,
      ),
    );
    for (final channel in [
      const MethodChannel('window_manager'),
      SystemChannels.platform,
    ]) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (_) async => true);
    }
  });
  tearDown(() async {
    await engine.dispose();
    for (final channel in [
      const MethodChannel('window_manager'),
      SystemChannels.platform,
    ]) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    }
  });

  Widget app({PlayerInputSettings input = const PlayerInputSettings()}) =>
      ProviderScope(
        overrides: [
          playerSettingsProvider.overrideWith(
            () => PlayerSettingsController(
              initialSettings: PlayerSettings(input: input),
            ),
          ),
          playerSessionProvider.overrideWithValue(
            PlaybackSession(
              engine: engine,
              videoBuilder: (_) => const ColoredBox(color: Colors.black),
              maxVolume: 200,
            ),
          ),
        ],
        child: const MaterialApp(home: PlayerPage()),
      );

  Future<void> chord(
    WidgetTester tester,
    LogicalKeyboardKey modifier,
    LogicalKeyboardKey key,
  ) async {
    await tester.sendKeyDownEvent(modifier);
    await tester.sendKeyEvent(key);
    await tester.sendKeyUpEvent(modifier);
    await tester.pump();
  }

  testWidgets('默认定位、修饰键和倍速互不串键，音量及静音沿用会话状态', (tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(engine.lastSeekPosition, const Duration(seconds: 72));
    await chord(
      tester,
      LogicalKeyboardKey.shiftLeft,
      LogicalKeyboardKey.arrowRight,
    );
    expect(engine.lastSeekPosition, const Duration(seconds: 132));
    final seekCount = engine.seekCount;
    await chord(
      tester,
      LogicalKeyboardKey.controlLeft,
      LogicalKeyboardKey.arrowRight,
    );
    await chord(
      tester,
      LogicalKeyboardKey.altLeft,
      LogicalKeyboardKey.arrowRight,
    );
    expect(engine.seekCount, seekCount);
    expect(engine.shortcutActions, [
      PlayerShortcutAction.subtitlesLater,
      PlayerShortcutAction.audioLater,
    ]);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
    await tester.pump();
    expect(engine.lastRate, 1.1);
    await chord(
      tester,
      LogicalKeyboardKey.controlLeft,
      LogicalKeyboardKey.keyC,
    );
    expect(engine.lastRate, 2.2);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
    await tester.pump();
    expect(engine.lastRate, 1);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    expect(engine.lastVolume, 52);
    await chord(
      tester,
      LogicalKeyboardKey.shiftLeft,
      LogicalKeyboardKey.arrowUp,
    );
    expect(engine.lastVolume, 57);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
    await tester.pump();
    expect(engine.lastVolume, 0);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
    await tester.pump();
    expect(engine.lastVolume, 57);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('自定义按键替换默认值，长按只重复连续操作', (tester) async {
    await tester.pumpWidget(
      app(
        input: const PlayerInputSettings(
          bindings: {
            PlayerShortcutAction.togglePause: PlayerKeyBinding(
              LogicalKeyboardKey.f2,
            ),
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    expect(engine.playCount, 0);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.f2);
    await tester.sendKeyRepeatEvent(LogicalKeyboardKey.f2);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.f2);
    await tester.pump();
    expect(engine.playCount, 1);
    expect(engine.pauseCount, 0);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    await tester.sendKeyRepeatEvent(LogicalKeyboardKey.arrowRight);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(engine.seekCount, 2);
    expect(engine.lastSeekPosition, const Duration(seconds: 74));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('鼠标单击暂停、滚轮及右键菜单可用，触屏点按保留控件行为', (tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    final point = tester.getCenter(
      find.byKey(const Key('player_video_region')),
    );
    await tester.tapAt(point, kind: PointerDeviceKind.mouse);
    await tester.pump(const Duration(milliseconds: 350));
    expect(engine.playCount, 1);
    await tester.tapAt(point);
    await tester.pump();
    expect(engine.pauseCount, 0);
    await tester.sendEventToBinding(
      PointerScrollEvent(position: point, scrollDelta: const Offset(0, -120)),
    );
    await tester.pump();
    expect(engine.lastVolume, 52);
    await tester.sendEventToBinding(
      PointerScrollEvent(position: point, scrollDelta: const Offset(-120, 0)),
    );
    await tester.pump();
    expect(engine.lastSeekPosition, const Duration(seconds: 72));
    await tester.tapAt(
      point,
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryMouseButton,
    );
    await tester.pumpAndSettle();
    expect(find.text('单文件循环'), findsOneWidget);
    await tester.tap(find.text('单文件循环'));
    await tester.pumpAndSettle();
    expect(engine.shortcutActions.last, PlayerShortcutAction.loopFile);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('鼠标双击切换全屏且不会触发单击暂停', (tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    final point = tester.getCenter(
      find.byKey(const Key('player_video_region')),
    );
    await tester.tapAt(point, kind: PointerDeviceKind.mouse);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tapAt(point, kind: PointerDeviceKind.mouse);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('fullscreen_exit_back_button')),
      findsOneWidget,
    );
    expect(engine.playCount, 0);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('关闭键盘与鼠标滚轮后不再执行对应操作', (tester) async {
    await tester.pumpWidget(
      app(
        input: const PlayerInputSettings(
          keyboardEnabled: false,
          wheelVolume: false,
          horizontalWheelSeek: false,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    final point = tester.getCenter(
      find.byKey(const Key('player_video_region')),
    );
    await tester.sendEventToBinding(
      PointerScrollEvent(position: point, scrollDelta: const Offset(0, -120)),
    );
    await tester.sendEventToBinding(
      PointerScrollEvent(position: point, scrollDelta: const Offset(-120, 0)),
    );
    await tester.pump();
    expect(engine.playCount, 0);
    expect(engine.setVolumeCount, 0);
    expect(engine.seekCount, 0);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
