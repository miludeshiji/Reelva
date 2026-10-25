import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:reelva/features/player/domain/playback_resource.dart';
import 'package:reelva/features/player/domain/playback_snapshot.dart';
import 'package:reelva/features/player/infrastructure/media_kit_player_engine.dart';

import '../test_platform_player.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late TestPlatformPlayer platformPlayer;
  late Player player;
  late MediaKitPlayerEngine engine;

  setUp(() {
    platformPlayer = TestPlatformPlayer();
    player = Player(platformPlayer: platformPlayer);
    engine = MediaKitPlayerEngine(player: player);
  });

  tearDown(() async {
    await engine.dispose();
  });

  group('MediaKitPlayerEngine Remote Resource Integration', () {
    test('calls prepare on open and plays concrete lease URI', () async {
      bool prepared = false;
      final concreteUri = Uri.parse('http://127.0.0.1:9090/concrete.mp4');

      final logical = PlaybackResource(
        uri: Uri.parse('reelva-remote://placeholder'),
        displayName: 'Logical Movie',
        prepare: () async {
          prepared = true;
          return PlaybackResource(
            uri: concreteUri,
            displayName: 'Logical Movie',
          );
        },
      );

      await engine.open(logical);

      expect(prepared, isTrue);
      expect(platformPlayer.lastOpened, isA<Media>());
      expect((platformPlayer.lastOpened! as Media).uri, concreteUri.toString());
    });

    test('releases active concrete lease when new media is opened', () async {
      bool firstReleased = false;
      bool secondReleased = false;

      final first = PlaybackResource(
        uri: Uri.parse('http://127.0.0.1/first.mp4'),
        displayName: 'First',
        prepare: () async => PlaybackResource(
          uri: Uri.parse('http://127.0.0.1/first.mp4'),
          displayName: 'First',
          release: () async => firstReleased = true,
        ),
      );

      final second = PlaybackResource(
        uri: Uri.parse('http://127.0.0.1/second.mp4'),
        displayName: 'Second',
        prepare: () async => PlaybackResource(
          uri: Uri.parse('http://127.0.0.1/second.mp4'),
          displayName: 'Second',
          release: () async => secondReleased = true,
        ),
      );

      await engine.open(first);
      expect(firstReleased, isFalse);

      await engine.open(second);
      expect(firstReleased, isTrue);
      expect(secondReleased, isFalse);
    });

    test('releases active concrete lease on stop and dispose', () async {
      bool released = false;

      final resource = PlaybackResource(
        uri: Uri.parse('http://127.0.0.1/stream.mp4'),
        displayName: 'Stream',
        prepare: () async => PlaybackResource(
          uri: Uri.parse('http://127.0.0.1/stream.mp4'),
          displayName: 'Stream',
          release: () async => released = true,
        ),
      );

      await engine.open(resource);
      expect(released, isFalse);

      await engine.stop();
      expect(released, isTrue);
    });

    test(
      'releases stale concrete lease if superseded during prepare',
      () async {
        final prepareCompleter = Completer<PlaybackResource>();
        final prepareStarted = Completer<void>();
        bool staleReleased = false;

        final staleResource = PlaybackResource(
          uri: Uri.parse('http://127.0.0.1/slow.mp4'),
          displayName: 'Slow',
          prepare: () {
            if (!prepareStarted.isCompleted) prepareStarted.complete();
            return prepareCompleter.future;
          },
        );

        final immediateResource = PlaybackResource(
          uri: Uri.parse('http://127.0.0.1/fast.mp4'),
          displayName: 'Fast',
        );

        // 启动第一个慢速 open
        final firstOpenFuture = engine.open(staleResource);
        // 等待排队的 prepare 真正开始执行
        await prepareStarted.future;

        // 启动第二个快速 open，此时第一个仍在 prepare 挂起，epoch 已变更
        final secondOpenFuture = engine.open(immediateResource);

        // 第一个慢速 prepare 终于完成
        prepareCompleter.complete(
          PlaybackResource(
            uri: Uri.parse('http://127.0.0.1/slow.mp4'),
            displayName: 'Slow',
            release: () async => staleReleased = true,
          ),
        );

        await firstOpenFuture;
        await secondOpenFuture;

        // 过时租约必须被立即释放
        expect(staleReleased, isTrue);
        expect(platformPlayer.lastOpened, isA<Media>());
        expect(
          (platformPlayer.lastOpened! as Media).uri,
          'http://127.0.0.1/fast.mp4',
        );
      },
    );

    test(
      'releases stale lease when stop is called during pending prepare',
      () async {
        final prepareCompleter = Completer<PlaybackResource>();
        final prepareStarted = Completer<void>();
        bool staleReleased = false;

        final pendingResource = PlaybackResource(
          uri: Uri.parse('http://127.0.0.1/slow_stop.mp4'),
          displayName: 'Slow Stop',
          prepare: () {
            if (!prepareStarted.isCompleted) prepareStarted.complete();
            return prepareCompleter.future;
          },
        );

        final openFuture = engine.open(pendingResource);
        // 等待排队的 prepare 真正开始执行
        await prepareStarted.future;

        // 启动 stop 任务（此时 stop 队列在 open 之后排队，先递增 _openEpoch）
        final stopFuture = engine.stop();

        // prepare 完成，触发 open 任务检测到 epoch != _openEpoch 并释放租约
        prepareCompleter.complete(
          PlaybackResource(
            uri: Uri.parse('http://127.0.0.1/slow_stop.mp4'),
            displayName: 'Slow Stop',
            release: () async => staleReleased = true,
          ),
        );

        await openFuture;
        await stopFuture;

        expect(staleReleased, isTrue);
        expect(engine.snapshot.status, PlaybackStatus.idle);
      },
    );
    test(
      'calls player.stop before releasing lease when player.open fails',
      () async {
        final lifecycleEvents = <String>[];

        platformPlayer.onOpen = (playable) async {
          throw Exception('底层 open 失败');
        };
        platformPlayer.onStop = () async {
          lifecycleEvents.add('player_stopped');
        };

        final resource = PlaybackResource(
          uri: Uri.parse('http://127.0.0.1/fail_open.mp4'),
          displayName: 'Fail Open',
          prepare: () async => PlaybackResource(
            uri: Uri.parse('http://127.0.0.1/fail_open.mp4'),
            displayName: 'Fail Open',
            release: () async => lifecycleEvents.add('lease_released'),
          ),
        );

        await engine.open(resource);

        expect(engine.snapshot.status, PlaybackStatus.error);
        // Invariant: stop-before-release
        final stopIdx = lifecycleEvents.lastIndexOf('player_stopped');
        final releaseIdx = lifecycleEvents.lastIndexOf('lease_released');
        expect(stopIdx, isNonNegative);
        expect(releaseIdx, isNonNegative);
        expect(stopIdx, lessThan(releaseIdx));
      },
    );

    test('releases active lease when player.play fails', () async {
      platformPlayer.onPlay = () async {
        throw Exception('底层起播异常');
      };
      bool released = false;

      final resource = PlaybackResource(
        uri: Uri.parse('http://127.0.0.1/fail_play.mp4'),
        displayName: 'Fail Play',
        prepare: () async => PlaybackResource(
          uri: Uri.parse('http://127.0.0.1/fail_play.mp4'),
          displayName: 'Fail Play',
          release: () async => released = true,
        ),
      );

      await engine.open(resource);

      expect(engine.snapshot.status, PlaybackStatus.error);
      expect(released, isTrue);
    });

    test('subscribes to errors stream and maps error to snapshot', () async {
      final errorsController = StreamController<String>.broadcast();

      final resource = PlaybackResource(
        uri: Uri.parse('http://127.0.0.1/err.mp4'),
        displayName: 'Error Stream',
        prepare: () async => PlaybackResource(
          uri: Uri.parse('http://127.0.0.1/err.mp4'),
          displayName: 'Error Stream',
          errors: errorsController.stream,
        ),
      );

      await engine.open(resource);
      expect(engine.snapshot.status, isNot(PlaybackStatus.error));

      platformPlayer.emitError('Could not open codec');
      await pumpEventQueue();
      errorsController.add('网络媒体流传输异常，已断开连接');
      await pumpEventQueue();

      platformPlayer.emitPosition(const Duration(seconds: 1));
      platformPlayer.emitBuffering(false);
      await pumpEventQueue();

      expect(engine.snapshot.status, PlaybackStatus.error);
      expect(engine.snapshot.errorMessage, '网络媒体流传输异常，已断开连接');

      await errorsController.close();
    });

    test(
      'safely maps PlaybackResourceException thrown by prepare into snapshot',
      () async {
        final failingResource = PlaybackResource(
          uri: Uri.parse('http://127.0.0.1/missing.mp4'),
          displayName: 'Missing',
          prepare: () async {
            throw const PlaybackResourceException(
              '媒体文件不存在或已移动 (404)',
              code: 'file_missing',
            );
          },
        );

        await engine.open(failingResource);

        expect(engine.snapshot.status, PlaybackStatus.error);
        expect(engine.snapshot.errorMessage, '媒体文件不存在或已移动 (404)');
      },
    );
  });
}
