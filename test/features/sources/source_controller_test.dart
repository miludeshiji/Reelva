import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reelva/core/database/app_database.dart';
import 'package:reelva/features/library/infrastructure/media_library_repository.dart';
import 'package:reelva/features/metadata/application/metadata_providers.dart';
import 'package:reelva/features/player/domain/playback_resource.dart';
import 'package:reelva/features/progress/infrastructure/playback_progress_repository.dart';
import 'package:reelva/features/sources/application/source_providers.dart';
import 'package:reelva/features/sources/domain/media_source_adapter.dart';
import 'package:reelva/features/sources/domain/source_models.dart';

class _CountingMetadataController extends MetadataController {
  int refreshCount = 0;
  @override
  Future<void> refresh() async {
    refreshCount++;
  }
}

class FakeMediaSourceAdapter implements MediaSourceAdapter {
  FakeMediaSourceAdapter({
    this.kind = 'local',
    this.directorySelection,
    Map<String, List<MediaEntry>>? entriesByDir,
    this.listError,
    this.delayPerEntry,
  }) : entriesByDir = entriesByDir ?? {};

  @override
  final String kind;

  DirectorySelection? directorySelection;
  final Map<String, List<MediaEntry>> entriesByDir;
  Object? listError;
  Duration? delayPerEntry;
  Completer<void>? scanGate;

  int listEntriesCallCount = 0;
  final List<String> requestedDirectories = [];

  @override
  Future<DirectorySelection?> pickDirectory({String? initialLocator}) async {
    return directorySelection;
  }

  @override
  Stream<MediaEntry> listEntries(
    MediaSourceConfig source,
    String directoryId,
  ) async* {
    listEntriesCallCount++;
    requestedDirectories.add(directoryId);
    if (scanGate != null) await scanGate!.future;

    if (listError != null) {
      throw listError!;
    }

    final entries = entriesByDir[directoryId] ?? [];
    for (final entry in entries) {
      if (delayPerEntry != null) {
        await Future<void>.delayed(delayPerEntry!);
      }
      yield entry;
    }
  }

  @override
  Future<MediaStat> stat(MediaSourceConfig source, String entryId) async {
    return MediaStat(
      size: 1024,
      modifiedAt: DateTime.fromMillisecondsSinceEpoch(
        1600000000000,
        isUtc: true,
      ),
    );
  }

