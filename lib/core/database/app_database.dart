import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'tables.dart';

part 'app_database.g.dart';

@DriftDatabase(
  tables: [
    MediaSources,
    MediaEntries,
    MediaFiles,
    Works,
    Seasons,
    Episodes,
    MediaAssignments,
    PlaybackProgresses,
    ExternalIds,
    MetadataCaches,
    SyncState,
    SyncCursors,
    SyncLocalRegisters,
    SyncOutbox,
    SyncPending,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase({QueryExecutor? executor, this.removeRetiredCredentials})
    : super(
        executor ??
            driftDatabase(
              name: 'reelva',
              native: !kIsWeb && defaultTargetPlatform == TargetPlatform.windows
                  ? const DriftNativeOptions(
                      databaseDirectory: getApplicationSupportDirectory,
                    )
                  : null,
            ),
      );

  @override
  int get schemaVersion => 4;

  final Future<void> Function(List<String>)? removeRetiredCredentials;
  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      await m.createAll();

      // Invariant: seasons must belong to a series (type = 'series', rejecting null and movie)
      await customStatement('''
            CREATE TRIGGER trg_season_series_check
            BEFORE INSERT ON seasons
            WHEN EXISTS (SELECT 1 FROM works WHERE id = NEW.series_id AND (type IS NULL OR type != 'series'))
            BEGIN
              SELECT RAISE(ABORT, 'Season must belong to a series work');
            END;
          ''');
      await customStatement('''
            CREATE TRIGGER trg_season_series_check_update
            BEFORE UPDATE OF series_id ON seasons
            WHEN EXISTS (SELECT 1 FROM works WHERE id = NEW.series_id AND (type IS NULL OR type != 'series'))
            BEGIN
              SELECT RAISE(ABORT, 'Season must belong to a series work');
            END;
          ''');

      // Invariant: media_assignments work_id cannot point to a series (series-as-movie prevention)
      await customStatement('''
            CREATE TRIGGER trg_assignment_not_series_movie
            BEFORE INSERT ON media_assignments
            WHEN NEW.work_id IS NOT NULL AND EXISTS (SELECT 1 FROM works WHERE id = NEW.work_id AND type = 'series')
            BEGIN
              SELECT RAISE(ABORT, 'Cannot assign series work directly as movie');
            END;
          ''');
      await customStatement('''
            CREATE TRIGGER trg_assignment_not_series_movie_update
            BEFORE UPDATE OF work_id ON media_assignments
            WHEN NEW.work_id IS NOT NULL AND EXISTS (SELECT 1 FROM works WHERE id = NEW.work_id AND type = 'series')
            BEGIN
              SELECT RAISE(ABORT, 'Cannot assign series work directly as movie');
            END;
          ''');

      // Invariant: updating works.type must not violate existing season or assignment relationships
      await customStatement('''
            CREATE TRIGGER trg_work_type_update_seasons
            BEFORE UPDATE OF type ON works
            WHEN (NEW.type IS NULL OR NEW.type != 'series') AND EXISTS (SELECT 1 FROM seasons WHERE series_id = OLD.id)
            BEGIN
              SELECT RAISE(ABORT, 'Cannot change work type from series while seasons exist');
            END;
          ''');
      await customStatement('''
            CREATE TRIGGER trg_work_type_update_assignments
            BEFORE UPDATE OF type ON works
            WHEN NEW.type = 'series' AND EXISTS (SELECT 1 FROM media_assignments WHERE work_id = OLD.id)
            BEGIN
              SELECT RAISE(ABORT, 'Cannot change work type to series while movie assignments exist');
            END;
          ''');
    },
    onUpgrade: (m, from, to) async {
      if (from < 2) {
        await m.createTable(externalIds);
        await m.createTable(metadataCaches);
        await m.addColumn(mediaFiles, mediaFiles.candidateType);
        await m.addColumn(mediaFiles, mediaFiles.candidateSeasonNumber);
        await m.addColumn(mediaFiles, mediaFiles.candidateEpisodeNumber);
        await m.addColumn(mediaFiles, mediaFiles.candidateDetails);
      }
      if (from < 3) {
        await m.createTable(syncState);
        await m.createTable(syncCursors);
        await m.createTable(syncLocalRegisters);
        await m.createTable(syncOutbox);
        await m.createTable(syncPending);
      }
      if (from < 4) {
        await m.addColumn(works, works.posterLocator);
        await m.addColumn(works, works.backdropLocator);
        await m.addColumn(works, works.premiered);
        await m.addColumn(episodes, episodes.tmdbId);
      }
    },
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON');
      // 清理已移除的源类型；作品观看历史继续保留。
      final retired = await customSelect(
        "SELECT credential_ref FROM media_sources WHERE kind = 'openlist'",
      ).get();
      if (retired.isNotEmpty) {
        await removeRetiredCredentials?.call(
          retired
              .map((row) => row.readNullable<String>('credential_ref'))
              .whereType<String>()
              .toList(),
        );
        final workIds = await customSelect(
          '''SELECT DISTINCT COALESCE(a.work_id, s.series_id) AS work_id
          FROM media_assignments a JOIN media_files f ON f.id = a.file_id
          JOIN media_entries e ON e.id = f.entry_id JOIN media_sources ms ON ms.id = e.source_id
          LEFT JOIN episodes ep ON ep.id = a.episode_id LEFT JOIN seasons s ON s.id = ep.season_id
          WHERE ms.kind = 'openlist'
        ''',
        ).get();
        await customStatement(
          "DELETE FROM media_sources WHERE kind = 'openlist'",
        );
        final retiredWorkIds = workIds
            .map((row) => row.read<int>('work_id'))
            .toList();
        if (retiredWorkIds.isNotEmpty) {
          await customStatement(
            '''DELETE FROM works
          WHERE id IN (${List.filled(retiredWorkIds.length, '?').join(',')}) AND
          NOT EXISTS (SELECT 1 FROM media_assignments a LEFT JOIN episodes e ON e.id = a.episode_id
            LEFT JOIN seasons s ON s.id = e.season_id WHERE a.work_id = works.id OR s.series_id = works.id)
          AND NOT EXISTS (SELECT 1 FROM playback_progress p LEFT JOIN episodes e ON e.id = p.episode_id
            LEFT JOIN seasons s ON s.id = e.season_id WHERE p.work_id = works.id OR s.series_id = works.id)''',
            retiredWorkIds,
          );
        }
      }
    },
  );
}
