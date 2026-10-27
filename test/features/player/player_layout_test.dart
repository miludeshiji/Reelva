import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reelva/app/theme/reelva_theme.dart';
import 'package:reelva/features/player/application/player_providers.dart';
import 'package:reelva/features/player/domain/playback_resource.dart';
import 'package:reelva/features/player/domain/playback_snapshot.dart';
import 'package:reelva/features/player/infrastructure/media_file_picker.dart';
import 'package:reelva/features/player/presentation/player_controls.dart';
import 'package:reelva/features/player/presentation/player_page.dart';

import 'fake_player_engine.dart';

class _LayoutFilePicker extends MediaFilePicker {
  @override
  Future<PlaybackResource?> pick() async => PlaybackResource(
    uri: Uri.parse('file:///layout-fixture/episode.mkv'),
    displayName: '雾山来信.S01E04.1080p.mkv',
  );
}

const _frameKey = Key('player_layout_video_frame');
const _panelKey = Key('player_controls_panel');
const _videoKey = Key('player_video_region');
const _fullscreenKey = Key('player_fullscreen_button');

Future<void> _mountPlayer(
  WidgetTester tester,
  FakePlayerEngine engine, {
  required Size size,
  double textScale = 1,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await engine.dispose();
  });
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        playerSessionProvider.overrideWithValue(
          createFakeSession(
            engine: engine,
            videoBuilder: (_) =>
                const ColoredBox(key: _frameKey, color: Color(0xFF213C50)),
          ),
        ),
        mediaFilePickerProvider.overrideWithValue(_LayoutFilePicker()),
      ],
      child: MaterialApp(
        theme: ReelvaTheme.light,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: const PlayerPage(),
      ),
    ),
  );
  await tester.pump();
}

double _panelOpacity(WidgetTester tester) => tester
    .widget<AnimatedOpacity>(
      find
          .ancestor(
            of: find.byKey(_panelKey),
            matching: find.byType(AnimatedOpacity),
          )
          .first,
    )
    .opacity;