  @override
  Future<PlaybackResource> resolvePlayback(
    MediaSourceConfig source,
    String entryId,
  ) async {
    return PlaybackResource(
      uri: Uri.parse('file:///videos/$entryId'),
      displayName: entryId,
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late MediaLibraryRepository repo;
  late FakeMediaSourceAdapter fakeAdapter;
  late ProviderContainer container;
  late _CountingMetadataController metadata;

  setUp(() {
    db = AppDatabase(executor: NativeDatabase.memory());
    repo = MediaLibraryRepository(db);
    fakeAdapter = FakeMediaSourceAdapter();
    metadata = _CountingMetadataController();

    container = ProviderContainer(
      overrides: [
        platformOverrideProvider.overrideWithValue(TargetPlatform.windows),
        appDatabaseProvider.overrideWithValue(db),
        mediaLibraryRepositoryProvider.overrideWithValue(repo),
        sourceAdaptersProvider.overrideWithValue({'local': fakeAdapter}),
        metadataControllerProvider.overrideWith(() => metadata),
      ],
    );
  });

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  group('SourceController', () {
    test('绑定已有索引时添加目录不触发首次扫描', () async {
      fakeAdapter.directorySelection = const DirectorySelection(
        kind: 'local',
        rootLocator: '/indexed',
        name: '已同步目录',
      );
      final source = await container
          .read(sourceControllerProvider.notifier)
          .addDirectory(scanAfterAdd: false);
      expect(source, isNotNull);
      expect(fakeAdapter.listEntriesCallCount, 0);
      expect(container.read(sourceControllerProvider), isEmpty);
    });
    test('源扫描完成后不自动触发元数据匹配', () async {
      final source = await repo.upsertSource(
        kind: 'local',
        rootLocator: '/manual-refresh',
        name: '媒体',
      );
      await container
          .read(sourceControllerProvider.notifier)
          .refreshSource(source.id);
      expect(
        container.read(sourceControllerProvider)[source.id]!.running,
        isFalse,
      );
      expect(metadata.refreshCount, 0);
    });
    test('initial state is empty', () {
      final state = container.read(sourceControllerProvider);
      expect(state, isEmpty);
    });

    test('addDirectory quietly exits when user cancels picker', () async {
      fakeAdapter.directorySelection = null;
      final controller = container.read(sourceControllerProvider.notifier);

      expect(await controller.addDirectory(), isNull);

      final sources = await repo.watchSources().first;
      expect(sources, isEmpty);
      expect(container.read(sourceControllerProvider), isEmpty);
    });

    test(
      'addDirectory saves and returns while the initial scan is pending',
      () async {
        fakeAdapter.scanGate = Completer<void>();
        fakeAdapter.directorySelection = const DirectorySelection(
          kind: 'local',
          rootLocator: '/movies',
          name: 'Movies',
        );
        fakeAdapter.entriesByDir['/movies'] = [
          const MediaEntry(
            externalId: 'avatar.mp4',
            locator: 'Avatar.mp4',
            name: 'Avatar.mp4',
            isDirectory: false,
            size: 2000,
          ),
        ];

        final controller = container.read(sourceControllerProvider.notifier);
        final created = await controller.addDirectory();

        final sources = await repo.watchSources().first;
        expect(sources.length, 1);
        final source = sources.first;
        expect(created?.id, source.id);
        expect(source.name, 'Movies');
        expect(source.rootLocator, '/movies');

        expect(
          container.read(sourceControllerProvider)[source.id]!.running,
          isTrue,
        );
        fakeAdapter.scanGate!.complete();
        await controller.refreshSource(source.id);

        final progress = container.read(sourceControllerProvider)[source.id];
        expect(progress, isNotNull);
        expect(progress!.running, isFalse);
        expect(progress.videos, 1);
        expect(progress.visited, 1);

        final videos = await repo.watchLibrary().first;
        expect(videos.length, 1);
        expect(videos.first.fileName, 'Avatar.mp4');
      },
    );

    test(
      'refreshSource deduplicates concurrent calls (single flight)',
      () async {
        final source = await repo.upsertSource(
          kind: 'local',
          rootLocator: '/shared',
          name: 'Shared',
        );

        fakeAdapter.delayPerEntry = const Duration(milliseconds: 30);
        fakeAdapter.entriesByDir['/shared'] = [
          const MediaEntry(
            externalId: 'video1.mkv',
            locator: 'video1.mkv',
            name: 'video1.mkv',
            isDirectory: false,
          ),
          const MediaEntry(
            externalId: 'video2.mkv',
            locator: 'video2.mkv',
            name: 'video2.mkv',
            isDirectory: false,
          ),
        ];

        final controller = container.read(sourceControllerProvider.notifier);

        // 连续发起两个刷新操作
        final f1 = controller.refreshSource(source.id);
        final f2 = controller.refreshSource(source.id);

        await Future.wait([f1, f2]);

        // 由于单飞机制，对该目录仅遍历一次
        expect(fakeAdapter.listEntriesCallCount, 1);
        final progress = container.read(sourceControllerProvider)[source.id];
        expect(progress!.running, isFalse);
        expect(progress.videos, 2);
      },
    );

    test('refreshSource recurses into subdirectories and filters non-video/hidden/excluded', () async {
      final source = await repo.upsertSource(
        kind: 'local',
        rootLocator: '/root',
        name: 'Root',
      );

      fakeAdapter.entriesByDir['/root'] = [
        // 隐藏文件应跳过
        const MediaEntry(
          externalId: '.hidden.mp4',
          locator: '.hidden.mp4',
          name: '.hidden.mp4',
          isDirectory: false,
        ),
        // 非视频文件应跳过
        const MediaEntry(
          externalId: 'info.txt',
          locator: 'info.txt',
          name: 'info.txt',
          isDirectory: false,
        ),
        // 排除目录应跳过
        const MediaEntry(
          externalId: '.cache',
          locator: '.cache',
          name: '.cache',
          isDirectory: true,
        ),
        // 正常子目录
        const MediaEntry(
          externalId: 'anime',
          locator: 'Anime',
          name: 'Anime',
          isDirectory: true,
        ),
        // 根目录下的视频
        const MediaEntry(
          externalId: 'movie.mp4',
          locator: 'movie.mp4',
          name: 'movie.mp4',
          isDirectory: false,
        ),
      ];

      fakeAdapter.entriesByDir['anime'] = [
        const MediaEntry(
          externalId: 'anime/ep1.mkv',
          locator: 'Anime/ep1.mkv',
          name: 'ep1.mkv',
          isDirectory: false,
        ),
        const MediaEntry(
          externalId: 'anime/sub.srt',
          locator: 'Anime/sub.srt',
          name: 'sub.srt',
          isDirectory: false,
        ),
      ];

      final controller = container.read(sourceControllerProvider.notifier);
      await controller.refreshSource(source.id);

      final progress = container.read(sourceControllerProvider)[source.id];
      expect(progress!.videos, 2); // movie.mp4, ep1.mkv
      expect(progress.visited, 2); // /root, anime

      final library = await repo.watchLibrary().first;
      expect(library.length, 2);
      final names = library.map((v) => v.fileName).toList()..sort();
      expect(names, ['ep1.mkv', 'movie.mp4']);
    });

    test(
      'cancelScan stops traversal and does not mark existing rows missing',
      () async {
        final source = await repo.upsertSource(
          kind: 'local',
          rootLocator: '/big_dir',
          name: 'BigDir',
        );

        // 初次成功扫描
        fakeAdapter.entriesByDir['/big_dir'] = [
          const MediaEntry(
            externalId: 'v1.mp4',
            locator: 'v1.mp4',
            name: 'v1.mp4',
            isDirectory: false,
          ),
          const MediaEntry(
            externalId: 'v2.mp4',
            locator: 'v2.mp4',
            name: 'v2.mp4',
            isDirectory: false,
          ),
        ];
        final controller = container.read(sourceControllerProvider.notifier);
        await controller.refreshSource(source.id);

        var library = await repo.watchLibrary().first;
        expect(library.length, 2);
        expect(library.every((v) => v.available), isTrue);

        // 第二次扫描：加入延迟并中途取消
        fakeAdapter.delayPerEntry = const Duration(milliseconds: 50);
        fakeAdapter.entriesByDir['/big_dir'] = [
          const MediaEntry(
            externalId: 'v1.mp4',
            locator: 'v1.mp4',
            name: 'v1.mp4',
            isDirectory: false,
          ),
          const MediaEntry(
            externalId: 'v3.mp4',
            locator: 'v3.mp4',
            name: 'v3.mp4',
            isDirectory: false,
          ),
        ];

        final v2Video = library.firstWhere((v) => v.fileName == 'v2.mp4');
        final progressRepo = PlaybackProgressRepository(db: db);
        await progressRepo.saveProgress(
          fileId: v2Video.fileId,
          position: const Duration(seconds: 40),
          duration: const Duration(seconds: 120),
        );

        final refreshFuture = controller.refreshSource(source.id);
        // 触发取消
        controller.cancelScan(source.id);
        await refreshFuture;
        final progress = container.read(sourceControllerProvider)[source.id];
        expect(progress!.cancelled, isTrue);
        expect(progress.running, isFalse);

        // 验证未被标记为 missing/unavailable
        library = await repo.watchLibrary().first;
        expect(
          library.any((v) => v.fileName == 'v2.mp4' && v.available),
          isTrue,
        );

        // 验证取消扫描后已有播放进度依然完整保留
        final v2Progress = await progressRepo.getProgress(v2Video.fileId);
        expect(v2Progress, isNotNull);
        expect(v2Progress!.position, const Duration(seconds: 40));
      },
    );
    test('enumeration failure fails whole scan without deleting/marking old rows missing', () async {
      final source = await repo.upsertSource(
        kind: 'local',
        rootLocator: '/unstable_dir',
        name: 'UnstableDir',
      );

      // 首次扫描正常
      fakeAdapter.entriesByDir['/unstable_dir'] = [
        const MediaEntry(
          externalId: 'stable.mp4',
          locator: 'stable.mp4',
          name: 'stable.mp4',
          isDirectory: false,
        ),
      ];
      final controller = container.read(sourceControllerProvider.notifier);
      await controller.refreshSource(source.id);

      var library = await repo.watchLibrary().first;
      expect(library.length, 1);
      expect(library.first.available, isTrue);

      final stableVideo = library.first;
      final progressRepo = PlaybackProgressRepository(db: db);
      await progressRepo.saveProgress(
        fileId: stableVideo.fileId,
        position: const Duration(seconds: 35),
        duration: const Duration(seconds: 90),
      );

      // 第二次扫描发生权限或 I/O 异常
      fakeAdapter.listError = const MediaSourceException(
        '网络共享连接已断开',
        code: 'io_error',
      );
      await controller.refreshSource(source.id);

      final progress = container.read(sourceControllerProvider)[source.id];
      expect(progress!.running, isFalse);
      expect(progress.error, contains('网络共享连接已断开'));

      // 确认旧数据状态仍保持可用
      library = await repo.watchLibrary().first;
      expect(library.length, 1);
      expect(library.first.available, isTrue);

      final refreshedSource = await repo.getSource(source.id);
      expect(refreshedSource.errorMessage, contains('网络共享连接已断开'));

      // 验证扫描失败后旧视频进度依然完好无损
      final stableProgress = await progressRepo.getProgress(stableVideo.fileId);
      expect(stableProgress, isNotNull);
      expect(stableProgress!.position, const Duration(seconds: 35));
    });
    test('reauthorizeSource requires same root locator', () async {
      final source = await repo.upsertSource(
        kind: 'local',
        rootLocator: '/original/path',
        name: 'Original',
      );

      final controller = container.read(sourceControllerProvider.notifier);

      // 用户选择了不同的根目录 -> 抛出安全异常并记录错误
      fakeAdapter.directorySelection = const DirectorySelection(
        kind: 'local',
        rootLocator: '/different/path',
        name: 'Different',
      );

      await expectLater(
        controller.reauthorizeSource(source.id),
        throwsA(
          isA<MediaSourceException>().having(
            (e) => e.code,
            'code',
            'root_mismatch',
          ),
        ),
      );

      final progress = container.read(sourceControllerProvider)[source.id];
      expect(progress?.error, isNotNull);

      final unchangedSource = await repo.getSource(source.id);
      expect(unchangedSource.rootLocator, '/original/path');
      // 用户重新选择了相同的根目录 -> 成功触发刷新
      fakeAdapter.directorySelection = const DirectorySelection(
        kind: 'local',
        rootLocator: '/original/path',
        name: 'Original',
      );
      fakeAdapter.entriesByDir['/original/path'] = [
        const MediaEntry(
          externalId: 'recovered.mp4',
          locator: 'recovered.mp4',
          name: 'recovered.mp4',
          isDirectory: false,
        ),
      ];

      await controller.reauthorizeSource(source.id);
      final finalProgress = container.read(sourceControllerProvider)[source.id];
      expect(finalProgress?.running, isFalse);
      expect(finalProgress?.videos, 1);
    });

    test('removeSource cancels in-flight scan and disables source preserving records', () async {
      final source = await repo.upsertSource(
        kind: 'local',
        rootLocator: '/to_remove',
        name: 'ToRemove',
      );

      fakeAdapter.entriesByDir['/to_remove'] = [
        const MediaEntry(
          externalId: 'legacy.mp4',
          locator: 'legacy.mp4',
          name: 'legacy.mp4',
          isDirectory: false,
        ),
      ];

      final controller = container.read(sourceControllerProvider.notifier);
      await controller.refreshSource(source.id);
      final library = await repo.watchLibrary().first;
      final video = library.first;
      final progressRepo = PlaybackProgressRepository(db: db);
      await progressRepo.saveProgress(
        fileId: video.fileId,
        position: const Duration(seconds: 45),
        duration: const Duration(seconds: 120),
      );

      var sources = await repo.watchSources().first;
      expect(sources.length, 1);

      await controller.removeSource(source.id);
      // watchSources 仅返回 active 源，已软停用的不再出现在活跃源列表
      sources = await repo.watchSources().first;
      expect(sources, isEmpty);

      // 但该源记录与数据依然安全保存在 DB 中
      final dbSource = await repo.getSource(source.id);
      expect(dbSource.enabled, isFalse);

      // 软删除源后播放进度依然保留，Continue Watching 保持条目但标记为不可用
      final preservedProgress = await progressRepo.getProgress(video.fileId);
      expect(preservedProgress, isNotNull);
      expect(preservedProgress!.position, const Duration(seconds: 45));

      final continueList = await progressRepo.getContinueWatching();
      expect(continueList, hasLength(1));
      expect(continueList.first.fileId, video.fileId);
      expect(continueList.first.available, isFalse);
    });
    test(
      'resolvePlayback looks up video and source and delegates to adapter',
      () async {
        final source = await repo.upsertSource(
          kind: 'local',
          rootLocator: '/playback_test',
          name: 'PlaybackTest',
        );

        fakeAdapter.entriesByDir['/playback_test'] = [
          const MediaEntry(
            externalId: 'play_me.mp4',
            locator: 'play_me.mp4',
            name: 'play_me.mp4',
            isDirectory: false,
          ),
        ];

        final controller = container.read(sourceControllerProvider.notifier);
        await controller.refreshSource(source.id);

        final library = await repo.watchLibrary().first;
        expect(library.length, 1);
        final video = library.first;

        final resource = await controller.resolvePlayback(video.fileId);
        expect(resource.displayName, 'play_me.mp4');
        expect(resource.uri.toString(), 'file:///videos/play_me.mp4');
        expect(resource.libraryFileId, video.fileId);
        expect(resource.sourceId, source.id);
        fakeAdapter.entriesByDir['/playback_test']!.add(
          const MediaEntry(
            externalId: 'play_me.zh.ass',
            locator: 'play_me.zh.ass',
            name: 'play_me.zh.ass',
            isDirectory: false,
          ),
        );
        final subtitles = await resource.discoverSubtitles!();
        expect(subtitles.single.displayName, 'play_me.zh.ass');
        // 当媒体源停用时，抛出 source_disabled 异常
        await controller.removeSource(source.id);
        expect(
          () => controller.resolvePlayback(video.fileId),
          throwsA(
            isA<MediaSourceException>().having(
              (e) => e.code,
              'code',
              'source_disabled',
            ),
          ),
        );
      },
    );
  });
}
