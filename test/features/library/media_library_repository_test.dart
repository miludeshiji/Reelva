import 'dart:io';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reelva/core/database/app_database.dart';
import 'package:reelva/features/library/infrastructure/media_library_repository.dart';
import 'package:reelva/features/sources/domain/source_models.dart';

void main() {
  group('MediaLibraryRepository behavioral invariants', () {
    late AppDatabase db;
    late MediaLibraryRepository repo;

    setUp(() {
      db = AppDatabase(executor: NativeDatabase.memory());
      repo = MediaLibraryRepository(db);
    });

    tearDown(() async {
      await db.close();
    });

    test('upsertSource and watchSources active-only filtering', () async {
      final source1 = await repo.upsertSource(
        kind: 'local',
        rootLocator: 'C:/Movies',
        name: 'Movies',
      );
      expect(source1.id, isPositive);
      expect(source1.name, 'Movies');
      expect(source1.enabled, isTrue);

      final sources = await repo.watchSources().first;
      expect(sources, hasLength(1));
      expect(sources.first.id, source1.id);

      // Disable source -> watchSources should emit empty
      await repo.disableSource(source1.id);
      final sourcesAfterDisable = await repo.watchSources().first;
      expect(sourcesAfterDisable, isEmpty);

      // Upserting with same kind and rootLocator reactivates old source with same ID
      final reactivated = await repo.upsertSource(
        kind: 'local',
        rootLocator: 'C:/Movies',
        name: 'Movies Renamed',
      );
      expect(reactivated.id, source1.id);
      expect(reactivated.enabled, isTrue);
      expect(reactivated.name, 'Movies Renamed');

      final sourcesAfterReactivate = await repo.watchSources().first;
      expect(sourcesAfterReactivate, hasLength(1));
      expect(sourcesAfterReactivate.first.name, 'Movies Renamed');
    });

    test('same rescan causes no duplicate files or candidate churn', () async {
      final source = await repo.upsertSource(
        kind: 'local',
        rootLocator: 'C:/Media',
        name: 'Media',
      );

      final now = DateTime.now();
      final entries = [
        MediaEntry(
          externalId: 'ext-video-1',
          locator: 'Subdir/video1.mp4',
          name: 'video1.mp4',
          isDirectory: false,
          size: 1000000,
          modifiedAt: now,
        ),
        MediaEntry(
          externalId: 'ext-video-2',
          locator: 'Subdir/video2.mkv',
          name: 'video2.mkv',
          isDirectory: false,
          size: 2000000,
          modifiedAt: now,
        ),
      ];

      // Scan 1
      final scan1 = await repo.beginScan(source.id);
      await repo.applyScanBatch(source.id, scan1, entries);
      await repo.finishScan(source.id, scan1);

      final videos1 = await repo.watchLibrary().first;
      expect(videos1, hasLength(2));
      final fileId1 = videos1[0].fileId;
      final fileId2 = videos1[1].fileId;

      final allWorks1 = await db.select(db.works).get();
      expect(allWorks1, hasLength(2));
      final workIds1 = allWorks1.map((w) => w.id).toSet();

      // Scan 2 with exact same modifiedAt timestamps
      final scan2 = await repo.beginScan(source.id);
      await repo.applyScanBatch(source.id, scan2, entries);
      await repo.finishScan(source.id, scan2);

      // Verify no duplicates or churn
      final videos2 = await repo.watchLibrary().first;
      expect(videos2, hasLength(2));
      expect(videos2.map((v) => v.fileId).toList(), [fileId1, fileId2]);

      final allWorks2 = await db.select(db.works).get();
      expect(allWorks2, hasLength(2));
      expect(allWorks2.map((w) => w.id).toSet(), workIds1);
    });

    test('exact millisecond modifiedAt detects change without churn', () async {
      final source = await repo.upsertSource(
        kind: 'local',
        rootLocator: 'C:/Media',
        name: 'Media',
      );

      final t1 = DateTime.fromMillisecondsSinceEpoch(1700000000123);
      final entries1 = [
        MediaEntry(
          externalId: 'v1',
          locator: 'v1.mp4',
          name: 'v1.mp4',
          isDirectory: false,
          size: 500,
          modifiedAt: t1,
        ),
      ];

      final scan1 = await repo.beginScan(source.id);
      await repo.applyScanBatch(source.id, scan1, entries1);
      await repo.finishScan(source.id, scan1);

      final entryInDb1 = await (db.select(
        db.mediaEntries,
      )..where((e) => e.externalEntryId.equals('v1'))).getSingle();
      expect(entryInDb1.modifiedAt, 1700000000123);

      // File modified within the same second (+150ms)
      final t2 = DateTime.fromMillisecondsSinceEpoch(1700000000273);
      final entries2 = [
        MediaEntry(
          externalId: 'v1',
          locator: 'v1.mp4',
          name: 'v1.mp4',
          isDirectory: false,
          size: 500,
          modifiedAt: t2,
        ),
      ];

      final scan2 = await repo.beginScan(source.id);
      await repo.applyScanBatch(source.id, scan2, entries2);
      await repo.finishScan(source.id, scan2);

      final entryInDb2 = await (db.select(
        db.mediaEntries,
      )..where((e) => e.externalEntryId.equals('v1'))).getSingle();
      // Millisecond difference was detected and updated!
      expect(entryInDb2.modifiedAt, 1700000000273);

      // But fileId and workId remain completely stable
      final libraryVideos = await repo.watchLibrary().first;
      expect(libraryVideos, hasLength(1));
    });

    test(
      'directory type transitions are excluded from library and recover',
      () async {
        final source = await repo.upsertSource(
          kind: 'local',
          rootLocator: 'C:/Media',
          name: 'Media',
        );

        // Scan 1: item is a video file
        final scan1 = await repo.beginScan(source.id);
        await repo.applyScanBatch(source.id, scan1, [
          const MediaEntry(
            externalId: 'item-path',
            locator: 'folder_or_file',
            name: 'folder_or_file',
            isDirectory: false,
            size: 1000,
          ),
        ]);
        await repo.finishScan(source.id, scan1);

        final videos1 = await repo.watchLibrary().first;
        expect(videos1, hasLength(1));
        final fileId = videos1.first.fileId;

        // Scan 2: path is replaced by a directory of the same name
        final scan2 = await repo.beginScan(source.id);
        await repo.applyScanBatch(source.id, scan2, [
          const MediaEntry(
            externalId: 'item-path',
            locator: 'folder_or_file',
            name: 'folder_or_file',
            isDirectory: true,
          ),
        ]);
        await repo.finishScan(source.id, scan2);

        // Directory must be excluded from library view
        final videos2 = await repo.watchLibrary().first;
        expect(videos2, isEmpty);

        final lookupDir = await repo.getVideo(fileId);
        expect(lookupDir?.available, isFalse);

        // Scan 3: turns back into a video file -> recovers original file and work!
        final scan3 = await repo.beginScan(source.id);
        await repo.applyScanBatch(source.id, scan3, [
          const MediaEntry(
            externalId: 'item-path',
            locator: 'folder_or_file',
            name: 'folder_or_file',
            isDirectory: false,
            size: 1000,
          ),
        ]);
        await repo.finishScan(source.id, scan3);

        final videos3 = await repo.watchLibrary().first;
        expect(videos3, hasLength(1));
        expect(videos3.first.fileId, fileId);
        expect(videos3.first.available, isTrue);
      },
    );

    test('partial failure does not mark existing rows missing', () async {
      final source = await repo.upsertSource(
        kind: 'local',
        rootLocator: 'C:/Media',
        name: 'Media',
      );

      final scan1 = await repo.beginScan(source.id);
      await repo.applyScanBatch(source.id, scan1, [
        const MediaEntry(
          externalId: 'v1',
          locator: 'v1.mp4',
          name: 'v1.mp4',
          isDirectory: false,
        ),
        const MediaEntry(
          externalId: 'v2',
          locator: 'v2.mp4',
          name: 'v2.mp4',
          isDirectory: false,
        ),
      ]);
      await repo.finishScan(source.id, scan1);

      final initialSource = await repo.getSource(source.id);
      final initialLastScanAt = initialSource.lastScanAt;
      expect(initialLastScanAt, isNotNull);

      // Scan 2 begins, discovers v1, then encounters a failure mid-flight
      final scan2 = await repo.beginScan(source.id);
      await repo.applyScanBatch(source.id, scan2, [
        const MediaEntry(
          externalId: 'v1',
          locator: 'v1.mp4',
          name: 'v1.mp4',
          isDirectory: false,
        ),
      ]);
      await repo.failScan(source.id, 'Permission denied on subfolder');

      // Both v1 and v2 must remain available, not marked missing!
      final libraryVideos = await repo.watchLibrary().first;
      expect(libraryVideos, hasLength(2));
      expect(libraryVideos.every((v) => v.available), isTrue);

      // Source error is set, and lastScanAt was NOT updated by failed scan
      final failedSource = await repo.getSource(source.id);
      expect(failedSource.errorMessage, 'Permission denied on subfolder');
      expect(failedSource.lastScanAt, initialLastScanAt);
    });

    test(
      'completed scan marks missing entries unavailable without deleting',
      () async {
        final source = await repo.upsertSource(
          kind: 'local',
          rootLocator: 'C:/Media',
          name: 'Media',
        );

        final scan1 = await repo.beginScan(source.id);
        await repo.applyScanBatch(source.id, scan1, [
          const MediaEntry(
            externalId: 'v1',
            locator: 'v1.mp4',
            name: 'v1.mp4',
            isDirectory: false,
          ),
          const MediaEntry(
            externalId: 'v2',
            locator: 'v2.mp4',
            name: 'v2.mp4',
            isDirectory: false,
          ),
        ]);
        await repo.finishScan(source.id, scan1);

        // Scan 2 completes with only v1 present (v2 has disappeared)
        final scan2 = await repo.beginScan(source.id);
        await repo.applyScanBatch(source.id, scan2, [
          const MediaEntry(
            externalId: 'v1',
            locator: 'v1.mp4',
            name: 'v1.mp4',
            isDirectory: false,
          ),
        ]);
        await repo.finishScan(source.id, scan2);

        // Library still includes both, but v2 is marked available == false
        final libraryVideos = await repo.watchLibrary().first;
        expect(libraryVideos, hasLength(2));

        final v1 = libraryVideos.firstWhere((v) => v.externalId == 'v1');
        final v2 = libraryVideos.firstWhere((v) => v.externalId == 'v2');
        expect(v1.available, isTrue);
        expect(v2.available, isFalse);

        // Ensure v2 was NOT deleted from media_entries
        final allEntries = await db.select(db.mediaEntries).get();
        expect(allEntries, hasLength(2));
      },
    );

    test('returning file recovers same IDs and works', () async {
      final source = await repo.upsertSource(
        kind: 'local',
        rootLocator: 'C:/Media',
        name: 'Media',
      );

      // Scan 1: v1 and v2
      final scan1 = await repo.beginScan(source.id);
      await repo.applyScanBatch(source.id, scan1, [
        const MediaEntry(
          externalId: 'v1',
          locator: 'v1.mp4',
          name: 'v1.mp4',
          isDirectory: false,
        ),
        const MediaEntry(
          externalId: 'v2',
          locator: 'v2.mp4',
          name: 'v2.mp4',
          isDirectory: false,
        ),
      ]);
      await repo.finishScan(source.id, scan1);

      final v2Initial = (await repo.watchLibrary().first).firstWhere(
        (v) => v.externalId == 'v2',
      );

      // Scan 2: v2 missing
      final scan2 = await repo.beginScan(source.id);
      await repo.applyScanBatch(source.id, scan2, [
        const MediaEntry(
          externalId: 'v1',
          locator: 'v1.mp4',
          name: 'v1.mp4',
          isDirectory: false,
        ),
      ]);
      await repo.finishScan(source.id, scan2);

      // Scan 3: v2 returns!
      final scan3 = await repo.beginScan(source.id);
      await repo.applyScanBatch(source.id, scan3, [
        const MediaEntry(
          externalId: 'v1',
          locator: 'v1.mp4',
          name: 'v1.mp4',
          isDirectory: false,
        ),
        const MediaEntry(
          externalId: 'v2',
          locator: 'v2.mp4',
          name: 'v2.mp4',
          isDirectory: false,
        ),
      ]);
      await repo.finishScan(source.id, scan3);

      final v2Recovered = (await repo.watchLibrary().first).firstWhere(
        (v) => v.externalId == 'v2',
      );
      expect(v2Recovered.available, isTrue);
      expect(v2Recovered.fileId, v2Initial.fileId);
      expect(v2Recovered.title, v2Initial.title);
    });

    test(
      'source disable preserves metadata, assignments and playback progress',
      () async {
        final source = await repo.upsertSource(
          kind: 'local',
          rootLocator: 'C:/Media',
          name: 'Media',
        );

        final scan1 = await repo.beginScan(source.id);
        await repo.applyScanBatch(source.id, scan1, [
          const MediaEntry(
            externalId: 'movie-1',
            locator: 'Inception.2010.mp4',
            name: 'Inception.2010.mp4',
            isDirectory: false,
          ),
        ]);
        await repo.finishScan(source.id, scan1);

        final video = (await repo.watchLibrary().first).first;

        // Find the work and lock user metadata
        final assignment = await (db.select(
          db.mediaAssignments,
        )..where((a) => a.fileId.equals(video.fileId))).getSingle();
        final workId = assignment.workId!;

        await (db.update(db.works)..where((w) => w.id.equals(workId))).write(
          const WorksCompanion(
            title: Value('Inception (Custom Title)'),
            metadataLocked: Value(true),
          ),
        );

        // Record playback progress adhering to strict target XOR constraints
        await db
            .into(db.playbackProgresses)
            .insert(
              PlaybackProgressesCompanion.insert(
                targetType: 'work',
                targetId: workId,
                workId: Value(workId),
                episodeId: const Value(null),
                lastFileId: Value(video.fileId),
                positionMs: const Value(54000),
                durationMs: const Value(8800000),
              ),
            );

        // Disable source
        await repo.disableSource(source.id);

        // watchLibrary should not return disabled sources' videos
        final activeVideos = await repo.watchLibrary().first;
        expect(activeVideos, isEmpty);

        // But in DB, work, progress and file records are intact!
        final work = await (db.select(
          db.works,
        )..where((w) => w.id.equals(workId))).getSingle();
        expect(work.title, 'Inception (Custom Title)');
        expect(work.metadataLocked, isTrue);

        final progress = await (db.select(
          db.playbackProgresses,
        )..where((p) => p.workId.equals(workId))).getSingle();
        expect(progress.positionMs, 54000);

        // Re-enabling source restores visibility with preserved metadata
        await repo.upsertSource(
          kind: 'local',
          rootLocator: 'C:/Media',
          name: 'Media',
        );

        final restoredVideos = await repo.watchLibrary().first;
        expect(restoredVideos, hasLength(1));
        expect(restoredVideos.first.fileId, video.fileId);
        expect(restoredVideos.first.title, 'Inception (Custom Title)');
      },
    );

    test(
      'reopening file DB retains repository watchLibrary and getVideo',
      () async {
        final tempDir = Directory.systemTemp.createTempSync(
          'reelva_repo_file_test_',
        );
        final dbFile = File('${tempDir.path}/repo_test.sqlite');

        try {
          // Close unused in-memory fixture from setUp so multiple AppDatabases aren't open concurrently
          await db.close();

          late int fileId;
          late String persistedTitle;

          // Run Phase 1 with repo1
          final db1 = AppDatabase(executor: NativeDatabase(dbFile));
          try {
            final repo1 = MediaLibraryRepository(db1);
            final src = await repo1.upsertSource(
              kind: 'local',
              rootLocator: 'D:/Films',
              name: 'Films',
            );
            final scan = await repo1.beginScan(src.id);
            await repo1.applyScanBatch(src.id, scan, [
              const MediaEntry(
                externalId: 'f-1',
                locator: 'Gladiator.1080p.mkv',
                name: 'Gladiator.1080p.mkv',
                isDirectory: false,
                size: 4000000,
              ),
            ]);
            await repo1.finishScan(src.id, scan);

            final v1 = (await repo1.watchLibrary().first).first;
            fileId = v1.fileId;
            persistedTitle = v1.title;
            expect(persistedTitle, isNotEmpty);
            expect(v1.fileName, 'Gladiator.1080p.mkv');
            expect(v1.locator, 'Gladiator.1080p.mkv');
            expect(v1.sourceName, 'Films');
          } finally {
            await db1.close();
          }

          // Run Phase 2 with reopened repo2
          final db2 = AppDatabase(executor: NativeDatabase(dbFile));
          try {
            final repo2 = MediaLibraryRepository(db2);

            final sources = await repo2.watchSources().first;
            expect(sources, hasLength(1));
            expect(sources.first.name, 'Films');

            final library = await repo2.watchLibrary().first;
            expect(library, hasLength(1));
            expect(library.first.fileId, fileId);
            expect(library.first.title, persistedTitle);
            expect(library.first.fileName, 'Gladiator.1080p.mkv');
            expect(library.first.locator, 'Gladiator.1080p.mkv');
            expect(library.first.sourceName, 'Films');

            final lookedUp = await repo2.getVideo(fileId);
            expect(lookedUp, isNotNull);
            expect(lookedUp!.fileName, 'Gladiator.1080p.mkv');
            expect(lookedUp.title, persistedTitle);
            expect(lookedUp.available, isTrue);
          } finally {
            await db2.close();
          }
        } finally {
          if (tempDir.existsSync()) {
            tempDir.deleteSync(recursive: true);
          }
        }
      },
    );
  });
}
