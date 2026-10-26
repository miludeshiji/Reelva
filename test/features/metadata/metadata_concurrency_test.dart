import 'package:reelva/features/metadata/domain/work_metadata.dart';

import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reelva/core/database/app_database.dart';
import 'package:reelva/features/library/infrastructure/media_library_repository.dart';
import 'package:reelva/features/metadata/application/metadata_service.dart';
import 'package:reelva/features/metadata/domain/matching_file.dart';
import 'package:reelva/features/metadata/domain/tmdb_models.dart';
import 'package:reelva/features/metadata/infrastructure/tmdb_token_store.dart';
import 'package:reelva/features/sources/domain/source_models.dart';

import 'metadata_service_test.dart'
    show FakeFlutterSecureStorage, FakeTmdbClient;

class _RecordingRepository extends MediaLibraryRepository {
  _RecordingRepository(super.db);
  int activeWrites = 0;
  int peakWrites = 0;

  @override
  Future<int?> applyMetadataToFiles(
    Map<int, TmdbEpisode?> files,
    WorkMetadata metadata, {
    bool manual = true,
    String metadataSource = 'tmdb',
    int? localWorkId,
    bool respectExistingMetadata = true,
  }) async {
    activeWrites++;
    if (activeWrites > peakWrites) peakWrites = activeWrites;
    try {
      await Future<void>.delayed(const Duration(milliseconds: 1));
      return await super.applyMetadataToFiles(files, metadata, manual: manual);
    } finally {
      activeWrites--;
    }
  }
}

void main() {
  late AppDatabase db;
  late _RecordingRepository repo;
  late FakeTmdbClient client;
  late MetadataService service;
  late List<MatchingFile> files;

  TmdbWork movie(int id) =>
      TmdbWork(id: id, type: 'movie', title: 'Movie ${id - 100}', year: 2024);

  setUp(() async {
    db = AppDatabase(executor: NativeDatabase.memory());
    repo = _RecordingRepository(db);
    client = FakeTmdbClient();
    final tokens = TmdbTokenStore(storage: FakeFlutterSecureStorage());
    await tokens.save('1234567890abcdef1234567890abcdef');
    service = MetadataService(
      tmdbClient: client,
      mediaLibraryRepository: repo,
      tokenStore: tokens,
    );
    final source = await repo.upsertSource(
      kind: 'local',
      rootLocator: 'C:/media',
      name: '媒体',
    );
    final ids = await repo.indexSourceFiles(source.id, [
      for (var n = 1; n <= 6; n++)
        MediaEntry(
          externalId: '$n',
          locator: 'Movie $n.2024.mkv',
          name: 'Movie $n.2024.mkv',
          isDirectory: false,
        ),
    ]);
    files = [
      for (var n = 1; n <= 6; n++)
        MatchingFile(fileId: ids['$n']!, name: 'Movie $n.2024.mkv'),
    ];
    client.searchMovieHandler = (query, year) {
      final title = query.replaceFirst(RegExp(r' 2024$'), '');
      return [movie(100 + int.parse(title.split(' ').last))];
    };
  });
  tearDown(() => db.close());

  for (final fullLibrary in [true, false]) {
    test('${fullLibrary ? '全库' : '所选文件'}最多并发 4 项，乱序完成的进度单调累计且写入串行', () async {
      final started = [for (var n = 0; n < 6; n++) Completer<void>()];
      final responses = <int, Completer<TmdbWork>>{};
      final completed = <int>[];
      final active = <int>[];
      client.getMovieDetailsHandler = (id) {
        final response = Completer<TmdbWork>();
        responses[id] = response;
        started[responses.length - 1].complete();
        return response.future;
      };
      final Future<MetadataRefreshResult> result;
      if (fullLibrary) {
        result = service.refresh(
          onProgress: (phase, done, total) {
            if (phase == MetadataPhase.matching) completed.add(done);
          },
          onActiveChanged: active.add,
        );
      } else {
        result = service.matchFilesAutomatically(
          files,
          onProgress: (done, total) => completed.add(done),
          onActiveChanged: active.add,
        );
      }
      await started[3].future.timeout(const Duration(seconds: 3));
      expect(responses, hasLength(4));
      expect(completed.last, 0);
      final firstCompleted = responses.keys.elementAt(3);
      responses[firstCompleted]!.complete(movie(firstCompleted));
      await started[4].future.timeout(const Duration(seconds: 3));
      expect(completed.last, 1);
      for (final entry
          in responses.entries
              .where((entry) => !entry.value.isCompleted)
              .toList()) {
        entry.value.complete(movie(entry.key));
      }
      await started[5].future.timeout(const Duration(seconds: 3));
      for (final entry in responses.entries.where(
        (entry) => !entry.value.isCompleted,
      )) {
        entry.value.complete(movie(entry.key));
      }
      expect((await result).matched, 6);
      expect(completed, [0, 1, 2, 3, 4, 5, 6]);
      expect(active, everyElement(inInclusiveRange(0, 4)));
      expect(active, contains(4));
      expect(active.last, 0);
      expect(repo.peakWrites, 1);
      expect(await db.select(db.externalIds).get(), hasLength(6));
    });
  }

  test('鉴权失败停止派发后续任务，已在途任务结束后不再自动写入', () async {
    final started = Completer<void>();
    final stopped = Completer<void>();
    final responses = <int, Completer<TmdbWork>>{};
    var reachedFour = false;
    final completed = <int>[];
    client.getMovieDetailsHandler = (id) {
      final response = Completer<TmdbWork>();
      responses[id] = response;
      if (responses.length == 4) started.complete();
      return response.future;
    };
    final result = service.matchFilesAutomatically(
      files,
      onProgress: (done, total) => completed.add(done),
      onActiveChanged: (active) {
        if (active == 4) reachedFour = true;
        if (reachedFour && active == 3 && !stopped.isCompleted) {
          stopped.complete();
        }
      },
    );
    await started.future.timeout(const Duration(seconds: 3));
    responses.values.first.completeError(
      const MetadataException('凭据无效', code: 'unauthorized'),
    );
    await stopped.future.timeout(const Duration(seconds: 3));
    for (final entry in responses.entries.where(
      (entry) => !entry.value.isCompleted,
    )) {
      entry.value.complete(movie(entry.key));
    }
    final summary = await result;
    expect(responses, hasLength(4));
    expect(completed.last, 4);
    expect(summary.errors, ['凭据无效']);
    expect(summary.matched, 0);
    expect(await db.select(db.externalIds).get(), isEmpty);
  });
}
