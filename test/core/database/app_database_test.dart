import 'dart:io';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reelva/core/database/app_database.dart';

void main() {
  group('AppDatabase schema and constraints', () {
    late AppDatabase db;

    setUp(() {
      db = AppDatabase(executor: NativeDatabase.memory());
    });

    tearDown(() async {
      await db.close();
    });

    test('foreign key enforcement is active', () async {
      // Inserting a media_entry referencing a non-existent source must fail
      expect(
        () => db
            .into(db.mediaEntries)
            .insert(
              MediaEntriesCompanion.insert(
                sourceId: 99999,
                externalEntryId: 'ext-1',
                relativeLocator: 'movie.mp4',
                name: 'movie.mp4',
                isDirectory: false,
              ),
            ),
        throwsA(isA<SqliteException>()),
      );
    });

    test('unique constraint on media_sources (kind, root_locator)', () async {
      await db
          .into(db.mediaSources)
          .insert(
            MediaSourcesCompanion.insert(
              kind: 'local',
              name: 'Source 1',
              rootLocator: 'C:/Videos',
            ),
          );

      expect(
        () => db
            .into(db.mediaSources)
            .insert(
              MediaSourcesCompanion.insert(
                kind: 'local',
                name: 'Source 1 Duplicate',
                rootLocator: 'C:/Videos',
              ),
            ),
        throwsA(isA<SqliteException>()),
      );
    });

    test(
      'unique constraint on media_entries (source_id, external_entry_id)',
      () async {
        final sourceId = await db
            .into(db.mediaSources)
            .insert(
              MediaSourcesCompanion.insert(
                kind: 'local',
                name: 'Source',
                rootLocator: 'C:/Videos',
              ),
            );

        await db
            .into(db.mediaEntries)
            .insert(
              MediaEntriesCompanion.insert(
                sourceId: sourceId,
                externalEntryId: 'entry-stable-1',
                relativeLocator: 'video.mkv',
                name: 'video.mkv',
                isDirectory: false,
              ),
            );

        expect(
          () => db
              .into(db.mediaEntries)
              .insert(
                MediaEntriesCompanion.insert(
                  sourceId: sourceId,
                  externalEntryId: 'entry-stable-1',
                  relativeLocator: 'video_copy.mkv',
                  name: 'video_copy.mkv',
                  isDirectory: false,
                ),
              ),
          throwsA(isA<SqliteException>()),
        );
      },
    );

    test('unique constraint on media_files (entry_id)', () async {
      final sourceId = await db
          .into(db.mediaSources)
          .insert(
            MediaSourcesCompanion.insert(
              kind: 'local',
              name: 'Source',
              rootLocator: 'C:/Videos',
            ),
          );

      final entryId = await db
          .into(db.mediaEntries)
          .insert(
            MediaEntriesCompanion.insert(
              sourceId: sourceId,
              externalEntryId: 'e-1',
              relativeLocator: 'v.mp4',
              name: 'v.mp4',
              isDirectory: false,
            ),
          );

      await db
          .into(db.mediaFiles)
          .insert(MediaFilesCompanion.insert(entryId: entryId));

      expect(
        () => db
            .into(db.mediaFiles)
            .insert(MediaFilesCompanion.insert(entryId: entryId)),
        throwsA(isA<SqliteException>()),
      );
    });

    test('check constraint on media_assignments (work XOR episode)', () async {
      final sourceId = await db
          .into(db.mediaSources)
          .insert(
            MediaSourcesCompanion.insert(
              kind: 'local',
              name: 'Source',
              rootLocator: 'C:/Videos',
            ),
          );

      final entryId = await db
          .into(db.mediaEntries)
          .insert(
            MediaEntriesCompanion.insert(
              sourceId: sourceId,
              externalEntryId: 'e-1',
              relativeLocator: 'v.mp4',
              name: 'v.mp4',
              isDirectory: false,
            ),
          );

      final fileId = await db
          .into(db.mediaFiles)
          .insert(MediaFilesCompanion.insert(entryId: entryId));

      final workId = await db
          .into(db.works)
          .insert(
            WorksCompanion.insert(
              title: 'Movie Title',
              type: const Value('movie'),
            ),
          );

      final seriesId = await db
          .into(db.works)
          .insert(
            WorksCompanion.insert(
              title: 'Series Title',
              type: const Value('series'),
            ),
          );

      final seasonId = await db
          .into(db.seasons)
          .insert(SeasonsCompanion.insert(seriesId: seriesId, seasonNumber: 1));

      final episodeId = await db
          .into(db.episodes)
          .insert(
            EpisodesCompanion.insert(seasonId: seasonId, episodeNumber: 1),
          );

      // 1. Both null -> should fail check constraint
      expect(
        () => db
            .into(db.mediaAssignments)
            .insert(
              MediaAssignmentsCompanion.insert(
                fileId: fileId,
                workId: const Value(null),
                episodeId: const Value(null),
              ),
            ),
        throwsA(isA<SqliteException>()),
      );

      // 2. Both set -> should fail check constraint
      expect(
        () => db
            .into(db.mediaAssignments)
            .insert(
              MediaAssignmentsCompanion.insert(
                fileId: fileId,
                workId: Value(workId),
                episodeId: Value(episodeId),
              ),
            ),
        throwsA(isA<SqliteException>()),
      );

      // 3. Exactly one set (workId for movie work) -> succeeds
      final assignmentId = await db
          .into(db.mediaAssignments)
          .insert(
            MediaAssignmentsCompanion.insert(
              fileId: fileId,
              workId: Value(workId),
              episodeId: const Value(null),
            ),
          );
      expect(assignmentId, isPositive);
    });

    test('trigger prevents assigning series work directly as movie', () async {
      final sourceId = await db
          .into(db.mediaSources)
          .insert(
            MediaSourcesCompanion.insert(
              kind: 'local',
              name: 'Source',
              rootLocator: 'C:/Videos',
            ),
          );

      final entryId = await db
          .into(db.mediaEntries)
          .insert(
            MediaEntriesCompanion.insert(
              sourceId: sourceId,
              externalEntryId: 'e-series',
              relativeLocator: 'episode.mp4',
              name: 'episode.mp4',
              isDirectory: false,
            ),
          );

      final fileId = await db
          .into(db.mediaFiles)
          .insert(MediaFilesCompanion.insert(entryId: entryId));

      final seriesWorkId = await db
          .into(db.works)
          .insert(
            WorksCompanion.insert(
              title: 'Breaking Bad',
              type: const Value('series'),
            ),
          );

      // Attempting to assign a series work directly as movie must abort by trigger
      expect(
        () => db
            .into(db.mediaAssignments)
            .insert(
              MediaAssignmentsCompanion.insert(
                fileId: fileId,
                workId: Value(seriesWorkId),
                episodeId: const Value(null),
              ),
            ),
        throwsA(
          isA<SqliteException>().having(
            (e) => e.message,
            'message',
            contains('Cannot assign series work directly as movie'),
          ),
        ),
      );
    });

    test('trigger enforces seasons only attach to works with type = series', () async {
      final movieWorkId = await db
          .into(db.works)
          .insert(
            WorksCompanion.insert(
              title: 'Inception',
              type: const Value('movie'),
            ),
          );

      final unclassifiedWorkId = await db
          .into(db.works)
          .insert(
            WorksCompanion.insert(
              title: 'Unclassified Video',
              type: const Value(null),
            ),
          );

      final seriesWorkId = await db
          .into(db.works)
          .insert(
            WorksCompanion.insert(
              title: 'Chernobyl',
              type: const Value('series'),
            ),
          );

      // 1. Attaching season to a movie work must abort
      expect(
        () => db
            .into(db.seasons)
            .insert(
              SeasonsCompanion.insert(seriesId: movieWorkId, seasonNumber: 1),
            ),
        throwsA(
          isA<SqliteException>().having(
            (e) => e.message,
            'message',
            contains('Season must belong to a series work'),
          ),
        ),
      );

      // 2. Attaching season to an unclassified (null type) work must also abort
      expect(
        () => db
            .into(db.seasons)
            .insert(
              SeasonsCompanion.insert(
                seriesId: unclassifiedWorkId,
                seasonNumber: 1,
              ),
            ),
        throwsA(
          isA<SqliteException>().having(
            (e) => e.message,
            'message',
            contains('Season must belong to a series work'),
          ),
        ),
      );

      // 3. Attaching season to a confirmed series work succeeds
      final seasonId = await db
          .into(db.seasons)
          .insert(
            SeasonsCompanion.insert(seriesId: seriesWorkId, seasonNumber: 1),
          );
      expect(seasonId, isPositive);
    });

    test('triggers prevent works.type updates that break existing relations', () async {
      // Part A: Changing series work to movie or null while seasons exist must fail
      final seriesWorkId = await db
          .into(db.works)
          .insert(
            WorksCompanion.insert(
              title: 'Series A',
              type: const Value('series'),
            ),
          );
      await db
          .into(db.seasons)
          .insert(
            SeasonsCompanion.insert(seriesId: seriesWorkId, seasonNumber: 1),
          );

      expect(
        () => (db.update(db.works)..where((w) => w.id.equals(seriesWorkId)))
            .write(const WorksCompanion(type: Value('movie'))),
        throwsA(
          isA<SqliteException>().having(
            (e) => e.message,
            'message',
            contains('Cannot change work type from series while seasons exist'),
          ),
        ),
      );

      expect(
        () => (db.update(db.works)..where((w) => w.id.equals(seriesWorkId)))
            .write(const WorksCompanion(type: Value(null))),
        throwsA(
          isA<SqliteException>().having(
            (e) => e.message,
            'message',
            contains('Cannot change work type from series while seasons exist'),
          ),
        ),
      );

      // Part B: Changing movie/unclassified work to series while movie assignment exists must fail
      final sourceId = await db
          .into(db.mediaSources)
          .insert(
            MediaSourcesCompanion.insert(
              kind: 'local',
              name: 'Source',
              rootLocator: 'C:/Videos',
            ),
          );
      final entryId = await db
          .into(db.mediaEntries)
          .insert(
            MediaEntriesCompanion.insert(
              sourceId: sourceId,
              externalEntryId: 'e-movie',
              relativeLocator: 'movie.mp4',
              name: 'movie.mp4',
              isDirectory: false,
            ),
          );
      final fileId = await db
          .into(db.mediaFiles)
          .insert(MediaFilesCompanion.insert(entryId: entryId));
      final movieWorkId = await db
          .into(db.works)
          .insert(
            WorksCompanion.insert(title: 'Movie M', type: const Value('movie')),
          );
      await db
          .into(db.mediaAssignments)
          .insert(
            MediaAssignmentsCompanion.insert(
              fileId: fileId,
              workId: Value(movieWorkId),
              episodeId: const Value(null),
            ),
          );

      expect(
        () => (db.update(db.works)..where((w) => w.id.equals(movieWorkId)))
            .write(const WorksCompanion(type: Value('series'))),
        throwsA(
          isA<SqliteException>().having(
            (e) => e.message,
            'message',
            contains(
              'Cannot change work type to series while movie assignments exist',
            ),
          ),
        ),
      );
    });

    test('check constraint on works (type null or movie or series)', () async {
      // 1. type null -> succeeds
      final id1 = await db
          .into(db.works)
          .insert(
            WorksCompanion.insert(
              title: 'Unclassified Candidate',
              type: const Value(null),
            ),
          );
      expect(id1, isPositive);

      // 2. type 'movie' -> succeeds
      final id2 = await db
          .into(db.works)
          .insert(
            WorksCompanion.insert(title: 'A Movie', type: const Value('movie')),
          );
      expect(id2, isPositive);

      // 3. type 'series' -> succeeds
      final id3 = await db
          .into(db.works)
          .insert(
            WorksCompanion.insert(
              title: 'A Series',
              type: const Value('series'),
            ),
          );
      expect(id3, isPositive);

      // 4. type 'invalid_type' -> fails check constraint
      expect(
        () => db
            .into(db.works)
            .insert(
              WorksCompanion.insert(
                title: 'Invalid Work',
                type: const Value('invalid_type'),
              ),
            ),
        throwsA(isA<SqliteException>()),
      );
    });

    test(
      'playback_progress strict entity correlation and XOR constraints',
      () async {
        final workId = await db
            .into(db.works)
            .insert(
              WorksCompanion.insert(
                title: 'Series',
                type: const Value('series'),
              ),
            );

        final seasonId = await db
            .into(db.seasons)
            .insert(SeasonsCompanion.insert(seriesId: workId, seasonNumber: 1));

        final episodeId = await db
            .into(db.episodes)
            .insert(
              EpisodesCompanion.insert(seasonId: seasonId, episodeNumber: 1),
            );

        // 1. target_type = 'work' with matching targetId and workId -> succeeds
        await db
            .into(db.playbackProgresses)
            .insert(
              PlaybackProgressesCompanion.insert(
                targetType: 'work',
                targetId: workId,
                workId: Value(workId),
                episodeId: const Value(null),
                positionMs: const Value(12000),
              ),
            );

        // Duplicate target (target_type, target_id) fails unique constraint
        expect(
          () => db
              .into(db.playbackProgresses)
              .insert(
                PlaybackProgressesCompanion.insert(
                  targetType: 'work',
                  targetId: workId,
                  workId: Value(workId),
                  episodeId: const Value(null),
                  positionMs: const Value(24000),
                ),
              ),
          throwsA(isA<SqliteException>()),
        );

        // 2. target_type = 'work' but targetId does not match workId -> fails check constraint
        expect(
          () => db
              .into(db.playbackProgresses)
              .insert(
                PlaybackProgressesCompanion.insert(
                  targetType: 'work',
                  targetId: 99999,
                  workId: Value(workId),
                  episodeId: const Value(null),
                ),
              ),
          throwsA(isA<SqliteException>()),
        );

        // 3. target_type = 'work' with non-null episodeId -> fails check constraint
        expect(
          () => db
              .into(db.playbackProgresses)
              .insert(
                PlaybackProgressesCompanion.insert(
                  targetType: 'work',
                  targetId: workId,
                  workId: Value(workId),
                  episodeId: Value(episodeId),
                ),
              ),
          throwsA(isA<SqliteException>()),
        );

        // 4. target_type = 'episode' with matching targetId and episodeId -> succeeds
        final episodeProgressId = await db
            .into(db.playbackProgresses)
            .insert(
              PlaybackProgressesCompanion.insert(
                targetType: 'episode',
                targetId: episodeId,
                workId: const Value(null),
                episodeId: Value(episodeId),
                positionMs: const Value(5000),
              ),
            );
        expect(episodeProgressId, isPositive);
      },
    );
  });

  group('File DB reopen behavior', () {
    late Directory tempDir;
    late File dbFile;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('reelva_file_db_test_');
      dbFile = File('${tempDir.path}/reelva_test.sqlite');
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test(
      'reopening file DB retains tables, entries and relationships',
      () async {
        // Phase 1: create db, write source, entry, file, work, assignment
        final db1 = AppDatabase(executor: NativeDatabase(dbFile));

        final sourceId = await db1
            .into(db1.mediaSources)
            .insert(
              MediaSourcesCompanion.insert(
                kind: 'local',
                name: 'Persistent Source',
                rootLocator: 'D:/Movies',
              ),
            );

        final entryId = await db1
            .into(db1.mediaEntries)
            .insert(
              MediaEntriesCompanion.insert(
                sourceId: sourceId,
                externalEntryId: 'ext-persistent-1',
                relativeLocator: 'Avatar.mkv',
                name: 'Avatar.mkv',
                isDirectory: false,
                size: const Value(1024 * 1024 * 500),
              ),
            );

        final fileId = await db1
            .into(db1.mediaFiles)
            .insert(
              MediaFilesCompanion.insert(
                entryId: entryId,
                container: const Value('mkv'),
                parseState: const Value('pending'),
              ),
            );

        final workId = await db1
            .into(db1.works)
            .insert(
              WorksCompanion.insert(
                title: 'Avatar',
                metadataSource: const Value('local'),
              ),
            );

        await db1
            .into(db1.mediaAssignments)
            .insert(
              MediaAssignmentsCompanion.insert(
                fileId: fileId,
                workId: Value(workId),
                episodeId: const Value(null),
              ),
            );

        await db1.close();

        // Phase 2: reopen same file in a brand new AppDatabase instance
        final db2 = AppDatabase(executor: NativeDatabase(dbFile));

        final sources = await db2.select(db2.mediaSources).get();
        expect(sources, hasLength(1));
        expect(sources.first.id, sourceId);
        expect(sources.first.name, 'Persistent Source');
        expect(sources.first.rootLocator, 'D:/Movies');

        final entries = await db2.select(db2.mediaEntries).get();
        expect(entries, hasLength(1));
        expect(entries.first.id, entryId);
        expect(entries.first.name, 'Avatar.mkv');
        expect(entries.first.size, 1024 * 1024 * 500);

        final files = await db2.select(db2.mediaFiles).get();
        expect(files, hasLength(1));
        expect(files.first.id, fileId);
        expect(files.first.container, 'mkv');

        final works = await db2.select(db2.works).get();
        expect(works, hasLength(1));
        expect(works.first.id, workId);
        expect(works.first.title, 'Avatar');

        final assignments = await db2.select(db2.mediaAssignments).get();
        expect(assignments, hasLength(1));
        expect(assignments.first.fileId, fileId);
        expect(assignments.first.workId, workId);

        await db2.close();
      },
    );
  });
}
