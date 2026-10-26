import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reelva/core/database/app_database.dart';
import 'package:reelva/features/library/infrastructure/media_library_repository.dart';
import 'package:reelva/features/metadata/domain/tmdb_models.dart';
import 'package:reelva/features/progress/infrastructure/playback_progress_repository.dart';
import 'package:reelva/features/sources/domain/source_models.dart';

void main() {
  late AppDatabase db;
  late MediaLibraryRepository repo;
  late PlaybackProgressRepository progress;
  late int sourceId;

  setUp(() async {
    db = AppDatabase(executor: NativeDatabase.memory());
    repo = MediaLibraryRepository(db);
    progress = PlaybackProgressRepository(db: db);
    sourceId = (await repo.upsertSource(
      kind: 'local',
      rootLocator: 'C:/media',
      name: '媒体',
    )).id;
  });
  tearDown(() => db.close());

  Future<Map<String, int>> index(List<String> names) =>
      repo.indexSourceFiles(sourceId, [
        for (final name in names)
          MediaEntry(
            externalId: name,
            locator: name,
            name: name,
            isDirectory: false,
          ),
      ]);

  const series = TmdbWork(id: 123, type: 'series', title: '新剧集', year: 2024);

  test('目录文件匹配信息限定来源与文件，实时反映电影、季集和重新匹配', () async {
    final files = await index(['Movie.mkv', 'Show.S02E03.mkv', 'Pending.mkv']);
    await repo.applyMetadataToFiles({
      files['Movie.mkv']!: null,
    }, const TmdbWork(id: 1, type: 'movie', title: '电影', year: 2025));
    final other = await repo.upsertSource(
      kind: 'local',
      rootLocator: 'C:/other',
      name: '另一个来源',
    );
    final otherFile = await repo.indexSourceFiles(other.id, [
      const MediaEntry(
        externalId: 'Pending.mkv',
        locator: 'Pending.mkv',
        name: 'Pending.mkv',
        isDirectory: false,
      ),
    ]);
    await repo.applyMetadataToFiles({
      otherFile.values.single: null,
    }, const TmdbWork(id: 2, type: 'movie', title: '其他来源的电影'));
    final matches = StreamIterator(
      repo.watchSourceFileMatches(sourceId, [
        'Movie.mkv',
        'Show.S02E03.mkv',
        'Pending.mkv',
        'NotIndexed.mkv',
      ]),
    );
    addTearDown(matches.cancel);
    expect(await matches.moveNext(), isTrue);
    expect(matches.current.keys, ['Movie.mkv']);
    expect(matches.current['Movie.mkv']!.title, '电影');
    expect(matches.current['Movie.mkv']!.year, 2025);
    expect(matches.current['Movie.mkv']!.seasonNumber, isNull);

    await repo.applyMetadataToFiles({
      files['Show.S02E03.mkv']!: const TmdbEpisode(
        seasonNumber: 2,
        episodeNumber: 3,
        title: '重逢',
      ),
    }, series);
    expect(await matches.moveNext(), isTrue);
    final episode = matches.current['Show.S02E03.mkv']!;
    expect(episode.title, '新剧集');
    expect(episode.seasonNumber, 2);
    expect(episode.episodeNumber, 3);
    expect(episode.episodeTitle, '重逢');
    expect(
      await repo.watchSourceFileMatches(sourceId, ['Pending.mkv']).first,
      isEmpty,
    );

    await repo.applyMetadataToFiles({
      files['Movie.mkv']!: null,
    }, const TmdbWork(id: 3, type: 'movie', title: '重新匹配的电影'));
    expect(await matches.moveNext(), isTrue);
    expect(matches.current['Movie.mkv']!.title, '重新匹配的电影');
    expect(matches.current.containsKey('Pending.mkv'), isFalse);
  });

  test('只重绑选中的版本，保留未选版本及其观看历史', () async {
    final files = await index(['Old.2024.1080p.mkv', 'Old.2024.2160p.mkv']);
    await repo.recognizePendingFiles();
    final oldWork = (await repo.watchWorks().first).single;
    final selected = files['Old.2024.2160p.mkv']!;
    final untouched = files['Old.2024.1080p.mkv']!;
    await progress.saveProgress(
      fileId: selected,
      position: const Duration(minutes: 10),
      duration: const Duration(hours: 1),
    );
    final workId = await repo.applyMetadataToFiles({
      selected: const TmdbEpisode(seasonNumber: 2, episodeNumber: 3),
    }, series);

    final old = (await repo.getWorkDetails(oldWork.id))!;
    expect(old.versions.single.fileId, untouched);
    expect(old.work.metadataLocked, isFalse);
    final matched = (await repo.getWorkDetails(workId!))!;
    expect(matched.work.metadataLocked, isTrue);
    expect(matched.versions.single.seasonNumber, 2);
    expect(matched.versions.single.episodeNumber, 3);
    expect(
      (await progress.getProgress(selected))!.position,
      const Duration(minutes: 10),
    );
    expect(
      (await progress.getProgress(untouched))!.position,
      const Duration(minutes: 10),
    );
  });

  test('多季分别归集，同一集的多版本共享季集且保留未选剧集', () async {
    final files = await index([
      'Old.S01E01.1080p.mkv',
      'Old.S01E01.2160p.mkv',
      'Old.S02E01.mkv',
      'Old.S01E09.mkv',
    ]);
    await repo.recognizePendingFiles();
    final oldWork = (await repo.watchWorks().first).single;
    final id = await repo.applyMetadataToFiles({
      files['Old.S01E01.1080p.mkv']!: const TmdbEpisode(
        seasonNumber: 1,
        episodeNumber: 1,
      ),
      files['Old.S01E01.2160p.mkv']!: const TmdbEpisode(
        seasonNumber: 1,
        episodeNumber: 1,
      ),
      files['Old.S02E01.mkv']!: const TmdbEpisode(
        seasonNumber: 2,
        episodeNumber: 1,
      ),
    }, series);
    final details = (await repo.getWorkDetails(id!))!;
    expect(details.versions.length, 3);
    expect(details.versions.map((file) => file.seasonNumber).toSet(), {1, 2});
    final assignments = await db.select(db.mediaAssignments).get();
    final versions = assignments.where(
      (a) =>
          a.fileId == files['Old.S01E01.1080p.mkv'] ||
          a.fileId == files['Old.S01E01.2160p.mkv'],
    );
    expect(versions.map((a) => a.episodeId).toSet().length, 1);
    expect(
      (await repo.getWorkDetails(oldWork.id))!.versions.single.fileId,
      files['Old.S01E09.mkv'],
    );
  });

  test('手动结果阻止迟到的自动匹配覆盖，后台本地识别也不重绑', () async {
    final fileId = (await index(['Unknown.mkv'])).values.single;
    final manual = repo.applyMetadataToFiles({
      fileId: const TmdbEpisode(seasonNumber: 2, episodeNumber: 3),
    }, series);
    final recognition = repo.recognizePendingFiles();
    final workId = await manual;
    await recognition;
    final ignored = await repo.applyMetadataToFiles(
      {fileId: null},
      const TmdbWork(id: 99, type: 'movie', title: '错误电影'),
      manual: false,
    );
    expect(ignored, isNull);
    final works = await repo.watchWorks().first;
    expect(works.single.id, workId);
    expect(works.single.title, '新剧集');
  });

  test('无效文件使整个批次回滚，索引复用文件编号且不假装扫描已完成', () async {
    final files = await index(['Movie.2024.mkv']);
    expect(await index(['Movie.2024.mkv']), files);
    expect((await repo.getSource(sourceId)).lastScanAt, isNull);
    final before = (await repo.watchWorks().first).single;
    await expectLater(
      repo.applyMetadataToFiles({
        files.values.single: null,
        -1: null,
      }, const TmdbWork(id: 1, type: 'movie', title: '错误目标')),
      throwsA(isA<MetadataException>()),
    );
    expect((await repo.watchWorks().first).single.id, before.id);
  });
}
