import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reelva/app/router.dart';
import 'package:reelva/features/home/home_page.dart';
import 'package:reelva/features/player/application/player_providers.dart';
import 'package:reelva/features/player/domain/playback_resource.dart';
import 'package:reelva/features/player/domain/playback_snapshot.dart';
import 'package:reelva/features/player/infrastructure/media_file_picker.dart';
import 'package:reelva/features/player/presentation/player_page.dart';

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
        addTearDown(router.dispose);

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
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
        expect(find.widgetWithText(FilledButton, '前往媒体源'), findsOneWidget);

        // Rapid repeated taps on FAB
        final fab = find.byKey(const Key('home_open_player_fab'));
        expect(fab, findsOneWidget);
        await tester.tap(fab);
        await tester.tap(fab);
        await tester.tap(fab);
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
        final fakeEngine = FakePlayerEngine();
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

        expect(find.byType(PlayerPage), findsOneWidget);

        // Enter fullscreen
        await tester.tap(find.byKey(const Key('player_fullscreen_button')));
        await tester.pumpAndSettle();

        expect(
          find.byKey(const Key('fullscreen_exit_back_button')),
          findsOneWidget,
        );

        // First back: exits fullscreen only, stays on PlayerPage
        await tester.tap(find.byKey(const Key('fullscreen_exit_back_button')));
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
      },
    );

    testWidgets('Escape key exits fullscreen', (tester) async {
      final fakeEngine = FakePlayerEngine();
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
        addTearDown(router.dispose);

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
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
          reason:
              'Pending picker resolving after disposal must not invoke open()',
        );
      },
    );
  });
}
