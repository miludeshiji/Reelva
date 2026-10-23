import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:reelva/core/database/app_database.dart';
import 'package:reelva/features/library/infrastructure/media_library_repository.dart';
import 'package:reelva/features/progress/domain/playback_progress.dart';
import 'package:reelva/features/progress/infrastructure/playback_progress_repository.dart';
import 'package:reelva/features/sources/domain/source_models.dart';

void main() {
  test(
    'movie and episode progress survive database close and reopen',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'reelva_progress_',
      );
      final file = File(p.join(directory.path, 'library.sqlite'));
      var db = AppDatabase(executor: NativeDatabase(file));
      try {
        final library = MediaLibraryRepository(db);
        final source = await library.upsertSource(
          kind: 'local',
          rootLocator: '/media',
          name: 'Library',
        );
        final scan = await library.beginScan(source.id);
        await library.applyScanBatch(source.id, scan, [
          for (final name in ['Movie.Name.2024.mp4', 'Show.Name.S01E05.mkv'])
            MediaEntry(
              externalId: name,
              locator: name,
              name: name,
              isDirectory: false,
            ),
        ]);
        await library.finishScan(source.id, scan);
        final videos = await library.watchLibrary().first;
        final movieId = videos
            .firstWhere((v) => v.fileName.endsWith('.mp4'))
            .fileId;
        final episodeId = videos
            .firstWhere((v) => v.fileName.endsWith('.mkv'))
            .fileId;
        var repository = PlaybackProgressRepository(db: db);
        await repository.saveProgress(
          fileId: movieId,
          position: const Duration(seconds: 35),
          duration: const Duration(seconds: 120),
        );
        await repository.saveProgress(
          fileId: episodeId,
          position: const Duration(seconds: 45),
          duration: const Duration(seconds: 200),
        );
        final originalEpisode = await repository.getProgress(episodeId);
        await db.close();

        db = AppDatabase(executor: NativeDatabase(file));
        repository = PlaybackProgressRepository(db: db);
        final movie = await repository.getProgress(movieId);
        final episode = await repository.getProgress(episodeId);
        expect(movie!.targetType, ProgressTargetType.work);
        expect(movie.position, const Duration(seconds: 35));
        expect(movie.lastFileId, movieId);
        expect(episode!.targetType, ProgressTargetType.episode);
        expect(episode.targetId, originalEpisode!.targetId);
        expect(episode.position, const Duration(seconds: 45));
        expect(episode.lastFileId, episodeId);
        final continuing = await repository.getContinueWatching();
        expect(continuing.map((entry) => entry.fileId).toSet(), {
          movieId,
          episodeId,
        });
        final series = continuing.singleWhere(
          (entry) => entry.fileId == episodeId,
        );
        expect(series.seasonNumber, 1);
        expect(series.episodeNumber, 5);

        await repository.saveProgress(
          fileId: episodeId,
          position: const Duration(seconds: 60),
          duration: const Duration(seconds: 200),
        );
        expect(
          (await repository.getProgress(episodeId))!.targetId,
          originalEpisode.targetId,
        );
        expect(
          (await repository.getProgress(episodeId))!.position,
          const Duration(seconds: 60),
        );
        expect(
          (await repository.getProgress(movieId))!.position,
          const Duration(seconds: 35),
        );
      } finally {
        await db.close();
        await directory.delete(recursive: true);
      }
    },
  );
}
