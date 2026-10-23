import 'dart:io';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reelva/core/database/app_database.dart';
import 'package:reelva/features/progress/infrastructure/playback_progress_repository.dart';
import 'package:reelva/features/sync/domain/sync_models.dart';
import 'package:reelva/features/sync/infrastructure/sync_repository.dart';

void main() {
  group('Schema v3 migration and sync integration', () {
    test('migrates from v2 database preserving existing data and enabling real SyncRepository workflow', () async {
      final tempDir = Directory.systemTemp.createTempSync(
        'reelva_schema_v3_test_',
      );
      final dbFile = File('${tempDir.path}/test_v2.db');

      try {
        // 1. 手动以真实 v2 结构创建数据库并写入初始数据
        final rawDb = NativeDatabase(dbFile);
        try {
          await rawDb.ensureOpen(_SimpleV2User());
          await rawDb.runCustom('PRAGMA foreign_keys = ON;');
          await rawDb.runCustom('PRAGMA user_version = 2;');

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
                parse_state TEXT NOT NULL DEFAULT 'pending',
                candidate_type TEXT,
                candidate_season_number INTEGER,
                candidate_episode_number INTEGER,
                candidate_details TEXT
              );
            ''');
          await rawDb.runCustom('''
              CREATE TABLE works (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                type TEXT CHECK (type IS NULL OR type IN ('movie', 'series')),
                title TEXT NOT NULL,
                original_title TEXT,
                year INTEGER,
                overview TEXT,
                poster_path TEXT,
                backdrop_path TEXT,
                metadata_source TEXT NOT NULL DEFAULT 'local',
                metadata_locked INTEGER NOT NULL DEFAULT 0,
                created_at INTEGER NOT NULL DEFAULT (strftime('%s', 'now')),
                updated_at INTEGER NOT NULL DEFAULT (strftime('%s', 'now'))
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
          await rawDb.runCustom('''
              CREATE TABLE external_ids (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                work_id INTEGER NOT NULL REFERENCES works(id) ON DELETE CASCADE,
                provider TEXT NOT NULL,
                provider_entity_id TEXT NOT NULL,
                created_at INTEGER NOT NULL DEFAULT (strftime('%s', 'now')),
                UNIQUE (provider, provider_entity_id)
              );
            ''');
          await rawDb.runCustom('''
              CREATE TABLE metadata_cache (
                cache_key TEXT NOT NULL PRIMARY KEY,
                provider TEXT NOT NULL,
                payload_json TEXT NOT NULL,
                etag TEXT,
                expires_at INTEGER NOT NULL,
                updated_at INTEGER NOT NULL DEFAULT (strftime('%s', 'now'))
              );
            ''');

          // 写入初始真实业务数据
          await rawDb.runCustom('''
              INSERT INTO media_sources (id, kind, name, root_locator)
              VALUES (1, 'local', 'Movies', '/media/movies');
            ''');
          await rawDb.runCustom('''
              INSERT INTO media_entries (id, source_id, external_entry_id, relative_locator, name, is_directory)
              VALUES (1, 1, 'ent_1', 'Inception.mkv', 'Inception.mkv', 0);
            ''');
          await rawDb.runCustom('''
              INSERT INTO media_files (id, entry_id, container, duration_ms, resolution_width, resolution_height, parse_state)
              VALUES (1, 1, 'mkv', 8880000, 1920, 1080, 'parsed');
            ''');
          await rawDb.runCustom('''
              INSERT INTO works (id, type, title, year, metadata_locked)
              VALUES (1, 'movie', 'Inception', 2010, 1);
            ''');
          await rawDb.runCustom('''
              INSERT INTO media_assignments (id, file_id, work_id, preferred)
              VALUES (1, 1, 1, 1);
            ''');
          await rawDb.runCustom('''
              INSERT INTO playback_progress (id, target_type, target_id, work_id, last_file_id, position_ms, duration_ms)
              VALUES (1, 'work', 1, 1, 1, 60000, 120000);
            ''');
          await rawDb.runCustom('''
              INSERT INTO external_ids (id, work_id, provider, provider_entity_id)
              VALUES (1, 1, 'tmdb', 'movie:27205');
            ''');
          await rawDb.runCustom('''
              INSERT INTO metadata_cache (cache_key, provider, payload_json, expires_at)
              VALUES ('cache_inc', 'tmdb', '{"title":"Inception"}', 9999999999);
            ''');
        } finally {
          await rawDb.close();
        }

        // 2. 用 AppDatabase 打开该 v2 数据库文件触发升级至 Schema v3
        final appDb = AppDatabase(executor: NativeDatabase(dbFile));
        try {
          expect(appDb.schemaVersion, 3);

          // 验证原有的 v1 和 v2 业务数据全部完好无损
          final sources = await appDb.select(appDb.mediaSources).get();
          expect(sources, hasLength(1));
          expect(sources.first.name, 'Movies');

          final works = await appDb.select(appDb.works).get();
          expect(works, hasLength(1));
          expect(works.first.title, 'Inception');
          expect(works.first.metadataLocked, isTrue);

          final progressRepo = PlaybackProgressRepository(db: appDb);
          final prog = await progressRepo.getProgress(1);
          expect(prog, isNotNull);
          expect(prog!.targetId, 1);
          expect(prog.position, const Duration(milliseconds: 60000));

          final extIds = await appDb.select(appDb.externalIds).get();
          expect(extIds, hasLength(1));
          expect(extIds.first.providerEntityId, 'movie:27205');

          final caches = await appDb.select(appDb.metadataCaches).get();
          expect(caches, hasLength(1));
          expect(caches.first.cacheKey, 'cache_inc');

          // 3. 验证升级后真实的 SyncRepository 工作流直接可用
          final syncRepo = SyncRepository(
            appDb,
            createDeviceId: () => '1234567890abcdef1234567890abcdef',
          );

          // 捕获本地数据变更（包含已匹配 TMDB 的电影进度与锁定元数据）
          await syncRepo.captureLocalChanges();

          // 准备发件箱
          final batch = await syncRepo.prepareUpload();
          expect(batch, isNotNull);
          expect(batch!.deviceId, '1234567890abcdef1234567890abcdef');
          expect(batch.sequence, 1);
          expect(batch.records, hasLength(2));

          final kinds = batch.records.map((r) => r.kind).toSet();
          expect(kinds, contains(SyncRecordKind.progress));
          expect(kinds, contains(SyncRecordKind.metadata));

          // 确认上传，持久化本设备游标并清理发件箱
          await syncRepo.acknowledgeUpload(batch);

          final nextBatch = await syncRepo.prepareUpload();
          expect(nextBatch, isNull);

          final cursors = await syncRepo.readCursors();
          expect(cursors['1234567890abcdef1234567890abcdef'], 1);
        } finally {
          await appDb.close();
        }
      } finally {
        if (tempDir.existsSync()) {
          tempDir.deleteSync(recursive: true);
        }
      }
    });

    test('migrates from v1 database directly to v3 creating both v2 and v3 tables without data loss', () async {
      final tempDir = Directory.systemTemp.createTempSync(
        'reelva_schema_v1_to_v3_test_',
      );
      final dbFile = File('${tempDir.path}/test_v1.db');

      try {
        final rawDb = NativeDatabase(dbFile);
        try {
          await rawDb.ensureOpen(_SimpleV1User());
          await rawDb.runCustom('PRAGMA foreign_keys = ON;');
          await rawDb.runCustom('PRAGMA user_version = 1;');
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
                updated_at INTEGER NOT NULL DEFAULT (strftime('%s', 'now'))
              );
            ''');
          await rawDb.runCustom('''
              INSERT INTO works (id, type, title) VALUES (1, 'movie', 'Matrix');
            ''');
        } finally {
          await rawDb.close();
        }

        final appDb = AppDatabase(executor: NativeDatabase(dbFile));
        try {
          expect(appDb.schemaVersion, 3);
          final works = await appDb.select(appDb.works).get();
          expect(works, hasLength(1));
          expect(works.first.title, 'Matrix');

          // 验证 v2 增加的列与表均已生效
          final cols = await appDb
              .customSelect("PRAGMA table_info('media_files')")
              .get();
          final colNames = cols.map((r) => r.read<String>('name')).toSet();
          expect(colNames, contains('candidate_type'));
          expect(colNames, contains('candidate_season_number'));

          final v2Tables = await appDb
              .customSelect(
                "SELECT name FROM sqlite_master WHERE type='table' AND name IN ('external_ids', 'metadata_cache')",
              )
              .get();
          expect(v2Tables, hasLength(2));

          // 验证 v3 的 sync 表结构均已就绪
          final v3Tables = await appDb
              .customSelect(
                "SELECT name FROM sqlite_master WHERE type='table' AND name LIKE 'sync_%'",
              )
              .get();
          expect(
            v3Tables.map((r) => r.read<String>('name')).toSet(),
            containsAll([
              'sync_state',
              'sync_cursors',
              'sync_local_registers',
              'sync_outbox',
              'sync_pending',
            ]),
          );
        } finally {
          await appDb.close();
        }
      } finally {
        if (tempDir.existsSync()) {
          tempDir.deleteSync(recursive: true);
        }
      }
    });
  });
}

class _SimpleV2User extends QueryExecutorUser {
  @override
  int get schemaVersion => 2;

  @override
  Future<void> beforeOpen(
    QueryExecutor executor,
    OpeningDetails details,
  ) async {}
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
