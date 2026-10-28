import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:reelva/core/database/app_database.dart';
import 'package:reelva/features/library/infrastructure/media_library_repository.dart';
import 'package:reelva/features/metadata/domain/tmdb_models.dart';
import 'package:reelva/features/sources/domain/source_models.dart';

void main() {
  test('重新打开及 v3 升级保留所有媒体源、凭据引用、索引和观看历史', () async {
    final directory = await Directory.systemTemp.createTemp(
      'reelva_nfo_migration_',
    );
    final file = File(p.join(directory.path, 'library.sqlite'));
    var db = AppDatabase(executor: NativeDatabase(file));
    try {
      final repo = MediaLibraryRepository(db);
      final openlist = await repo.upsertSource(
        kind: 'openlist',
        name: '网盘',
        rootLocator: 'https://example.test/#/Movies',
        credentialRef: 'openlist-credential',
      );
      final local = await repo.upsertSource(
        kind: 'local',
        name: '本地',
        rootLocator: directory.path,
      );
      final indexed = await repo.indexSourceFiles(openlist.id, const [
        MediaEntry(
          externalId: '/Movies/movie.mkv',
          locator: '/Movies/movie.mkv',
          name: 'movie.mkv',
          isDirectory: false,
        ),
      ]);
      final workId = await repo.applyMetadataToFiles({
        indexed.values.single: null,
      }, const TmdbWork(id: 42, type: 'movie', title: '历史电影'));
      await db
          .into(db.playbackProgresses)
          .insert(
            PlaybackProgressesCompanion.insert(
              targetType: 'work',
              targetId: workId!,
              workId: Value(workId),
              positionMs: const Value(12345),
              lastFileId: Value(indexed.values.single),
              updatedAt: Value(DateTime(2024)),
            ),
          );
      await db.into(db.works).insert(WorksCompanion.insert(title: '未关联的本地作品'));
      await db.close();

      Future<void> expectPreservedData() async {
        final sources = await db.select(db.mediaSources).get();
        expect(sources.map((source) => source.id).toSet(), {
          openlist.id,
          local.id,
        });
        expect(
          sources
              .singleWhere((source) => source.id == openlist.id)
              .credentialRef,
          'openlist-credential',
        );
        expect(
          (await db.select(db.mediaEntries).getSingle()).externalEntryId,
          '/Movies/movie.mkv',
        );
        expect(
          (await db.select(db.mediaFiles).getSingle()).id,
          indexed.values.single,
        );
        expect(
          (await db.select(db.mediaAssignments).getSingle()).workId,
          workId,
        );
        final progress = await db.select(db.playbackProgresses).getSingle();
        expect(progress.positionMs, 12345);
        expect(progress.lastFileId, indexed.values.single);
        expect(
          (await db.select(db.works).get()).map((work) => work.title).toSet(),
          {'历史电影', '未关联的本地作品'},
        );
      }

      db = AppDatabase(executor: NativeDatabase(file));
      await expectPreservedData();
      await db.close();

      db = AppDatabase(
        executor: NativeDatabase(
          file,
          setup: (raw) {
            // 模拟发布中的 v3 结构，确保确实执行 v3 -> v4 的增列迁移。
            for (final column in [
              'poster_locator',
              'backdrop_locator',
              'premiered',
            ]) {
              raw.execute('ALTER TABLE works DROP COLUMN $column');
            }
            raw.execute('ALTER TABLE episodes DROP COLUMN tmdb_id');
            raw.execute('PRAGMA user_version = 3');
          },
        ),
      );
      await expectPreservedData();
      await db.customStatement(
        'UPDATE works SET poster_locator = ?, premiered = ? WHERE id = ?',
        ['reelva-art://1/image', 0, workId],
      );
      expect(
        (await (db.select(
          db.works,
        )..where((work) => work.id.equals(workId))).getSingle()).posterLocator,
        'reelva-art://1/image',
      );
    } finally {
      await db.close();
      await directory.delete(recursive: true);
    }
  });
}
