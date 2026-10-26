import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:reelva/features/player/domain/playback_resource.dart';
import 'package:reelva/features/player/domain/playback_snapshot.dart';
import 'package:reelva/features/player/domain/player_engine.dart';
import 'package:reelva/features/player/domain/player_shortcuts.dart';
import 'package:reelva/features/progress/application/progress_player_engine.dart';
import 'package:reelva/features/progress/domain/playback_progress.dart';
import 'package:reelva/features/progress/infrastructure/playback_progress_repository.dart';

class _FakeInnerEngine implements PlayerEngine {
  @override
  Future<void> loadSubtitle(PlaybackResource resource) async {}

  PlaybackSnapshot _snapshot = const PlaybackSnapshot();
  final StreamController<PlaybackSnapshot> _controller =
      StreamController<PlaybackSnapshot>.broadcast();

  int openCount = 0;
  int playCount = 0;
  int pauseCount = 0;
  int seekCount = 0;
  int stopCount = 0;
  int disposeCount = 0;
  String? audioTrackId;
  String? subtitleTrackId;
  PlaybackResource? lastResource;
  Duration? lastResumeAt;
  bool isDisposed = false;
  final shortcutActions = <PlayerShortcutAction>[];
  void Function(PlayerShortcutAction)? onShortcut;

  @override
  PlaybackSnapshot get snapshot => _snapshot;

  @override
  Stream<PlaybackSnapshot> get snapshots => _controller.stream;

  void emit(PlaybackSnapshot next) {
    _snapshot = next;
    if (!_controller.isClosed) {
      _controller.add(next);
    }
  }

  @override
  Future<void> open(PlaybackResource resource, {Duration? resumeAt}) async {
    openCount++;
    lastResource = resource;
    lastResumeAt = resumeAt;
    emit(
      PlaybackSnapshot(
        status: PlaybackStatus.playing,
        position: resumeAt ?? Duration.zero,
      ),
    );
  }

  @override
  Future<void> play() async {
    playCount++;
    emit(_snapshot.copyWith(status: PlaybackStatus.playing));
  }

  @override
  Future<void> pause() async {
    pauseCount++;
    emit(_snapshot.copyWith(status: PlaybackStatus.paused));
  }

  @override
  Future<void> seek(Duration position) async {
    seekCount++;
    emit(_snapshot.copyWith(position: position));
  }

  @override
  Future<void> setRate(double rate) async {
    emit(_snapshot.copyWith(rate: rate));
  }

  @override
  Future<void> setVolume(double volume) async {
    emit(_snapshot.copyWith(volume: volume));
  }

  @override
  Future<void> setAudioTrack(String id) async {
    audioTrackId = id;
    emit(_snapshot.copyWith(audioTrackId: () => id));
  }

  @override
  Future<void> setSubtitleTrack(String id) async {
    subtitleTrackId = id;
    emit(_snapshot.copyWith(subtitleTrackId: () => id));
  }

  @override
  Future<void> stop() async {
    stopCount++;
    // 模拟底层播放器在 stop 时将 position 归零
    emit(
      _snapshot.copyWith(status: PlaybackStatus.idle, position: Duration.zero),
    );
  }

  @override
  Future<void> executeShortcut(PlayerShortcutAction action) async {
    shortcutActions.add(action);
    onShortcut?.call(action);
  }

  @override
  Future<void> dispose() async {
    disposeCount++;
    isDisposed = true;
    await _controller.close();
  }
}

class _MockProgressRepository implements PlaybackProgressRepository {
  final Map<int, PlaybackProgress> progressMap = {};
  final List<Map<String, dynamic>> saveCalls = [];
  bool shouldThrowOnSave = false;
  bool shouldThrowOnRead = false;
  Completer<void>? readGate;
  Completer<void>? saveGate;
  int activeWrites = 0;
  int maxActiveWrites = 0;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  @override
  Future<PlaybackProgress?> getProgress(int fileId) async {
    await readGate?.future;
    if (shouldThrowOnRead) throw StateError('storage unavailable');
    return progressMap[fileId];
  }

