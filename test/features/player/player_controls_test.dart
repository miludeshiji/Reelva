import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reelva/features/player/domain/playback_snapshot.dart';
import 'package:reelva/features/player/presentation/player_controls.dart';

import 'fake_player_engine.dart';

void main() {
  group('PlayerControls State & Interaction Tests', () {
    testWidgets('没有内嵌轨道也能通过字幕菜单选择本地和源文件', (tester) async {
      final engine = FakePlayerEngine();
      var local = 0;
      var source = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PlayerControls(
              snapshot: const PlaybackSnapshot(status: PlaybackStatus.playing),
              engine: engine,
              isFullscreen: false,
              onToggleFullscreen: () {},
              onPickLocalSubtitle: () {
                local++;
              },
              onPickSourceSubtitle: () {
                source++;
              },
            ),
          ),
        ),
      );
      final menu = find.byKey(const Key('player_subtitle_track_button'));
      await tester.tap(menu);
      await tester.pumpAndSettle();
      await tester.tap(find.text('选择本地字幕'));
      await tester.pumpAndSettle();
      expect(local, 1);
      await tester.tap(menu);
      await tester.pumpAndSettle();
      await tester.tap(find.text('选择媒体源字幕'));
      await tester.pumpAndSettle();
      expect(source, 1);
      expect(engine.setSubtitleTrackCount, 0);
    });

    testWidgets('音量面板遵循会话上限，可调节到 100% 以上', (tester) async {
      const snapshot = PlaybackSnapshot(
        status: PlaybackStatus.paused,
        volume: 150,
      );
      final engine = FakePlayerEngine(initialSnapshot: snapshot);
      addTearDown(engine.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PlayerControls(
              snapshot: snapshot,
              engine: engine,
              maxVolume: 200,
              isFullscreen: false,
              onToggleFullscreen: () {},
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(const Key('player_volume_button')));
      await tester.pumpAndSettle();
      final slider = find.byKey(const Key('player_volume_slider'));
      expect(tester.widget<Slider>(slider).max, 200);
      expect(tester.widget<Slider>(slider).value, 150);
      await tester.tapAt(
        tester.getTopRight(slider) +
            Offset(-30, tester.getSize(slider).height / 2),
      );
      await tester.pump();
      expect(engine.lastVolume, greaterThan(150));
      expect(engine.lastVolume, lessThanOrEqualTo(200));
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets(
      'Controls state transitions: paused, playing, completed, buffering, and error',
      (tester) async {
        final engine = FakePlayerEngine();

        // 1. Paused state -> Play button active, tap triggers engine.play()
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: PlayerControls(
                snapshot: const PlaybackSnapshot(
                  status: PlaybackStatus.paused,
                  duration: Duration(seconds: 100),
                ),
                engine: engine,
                isFullscreen: false,
                onToggleFullscreen: () {},
              ),
            ),
          ),
        );

        expect(find.byKey(const Key('player_play_button')), findsOneWidget);
        expect(find.byKey(const Key('player_pause_button')), findsNothing);
        expect(find.byKey(const Key('player_replay_button')), findsNothing);

        await tester.tap(find.byKey(const Key('player_play_button')));
        await tester.pump();
        expect(engine.playCount, 1);

        // 2. Playing state -> Pause button active, tap triggers engine.pause()
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: PlayerControls(
                snapshot: const PlaybackSnapshot(
                  status: PlaybackStatus.playing,
                  duration: Duration(seconds: 100),
                ),
                engine: engine,
                isFullscreen: false,
                onToggleFullscreen: () {},
              ),
            ),
          ),
        );

        expect(find.byKey(const Key('player_pause_button')), findsOneWidget);
        await tester.tap(find.byKey(const Key('player_pause_button')));
        await tester.pump();
        expect(engine.pauseCount, 1);

        // 3. Completed state -> Replay button active, tap seeks to zero and resumes playback
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: PlayerControls(
                snapshot: const PlaybackSnapshot(
                  status: PlaybackStatus.completed,
                  duration: Duration(seconds: 100),
                ),
                engine: engine,
                isFullscreen: false,
                onToggleFullscreen: () {},
              ),
            ),
          ),
        );

        expect(find.byKey(const Key('player_replay_button')), findsOneWidget);
        await tester.tap(find.byKey(const Key('player_replay_button')));
        await tester.pump();
        expect(engine.seekCount, 1);
        expect(engine.lastSeekPosition, Duration.zero);
        expect(engine.playCount, 2);

        // 4. Resolving / Opening state -> disabled loading indicator
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: PlayerControls(
                snapshot: const PlaybackSnapshot(
                  status: PlaybackStatus.opening,
                  duration: Duration(seconds: 100),
                ),
                engine: engine,
                isFullscreen: false,
                onToggleFullscreen: () {},
              ),
            ),
          ),
        );

        final loadingBtn = tester.widget<IconButton>(
          find.byKey(const Key('player_play_button')),
        );
        expect(loadingBtn.onPressed, isNull);

        // 5. Error state -> play button disabled
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: PlayerControls(
                snapshot: const PlaybackSnapshot(
                  status: PlaybackStatus.error,
                  duration: Duration(seconds: 100),
                ),
                engine: engine,
                isFullscreen: false,
                onToggleFullscreen: () {},
              ),
            ),
          ),
        );

        final errorPlayBtn = tester.widget<IconButton>(
          find.byKey(const Key('player_play_button')),
        );
        expect(errorPlayBtn.onPressed, isNull);
      },
    );

    testWidgets(
      'Seek slider correctly disabled when duration is unknown, idle, or in error',
      (tester) async {
        final engine = FakePlayerEngine();

        // Zero duration
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: PlayerControls(
                snapshot: const PlaybackSnapshot(
                  status: PlaybackStatus.playing,
                  position: Duration.zero,
                  duration: Duration.zero,
                ),
                engine: engine,
                isFullscreen: false,
                onToggleFullscreen: () {},
              ),
            ),
          ),
        );

        var slider = tester.widget<Slider>(
          find.byKey(const Key('player_seek_slider')),
        );
        expect(slider.onChanged, isNull);
        expect(find.text('00:00 / --:--'), findsOneWidget);

        // Error state even with duration
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: PlayerControls(
                snapshot: const PlaybackSnapshot(
                  status: PlaybackStatus.error,
                  duration: Duration(seconds: 120),
                ),
                engine: engine,
                isFullscreen: false,
                onToggleFullscreen: () {},
              ),
            ),
          ),
        );
        slider = tester.widget<Slider>(
          find.byKey(const Key('player_seek_slider')),
        );
        expect(slider.onChanged, isNull);
      },
    );

    testWidgets(
      'Known duration enables local seek preview and commits on change end',
      (tester) async {
        final engine = FakePlayerEngine();

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: PlayerControls(
                snapshot: const PlaybackSnapshot(
                  status: PlaybackStatus.playing,
                  position: Duration(seconds: 30),
                  duration: Duration(seconds: 120),
                  buffered: Duration(seconds: 60),
                ),
                engine: engine,
                isFullscreen: false,
                onToggleFullscreen: () {},
              ),
            ),
          ),
        );

        final sliderFinder = find.byKey(const Key('player_seek_slider'));
        final slider = tester.widget<Slider>(sliderFinder);
        expect(slider.onChanged, isNotNull);
        // Secondary track value in milliseconds
        expect(slider.secondaryTrackValue, 60000.0);

        expect(find.text('00:30 / 02:00'), findsOneWidget);
        expect(find.text('缓冲: 01:00'), findsOneWidget);

        // Dragging slider updates local time display preview without triggering engine.seek
        slider.onChanged!(75000.0);
        await tester.pump();
        expect(find.text('01:15 / 02:00'), findsOneWidget);
        expect(engine.seekCount, 0);

        // Releasing slider issues seek
        slider.onChangeEnd!(75000.0);
        await tester.pump();
        expect(engine.seekCount, 1);
        expect(engine.lastSeekPosition, const Duration(milliseconds: 75000));
      },
    );

    testWidgets(
      'Rate selection triggers engine.setRate with supported options',
      (tester) async {
        final engine = FakePlayerEngine();

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: PlayerControls(
                snapshot: const PlaybackSnapshot(
                  status: PlaybackStatus.playing,
                  rate: 1.0,
                ),
                engine: engine,
                isFullscreen: false,
                onToggleFullscreen: () {},
              ),
            ),
          ),
        );

        expect(find.text('1.0x'), findsOneWidget);

        await tester.tap(find.byKey(const Key('player_rate_button')));
        await tester.pumpAndSettle();

        final rateItem = find.text('1.5x');
        expect(rateItem, findsOneWidget);
        await tester.tap(rateItem);
        await tester.pumpAndSettle();

        expect(engine.setRateCount, 1);
        expect(engine.lastRate, 1.5);
      },
    );

    testWidgets(
      'Volume panel adjusts volume, restores mute level and dismisses on toggle, outside tap and Escape',
      (tester) async {
        const snapshot = PlaybackSnapshot(
          status: PlaybackStatus.playing,
          volume: 80,
        );
        final engine = FakePlayerEngine(initialSnapshot: snapshot);
        addTearDown(engine.dispose);
        final interactions = <bool>[];

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: StreamBuilder<PlaybackSnapshot>(
                stream: engine.snapshots,
                initialData: snapshot,
                builder: (context, state) => PlayerControls(
                  snapshot: state.data!,
                  engine: engine,
                  isFullscreen: false,
                  onToggleFullscreen: () {},
                  onInteractionChanged: interactions.add,
                ),
              ),
            ),
          ),
        );

        final volumeButton = find.byKey(const Key('player_volume_button'));
        final panel = find.byKey(const Key('player_volume_panel'));
        final slider = find.byKey(const Key('player_volume_slider'));
        final mute = find.byKey(const Key('player_mute_button'));
        expect(slider, findsNothing);
        expect(find.byKey(const Key('player_volume_text')), findsNothing);
        expect(find.byKey(const Key('player_stop_button')), findsNothing);

        await tester.tap(volumeButton);
        await tester.pumpAndSettle();
        expect(panel, findsOneWidget);
        expect(find.text('80%'), findsOneWidget);
        expect(engine.setVolumeCount, 0);
        expect(interactions, [true]);

        await tester.tap(mute);
        await tester.pumpAndSettle();
        expect(engine.lastVolume, 0);
        expect(find.text('取消静音'), findsOneWidget);
        expect(tester.widget<Slider>(slider).value, 0);
        expect(
          tester.widget<IconButton>(volumeButton).icon,
          isA<Icon>().having(
            (icon) => icon.icon,
            'icon',
            Icons.volume_off_rounded,
          ),
        );

        await tester.tap(mute);
        await tester.pumpAndSettle();
        expect(engine.setVolumeCount, 2);
        expect(engine.lastVolume, 80);
        expect(find.text('静音'), findsOneWidget);

        await tester.drag(slider, const Offset(-25, 0));
        await tester.pump();
        final adjustedVolume = engine.lastVolume!;
        expect(adjustedVolume, inExclusiveRange(0, 80));
        expect(tester.widget<Slider>(slider).value, adjustedVolume);
        expect(find.text('${adjustedVolume.round()}%'), findsOneWidget);
        await tester.tap(mute);
        await tester.pumpAndSettle();
        expect(engine.lastVolume, 0);
        await tester.tap(mute);
        await tester.pumpAndSettle();
        expect(engine.lastVolume, adjustedVolume);

        await tester.tap(mute);
        await tester.pumpAndSettle();
        await tester.drag(slider, const Offset(25, 0));
        await tester.pump();
        expect(engine.lastVolume, greaterThan(0));
        expect(find.text('静音'), findsOneWidget);

        await tester.tap(volumeButton);
        await tester.pumpAndSettle();
        expect(panel, findsNothing);
        expect(interactions, [true, false]);
        await tester.tap(volumeButton);
        await tester.pumpAndSettle();
        await tester.tapAt(const Offset(10, 10));
        await tester.pumpAndSettle();
        expect(panel, findsNothing);
        await tester.tap(volumeButton);
        await tester.pumpAndSettle();
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(panel, findsNothing);
        expect(interactions, [true, false, true, false, true, false]);
        expect(engine.stopCount, 0);
      },
    );

    testWidgets(
      'Narrow viewport with large text and hour-long duration keeps seek and fullscreen usable',
      (tester) async {
        tester.view.physicalSize = const Size(320, 600);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final engine = FakePlayerEngine();
        addTearDown(engine.dispose);

        await tester.pumpWidget(
          MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: const TextScaler.linear(1.5)),
              child: child!,
            ),
            home: Scaffold(
              body: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: PlayerControls(
                  snapshot: const PlaybackSnapshot(
                    status: PlaybackStatus.playing,
                    position: Duration(minutes: 18, seconds: 24),
                    duration: Duration(hours: 2, minutes: 16),
                    buffered: Duration(minutes: 28),
                    volume: 90.0,
                    rate: 1.25,
                  ),
                  engine: engine,
                  isFullscreen: false,
                  onToggleFullscreen: () {},
                ),
              ),
            ),
          ),
        );

        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.text('18:24 / 2:16:00'), findsOneWidget);
        final slider = find.byKey(const Key('player_seek_slider'));
        expect(slider.hitTestable(), findsOneWidget);
        expect(
          find.byKey(const Key('player_fullscreen_button')).hitTestable(),
          findsOneWidget,
        );
        await tester.drag(slider, const Offset(60, 0));
        await tester.pump();
        expect(engine.seekCount, 1);
        expect(
          engine.lastSeekPosition,
          greaterThan(const Duration(minutes: 18, seconds: 24)),
        );
      },
    );

    testWidgets(
      'Audio and subtitle track menus trigger engine track selection',
      (tester) async {
        final engine = FakePlayerEngine();
        const audioTracks = [
          PlaybackTrack(id: 'auto', label: '自动'),
          PlaybackTrack(id: '1', label: '英语 5.1'),
          PlaybackTrack(id: '2', label: '国语配音'),
        ];
        const subtitleTracks = [
          PlaybackTrack(id: 'no', label: '关闭字幕'),
          PlaybackTrack(id: 'sub-1', label: '简体中文'),
        ];

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: PlayerControls(
                snapshot: const PlaybackSnapshot(
                  status: PlaybackStatus.playing,
                  position: Duration(seconds: 10),
                  duration: Duration(minutes: 5),
                  audioTracks: audioTracks,
                  subtitleTracks: subtitleTracks,
                  audioTrackId: '1',
                  subtitleTrackId: 'no',
                ),
                engine: engine,
                isFullscreen: false,
                onToggleFullscreen: () {},
              ),
            ),
          ),
        );

        // Audio track popup
        final audioBtn = find.byKey(const Key('player_audio_track_button'));
        expect(audioBtn, findsOneWidget);
        await tester.tap(audioBtn);
        await tester.pumpAndSettle();

        expect(find.text('国语配音'), findsOneWidget);
        await tester.tap(find.text('国语配音'));
        await tester.pumpAndSettle();

        expect(engine.setAudioTrackCount, 1);
        expect(engine.lastAudioTrackId, '2');

        // Subtitle track popup
        final subtitleBtn = find.byKey(
          const Key('player_subtitle_track_button'),
        );
        expect(subtitleBtn, findsOneWidget);
        await tester.tap(subtitleBtn);
        await tester.pumpAndSettle();

        expect(find.text('简体中文'), findsOneWidget);
        await tester.tap(find.text('简体中文'));
        await tester.pumpAndSettle();

        expect(engine.setSubtitleTrackCount, 1);
        expect(engine.lastSubtitleTrackId, 'sub-1');
      },
    );

    testWidgets('Nonfatal progressErrorMessage displays in banner safely', (
      tester,
    ) async {
      final engine = FakePlayerEngine();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PlayerControls(
              snapshot: const PlaybackSnapshot(
                status: PlaybackStatus.playing,
                position: Duration(seconds: 10),
                duration: Duration(minutes: 5),
                progressErrorMessage: '保存播放进度失败：磁盘空间不足',
              ),
              engine: engine,
              isFullscreen: false,
              onToggleFullscreen: () {},
            ),
          ),
        ),
      );

      expect(
        find.byKey(const Key('player_progress_error_banner')),
        findsOneWidget,
      );
      expect(find.text('保存播放进度失败：磁盘空间不足'), findsOneWidget);
    });
  });
}
