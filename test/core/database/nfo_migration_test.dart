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
  test('v3 升级保留普通源和观看历史，清理已移除源及凭据', () async {
    final directory = await Directory.systemTemp.createTemp(
      'reelva_nfo_migration_',
    );
    final file = File(p.join(directory.path, 'library.sqlite'));
    var db = AppDatabase(executor: NativeDatabase(file));
    try {
      final repo = MediaLibraryRepository(db);
      final retired = await repo.upsertSource(
        kind: 'openlist',
        name: '旧源',
        rootLocator: 'https://example.test/#/Movies',
        credentialRef: 'retired-credential',
      );
      final active = await repo.upsertSource(
        kind: 'local',
        name: '本地',
        rootLocator: directory.path,
      );
      final indexed = await repo.indexSourceFiles(retired.id, const [
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

      final deletedCredentials = <String>[];
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
        removeRetiredCredentials: (references) async {
          deletedCredentials.addAll(references);
        },
      );
      final sources = await db.select(db.mediaSources).get();
      expect(sources.map((source) => source.id), [active.id]);
      expect(deletedCredentials, ['retired-credential']);
      expect(await db.select(db.mediaEntries).get(), isEmpty);
      final progress = await db.select(db.playbackProgresses).getSingle();
      expect(progress.positionMs, 12345);
      expect(progress.lastFileId, isNull);
      expect(
        (await db.select(db.works).get()).map((work) => work.title).toSet(),
        {'历史电影', '未关联的本地作品'},
      );
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