  @override
  Future<void> saveProgress({
    required int fileId,
    required Duration position,
    required Duration duration,
    bool? completed,
  }) async {
    activeWrites++;
    if (activeWrites > maxActiveWrites) maxActiveWrites = activeWrites;
    try {
      await saveGate?.future;
      if (shouldThrowOnSave) throw StateError('storage unavailable');
      final isCompleted =
          completed ??
          (duration > Duration.zero &&
              position.inMilliseconds >= duration.inMilliseconds * 0.90);
      saveCalls.add({
        'fileId': fileId,
        'position': position,
        'duration': duration,
        'completed': isCompleted,
      });
      progressMap[fileId] = PlaybackProgress(
        targetType: ProgressTargetType.work,
        targetId: fileId,
        lastFileId: fileId,
        position: position,
        duration: duration,
        completed: isCompleted,
        updatedAt: DateTime.now(),
      );
    } finally {
      activeWrites--;
    }
  }
}

void main() {
  group('ProgressPlayerEngine', () {
    late _FakeInnerEngine innerEngine;
    late _MockProgressRepository mockRepo;
    late DateTime currentTime;
    late ProgressPlayerEngine progressEngine;

    setUp(() {
      innerEngine = _FakeInnerEngine();
      mockRepo = _MockProgressRepository();
      currentTime = DateTime(2026, 1, 1, 12, 0, 0);

      progressEngine = ProgressPlayerEngine(
        inner: innerEngine,
        progressRepository: mockRepo,
        clock: () => currentTime,
        throttleInterval: const Duration(seconds: 10),
      );
    });

    tearDown(() async {
      await progressEngine.dispose();
    });

    test('章节和逐帧操作经进度层转发并保存新位置', () async {
      await progressEngine.open(
        PlaybackResource(
          uri: Uri.file('/movie.mkv'),
          displayName: 'Movie',
          libraryFileId: 10,
        ),
      );
      innerEngine.emit(
        const PlaybackSnapshot(
          status: PlaybackStatus.paused,
          position: Duration(seconds: 15),
          duration: Duration(minutes: 10),
        ),
      );
      await Future<void>.delayed(Duration.zero);
      innerEngine.onShortcut = (_) => innerEngine.emit(
        innerEngine.snapshot.copyWith(position: const Duration(seconds: 60)),
      );
      await progressEngine.executeShortcut(PlayerShortcutAction.nextChapter);
      expect(innerEngine.shortcutActions, [PlayerShortcutAction.nextChapter]);
      expect(mockRepo.saveCalls.last['position'], const Duration(seconds: 60));
    });

    test('open restores progress from repository', () async {
      // 预置已有 50 秒进度
      mockRepo.progressMap[10] = PlaybackProgress(
        targetType: ProgressTargetType.work,
        targetId: 100,
        lastFileId: 10,
        position: const Duration(seconds: 50),
        duration: const Duration(seconds: 120),
        completed: false,
        updatedAt: currentTime,
      );

      final resource = PlaybackResource(
        uri: Uri.parse('file:///test.mp4'),
        displayName: 'Test Video',
        libraryFileId: 10,
      );

      await progressEngine.open(resource);

      expect(innerEngine.openCount, 1);
      expect(innerEngine.lastResumeAt, const Duration(seconds: 50));
    });

    test(
      'open restarts from Duration.zero if progress < 5s or completed',
      () async {
        // 1. 进度 < 5s (4s)
        mockRepo.progressMap[11] = PlaybackProgress(
          targetType: ProgressTargetType.work,
          targetId: 101,
          lastFileId: 11,
          position: const Duration(seconds: 4),
          duration: const Duration(seconds: 120),
          completed: false,
          updatedAt: currentTime,
        );

        await progressEngine.open(
          PlaybackResource(
            uri: Uri.parse('file:///short.mp4'),
            displayName: 'Short',
            libraryFileId: 11,
          ),
        );
        expect(innerEngine.lastResumeAt, Duration.zero);

        // 2. 已完播
        mockRepo.progressMap[12] = PlaybackProgress(
          targetType: ProgressTargetType.work,
          targetId: 102,
          lastFileId: 12,
          position: const Duration(seconds: 115),
          duration: const Duration(seconds: 120),
          completed: true,
          updatedAt: currentTime,
        );

        await progressEngine.open(
          PlaybackResource(
            uri: Uri.parse('file:///completed.mp4'),
            displayName: 'Completed',
            libraryFileId: 12,
          ),
        );
        expect(innerEngine.lastResumeAt, Duration.zero);
      },
    );

    test('open bounds restore when saved position exceeds duration', () async {
      // 保存进度 150s，但新版本媒体时长为 100s
      mockRepo.progressMap[13] = PlaybackProgress(
        targetType: ProgressTargetType.work,
        targetId: 103,
        lastFileId: 13,
        position: const Duration(seconds: 150),
        duration: const Duration(seconds: 100),
        completed: false,
        updatedAt: currentTime,
      );

      await progressEngine.open(
        PlaybackResource(
          uri: Uri.parse('file:///new_ver.mp4'),
          displayName: 'New Version',
          libraryFileId: 13,
        ),
      );
      expect(innerEngine.lastResumeAt, Duration.zero);
    });

    test('open respects explicit resumeAt override', () async {
      mockRepo.progressMap[14] = PlaybackProgress(
        targetType: ProgressTargetType.work,
        targetId: 104,
        lastFileId: 14,
        position: const Duration(seconds: 80),
        duration: const Duration(seconds: 120),
        completed: false,
        updatedAt: currentTime,
      );

      await progressEngine.open(
        PlaybackResource(
          uri: Uri.parse('file:///override.mp4'),
          displayName: 'Override',
          libraryFileId: 14,
        ),
        resumeAt: const Duration(seconds: 15),
      );
      expect(innerEngine.lastResumeAt, const Duration(seconds: 15));
    });

    test(
      'direct file without libraryFileId does not save or query history',
      () async {
        await progressEngine.open(
          PlaybackResource(
            uri: Uri.parse('https://example.com/stream.m3u8'),
            displayName: 'Direct Stream',
            libraryFileId: null, // 无库文件 ID
          ),
        );

        innerEngine.emit(
          innerEngine.snapshot.copyWith(
            status: PlaybackStatus.playing,
            position: const Duration(seconds: 30),
            duration: const Duration(seconds: 120),
          ),
        );

        await progressEngine.pause();
        expect(mockRepo.saveCalls, isEmpty);
      },
    );

    test('10s throttle during playing snapshot emissions', () async {
      final resource = PlaybackResource(
        uri: Uri.parse('file:///movie.mp4'),
        displayName: 'Movie',
        libraryFileId: 20,
      );
      await progressEngine.open(resource);

      // 起播时首个快照
      innerEngine.emit(
        innerEngine.snapshot.copyWith(
          status: PlaybackStatus.playing,
          position: const Duration(seconds: 1),
          duration: const Duration(seconds: 120),
        ),
      );
      await Future<void>.delayed(Duration.zero);
      expect(mockRepo.saveCalls.length, 1);
      expect(mockRepo.saveCalls.first['position'], const Duration(seconds: 1));

      // 推进 5 秒（未达 10s 节流窗口）
      currentTime = currentTime.add(const Duration(seconds: 5));
      innerEngine.emit(
        innerEngine.snapshot.copyWith(position: const Duration(seconds: 6)),
      );
      await Future<void>.delayed(Duration.zero);
      expect(mockRepo.saveCalls.length, 1); // 未保存

      // 再推进 6 秒（总共 11s，已达 10s 窗口）
      currentTime = currentTime.add(const Duration(seconds: 6));
      innerEngine.emit(
        innerEngine.snapshot.copyWith(position: const Duration(seconds: 12)),
      );
      await Future<void>.delayed(Duration.zero);
      expect(mockRepo.saveCalls.length, 2);
      expect(mockRepo.saveCalls.last['position'], const Duration(seconds: 12));
    });

    test('dedup: throttle skips write if position change < 1s', () async {
      final resource = PlaybackResource(
        uri: Uri.parse('file:///movie.mp4'),
        displayName: 'Movie',
        libraryFileId: 21,
      );
      await progressEngine.open(resource);

      innerEngine.emit(
        innerEngine.snapshot.copyWith(
          status: PlaybackStatus.playing,
          position: const Duration(seconds: 10),
          duration: const Duration(seconds: 120),
        ),
      );
      await Future<void>.delayed(Duration.zero);
      expect(mockRepo.saveCalls.length, 1);

      // 推进 15 秒，但 position 只变化 200ms
      currentTime = currentTime.add(const Duration(seconds: 15));
      innerEngine.emit(
        innerEngine.snapshot.copyWith(
          position: const Duration(milliseconds: 10200),
        ),
      );
      await Future<void>.delayed(Duration.zero);
      expect(mockRepo.saveCalls.length, 1); // 跳过去重
    });

    test(
      'pause and seek save changed positions without duplicate writes',
      () async {
        await progressEngine.open(
          PlaybackResource(
            uri: Uri.file('movie.mp4'),
            displayName: 'Movie',
            libraryFileId: 22,
          ),
        );
        innerEngine.emit(
          const PlaybackSnapshot(
            status: PlaybackStatus.playing,
            position: Duration(seconds: 25),
            duration: Duration(seconds: 120),
          ),
        );
        await Future<void>.delayed(Duration.zero);
        innerEngine.emit(
          innerEngine.snapshot.copyWith(position: const Duration(seconds: 35)),
        );

        await progressEngine.pause();
        expect(mockRepo.progressMap[22]!.position, const Duration(seconds: 35));
        await progressEngine.seek(const Duration(seconds: 70));
        expect(mockRepo.progressMap[22]!.position, const Duration(seconds: 70));
        final savedCount = mockRepo.saveCalls.length;
        await progressEngine.pause();
        await progressEngine.forceSave();
        await progressEngine.stop();
        await progressEngine.dispose();
        expect(mockRepo.saveCalls.length, savedCount);
      },
    );

    test(
      'stop-zero overwrite prevention preserves last non-zero position',
      () async {
        final resource = PlaybackResource(
          uri: Uri.parse('file:///movie.mp4'),
          displayName: 'Movie',
          libraryFileId: 23,
        );
        await progressEngine.open(resource);

        innerEngine.emit(
          innerEngine.snapshot.copyWith(
            status: PlaybackStatus.playing,
            position: const Duration(seconds: 40),
            duration: const Duration(seconds: 120),
          ),
        );
        await Future<void>.delayed(Duration.zero);
        mockRepo.saveCalls.clear();
        innerEngine.emit(
          innerEngine.snapshot.copyWith(position: const Duration(seconds: 41)),
        );

        // stop 保存尚未到节流间隔的最新位置，随后归零不会覆盖。
        await progressEngine.stop();
        expect(innerEngine.stopCount, 1);
        expect(innerEngine.snapshot.position, Duration.zero);

        expect(mockRepo.saveCalls.isNotEmpty, isTrue);
        expect(
          mockRepo.saveCalls.last['position'],
          const Duration(seconds: 41),
        );
      },
    );

    test('natural completion forces save with completed = true', () async {
      final resource = PlaybackResource(
        uri: Uri.parse('file:///movie.mp4'),
        displayName: 'Movie',
        libraryFileId: 24,
      );
      await progressEngine.open(resource);

      innerEngine.emit(
        innerEngine.snapshot.copyWith(
          status: PlaybackStatus.completed,
          position: const Duration(seconds: 120),
          duration: const Duration(seconds: 120),
        ),
      );
      await Future<void>.delayed(Duration.zero);

      expect(mockRepo.saveCalls.any((c) => c['completed'] == true), isTrue);
    });

    test(
      'old snapshots during resolution cannot become new file progress',
      () async {
        await progressEngine.open(
          PlaybackResource(
            uri: Uri.file('a.mp4'),
            displayName: 'A',
            libraryFileId: 31,
          ),
        );
        innerEngine.emit(
          const PlaybackSnapshot(
            status: PlaybackStatus.playing,
            position: Duration(seconds: 15),
            duration: Duration(seconds: 100),
          ),
        );
        await Future<void>.delayed(Duration.zero);
        mockRepo.readGate = Completer<void>();
        final opening = progressEngine.open(
          PlaybackResource(
            uri: Uri.file('b.mp4'),
            displayName: 'B',
            libraryFileId: 32,
          ),
        );
        innerEngine.emit(
          innerEngine.snapshot.copyWith(position: const Duration(seconds: 18)),
        );
        await Future<void>.delayed(Duration.zero);
        mockRepo.readGate!.complete();
        await opening;
        await progressEngine.pause();

        expect(mockRepo.progressMap[31]!.position, const Duration(seconds: 15));
        expect(mockRepo.progressMap.containsKey(32), isFalse);
      },
    );

    test('recoverable save failure sets progressErrorMessage and clears on recovery', () async {
      final resource = PlaybackResource(
        uri: Uri.parse('file:///movie.mp4'),
        displayName: 'Movie',
        libraryFileId: 40,
      );
      await progressEngine.open(resource);

      // 模拟仓储抛出错误
      mockRepo.shouldThrowOnSave = true;

      innerEngine.emit(
        innerEngine.snapshot.copyWith(
          status: PlaybackStatus.playing,
          position: const Duration(seconds: 30),
          duration: const Duration(seconds: 120),
        ),
      );
      await progressEngine.forceSave();

      // 快照中应包含 progressErrorMessage，且引擎正常运行
      expect(progressEngine.snapshot.progressErrorMessage, isNotNull);
      expect(
        progressEngine.snapshot.progressErrorMessage,
        contains('保存播放进度失败'),
      );

      // 恢复正常
      mockRepo.shouldThrowOnSave = false;
      await progressEngine.forceSave();

      // 错误自动清除
      expect(progressEngine.snapshot.progressErrorMessage, isNull);
    });

    test(
      'dispose saves the latest position inside the throttle window',
      () async {
        await progressEngine.open(
          PlaybackResource(
            uri: Uri.file('movie.mp4'),
            displayName: 'Movie',
            libraryFileId: 51,
          ),
        );
        innerEngine.emit(
          const PlaybackSnapshot(
            status: PlaybackStatus.playing,
            position: Duration(seconds: 10),
            duration: Duration(seconds: 120),
          ),
        );
        await Future<void>.delayed(Duration.zero);
        innerEngine.emit(
          innerEngine.snapshot.copyWith(position: const Duration(seconds: 35)),
        );
        await Future<void>.delayed(Duration.zero);

        await progressEngine.dispose();

        expect(mockRepo.progressMap[51]!.position, const Duration(seconds: 35));
        expect(innerEngine.disposeCount, 1);
      },
    );

    test('seek to start replaces the previous nonzero progress', () async {
      await progressEngine.open(
        PlaybackResource(
          uri: Uri.file('movie.mp4'),
          displayName: 'Movie',
          libraryFileId: 52,
        ),
      );
      innerEngine.emit(
        const PlaybackSnapshot(
          status: PlaybackStatus.playing,
          position: Duration(seconds: 35),
          duration: Duration(seconds: 120),
        ),
      );
      await Future<void>.delayed(Duration.zero);

      await progressEngine.seek(Duration.zero);

      expect(mockRepo.progressMap[52]!.position, Duration.zero);
    });

    test('dispose guarantees inner.dispose() even when save throws', () async {
      final resource = PlaybackResource(
        uri: Uri.parse('file:///movie.mp4'),
        displayName: 'Movie',
        libraryFileId: 50,
      );
      await progressEngine.open(resource);

      innerEngine.emit(
        innerEngine.snapshot.copyWith(
          status: PlaybackStatus.playing,
          position: const Duration(seconds: 50),
          duration: const Duration(seconds: 120),
        ),
      );

      // 退出时保存抛错
      mockRepo.shouldThrowOnSave = true;

      await progressEngine.dispose();

      // 底层引擎依然必须完成释放
      expect(innerEngine.disposeCount, 1);
      expect(innerEngine.isDisposed, isTrue);
    });

    test('slow writes coalesce while pause takes effect immediately', () async {
      await progressEngine.open(
        PlaybackResource(
          uri: Uri.file('movie.mp4'),
          displayName: 'Movie',
          libraryFileId: 61,
        ),
      );
      mockRepo.saveGate = Completer<void>();
      innerEngine.emit(
        const PlaybackSnapshot(
          status: PlaybackStatus.playing,
          position: Duration(seconds: 10),
          duration: Duration(seconds: 120),
        ),
      );
      await Future<void>.delayed(Duration.zero);
      final pausing = progressEngine.pause();
      final seekingFirst = progressEngine.seek(const Duration(seconds: 20));
      await Future<void>.delayed(Duration.zero);
      final seekingLast = progressEngine.seek(const Duration(seconds: 30));
      await Future<void>.delayed(Duration.zero);
      expect(innerEngine.snapshot.status, PlaybackStatus.paused);
      expect(mockRepo.maxActiveWrites, 1);

      mockRepo.saveGate!.complete();
      await Future.wait([pausing, seekingFirst, seekingLast]);

      expect(mockRepo.progressMap[61]!.position, const Duration(seconds: 30));
      expect(mockRepo.saveCalls.map((call) => call['position']), [
        const Duration(seconds: 10),
        const Duration(seconds: 30),
      ]);
      expect(mockRepo.maxActiveWrites, 1);
    });

    test('dispose during progress lookup cannot restart playback', () async {
      mockRepo.readGate = Completer<void>();
      final opening = progressEngine.open(
        PlaybackResource(
          uri: Uri.file('movie.mp4'),
          displayName: 'Movie',
          libraryFileId: 62,
        ),
      );
      await Future<void>.delayed(Duration.zero);
      final closing = progressEngine.dispose();
      mockRepo.readGate!.complete();
      await Future.wait([opening, closing]);
      await progressEngine.dispose();

      expect(innerEngine.openCount, 0);
      expect(innerEngine.disposeCount, 1);
      expect(mockRepo.progressMap.containsKey(62), isFalse);
    });

    test('latest selection wins when progress lookups overlap', () async {
      mockRepo.readGate = Completer<void>();
      final first = progressEngine.open(
        PlaybackResource(
          uri: Uri.file('a.mp4'),
          displayName: 'A',
          libraryFileId: 63,
        ),
      );
      await Future<void>.delayed(Duration.zero);
      final second = progressEngine.open(
        PlaybackResource(
          uri: Uri.file('b.mp4'),
          displayName: 'B',
          libraryFileId: 64,
        ),
      );
      await Future<void>.delayed(Duration.zero);
      mockRepo.readGate!.complete();
      await Future.wait([first, second]);

      expect(innerEngine.openCount, 1);
      expect(innerEngine.lastResource!.libraryFileId, 64);
    });

    test(
      'failed restore is visible and a later successful save recovers',
      () async {
        mockRepo.shouldThrowOnRead = true;
        await progressEngine.open(
          PlaybackResource(
            uri: Uri.file('movie.mp4'),
            displayName: 'Movie',
            libraryFileId: 65,
          ),
        );
        expect(progressEngine.snapshot.status, PlaybackStatus.playing);
        expect(
          progressEngine.snapshot.progressErrorMessage,
          contains('读取观看进度失败'),
        );
        innerEngine.emit(
          const PlaybackSnapshot(
            status: PlaybackStatus.playing,
            position: Duration(seconds: 35),
            duration: Duration(seconds: 120),
          ),
        );
        await progressEngine.pause();

        expect(mockRepo.progressMap[65]!.position, const Duration(seconds: 35));
        expect(progressEngine.snapshot.progressErrorMessage, isNull);
      },
    );
  });
}
