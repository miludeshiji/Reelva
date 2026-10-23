import 'dart:io';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reelva/core/database/app_database.dart';
import 'package:reelva/features/progress/domain/playback_progress.dart';
import 'package:reelva/features/progress/infrastructure/playback_progress_repository.dart';

void main() {
  group('Schema v2 migration and tables', () {
    test(
      'migrates from v1 database preserving data and adding v2 tables',
      () async {
        final tempDir = Directory.systemTemp.createTempSync(
          'reelva_migration_test_',
        );
        final dbFile = File('${tempDir.path}/test_v1.db');

        try {
          // 1. 手动以 v1 结构创建数据库并写入初始数据
          final rawDb = NativeDatabase(dbFile);
          try {
            await rawDb.ensureOpen(_SimpleV1User());
            await rawDb.runCustom('PRAGMA foreign_keys = ON;');
            await rawDb.runCustom('PRAGMA user_version = 1;');
            // 创建 v1 表结构
            await rawDb.runCustom('''
              CREATE TABLE media_sources (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                kind TEXT NOT NULL,
                name TEXT NOT NULL,
                root_locator TEXT NOT NULL,
                credential_ref TEXT,
                enabled INTEGER NOT NULL DEFAULT 1,
                extensions TEXT NOT NULL DEFAULT '["mkv","mp4"]',
                excluded_directories TEXT NOT NULL DEFAULT '[]',
                scan_revision INTEGER NOT NULL DEFAULT 0,
                last_scan_at INTEGER,
                error_message TEXT,
                UNIQUE (kind, root_locator)
              );
            ''');
            await rawDb.runCustom('''
              CREATE TABLE media_entries (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                source_id INTEGER NOT NULL REFERENCES media_sources(id) ON DELETE CASCADE,
                external_entry_id TEXT NOT NULL,
                relative_locator TEXT NOT NULL,
                name TEXT NOT NULL,
                is_directory INTEGER NOT NULL,
                size INTEGER,
                modified_at INTEGER,
                etag TEXT,
                available INTEGER NOT NULL DEFAULT 1,
                last_seen_scan_id INTEGER NOT NULL DEFAULT 0,
                UNIQUE (source_id, external_entry_id)
              );
            ''');
            await rawDb.runCustom('''
              CREATE TABLE media_files (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                entry_id INTEGER NOT NULL UNIQUE REFERENCES media_entries(id) ON DELETE CASCADE,
                container TEXT,
                duration_ms INTEGER,
                resolution_width INTEGER,
                resolution_height INTEGER,
                video_codec TEXT,
                audio_codec TEXT,
                parse_state TEXT NOT NULL DEFAULT 'pending'
              );
            ''');
            await rawDb.runCustom('''
              CREATE TABLE works (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                type TEXT,
                title TEXT NOT NULL,
                original_title TEXT,
                year INTEGER,
                overview TEXT,
                poster_path TEXT,
                backdrop_path TEXT,
                metadata_source TEXT NOT NULL DEFAULT 'local',
                metadata_locked INTEGER NOT NULL DEFAULT 0,
                created_at INTEGER NOT NULL DEFAULT (strftime('%s', 'now')),
                updated_at INTEGER NOT NULL DEFAULT (strftime('%s', 'now')),
                CHECK (type IS NULL OR type IN ('movie', 'series'))
              );
            ''');
            await rawDb.runCustom('''
              CREATE TABLE seasons (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                series_id INTEGER NOT NULL REFERENCES works(id) ON DELETE CASCADE,
                season_number INTEGER NOT NULL,
                title TEXT,
                UNIQUE (series_id, season_number)
              );
            ''');
            await rawDb.runCustom('''
              CREATE TABLE episodes (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                season_id INTEGER NOT NULL REFERENCES seasons(id) ON DELETE CASCADE,
                episode_number INTEGER NOT NULL,
                title TEXT,
                overview TEXT,
                air_date INTEGER,
                UNIQUE (season_id, episode_number)
              );
            ''');
            await rawDb.runCustom('''
              CREATE TABLE media_assignments (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                file_id INTEGER NOT NULL REFERENCES media_files(id) ON DELETE CASCADE,
                work_id INTEGER REFERENCES works(id) ON DELETE CASCADE,
                episode_id INTEGER REFERENCES episodes(id) ON DELETE CASCADE,
                edition_label TEXT,
                preferred INTEGER NOT NULL DEFAULT 0,
                CHECK ((work_id IS NOT NULL AND episode_id IS NULL) OR (work_id IS NULL AND episode_id IS NOT NULL))
              );
            ''');
            await rawDb.runCustom('''
              CREATE TABLE playback_progress (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                target_type TEXT NOT NULL,
                target_id INTEGER NOT NULL,
                work_id INTEGER REFERENCES works(id) ON DELETE CASCADE,
                episode_id INTEGER REFERENCES episodes(id) ON DELETE CASCADE,
                last_file_id INTEGER REFERENCES media_files(id) ON DELETE SET NULL,
                position_ms INTEGER NOT NULL DEFAULT 0,
                duration_ms INTEGER NOT NULL DEFAULT 0,
                completed INTEGER NOT NULL DEFAULT 0,
                updated_at INTEGER NOT NULL DEFAULT (strftime('%s', 'now')),
                UNIQUE (target_type, target_id),
                CHECK (
                  (target_type = 'work' AND work_id IS NOT NULL AND target_id = work_id AND episode_id IS NULL) OR
                  (target_type = 'episode' AND episode_id IS NOT NULL AND target_id = episode_id AND work_id IS NULL)
                )
              );
            ''');

            // 创建 v1 原有触发器（保持与 app_database.dart 一致）
            await rawDb.runCustom('''
              CREATE TRIGGER trg_season_series_check
              BEFORE INSERT ON seasons
              WHEN EXISTS (SELECT 1 FROM works WHERE id = NEW.series_id AND (type IS NULL OR type != 'series'))
              BEGIN
                SELECT RAISE(ABORT, 'Season must belong to a series work');
              END;
            ''');
            await rawDb.runCustom('''
              CREATE TRIGGER trg_season_series_check_update
              BEFORE UPDATE OF series_id ON seasons
              WHEN EXISTS (SELECT 1 FROM works WHERE id = NEW.series_id AND (type IS NULL OR type != 'series'))
              BEGIN
                SELECT RAISE(ABORT, 'Season must belong to a series work');
              END;
            ''');
            await rawDb.runCustom('''
              CREATE TRIGGER trg_assignment_not_series_movie
              BEFORE INSERT ON media_assignments
              WHEN NEW.work_id IS NOT NULL AND EXISTS (SELECT 1 FROM works WHERE id = NEW.work_id AND type = 'series')
              BEGIN
                SELECT RAISE(ABORT, 'Cannot assign series work directly as movie');
              END;
            ''');
            await rawDb.runCustom('''
              CREATE TRIGGER trg_assignment_not_series_movie_update
              BEFORE UPDATE OF work_id ON media_assignments
              WHEN NEW.work_id IS NOT NULL AND EXISTS (SELECT 1 FROM works WHERE id = NEW.work_id AND type = 'series')
              BEGIN
                SELECT RAISE(ABORT, 'Cannot assign series work directly as movie');
              END;
            ''');
            await rawDb.runCustom('''
              CREATE TRIGGER trg_work_type_update_seasons
              BEFORE UPDATE OF type ON works
              WHEN (NEW.type IS NULL OR NEW.type != 'series') AND EXISTS (SELECT 1 FROM seasons WHERE series_id = OLD.id)
              BEGIN
                SELECT RAISE(ABORT, 'Cannot change work type from series while seasons exist');
              END;
            ''');
            await rawDb.runCustom('''
              CREATE TRIGGER trg_work_type_update_assignments
              BEFORE UPDATE OF type ON works
              WHEN NEW.type = 'series' AND EXISTS (SELECT 1 FROM media_assignments WHERE work_id = OLD.id)
              BEGIN
                SELECT RAISE(ABORT, 'Cannot change work type to series while movie assignments exist');
              END;
            ''');
            // 插入 v1 测试数据
            await rawDb.runCustom('''
              INSERT INTO media_sources (id, kind, name, root_locator)
              VALUES (1, 'local', 'Movies', '/media/movies');
            ''');
            await rawDb.runCustom('''
              INSERT INTO media_entries (id, source_id, external_entry_id, relative_locator, name, is_directory)
              VALUES (1, 1, 'entry-1', 'Movie.mp4', 'Movie.mp4', 0);
            ''');
            await rawDb.runCustom('''
              INSERT INTO media_files (id, entry_id, parse_state)
              VALUES (1, 1, 'pending');
            ''');
            await rawDb.runCustom('''
              INSERT INTO works (id, title, metadata_source, metadata_locked)
              VALUES (1, 'Movie', 'local', 0);
            ''');
            await rawDb.runCustom('''
              INSERT INTO media_assignments (id, file_id, work_id)
              VALUES (1, 1, 1);
            ''');
            await rawDb.runCustom('''
              INSERT INTO playback_progress (id, target_type, target_id, work_id, position_ms, duration_ms)
              VALUES (1, 'work', 1, 1, 5000, 100000);
            ''');
          } finally {
            await rawDb.close();
          }

          // 2. 用升级后的 AppDatabase (Schema v2) 打开该文件
          final appDb = AppDatabase(executor: NativeDatabase(dbFile));
          try {
            // 验证原数据依然完整
            final sources = await appDb.select(appDb.mediaSources).get();
            expect(sources, hasLength(1));
            expect(sources.first.name, 'Movies');

            final works = await appDb.select(appDb.works).get();
            expect(works, hasLength(1));
            expect(works.first.title, 'Movie');

            final progress = await appDb.select(appDb.playbackProgresses).get();
            expect(progress, hasLength(1));
            expect(progress.first.positionMs, 5000);

            // 验证迁移后的 v1 进度可通过新版 PlaybackProgressRepository 正常读取并进入继续观看展架
            final progressRepo = PlaybackProgressRepository(db: appDb);
            final migratedProgress = await progressRepo.getProgress(1);
            expect(migratedProgress, isNotNull);
            expect(migratedProgress!.targetType, ProgressTargetType.work);
            expect(migratedProgress.targetId, 1);
            expect(
              migratedProgress.position,
              const Duration(milliseconds: 5000),
            );
            expect(
              migratedProgress.duration,
              const Duration(milliseconds: 100000),
            );
            expect(migratedProgress.completed, isFalse);

            final continueList = await progressRepo.getContinueWatching();
            expect(continueList, hasLength(1));
            expect(continueList.first.workId, 1);
            expect(continueList.first.title, 'Movie');
            expect(continueList.first.fileId, 1);
            expect(
              continueList.first.position,
              const Duration(milliseconds: 5000),
            );
            expect(continueList.first.available, isTrue);
            // 验证 v2 新增的 candidate 列已存在
            final cols = await appDb
                .customSelect("PRAGMA table_info('media_files')")
                .get();
            final colNames = cols.map((r) => r.read<String>('name')).toSet();
            expect(colNames.contains('candidate_type'), isTrue);
            expect(colNames.contains('candidate_season_number'), isTrue);
            expect(colNames.contains('candidate_episode_number'), isTrue);
            expect(colNames.contains('candidate_details'), isTrue);

            // 验证 external_ids 表与 metadata_cache 表通过 Drift 生成 Companion 插入正常（避免时间戳单位混用）
            await appDb
                .into(appDb.externalIds)
                .insert(
                  ExternalIdsCompanion.insert(
                    workId: 1,
                    provider: 'tmdb',
                    providerEntityId: 'movie:1001',
                  ),
                );
            final extList = await appDb.select(appDb.externalIds).get();
            expect(extList, hasLength(1));
            expect(extList.first.workId, 1);
            expect(extList.first.providerEntityId, 'movie:1001');

            final futureExp = DateTime.now().add(const Duration(hours: 1));
            await appDb
                .into(appDb.metadataCaches)
                .insert(
                  MetadataCachesCompanion.insert(
                    cacheKey: 'test_cache_key',
                    provider: 'tmdb',
                    payloadJson: '{"title":"Test"}',
                    expiresAt: futureExp,
                  ),
                );
            final cacheList = await appDb.select(appDb.metadataCaches).get();
            expect(cacheList, hasLength(1));
            expect(cacheList.first.payloadJson, '{"title":"Test"}');

            // 验证迁移后 v1 触发器依然保持约束：无法直接将 series 作品挂载为 movie assignment
            final seriesWorkId = await appDb
                .into(appDb.works)
                .insert(
                  WorksCompanion.insert(
                    title: 'Series Test',
                    type: const Value('series'),
                  ),
                );
            await expectLater(
              () => appDb
                  .into(appDb.mediaAssignments)
                  .insert(
                    MediaAssignmentsCompanion.insert(
                      fileId: 1,
                      workId: Value(seriesWorkId),
                      episodeId: const Value(null),
                    ),
                  ),
              throwsException,
            );
          } finally {
            await appDb.close();
          }
        } finally {
          if (tempDir.existsSync()) {
            tempDir.deleteSync(recursive: true);
          }
        }
      },
    );

    test(
      'external_ids unique constraint on provider and provider_entity_id',
      () async {
        final db = AppDatabase(executor: NativeDatabase.memory());
        try {
          await db
              .into(db.works)
              .insert(
                WorksCompanion.insert(
                  title: 'Test Movie 1',
                  type: const Value('movie'),
                ),
              );
          await db
              .into(db.works)
              .insert(
                WorksCompanion.insert(
                  title: 'Test Movie 2',
                  type: const Value('movie'),
                ),
              );

          // 链接 work 1 到 tmdb movie:550
          await db.customStatement(
            'INSERT INTO external_ids (work_id, provider, provider_entity_id, created_at) VALUES (1, ?, ?, ?)',
            ['tmdb', 'movie:550', DateTime.now().millisecondsSinceEpoch],
          );
          var row = await db
              .customSelect(
                'SELECT work_id FROM external_ids WHERE provider = ? AND provider_entity_id = ?',
                variables: [
                  Variable.withString('tmdb'),
                  Variable.withString('movie:550'),
                ],
              )
              .getSingleOrNull();
          expect(row?.read<int>('work_id'), 1);

          // 唯一约束校验：同 (provider, provider_entity_id) 冲突抛出异常
          expect(
            () => db.customStatement(
              'INSERT INTO external_ids (work_id, provider, provider_entity_id, created_at) VALUES (2, ?, ?, ?)',
              ['tmdb', 'movie:550', DateTime.now().millisecondsSinceEpoch],
            ),
            throwsException,
          );

          // 级联删除：删除 work 1 后，对应的 external_ids 记录被级联删除
          await (db.delete(db.works)..where((w) => w.id.equals(1))).go();
          final afterDelete = await db
              .customSelect(
                'SELECT work_id FROM external_ids WHERE provider = ? AND provider_entity_id = ?',
                variables: [
                  Variable.withString('tmdb'),
                  Variable.withString('movie:550'),
                ],
              )
              .getSingleOrNull();
          expect(afterDelete, isNull);
        } finally {
          await db.close();
        }
      },
    );

    test('metadata_cache expiration and cleanup', () async {
      final db = AppDatabase(executor: NativeDatabase.memory());
      try {
        final pastDate = DateTime.now().subtract(const Duration(minutes: 5));
        final futureDate = DateTime.now().add(const Duration(hours: 2));

        await db.customStatement(
          'INSERT INTO metadata_cache (cache_key, provider, payload_json, expires_at, updated_at) VALUES (?, ?, ?, ?, ?)',
          [
            'expired_key',
            'tmdb',
            '{"status":"expired"}',
            pastDate.millisecondsSinceEpoch,
            DateTime.now().millisecondsSinceEpoch,
          ],
        );

        await db.customStatement(
          'INSERT INTO metadata_cache (cache_key, provider, payload_json, expires_at, updated_at) VALUES (?, ?, ?, ?, ?)',
          [
            'valid_key',
            'tmdb',
            '{"status":"valid"}',
            futureDate.millisecondsSinceEpoch,
            DateTime.now().millisecondsSinceEpoch,
          ],
        );

        // 清理过期缓存
        final nowMs = DateTime.now().millisecondsSinceEpoch;
        await db.customStatement(
          'DELETE FROM metadata_cache WHERE expires_at < ?',
          [nowMs],
        );

        final expiredRow = await db
            .customSelect(
              'SELECT cache_key FROM metadata_cache WHERE cache_key = ?',
              variables: [Variable.withString('expired_key')],
            )
            .getSingleOrNull();
        expect(expiredRow, isNull);

        final validRow = await db
            .customSelect(
              'SELECT cache_key FROM metadata_cache WHERE cache_key = ?',
              variables: [Variable.withString('valid_key')],
            )
            .getSingleOrNull();
        expect(validRow, isNotNull);
      } finally {
        await db.close();
      }
    });
  });
}

class _SimpleV1User extends QueryExecutorUser {
  @override
  int get schemaVersion => 1;

  @override
  Future<void> beforeOpen(
    QueryExecutor executor,
    OpeningDetails details,
  ) async {}
}