void main() {
  setUp(() {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('window_manager'),
      (_) async => true,
    );
    messenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (_) async => null,
    );
  });

  tearDown(() {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('window_manager'),
      null,
    );
    messenger.setMockMethodCallHandler(SystemChannels.platform, null);
  });

  for (final viewport in const [
    (size: Size(320, 568), scale: 1.5),
    (size: Size(568, 320), scale: 1.0),
    (size: Size(1440, 1000), scale: 1.0),
  ]) {
    testWidgets(
      'Player states and fullscreen at ${viewport.size}, text scale ${viewport.scale}',
      (tester) async {
        final engine = FakePlayerEngine(
          initialSnapshot: const PlaybackSnapshot(
            duration: Duration(minutes: 2),
            position: Duration(seconds: 30),
            buffered: Duration(minutes: 1),
          ),
        );
        await _mountPlayer(
          tester,
          engine,
          size: viewport.size,
          textScale: viewport.scale,
        );
        final originalFrame = tester.element(
          find.byKey(_frameKey, skipOffstage: false),
        );

        expect(find.byKey(const Key('player_empty_surface')), findsOneWidget);
        expect(find.byType(PlayerControls), findsNothing);
        expect(find.byKey(const Key('player_seek_slider')), findsNothing);
        expect(find.byKey(_fullscreenKey), findsNothing);
        expect(find.byKey(_frameKey), findsNothing);
        expect(
          tester.widget<Scaffold>(find.byType(Scaffold)).backgroundColor,
          ReelvaDesign.background,
        );

        await tester.ensureVisible(
          find.byKey(const Key('idle_open_file_button')),
        );
        await tester.tap(find.byKey(const Key('idle_open_file_button')));
        await tester.pumpAndSettle();
        expect(engine.openCount, 1);

        for (final status in const [
          PlaybackStatus.resolving,
          PlaybackStatus.opening,
          PlaybackStatus.playing,
          PlaybackStatus.buffering,
          PlaybackStatus.error,
          PlaybackStatus.paused,
          PlaybackStatus.completed,
        ]) {
          engine.emit(
            engine.snapshot.copyWith(
              status: status,
              errorMessage: () =>
                  status == PlaybackStatus.error ? '无法播放该视频' : null,
            ),
          );
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 250));
          expect(
            tester.takeException(),
            isNull,
            reason: '$status at ${viewport.size}',
          );
          expect(tester.element(find.byKey(_frameKey)), same(originalFrame));
          expect(find.byKey(const Key('player_empty_surface')), findsNothing);

          final videoRect = tester.getRect(find.byKey(_videoKey));
          final panelRect = tester.getRect(find.byKey(_panelKey));
          expect(videoRect, Offset.zero & viewport.size);
          expect(panelRect.top, greaterThan(videoRect.top));
          expect(panelRect.bottom, lessThanOrEqualTo(videoRect.bottom));
          expect(videoRect.contains(panelRect.topLeft), isTrue);
          expect(
            find.byKey(const Key('player_now_playing_title')),
            findsNothing,
          );
          expect(find.text('媒体库视频'), findsNothing);
          expect(find.byKey(const Key('player_title_text')), findsOneWidget);
          expect(
            Theme.of(
              tester.element(find.byKey(const Key('player_seek_slider'))),
            ).brightness,
            Brightness.dark,
          );
          final back = tester.getCenter(
            find.byKey(const Key('player_previous_episode_button')),
          );
          final forward = tester.getCenter(
            find.byKey(const Key('player_next_episode_button')),
          );
          expect(forward.dx - back.dx, lessThan(150));
          expect(forward.dy, back.dy);

          if (status == PlaybackStatus.resolving ||
              status == PlaybackStatus.opening ||
              status == PlaybackStatus.buffering) {
            expect(
              find.byKey(const Key('player_loading_text')),
              findsOneWidget,
            );
          }
          if (status == PlaybackStatus.error) {
            expect(find.text('无法播放该视频'), findsOneWidget);
            final retry = find.byKey(const Key('player_retry_button'));
            await tester.ensureVisible(retry);
            await tester.tap(retry);
            await tester.pump();
            expect(engine.openCount, 2);
          }
          if (status == PlaybackStatus.completed) {
            expect(
              find.byKey(const Key('center_replay_button')),
              findsOneWidget,
            );
            expect(
              find.byKey(const Key('player_replay_button')),
              findsOneWidget,
            );
          }
        }

        engine.emit(engine.snapshot.copyWith(status: PlaybackStatus.paused));
        await tester.pump();
        expect(find.byKey(const Key('player_stop_button')), findsNothing);
        expect(find.byKey(const Key('player_volume_slider')), findsNothing);
        final volumeButton = find.byKey(const Key('player_volume_button'));
        await tester.tap(volumeButton);
        await tester.pumpAndSettle();
        final volumePanel = tester.getRect(
          find.byKey(const Key('player_volume_panel')),
        );
        expect(volumePanel.left, greaterThanOrEqualTo(0));
        expect(volumePanel.right, lessThanOrEqualTo(viewport.size.width));
        expect(volumePanel.top, greaterThanOrEqualTo(0));
        expect(volumePanel.bottom, lessThan(tester.getRect(volumeButton).top));
        expect(tester.takeException(), isNull);
        await tester.tap(volumeButton);
        await tester.pumpAndSettle();
        final originalControls = tester.state(find.byType(PlayerControls));
        await tester.ensureVisible(find.byKey(_fullscreenKey));
        await tester.tap(find.byKey(_fullscreenKey));
        await tester.pumpAndSettle();

        expect(
          tester.getRect(find.byKey(_videoKey)),
          Offset.zero & viewport.size,
        );
        expect(
          tester.widget<Scaffold>(find.byType(Scaffold)).backgroundColor,
          ReelvaDesign.playerBackground,
        );
        expect(tester.element(find.byKey(_frameKey)), same(originalFrame));
        expect(
          tester.state(find.byType(PlayerControls)),
          same(originalControls),
        );
        expect(engine.openCount, 2);
        expect(engine.isDisposed, isFalse);
        await tester.tap(volumeButton);
        await tester.pumpAndSettle();
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('player_volume_panel')), findsNothing);
        expect(
          find.byKey(const Key('fullscreen_exit_back_button')),
          findsOneWidget,
        );
        await tester.tap(find.byKey(const Key('fullscreen_exit_back_button')));
        await tester.pumpAndSettle();
        expect(
          tester.widget<Scaffold>(find.byType(Scaffold)).backgroundColor,
          ReelvaDesign.playerBackground,
        );
        expect(tester.element(find.byKey(_frameKey)), same(originalFrame));
        expect(
          tester.state(find.byType(PlayerControls)),
          same(originalControls),
        );

        await engine.stop();
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('player_empty_surface')), findsOneWidget);
        expect(find.byType(PlayerControls), findsNothing);
        expect(
          tester.element(find.byKey(_frameKey, skipOffstage: false)),
          same(originalFrame),
        );
        expect(tester.takeException(), isNull);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.windows),
    );
  }

  testWidgets(
    'Overlay hides only during inactive playback and stays visible for hover, menus and status feedback',
    (tester) async {
      final engine = FakePlayerEngine(
        initialSnapshot: const PlaybackSnapshot(status: PlaybackStatus.playing),
      );
      await _mountPlayer(tester, engine, size: const Size(1440, 1000));
      expect(_panelOpacity(tester), 1);
      await tester.pump(const Duration(seconds: 3));
      await tester.pump(const Duration(milliseconds: 250));
      expect(_panelOpacity(tester), 0);
      expect(find.byKey(_panelKey).hitTestable(), findsNothing);

      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: const Offset(1, 1));
      addTearDown(mouse.removePointer);
      await mouse.moveTo(tester.getCenter(find.byKey(_videoKey)));
      await tester.pumpAndSettle();
      expect(_panelOpacity(tester), 1);

      final rate = find.byKey(const Key('player_rate_button'));
      await mouse.moveTo(tester.getCenter(rate));
      await tester.pump(const Duration(seconds: 4));
      expect(_panelOpacity(tester), 1);
      await tester.tap(rate);
      await tester.pumpAndSettle();
      await mouse.moveTo(const Offset(1, 1));
      await tester.pump(const Duration(seconds: 4));
      expect(find.text('1.5x'), findsOneWidget);
      expect(_panelOpacity(tester), 1);
      await tester.tap(find.text('1.5x'));
      await tester.pumpAndSettle();
      expect(engine.lastRate, 1.5);

      for (final status in [
        PlaybackStatus.paused,
        PlaybackStatus.buffering,
        PlaybackStatus.error,
        PlaybackStatus.completed,
      ]) {
        engine.emit(engine.snapshot.copyWith(status: status));
        await tester.pump();
        await tester.pump(const Duration(seconds: 4));
        expect(_panelOpacity(tester), 1, reason: '$status must remain visible');
      }
      engine.emit(
        engine.snapshot.copyWith(
          status: PlaybackStatus.playing,
          progressErrorMessage: () => '保存播放进度失败',
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 4));
      expect(_panelOpacity(tester), 1);
      expect(
        find.byKey(const Key('player_progress_error_banner')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Resizing preserves video and mute state with controls still overlaid',
    (tester) async {
      final engine = FakePlayerEngine(
        initialSnapshot: const PlaybackSnapshot(
          status: PlaybackStatus.playing,
          volume: 75,
        ),
      );
      await _mountPlayer(tester, engine, size: const Size(1440, 1000));
      final controls = tester.state(find.byType(PlayerControls));
      final frame = tester.element(find.byKey(_frameKey));
      final volumeButton = find.byKey(const Key('player_volume_button'));
      await tester.tap(volumeButton);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('player_mute_button')));
      await tester.pump();
      expect(engine.lastVolume, 0);
      await tester.tap(volumeButton);
      await tester.pumpAndSettle();

      tester.view.physicalSize = const Size(390, 844);
      await tester.pumpAndSettle();
      expect(tester.state(find.byType(PlayerControls)), same(controls));
      expect(tester.element(find.byKey(_frameKey)), same(frame));
      await tester.ensureVisible(volumeButton);
      await tester.tap(volumeButton);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('player_mute_button')));
      await tester.pump();
      expect(engine.lastVolume, 75);
      await tester.tap(volumeButton);
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 4));
      await tester.pump(const Duration(milliseconds: 250));
      expect(volumeButton.hitTestable(), findsNothing);
      await tester.tapAt(tester.getCenter(find.byKey(_videoKey)));
      await tester.pumpAndSettle();
      expect(volumeButton.hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Mobile controls toggle on tap and settings stay usable while open',
    (tester) async {
      final engine = FakePlayerEngine(
        initialSnapshot: const PlaybackSnapshot(
          status: PlaybackStatus.playing,
          duration: Duration(minutes: 20),
          volume: 75,
        ),
      );
      await _mountPlayer(tester, engine, size: const Size(390, 844));
      expect(find.byKey(const Key('player_volume_slider')), findsNothing);
      final center = tester.getCenter(find.byKey(_videoKey));
      await tester.tapAt(center);
      await tester.pumpAndSettle();
      expect(_panelOpacity(tester), 0);
      await tester.tapAt(center);
      await tester.pumpAndSettle();
      expect(_panelOpacity(tester), 1);
      await tester.tap(find.byKey(const Key('player_more_button')));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 4));
      expect(_panelOpacity(tester), 1);
      expect(
        find.byKey(const Key('player_subtitle_track_button')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('player_rate_button')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('1.5x'));
      await tester.pumpAndSettle();
      expect(engine.lastRate, 1.5);
      expect(find.byKey(const Key('player_stop_button')), findsNothing);
      expect(find.byKey(const Key('player_volume_slider')), findsNothing);
      await tester.tapAt(const Offset(10, 100));
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsNothing);

      final volumeButton = find.byKey(const Key('player_volume_button'));
      await tester.tap(volumeButton);
      await tester.pumpAndSettle();
      final slider = find.byKey(const Key('player_volume_slider'));
      await tester.drag(slider, const Offset(-25, 0));
      await tester.pump();
      expect(engine.lastVolume, lessThan(75));
      expect(tester.widget<Slider>(slider).value, engine.lastVolume);
      await tester.pump(const Duration(seconds: 4));
      expect(_panelOpacity(tester), 1);
      await tester.tapAt(const Offset(10, 100));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 4));
      await tester.pump(const Duration(milliseconds: 250));
      expect(_panelOpacity(tester), 0);
      await tester.tapAt(center);
      await tester.pumpAndSettle();
      await tester.tap(volumeButton);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('player_volume_panel')), findsOneWidget);
      await tester.tap(volumeButton);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('player_volume_panel')), findsNothing);
      expect(engine.stopCount, 0);
      await tester.pump(const Duration(seconds: 4));
      await tester.pump(const Duration(milliseconds: 250));
      expect(_panelOpacity(tester), 0);
      expect(tester.takeException(), isNull);
    },
  );
}
