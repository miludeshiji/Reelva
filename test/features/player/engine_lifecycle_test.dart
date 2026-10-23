import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:reelva/features/player/domain/playback_resource.dart';
import 'package:reelva/features/player/domain/playback_snapshot.dart';
import 'package:reelva/features/player/infrastructure/android_media_documents.dart';
import 'package:reelva/features/player/infrastructure/media_kit_player_engine.dart';

import 'test_platform_player.dart';

class FakeAndroidMediaDocuments extends AndroidMediaDocuments {
  FakeAndroidMediaDocuments({this.onOpenRead, this.onClose});

  Future<void> Function(Uri uri)? onOpenRead;
  Future<void> Function(int descriptor)? onClose;

  int _nextFd = 100;
  final List<int> openedFds = [];
  final List<int> closedFds = [];
  final List<String> callLog = [];

  @override
  Future<int> openRead(Uri uri) async {
    callLog.add('documents.openRead($uri)');
    final handler = onOpenRead;
    if (handler != null) {
      await handler(uri);
    }
    final fd = _nextFd++;
    openedFds.add(fd);
    return fd;
  }

  @override
  Future<void> close(int descriptor) async {
    callLog.add('documents.close($descriptor)');
    final handler = onClose;
    if (handler != null) {
      await handler(descriptor);
    }
    closedFds.add(descriptor);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late TestPlatformPlayer platformPlayer;
  late FakeAndroidMediaDocuments documents;
  late Player player;
  late MediaKitPlayerEngine engine;
  late List<String> unifiedAuditLog;

  setUp(() {
    unifiedAuditLog = [];
    platformPlayer = TestPlatformPlayer();
    documents = FakeAndroidMediaDocuments();

    // 跨组件联合事件时间线，精确断言 Player 与 SAF 描述符的相对时序
    platformPlayer.onStop = () async => unifiedAuditLog.add('player.stop');
    platformPlayer.onDispose = () async =>
        unifiedAuditLog.add('player.dispose');
    documents.onClose = (fd) async =>
        unifiedAuditLog.add('documents.close($fd)');
    player = Player(platformPlayer: platformPlayer);
    engine = MediaKitPlayerEngine(player: player, documents: documents);
  });

  tearDown(() async {
    await engine.dispose();
  });

  group('MediaKitPlayerEngine 生命周期、描述符时序与并发竞态', () {
    test('FD 关闭顺序保证: stop 时 Player 必须在 FD 关闭之前先停用', () async {
      final resource = PlaybackResource(
        uri: Uri.parse('content://com.android.providers.media/video/42'),
        displayName: 'SAF视频',
      );

      await engine.open(resource);
      expect(documents.openedFds, [100]);
      expect(documents.closedFds, isEmpty);

      await engine.stop();

      // 验证 Player.stop 严格在 documents.close(100) 之前调用
      final stopIndex = unifiedAuditLog.indexOf('player.stop');
      final closeIndex = unifiedAuditLog.indexOf('documents.close(100)');
      expect(stopIndex, isNot(-1));
      expect(closeIndex, isNot(-1));
      expect(stopIndex, lessThan(closeIndex));
      expect(documents.closedFds, contains(100));
      expect(engine.snapshot.status, PlaybackStatus.idle);
    });
    test('FD 关闭顺序保证: dispose 时 Player 必须在 FD 关闭之前先销毁', () async {
      final resource = PlaybackResource(
        uri: Uri.parse('content://com.android.providers.media/video/10'),
        displayName: '待释放视频',
      );

      await engine.open(resource);

      await engine.dispose();

      // 验证 Player.dispose 严格在 documents.close(100) 之前调用
      final disposeIndex = unifiedAuditLog.indexOf('player.dispose');
      final closeIndex = unifiedAuditLog.indexOf('documents.close(100)');
      expect(disposeIndex, isNot(-1));
      expect(closeIndex, isNot(-1));
      expect(disposeIndex, lessThan(closeIndex));
      expect(documents.closedFds, contains(100));
    });
    test('open 失败时先停止底层并立即释放本次申请的描述符，杜绝泄漏', () async {
      platformPlayer.onOpen = (playable) async {
        throw Exception('Native libmpv open failed');
      };

      final resource = PlaybackResource(
        uri: Uri.parse('content://com.android.providers.media/video/broken'),
        displayName: '损坏SAF媒体',
      );

      await engine.open(resource);

      expect(documents.openedFds, [100]);
      expect(documents.closedFds, [100]);
      expect(engine.snapshot.status, PlaybackStatus.error);
    });

    test(
      'replacement race: open 挂起时新请求接入，Completer 确定性控制时序，最终仅新媒体播放且旧 FD 正确释放',
      () async {
        final enteredA = Completer<void>();
        final completerA = Completer<void>();
        final completerB = Completer<void>();

        final resourceA = PlaybackResource(
          uri: Uri.parse('content://com.android.providers.media/video/A'),
          displayName: '视频A',
        );
        final resourceB = PlaybackResource(
          uri: Uri.parse('content://com.android.providers.media/video/B'),
          displayName: '视频B',
        );

        // 请求 A 在 openRead 时先触发 enteredA，再受 completerA 挂起
        documents.onOpenRead = (uri) async {
          if (uri.path.endsWith('A')) {
            if (!enteredA.isCompleted) {
              enteredA.complete();
            }
            await completerA.future;
          } else if (uri.path.endsWith('B')) {
            await completerB.future;
          }
        };

        final futureA = engine.open(resourceA);
        // 确保 A 已经正式进入 openRead 并分配 FD
        await enteredA.future;

        // 随后发起请求 B 提升 epoch
        final futureB = engine.open(resourceB);

        // 放行请求 A，但此时请求 B 已经提升了 epoch，A 必须被丢弃并关闭 FD
        completerA.complete();
        // 放行请求 B
        completerB.complete();

        await Future.wait([futureA, futureB]);

        // 验证两个 FD 均已分配
        expect(documents.openedFds, [100, 101]);
        // A 分配的 100 必须被关闭
        expect(documents.closedFds, contains(100));
        // B 正在使用 101，不能被关闭
        expect(documents.closedFds, isNot(contains(101)));

        // 底层播放器最终播放的必须是视频 B
        final opened = platformPlayer.lastOpened as Media?;
        expect(opened?.uri, 'fd://101');
      },
    );

    test('close race: open 已进入 native 挂起时调用 dispose，Completer 恢复后必须停止底层并关闭 FD，dispose 完成后无副作用', () async {
      final nativeEntered = Completer<void>();
      final nativeOpenCompleter = Completer<void>();

      platformPlayer.onOpen = (playable) async {
        if (!nativeEntered.isCompleted) {
          nativeEntered.complete();
        }
        await nativeOpenCompleter.future;
      };

      final resource = PlaybackResource(
        uri: Uri.parse('content://com.android.providers.media/video/slow'),
        displayName: '挂起慢速视频',
      );

      final openFuture = engine.open(resource);

      // 先等待 open 确实已经进入 native open
      await nativeEntered.future;

      // 在 native open 挂起期间调用 dispose
      final disposeFuture = engine.dispose();

      // 放行 native open
      nativeOpenCompleter.complete();

      await openFuture;
      await disposeFuture;

      // FD 必须被彻底关闭
      expect(documents.closedFds, [100]);
      // 底层 player 已被 dispose
      expect(platformPlayer.disposeCalled, isTrue);

      // 验证在关闭描述符之前，底层 Player 必定已先执行 stop 或 dispose 停用
      final closeIndex = unifiedAuditLog.indexOf('documents.close(100)');
      expect(closeIndex, isNot(-1));
      final stopIndex = unifiedAuditLog.lastIndexOf('player.stop', closeIndex);
      final disposeIndexBeforeClose = unifiedAuditLog.lastIndexOf(
        'player.dispose',
        closeIndex,
      );
      expect(stopIndex != -1 || disposeIndexBeforeClose != -1, isTrue);
      expect(unifiedAuditLog, contains('player.dispose'));
      // dispose 完成后调用任何控制无副作用
      await engine.play();
      await engine.pause();
      await engine.seek(const Duration(seconds: 5));
    });

    test('并发调用 dispose 返回同一个清理 Future', () {
      final f1 = engine.dispose();
      final f2 = engine.dispose();
      expect(identical(f1, f2), isTrue);
    });
  });
}
