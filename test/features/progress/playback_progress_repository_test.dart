import 'dart:async';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reelva/core/database/app_database.dart';
import 'package:reelva/features/progress/domain/playback_progress.dart';
import 'package:reelva/features/progress/infrastructure/playback_progress_repository.dart';

void main() {
  group('PlaybackProgressRepository', () {
    late AppDatabase db;
    late PlaybackProgressRepository repository;
    DateTime now = DateTime(2026, 1, 1, 12, 0, 0);

    setUp(() async {
      db = AppDatabase(executor: NativeDatabase.memory());
      now = DateTime(2026, 1, 1, 12, 0, 0);
      repository = PlaybackProgressRepository(db: db, clock: () => now);

      // 准备基础媒体源与条目
      await db
          .into(db.mediaSources)
          .insert(
            MediaSourcesCompanion.insert(
              id: const Value(1),
              kind: 'local',
              name: 'Local Movies',
              rootLocator: '/movies',
            ),
          );

      await db
          .into(db.mediaEntries)
          .insert(
            MediaEntriesCompanion.insert(
              id: const Value(1),
              sourceId: 1,
              externalEntryId: 'movie1.mp4',
              relativeLocator: 'movie1.mp4',
              name: 'movie1.mp4',
              isDirectory: false,
              available: const Value(true),
            ),
          );

      await db
          .into(db.mediaFiles)
          .insert(
            MediaFilesCompanion.insert(
              id: const Value(1),
              entryId: 1,
              durationMs: const Value(120000),
            ),
          );

      // 电影作品 1
      await db
          .into(db.works)
          .insert(
            WorksCompanion.insert(
              id: const Value(1),
              type: const Value('movie'),
              title: 'Inception',
              posterPath: const Value('/posters/inception.jpg'),
            ),
          );

      await db
          .into(db.mediaAssignments)
          .insert(
            MediaAssignmentsCompanion.insert(
              id: const Value(1),
              fileId: 1,
              workId: const Value(1),
              episodeId: const Value(null),
              preferred: const Value(true),
            ),
          );
    });

    tearDown(() async {
      await db.close();
    });

    test('saveProgress and getProgress for movies', () async {
      await repository.saveProgress(
        fileId: 1,
        position: const Duration(seconds: 45),
        duration: const Duration(seconds: 120),
      );

      final progress = await repository.getProgress(1);
      expect(progress, isNotNull);
      expect(progress!.targetType, ProgressTargetType.work);
      expect(progress.targetId, 1);
      expect(progress.workId, 1);
      expect(progress.episodeId, isNull);
      expect(progress.lastFileId, 1);
      expect(progress.position, const Duration(seconds: 45));
      expect(progress.duration, const Duration(seconds: 120));
      expect(progress.completed, isFalse);
      expect(progress.updatedAt, now);
    });

    test(
      'saveProgress automatically marks completed when position >= 90%',
      () async {
        await repository.saveProgress(
          fileId: 1,
          position: const Duration(seconds: 108), // 108 / 120 = 90%
          duration: const Duration(seconds: 120),
        );

        final progress = await repository.getProgress(1);
        expect(progress, isNotNull);
        expect(progress!.completed, isTrue);
        expect(progress.isEffectivelyCompleted, isTrue);
      },
    );

    test('saveProgress and getProgress for series episodes', () async {
      // 剧集作品 2
      await db
          .into(db.works)
          .insert(
            WorksCompanion.insert(
              id: const Value(2),
              type: const Value('series'),
              title: 'Breaking Bad',
              posterPath: const Value('/posters/bb.jpg'),
            ),
          );

      await db
          .into(db.seasons)
          .insert(
            SeasonsCompanion.insert(
              id: const Value(1),
              seriesId: 2,
              seasonNumber: 1,
              title: const Value('Season 1'),
            ),
          );

      await db
          .into(db.episodes)
          .insert(
            EpisodesCompanion.insert(
              id: const Value(1),
              seasonId: 1,
              episodeNumber: 1,
              title: const Value('Pilot'),
            ),
          );

      await db
          .into(db.mediaEntries)
          .insert(
            MediaEntriesCompanion.insert(
              id: const Value(2),
              sourceId: 1,
              externalEntryId: 'bb_s01e01.mp4',
              relativeLocator: 'bb_s01e01.mp4',
              name: 'bb_s01e01.mp4',
              isDirectory: false,
              available: const Value(true),
            ),
          );

      await db
          .into(db.mediaFiles)
          .insert(
            MediaFilesCompanion.insert(
              id: const Value(2),
              entryId: 2,
              durationMs: const Value(3000000),
            ),
          );

      await db
          .into(db.mediaAssignments)
          .insert(
            MediaAssignmentsCompanion.insert(
              id: const Value(2),
              fileId: 2,
              workId: const Value(null),
              episodeId: const Value(1),
            ),
          );

      await repository.saveProgress(
        fileId: 2,
        position: const Duration(minutes: 15),
        duration: const Duration(minutes: 50),
      );

      final progress = await repository.getProgress(2);
      expect(progress, isNotNull);
      expect(progress!.targetType, ProgressTargetType.episode);
      expect(progress.targetId, 1);
      expect(progress.workId, isNull);
      expect(progress.episodeId, 1);
      expect(progress.lastFileId, 2);
      expect(progress.position, const Duration(minutes: 15));
      expect(progress.duration, const Duration(minutes: 50));
    });

    test('getContinueWatching orders by updatedAt DESC and filters short/completed', () async {
      // 1. 作品 1 保存进度 10s（符合 >= 5s）
      now = DateTime(2026, 1, 1, 10, 0, 0);
      await repository.saveProgress(
        fileId: 1,
        position: const Duration(seconds: 10),
        duration: const Duration(seconds: 100),
      );

      // 2. 准备第二个作品 3
      await db
          .into(db.works)
          .insert(
            WorksCompanion.insert(
              id: const Value(3),
              type: const Value('movie'),
              title: 'Interstellar',
            ),
          );
      await db
          .into(db.mediaEntries)
          .insert(
            MediaEntriesCompanion.insert(
              id: const Value(3),
              sourceId: 1,
              externalEntryId: 'interstellar.mp4',
              relativeLocator: 'interstellar.mp4',
              name: 'interstellar.mp4',
              isDirectory: false,
              available: const Value(true),
            ),
          );
      await db
          .into(db.mediaFiles)
          .insert(MediaFilesCompanion.insert(id: const Value(3), entryId: 3));
      await db
          .into(db.mediaAssignments)
          .insert(
            MediaAssignmentsCompanion.insert(
              id: const Value(3),
              fileId: 3,
              workId: const Value(3),
            ),
          );

      // 作品 3 较新播放（11:00:00）
      now = DateTime(2026, 1, 1, 11, 0, 0);
      await repository.saveProgress(
        fileId: 3,
        position: const Duration(seconds: 50),
        duration: const Duration(seconds: 200),
      );

      // 3. 准备第三个作品 4，播放时间 < 5s（应被过滤）
      await db
          .into(db.works)
          .insert(
            WorksCompanion.insert(
              id: const Value(4),
              type: const Value('movie'),
              title: 'Short Progress',
            ),
          );
      await db
          .into(db.mediaEntries)
          .insert(
            MediaEntriesCompanion.insert(
              id: const Value(4),
              sourceId: 1,
              externalEntryId: 'short.mp4',
              relativeLocator: 'short.mp4',
              name: 'short.mp4',
              isDirectory: false,
              available: const Value(true),
            ),
          );
      await db
          .into(db.mediaFiles)
          .insert(MediaFilesCompanion.insert(id: const Value(4), entryId: 4));
      await db
          .into(db.mediaAssignments)
          .insert(
            MediaAssignmentsCompanion.insert(
              id: const Value(4),
              fileId: 4,
              workId: const Value(4),
            ),
          );
      now = DateTime(2026, 1, 1, 12, 0, 0);
      await repository.saveProgress(
        fileId: 4,
        position: const Duration(seconds: 4), // < 5s
        duration: const Duration(seconds: 200),
      );

      final list = await repository.getContinueWatching();
      expect(list.length, 2);
      // 作品 3 更新时间最新，排在最前
      expect(list[0].workId, 3);
      expect(list[0].title, 'Interstellar');
      expect(list[0].position, const Duration(seconds: 50));
      expect(list[0].available, isTrue);

      // 作品 1 排在第二
      expect(list[1].workId, 1);
      expect(list[1].title, 'Inception');
    });

    test('same-target versions and lastFile fallback resolution', () async {
      // 为作品 1 增加第二个版本文件 10 (非首选备用版本)
      await db
          .into(db.mediaEntries)
          .insert(
            MediaEntriesCompanion.insert(
              id: const Value(10),
              sourceId: 1,
              externalEntryId: 'movie1_720p.mp4',
              relativeLocator: 'movie1_720p.mp4',
              name: 'movie1_720p.mp4',
              isDirectory: false,
              available: const Value(true),
            ),
          );
      await db
          .into(db.mediaFiles)
          .insert(MediaFilesCompanion.insert(id: const Value(10), entryId: 10));
      await db
          .into(db.mediaAssignments)
          .insert(
            MediaAssignmentsCompanion.insert(
              id: const Value(10),
              fileId: 10,
              workId: const Value(1),
              preferred: const Value(false),
            ),
          );

      // 播放文件 1
      await repository.saveProgress(
        fileId: 1,
        position: const Duration(seconds: 30),
        duration: const Duration(seconds: 120),
      );

      // 情况 1: lastFile (file 1) 可用，推荐 file 1
      var continueList = await repository.getContinueWatching();
      expect(continueList.first.fileId, 1);
      expect(continueList.first.available, isTrue);

      // 情况 2: file 1 变为不可用，回退至同目标备选 file 10，状态保持 available = true
      await (db.update(db.mediaEntries)..where((tbl) => tbl.id.equals(1)))
          .write(const MediaEntriesCompanion(available: Value(false)));

      continueList = await repository.getContinueWatching();
      expect(continueList.first.fileId, 10);
      expect(continueList.first.available, isTrue);

      // 情况 3: file 10 也变为不可用，保留原 lastFile (file 1)，标记 available = false
      await (db.update(db.mediaEntries)..where((tbl) => tbl.id.equals(10)))
          .write(const MediaEntriesCompanion(available: Value(false)));

      continueList = await repository.getContinueWatching();
      expect(continueList.first.fileId, 1);
      expect(continueList.first.available, isFalse);
    });

    test(
      'deduplicates multiple episodes of the same series to latest watched',
      () async {
        await db
            .into(db.works)
            .insert(
              WorksCompanion.insert(
                id: const Value(5),
                type: const Value('series'),
                title: 'Severance',
              ),
            );
        await db
            .into(db.seasons)
            .insert(
              SeasonsCompanion.insert(
                id: const Value(50),
                seriesId: 5,
                seasonNumber: 1,
              ),
            );
        await db
            .into(db.episodes)
            .insert(
              EpisodesCompanion.insert(
                id: const Value(501),
                seasonId: 50,
                episodeNumber: 1,
              ),
            );
        await db
            .into(db.episodes)
            .insert(
              EpisodesCompanion.insert(
                id: const Value(502),
                seasonId: 50,
                episodeNumber: 2,
              ),
            );

        // 文件 51 -> E01, 文件 52 -> E02
        await db
            .into(db.mediaEntries)
            .insert(
              MediaEntriesCompanion.insert(
                id: const Value(51),
                sourceId: 1,
                externalEntryId: 's01e01.mp4',
                relativeLocator: 's01e01.mp4',
                name: 's01e01.mp4',
                isDirectory: false,
                available: const Value(true),
              ),
            );
        await db
            .into(db.mediaFiles)
            .insert(
              MediaFilesCompanion.insert(id: const Value(51), entryId: 51),
            );
        await db
            .into(db.mediaAssignments)
            .insert(
              MediaAssignmentsCompanion.insert(
                id: const Value(51),
                fileId: 51,
                episodeId: const Value(501),
              ),
            );

        await db
            .into(db.mediaEntries)
            .insert(
              MediaEntriesCompanion.insert(
                id: const Value(52),
                sourceId: 1,
                externalEntryId: 's01e02.mp4',
                relativeLocator: 's01e02.mp4',
                name: 's01e02.mp4',
                isDirectory: false,
                available: const Value(true),
              ),
            );
        await db
            .into(db.mediaFiles)
            .insert(
              MediaFilesCompanion.insert(id: const Value(52), entryId: 52),
            );
        await db
            .into(db.mediaAssignments)
            .insert(
              MediaAssignmentsCompanion.insert(
                id: const Value(52),
                fileId: 52,
                episodeId: const Value(502),
              ),
            );

        // 先看 E01
        now = DateTime(2026, 1, 1, 14, 0, 0);
        await repository.saveProgress(
          fileId: 51,
          position: const Duration(minutes: 10),
          duration: const Duration(minutes: 50),
        );

        // 后看 E02
        now = DateTime(2026, 1, 1, 15, 0, 0);
        await repository.saveProgress(
          fileId: 52,
          position: const Duration(minutes: 20),
          duration: const Duration(minutes: 50),
        );

        final list = await repository.getContinueWatching();
        final severanceEntries = list.where((e) => e.workId == 5).toList();
        expect(severanceEntries.length, 1);
        expect(severanceEntries.first.seasonNumber, 1);
        expect(severanceEntries.first.episodeNumber, 2);
        expect(severanceEntries.first.position, const Duration(minutes: 20));
      },
    );

    test(
      'does not save progress for unassigned file (no fake history)',
      () async {
        await db
            .into(db.mediaEntries)
            .insert(
              MediaEntriesCompanion.insert(
                id: const Value(99),
                sourceId: 1,
                externalEntryId: 'unassigned.mp4',
                relativeLocator: 'unassigned.mp4',
                name: 'unassigned.mp4',
                isDirectory: false,
                available: const Value(true),
              ),
            );
        await db
            .into(db.mediaFiles)
            .insert(
              MediaFilesCompanion.insert(id: const Value(99), entryId: 99),
            );

        await repository.saveProgress(
          fileId: 99,
          position: const Duration(seconds: 30),
          duration: const Duration(seconds: 100),
        );

        final progress = await repository.getProgress(99);
        expect(progress, isNull);
      },
    );

    test('metadata refresh merge: resolves updated workId dynamically in transaction', () async {
      // 初始：文件 1 关联作品 1
      await repository.saveProgress(
        fileId: 1,
        position: const Duration(seconds: 20),
        duration: const Duration(seconds: 100),
      );
      var p = await repository.getProgress(1);
      expect(p!.targetId, 1);

      // 模拟后台元数据刷新将文件 1 合并至新作品 88
      await db
          .into(db.works)
          .insert(
            WorksCompanion.insert(
              id: const Value(88),
              type: const Value('movie'),
              title: 'Inception (Merged)',
            ),
          );
      await (db.update(db.mediaAssignments)
            ..where((tbl) => tbl.fileId.equals(1)))
          .write(const MediaAssignmentsCompanion(workId: Value(88)));

      // 再次保存进度：事务内动态获取当前 assignment，成功更新至作品 88
      await repository.saveProgress(
        fileId: 1,
        position: const Duration(seconds: 50),
        duration: const Duration(seconds: 100),
      );

      p = await repository.getProgress(1);
      expect(p, isNotNull);
      expect(p!.targetId, 88);
      expect(p.position, const Duration(seconds: 50));
    });

    test('continue watching reacts to saved progress, offline sources and completion', () async {
      final updates = StreamIterator(repository.watchContinueWatching());
      try {
        expect(await updates.moveNext(), isTrue);
        expect(updates.current, isEmpty);

        await repository.saveProgress(
          fileId: 1,
          position: const Duration(seconds: 45),
          duration: const Duration(seconds: 120),
        );
        expect(await updates.moveNext(), isTrue);
        expect(updates.current.single.fileId, 1);
        expect(updates.current.single.position, const Duration(seconds: 45));
        expect(updates.current.single.available, isTrue);

        await (db.update(db.mediaSources)
              ..where((source) => source.id.equals(1)))
            .write(const MediaSourcesCompanion(enabled: Value(false)));
        expect(await updates.moveNext(), isTrue);
        expect(updates.current.single.available, isFalse);

        await repository.saveProgress(
          fileId: 1,
          position: const Duration(seconds: 110),
          duration: const Duration(seconds: 120),
        );
        expect(await updates.moveNext(), isTrue);
        expect(updates.current, isEmpty);
      } finally {
        await updates.cancel();
      }
    });
  });
}
