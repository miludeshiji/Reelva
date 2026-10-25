import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reelva/app/router.dart';
import 'package:reelva/features/home/application/home_providers.dart';
import 'package:reelva/features/home/home_page.dart';
import 'package:reelva/features/library/domain/library_work.dart';
import 'package:reelva/features/player/application/player_providers.dart';
import 'package:reelva/features/player/domain/playback_resource.dart';
import 'package:reelva/features/player/domain/playback_snapshot.dart';
import 'package:reelva/features/player/infrastructure/media_file_picker.dart';
import 'package:reelva/features/player/presentation/player_page.dart';
import 'package:reelva/features/progress/application/progress_providers.dart';

import 'fake_player_engine.dart';

class StubMediaFilePicker extends MediaFilePicker {
  StubMediaFilePicker({this.result, this.error});

  final PlaybackResource? result;
  final Object? error;
  int pickCallCount = 0;

  @override
  Future<PlaybackResource?> pick() async {
    pickCallCount++;
    if (error != null) {
      throw error!;
    }
    return result;
  }
}

class ControlledMediaFilePicker extends MediaFilePicker {
  final Completer<PlaybackResource?> completer = Completer<PlaybackResource?>();
  int pickCallCount = 0;

  @override
  Future<PlaybackResource?> pick() {
    pickCallCount++;
    return completer.future;
  }
}

