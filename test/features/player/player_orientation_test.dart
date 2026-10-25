import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reelva/features/player/application/player_providers.dart';
import 'package:reelva/features/player/domain/playback_snapshot.dart';
import 'package:reelva/features/player/presentation/player_page.dart';

import 'fake_player_engine.dart';

void main() {
  late List<MethodCall> calls;

  setUp(() {
    calls = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          calls.add(call);
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  Future<void> mount(WidgetTester tester, FakePlayerEngine engine) async {
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
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await engine.dispose();
    });
  }

  List<MethodCall> orientations() => calls
      .where((call) => call.method == 'SystemChrome.setPreferredOrientations')
      .toList();

  testWidgets(
    'Android waits for real dimensions, rotates landscape videos and restores on stop',
    (tester) async {
      final engine = FakePlayerEngine(
        initialSnapshot: const PlaybackSnapshot(status: PlaybackStatus.opening),
      );
      await mount(tester, engine);
      expect(orientations(), isEmpty);

      engine.emit(
        const PlaybackSnapshot(
          status: PlaybackStatus.playing,
          videoWidth: 1920,
          videoHeight: 1080,
        ),
      );
      await tester.pumpAndSettle();
      expect(orientations().single.arguments, [
        'DeviceOrientation.landscapeLeft',
        'DeviceOrientation.landscapeRight',
      ]);
      expect(
        calls
            .where(
              (call) => call.method == 'SystemChrome.setEnabledSystemUIMode',
            )
            .last
            .arguments,
        'SystemUiMode.immersiveSticky',
      );

      engine.emit(
        engine.snapshot.copyWith(position: const Duration(seconds: 3)),
      );
      await tester.pump();
      expect(orientations(), hasLength(1));

      engine.emit(
        engine.snapshot.copyWith(videoWidth: 1080, videoHeight: 1920),
      );
      await tester.pumpAndSettle();
      expect(orientations().last.arguments, ['DeviceOrientation.portraitUp']);

      await engine.stop();
      await tester.pumpAndSettle();
      expect(orientations().last.arguments, isEmpty);
      expect(
        calls
            .where(
              (call) => call.method == 'SystemChrome.setEnabledSystemUIMode',
            )
            .last
            .arguments,
        'SystemUiMode.edgeToEdge',
      );
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );

  testWidgets(
    'Leaving while an orientation request is pending restores system orientation last',
    (tester) async {
      final pending = Completer<void>();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
            calls.add(call);
            if (call.method == 'SystemChrome.setPreferredOrientations' &&
                (call.arguments as List<dynamic>).isNotEmpty) {
              await pending.future;
            }
            return null;
          });
      final engine = FakePlayerEngine(
        initialSnapshot: const PlaybackSnapshot(
          status: PlaybackStatus.playing,
          videoWidth: 1920,
          videoHeight: 1080,
        ),
      );
      await mount(tester, engine);
      expect(orientations(), hasLength(1));
      await tester.pumpWidget(const SizedBox.shrink());
      pending.complete();
      await tester.pumpAndSettle();
      expect(orientations().last.arguments, isEmpty);
      expect(
        calls
            .where(
              (call) => call.method == 'SystemChrome.setEnabledSystemUIMode',
            )
            .last
            .arguments,
        'SystemUiMode.edgeToEdge',
      );
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );
}
