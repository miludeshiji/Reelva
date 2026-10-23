import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

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
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase({QueryExecutor? executor})
    : super(executor ?? driftDatabase(name: 'reelva'));

  @override
  int get schemaVersion => 1;

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
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );
}