void main() {
  const windowManagerChannel = MethodChannel('window_manager');

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(windowManagerChannel, (
          MethodCall methodCall,
        ) async {
          return true;
        });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (
          MethodCall methodCall,
        ) async {
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(windowManagerChannel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  group('PlayerPage Integration & Lifecycle Tests', () {
    testWidgets(
      'Rapid repeated open on Home maintains single player session and returns cleanly',
      (tester) async {
        final fakeEngine = FakePlayerEngine();
        final fakeSession = createFakeSession(engine: fakeEngine);

        final router = createRouter(initialLocation: '/');
        tester.view.physicalSize = const Size(1200, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        try {
          await tester.pumpWidget(
            ProviderScope(
              overrides: [
                continueWatchingProvider.overrideWith(
                  (ref) => Stream.value(const []),
                ),
                recentWorksProvider.overrideWith(
                  (ref) => Stream.value(const [
                    LibraryWork(
                      id: 1,
                      title: '测试电影',
                      year: 2026,
                      versionCount: 1,
                    ),
                  ]),
                ),
                playerSessionProvider.overrideWith((ref) {
                  ref.onDispose(() {
                    fakeEngine.dispose().catchError((_, _) {});
                  });
                  return fakeSession;
                }),
              ],
              child: MaterialApp.router(routerConfig: router),
            ),
          );
          await tester.pumpAndSettle();

          expect(find.byType(HomePage), findsOneWidget);
          expect(find.text('测试电影'), findsWidgets);

          // Rapid repeated taps on the home player entry
          final openPlayer = find.byKey(const Key('home_open_player_fab'));
          expect(openPlayer, findsOneWidget);
          await tester.tap(openPlayer);
          await tester.tap(openPlayer);
          await tester.tap(openPlayer);
          await tester.pumpAndSettle();

          // Ensure exactly one PlayerPage instance is rendered (no stacked duplicates)
          expect(find.byType(PlayerPage), findsOneWidget);

          // Exit once
          final backBtn = find.byKey(const Key('player_back_button'));
          expect(backBtn, findsOneWidget);
          await tester.tap(backBtn);
          await tester.pumpAndSettle();

          // Returns directly to HomePage in one step and releases engine
          expect(find.byType(PlayerPage), findsNothing);
          expect(find.byType(HomePage), findsOneWidget);
          expect(fakeEngine.isDisposed, isTrue);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
          router.dispose();
        }
      },
    );

    testWidgets('Native file selection success opens resource in engine', (
      tester,
    ) async {
      final fakeEngine = FakePlayerEngine();
      final fakeSession = createFakeSession(engine: fakeEngine);
      final stubPicker = StubMediaFilePicker(
        result: PlaybackResource(
          uri: Uri.parse('file:///C:/test/sample.mp4'),
          displayName: 'sample.mp4',
        ),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            playerSessionProvider.overrideWithValue(fakeSession),
            mediaFilePickerProvider.overrideWithValue(stubPicker),
          ],
          child: const MaterialApp(home: PlayerPage()),
        ),
      );
      await tester.pumpAndSettle();

      final idlePickBtn = find.byKey(const Key('idle_open_file_button'));
      expect(idlePickBtn, findsOneWidget);
      await tester.tap(idlePickBtn);
      await tester.pumpAndSettle();

      expect(stubPicker.pickCallCount, 1);
      expect(fakeEngine.openCount, 1);
      expect(fakeEngine.lastOpenedResource?.displayName, 'sample.mp4');
      expect(find.text('sample.mp4'), findsOneWidget);
    });

    testWidgets(
      'Native file selection cancellation safely ignored without error',
      (tester) async {
        final fakeEngine = FakePlayerEngine();
        final fakeSession = createFakeSession(engine: fakeEngine);
        final stubPicker = StubMediaFilePicker(result: null);

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              playerSessionProvider.overrideWithValue(fakeSession),
              mediaFilePickerProvider.overrideWithValue(stubPicker),
            ],
            child: const MaterialApp(home: PlayerPage()),
          ),
        );
        await tester.pumpAndSettle();

        final idlePickBtn = find.byKey(const Key('idle_open_file_button'));
        await tester.tap(idlePickBtn);
        await tester.pumpAndSettle();

        expect(stubPicker.pickCallCount, 1);
        expect(fakeEngine.openCount, 0);
        expect(find.byType(SnackBar), findsNothing);
      },
    );

    testWidgets('Native file selection error visibly displays safe SnackBar', (
      tester,
    ) async {
      final fakeEngine = FakePlayerEngine();
      final fakeSession = createFakeSession(engine: fakeEngine);
      final stubPicker = StubMediaFilePicker(
        error: Exception('Platform file access denied'),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            playerSessionProvider.overrideWithValue(fakeSession),
            mediaFilePickerProvider.overrideWithValue(stubPicker),
          ],
          child: const MaterialApp(home: PlayerPage()),
        ),
      );
      await tester.pumpAndSettle();

      final idlePickBtn = find.byKey(const Key('idle_open_file_button'));
      await tester.tap(idlePickBtn);
      await tester.pumpAndSettle();

      expect(find.byType(SnackBar), findsOneWidget);
    });

    testWidgets(
      'Network URL input rejects invalid schemes and accepts valid HTTP/HTTPS',
      (tester) async {
        final fakeEngine = FakePlayerEngine();
        final fakeSession = createFakeSession(engine: fakeEngine);

        await tester.pumpWidget(
          ProviderScope(
            overrides: [playerSessionProvider.overrideWithValue(fakeSession)],
            child: const MaterialApp(home: PlayerPage()),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('idle_open_url_button')));
        await tester.pumpAndSettle();

        final textField = find.byKey(const Key('network_url_text_field'));
        final confirmBtn = find.byKey(
          const Key('network_dialog_confirm_button'),
        );

        // Invalid ftp scheme
        await tester.enterText(textField, 'ftp://server.example.com/video.mp4');
        await tester.tap(confirmBtn);
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('network_url_text_field')), findsOneWidget);
        expect(fakeEngine.openCount, 0);

        // Valid https URL
        await tester.enterText(
          textField,
          'https://cdn.example.com/stream.m3u8?token=secret123',
        );
        await tester.tap(confirmBtn);
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('network_url_text_field')), findsNothing);
        expect(fakeEngine.openCount, 1);
        expect(fakeEngine.lastOpenedResource?.displayName, '网络视频');
        expect(fakeEngine.lastOpenedResource?.uri.scheme, 'https');
        expect(find.text('网络视频'), findsOneWidget);
      },
    );

    testWidgets(
      'Background state pauses playback with proper lifecycle teardown',
      (tester) async {
        final fakeEngine = FakePlayerEngine(
          initialSnapshot: const PlaybackSnapshot(
            status: PlaybackStatus.playing,
          ),
        );
        final fakeSession = createFakeSession(engine: fakeEngine);

        await tester.pumpWidget(
          ProviderScope(
            overrides: [playerSessionProvider.overrideWithValue(fakeSession)],
            child: const MaterialApp(home: PlayerPage()),
          ),
        );
        await tester.pumpAndSettle();

        addTearDown(() {
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.resumed,
          );
        });

        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        await tester.pump();

        expect(fakeEngine.pauseCount, 1);
      },
    );

    testWidgets(
      'Fullscreen toggle and two-stage back exit using real GoRouter',
      (tester) async {
        final fakeEngine = FakePlayerEngine(
          initialSnapshot: const PlaybackSnapshot(
            status: PlaybackStatus.paused,
          ),
        );
        final fakeSession = createFakeSession(engine: fakeEngine);

        final router = createRouter(initialLocation: '/player');

        try {
          await tester.pumpWidget(
            ProviderScope(
              overrides: [
                continueWatchingProvider.overrideWith(
                  (ref) => Stream.value(const []),
                ),
                recentWorksProvider.overrideWith(
                  (ref) => Stream.value(const []),
                ),
                playerSessionProvider.overrideWithValue(fakeSession),
              ],
              child: MaterialApp.router(routerConfig: router),
            ),
          );
          await tester.pumpAndSettle();

          expect(find.byType(PlayerPage), findsOneWidget);

          // Enter fullscreen
          await tester.ensureVisible(
            find.byKey(const Key('player_fullscreen_button')),
          );
          await tester.tap(find.byKey(const Key('player_fullscreen_button')));
          await tester.pumpAndSettle();

          expect(
            find.byKey(const Key('fullscreen_exit_back_button')),
            findsOneWidget,
          );

          // First back: exits fullscreen only, stays on PlayerPage
          await tester.tap(
            find.byKey(const Key('fullscreen_exit_back_button')),
          );
          await tester.pumpAndSettle();

          expect(
            find.byKey(const Key('fullscreen_exit_back_button')),
            findsNothing,
          );
          expect(find.byType(PlayerPage), findsOneWidget);
          expect(find.byKey(const Key('player_back_button')), findsOneWidget);

          // Second back: exits PlayerPage and navigates to HomePage
          await tester.tap(find.byKey(const Key('player_back_button')));
          await tester.pumpAndSettle();

          expect(find.byType(PlayerPage), findsNothing);
          expect(find.byType(HomePage), findsOneWidget);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
          router.dispose();
        }
      },
    );

    testWidgets('Escape key exits fullscreen', (tester) async {
      final fakeEngine = FakePlayerEngine(
        initialSnapshot: const PlaybackSnapshot(status: PlaybackStatus.paused),
      );
      final fakeSession = createFakeSession(engine: fakeEngine);

      final router = createRouter(initialLocation: '/player');
      addTearDown(router.dispose);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [playerSessionProvider.overrideWithValue(fakeSession)],
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();

      await tester.ensureVisible(
        find.byKey(const Key('player_fullscreen_button')),
      );
      await tester.tap(find.byKey(const Key('player_fullscreen_button')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('fullscreen_exit_back_button')),
        findsOneWidget,
      );

      // Send Escape key
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('fullscreen_exit_back_button')),
        findsNothing,
      );
    });

    testWidgets(
      'Pending file selection returning after page disposal does not throw or open resource',
      (tester) async {
        final fakeEngine = FakePlayerEngine();
        final fakeSession = createFakeSession(engine: fakeEngine);
        final controlledPicker = ControlledMediaFilePicker();

        final router = createRouter(initialLocation: '/player');

        try {
          await tester.pumpWidget(
            ProviderScope(
              overrides: [
                continueWatchingProvider.overrideWith(
                  (ref) => Stream.value(const []),
                ),
                recentWorksProvider.overrideWith(
                  (ref) => Stream.value(const []),
                ),
                playerSessionProvider.overrideWithValue(fakeSession),
                mediaFilePickerProvider.overrideWithValue(controlledPicker),
              ],
              child: MaterialApp.router(routerConfig: router),
            ),
          );
          await tester.pumpAndSettle();

          // 1. Trigger delayed file picker; blocks on completer.future
          await tester.tap(find.byKey(const Key('idle_open_file_button')));
          await tester.pump();
          expect(controlledPicker.pickCallCount, 1);
          expect(fakeEngine.openCount, 0);

          // 2. Navigate away / dispose PlayerPage while picker is still waiting
          router.go('/');
          await tester.pumpAndSettle();

          expect(find.byType(PlayerPage), findsNothing);
          expect(find.byType(HomePage), findsOneWidget);

          // 3. Now complete the pending picker after PlayerPage is already disposed
          controlledPicker.completer.complete(
            PlaybackResource(
              uri: Uri.parse('file:///slow/video.mp4'),
              displayName: 'video.mp4',
            ),
          );
          await tester.pumpAndSettle();

          expect(tester.takeException(), isNull);
          expect(
            fakeEngine.openCount,
            0,
            reason: 'Pending picker resolving after disposal must not invoke open()',
          );
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
          router.dispose();
        }
      },
    );

    testWidgets('Keyboard shortcuts: Space, Arrows, Esc and volume', (
      tester,
    ) async {
      final fakeEngine = FakePlayerEngine(
        initialSnapshot: const PlaybackSnapshot(
          status: PlaybackStatus.playing,
          position: Duration(seconds: 15),
          duration: Duration(minutes: 2),
          volume: 50.0,
        ),
      );
      final fakeSession = createFakeSession(engine: fakeEngine);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [playerSessionProvider.overrideWithValue(fakeSession)],
          child: const MaterialApp(home: PlayerPage()),
        ),
      );
      await tester.pumpAndSettle();

      // Space while playing -> pause
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pumpAndSettle();
      expect(fakeEngine.pauseCount, 1);

      // Set to paused and Space -> play
      fakeEngine.emit(
        fakeEngine.snapshot.copyWith(status: PlaybackStatus.paused),
      );
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pumpAndSettle();
      expect(fakeEngine.playCount, 1);

      // ArrowRight -> seek +10s (15s + 10s = 25s)
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect(fakeEngine.seekCount, 1);
      expect(fakeEngine.lastSeekPosition, const Duration(seconds: 25));

      // ArrowLeft -> seek -10s (25s - 10s = 15s)
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pumpAndSettle();
      expect(fakeEngine.seekCount, 2);
      expect(fakeEngine.lastSeekPosition, const Duration(seconds: 15));

      // ArrowUp -> volume +5 (50 + 5 = 55)
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pumpAndSettle();
      expect(fakeEngine.setVolumeCount, 1);
      expect(fakeEngine.lastVolume, 55.0);

      // ArrowDown -> volume -5 (55 - 5 = 50)
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      expect(fakeEngine.setVolumeCount, 2);
      expect(fakeEngine.lastVolume, 50.0);

      // Seek clamp lower bound (0s):
      fakeEngine.emit(
        fakeEngine.snapshot.copyWith(position: const Duration(seconds: 5)),
      );
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pumpAndSettle();
      expect(fakeEngine.lastSeekPosition, Duration.zero);

      // Seek clamp upper bound (duration = 2m):
      fakeEngine.emit(
        fakeEngine.snapshot.copyWith(position: const Duration(seconds: 115)),
      );
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect(fakeEngine.lastSeekPosition, const Duration(minutes: 2));

      // Volume clamp upper bound (100.0):
      fakeEngine.emit(fakeEngine.snapshot.copyWith(volume: 98.0));
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pumpAndSettle();
      expect(fakeEngine.lastVolume, 100.0);

      // Volume clamp lower bound (0.0):
      fakeEngine.emit(fakeEngine.snapshot.copyWith(volume: 3.0));
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      expect(fakeEngine.lastVolume, 0.0);
    });

    testWidgets(
      'Keyboard shortcuts ignored in invalid states and when input focused',
      (tester) async {
        final fakeEngine = FakePlayerEngine(
          initialSnapshot: const PlaybackSnapshot(
            status: PlaybackStatus.idle,
            position: Duration.zero,
            duration: Duration.zero,
            volume: 50.0,
          ),
        );
        final fakeSession = createFakeSession(engine: fakeEngine);

        await tester.pumpWidget(
          ProviderScope(
            overrides: [playerSessionProvider.overrideWithValue(fakeSession)],
            child: const MaterialApp(home: PlayerPage()),
          ),
        );
        await tester.pumpAndSettle();

        // Idle: Space does not play, Arrows do not seek
        await tester.sendKeyEvent(LogicalKeyboardKey.space);
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
        await tester.pumpAndSettle();

        expect(fakeEngine.playCount, 0);
        expect(fakeEngine.pauseCount, 0);
        expect(fakeEngine.seekCount, 0);

        // Open Network Address Dialog (which contains a TextField)
        await tester.tap(find.byKey(const Key('idle_open_url_button')));
        await tester.pumpAndSettle();
        expect(find.byType(TextField), findsOneWidget);

        // Send Space and Arrow keys while TextField is focused
        final initialPlayCount = fakeEngine.playCount;
        final initialSeekCount = fakeEngine.seekCount;
        await tester.sendKeyEvent(LogicalKeyboardKey.space);
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
        await tester.pumpAndSettle();

        expect(fakeEngine.playCount, initialPlayCount);
        expect(fakeEngine.seekCount, initialSeekCount);
      },
    );

    testWidgets(
      'initialResource replacement and null clears/switches playback',
      (tester) async {
        final fakeEngine = FakePlayerEngine();
        final fakeSession = createFakeSession(engine: fakeEngine);

        final resource1 = PlaybackResource(
          uri: Uri.parse('file:///video1.mp4'),
          displayName: 'video1.mp4',
        );
        final resource2 = PlaybackResource(
          uri: Uri.parse('file:///video2.mp4'),
          displayName: 'video2.mp4',
        );

        await tester.pumpWidget(
          ProviderScope(
            overrides: [playerSessionProvider.overrideWithValue(fakeSession)],
            child: MaterialApp(home: PlayerPage(initialResource: resource1)),
          ),
        );
        await tester.pumpAndSettle();

        expect(fakeEngine.openCount, 1);
        expect(fakeEngine.lastOpenedResource, resource1);

        // Replace initialResource with resource2
        await tester.pumpWidget(
          ProviderScope(
            overrides: [playerSessionProvider.overrideWithValue(fakeSession)],
            child: MaterialApp(home: PlayerPage(initialResource: resource2)),
          ),
        );
        await tester.pumpAndSettle();

        expect(fakeEngine.openCount, 2);
        expect(fakeEngine.lastOpenedResource, resource2);

        // Replace initialResource with null
        await tester.pumpWidget(
          ProviderScope(
            overrides: [playerSessionProvider.overrideWithValue(fakeSession)],
            child: const MaterialApp(home: PlayerPage(initialResource: null)),
          ),
        );
        await tester.pumpAndSettle();

        expect(fakeEngine.stopCount, 1);
      },
    );

    testWidgets(
      'Windows window close intercepts, awaits engine dispose, then destroys window',
      (tester) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.windows;
        final fakeEngine = FakePlayerEngine();
        final fakeSession = createFakeSession(engine: fakeEngine);

        final windowManagerCalls = <String>[];
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(const MethodChannel('window_manager'), (
              call,
            ) async {
              windowManagerCalls.add(call.method);
              if (call.method == 'isPreventClose') {
                return true;
              }
              return true;
            });

        try {
          await tester.pumpWidget(
            ProviderScope(
              overrides: [playerSessionProvider.overrideWithValue(fakeSession)],
              child: const MaterialApp(home: PlayerPage()),
            ),
          );
          await tester.pumpAndSettle();

          // Initialized prevent close
          expect(windowManagerCalls, contains('setPreventClose'));

          // Simulate native window close event
          final binding =
              TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
          await binding.handlePlatformMessage(
            'window_manager',
            const StandardMethodCodec().encodeMethodCall(
              const MethodCall('onEvent', {'eventName': 'close'}),
            ),
            (data) {},
          );
          await tester.pumpAndSettle();

          // Disposed engine before destroying window
          expect(fakeEngine.isDisposed, isTrue);
          expect(windowManagerCalls.last, 'destroy');

          // Repeated close event is ignored and does not dispose again
          await binding.handlePlatformMessage(
            'window_manager',
            const StandardMethodCodec().encodeMethodCall(
              const MethodCall('onEvent', {'eventName': 'close'}),
            ),
            (data) {},
          );
          await tester.pumpAndSettle();
          expect(fakeEngine.disposeCount, 1);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
          debugDefaultTargetPlatformOverride = null;
        }
      },
    );

    testWidgets('Late picker resolving during window close is ignored', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      final fakeEngine = FakePlayerEngine();
      final fakeSession = createFakeSession(engine: fakeEngine);
      final controlledPicker = ControlledMediaFilePicker();

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(const MethodChannel('window_manager'), (
            call,
          ) async {
            if (call.method == 'isPreventClose') return true;
            return true;
          });

      try {
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              playerSessionProvider.overrideWithValue(fakeSession),
              mediaFilePickerProvider.overrideWithValue(controlledPicker),
            ],
            child: const MaterialApp(home: PlayerPage()),
          ),
        );
        await tester.pumpAndSettle();

        // Trigger picker
        await tester.tap(find.byKey(const Key('idle_open_file_button')));
        await tester.pump();
        expect(controlledPicker.pickCallCount, 1);

        // Trigger window close
        final binding =
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
        await binding.handlePlatformMessage(
          'window_manager',
          const StandardMethodCodec().encodeMethodCall(
            const MethodCall('onEvent', {'eventName': 'close'}),
          ),
          (data) {},
        );
        await tester.pumpAndSettle();

        // Resolve delayed picker
        controlledPicker.completer.complete(
          PlaybackResource(
            uri: Uri.parse('file:///late.mp4'),
            displayName: 'late.mp4',
          ),
        );
        await tester.pumpAndSettle();

        expect(fakeEngine.openCount, 0);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        debugDefaultTargetPlatformOverride = null;
      }
    });
  });
}
