import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:reelva/features/player/domain/playback_resource.dart';
import 'package:reelva/features/player/domain/playback_snapshot.dart';
import 'package:reelva/features/player/infrastructure/android_media_documents.dart';
import 'package:reelva/features/player/infrastructure/media_kit_player_engine.dart';

import 'test_platform_player.dart';

class ErrorThrowingDocuments extends AndroidMediaDocuments {
  const ErrorThrowingDocuments(this.exception);
  final MediaDocumentException exception;

  @override
  Future<int> openRead(Uri uri) async => throw exception;
}

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

  group('MediaKitPlayerEngine 状态演进与错误管理', () {
    test('open 正确传递 URI 与 httpHeaders，且 resource.toString() 脱敏不漏凭据', () async {
      final resource = PlaybackResource(
        uri: Uri.parse('https://example.com/live/stream.m3u8?token=secret123'),
        displayName: '测试加密流',
        httpHeaders: const {
          'Authorization': 'Bearer confidential_token',
          'X-Custom-Header': 'CustomValue',
        },
      );

      expect(resource.toString(), contains('测试加密流'));
      expect(resource.toString(), isNot(contains('secret123')));
      expect(resource.toString(), isNot(contains('confidential_token')));

      await engine.open(resource);

      final opened = platformPlayer.lastOpened as Media?;
      expect(opened, isNotNull);
      expect(
        opened!.httpHeaders?['Authorization'],
        'Bearer confidential_token',
      );
      expect(opened.httpHeaders?['X-Custom-Header'], 'CustomValue');
    });

    test(
      'buffering 与 isPlaying 语义: 播放中缓冲时 isPlaying 为 true，已暂停时保持 paused',
      () async {
        final resource = PlaybackResource(
          uri: Uri.parse('https://example.com/video.mp4'),
          displayName: '电影视频',
        );
        await engine.open(resource);

        // 播放中缓冲
        platformPlayer.emitBuffering(true);
        final bufSnap = await engine.snapshots.firstWhere(
          (s) => s.status == PlaybackStatus.buffering,
        );
        expect(bufSnap.isPlaying, isTrue);

        // 缓冲结束继续播放
        platformPlayer.emitBuffering(false);
        final playSnap = await engine.snapshots.firstWhere(
          (s) => s.status == PlaybackStatus.playing,
        );
        expect(playSnap.isPlaying, isTrue);

        // 暂停后，即使底层产生缓冲也必须保持 paused
        await engine.pause();
        expect(engine.snapshot.status, PlaybackStatus.paused);
        expect(engine.snapshot.isPlaying, isFalse);

        platformPlayer.emitBuffering(true);
        await Future<void>.delayed(Duration.zero);
        expect(engine.snapshot.status, PlaybackStatus.paused);
        expect(engine.snapshot.isPlaying, isFalse);
      },
    );

    test(
      'loaded-before-error: 播放中发生错误时保留已知时长进度，后续位置/缓冲 tick 绝不覆盖 error',
      () async {
        final resource = PlaybackResource(
          uri: Uri.parse('https://example.com/video.mp4'),
          displayName: '电影视频',
        );

        await engine.open(resource);

        platformPlayer.emitDuration(const Duration(minutes: 90));
        platformPlayer.emitPosition(const Duration(minutes: 12, seconds: 30));
        platformPlayer.emitBuffering(false);

        final loadedSnap = await engine.snapshots.firstWhere(
          (s) =>
              s.duration == const Duration(minutes: 90) &&
              s.position == const Duration(minutes: 12, seconds: 30) &&
              s.status == PlaybackStatus.playing,
        );
        expect(loadedSnap.position, const Duration(minutes: 12, seconds: 30));

        platformPlayer.emitError(
          'Server connection reset: 504 Gateway Timeout',
        );

        final errSnap = await engine.snapshots.firstWhere(
          (s) => s.status == PlaybackStatus.error,
        );
        expect(errSnap.duration, const Duration(minutes: 90));
        expect(errSnap.position, const Duration(minutes: 12, seconds: 30));
        expect(errSnap.errorMessage, isNotNull);

        // 验证终态稳定性：后续底层位置或缓冲更新不得将 status 还原
        platformPlayer.emitPosition(const Duration(minutes: 12, seconds: 31));
        platformPlayer.emitBuffering(false);
        await Future<void>.delayed(Duration.zero);

        expect(engine.snapshot.status, PlaybackStatus.error);
        expect(engine.snapshot.errorMessage, isNotNull);
      },
    );

    test('terminal error state stability: 错误状态下 play/pause/seek 不覆盖错误，stop 重置为 idle', () async {
      final resource = PlaybackResource(
        uri: Uri.parse('https://example.com/broken.mp4'),
        displayName: '损坏文件',
      );

      await engine.open(resource);
      platformPlayer.emitError(
        'Demuxer error: Could not find codec parameters',
      );

      final errSnap = await engine.snapshots.firstWhere(
        (s) => s.status == PlaybackStatus.error,
      );
      expect(errSnap.errorMessage, isNotNull);

      await engine.play();
      expect(engine.snapshot.status, PlaybackStatus.error);

      await engine.pause();
      expect(engine.snapshot.status, PlaybackStatus.error);

      await engine.seek(const Duration(seconds: 10));
      expect(engine.snapshot.status, PlaybackStatus.error);

      await engine.stop();
      expect(engine.snapshot.status, PlaybackStatus.idle);
      expect(engine.snapshot.errorMessage, isNull);
    });

    test('idle 期间忽略底层错误流，不将 idle 错变为 error', () async {
      expect(engine.snapshot.status, PlaybackStatus.idle);

      platformPlayer.emitError('late cleanup error');
      await Future<void>.delayed(Duration.zero);

      expect(engine.snapshot.status, PlaybackStatus.idle);
      expect(engine.snapshot.errorMessage, isNull);
    });

    test('pause/seek/rate/volume 异常时向 UI 反馈安全错误状态', () async {
      final resource = PlaybackResource(
        uri: Uri.parse('https://example.com/video.mp4'),
        displayName: '正常视频',
      );
      await engine.open(resource);

      platformPlayer.onPause = () async {
        throw Exception('Native pause failed with error');
      };

      await engine.pause();
      expect(engine.snapshot.status, PlaybackStatus.error);
      expect(engine.snapshot.errorMessage, isNotNull);
    });

    test('MediaDocumentException.code 精准映射权限及文件异常', () async {
      const docException = MediaDocumentException(
        '系统拒绝',
        code: 'SECURITY_ERROR',
      );
      final docEngine = MediaKitPlayerEngine(
        player: player,
        documents: const ErrorThrowingDocuments(docException),
      );
      addTearDown(docEngine.dispose);

      final resource = PlaybackResource(
        uri: Uri.parse('content://com.android.providers.media/video/secret'),
        displayName: '受保护媒体',
      );

      await docEngine.open(resource);

      expect(docEngine.snapshot.status, PlaybackStatus.error);
      expect(docEngine.snapshot.errorMessage, isNotNull);
    });
  });
}
