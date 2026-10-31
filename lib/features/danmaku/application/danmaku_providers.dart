import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../player/domain/playback_resource.dart';
import '../../sources/application/source_providers.dart';
import '../../sources/domain/media_sidecar_adapter.dart';
import '../domain/danmaku.dart';
import '../infrastructure/danmaku_api.dart';
import '../infrastructure/danmaku_store.dart';
import '../infrastructure/local_danmaku_loader.dart';
import 'danmaku_controller.dart';

final danmakuStoreProvider = Provider<DanmakuStore>((ref) => DanmakuStore());

final danmakuApiProvider = Provider.autoDispose<DanmakuApi>((ref) {
  final api = DanmakuApi(store: ref.watch(danmakuStoreProvider));
  ref.onDispose(api.dispose);
  return api;
});

final danmakuControllerProvider = Provider.autoDispose<DanmakuController>((
  ref,
) {
  const localFiles = LocalDanmakuLoader();
  final controller = DanmakuController(
    api: ref.watch(danmakuApiProvider),
    store: ref.watch(danmakuStoreProvider),
    localPicker: localFiles.pick,
    localLoader: (resource) async {
      if (resource.uri.scheme == 'file' || resource.libraryFileId == null) {
        return localFiles.loadSibling(resource);
      }
      final repository = ref.read(mediaLibraryRepositoryProvider);
      final video = await repository.getVideo(resource.libraryFileId!);
      if (video == null) return null;
      final source = await repository.getSource(video.sourceId);
      final adapter = ref.read(sourceAdaptersProvider)[source.kind];
      if (!source.enabled || adapter is! MediaSidecarAdapter) return null;
      return localFiles.loadFromSource(
        adapter: adapter,
        source: source,
        videoId: video.externalId,
        fileName: resource.fileName,
      );
    },
    queryLoader: (PlaybackResource resource) async {
      final fallback = DanmakuQuery.fromResource(resource);
      if (resource.libraryFileId == null) return fallback;
      final files = await ref
          .read(mediaLibraryRepositoryProvider)
          .metadataFiles(
            fileIds: [resource.libraryFileId!],
            matchedOnly: false,
          );
      if (files.isEmpty) return fallback;
      final file = files.single;
      final work = file.metadata;
      final episode = file.episode;
      final identity = work.tmdbId == null
          ? 'work:${file.workId}'
          : 'tmdb:${work.type}:${work.tmdbId}';
      return DanmakuQuery(
        title: work.title,
        originalTitle: work.originalTitle,
        fileName: resource.fileName,
        contentKey: episode == null
            ? identity
            : '$identity:${episode.seasonNumber}:${episode.episodeNumber}',
        versionKey: fallback.versionKey,
        year: work.year,
        season: episode?.seasonNumber,
        episode: episode?.episodeNumber,
        tmdbId: work.tmdbId,
        movie: work.type == 'movie',
        localPath: fallback.localPath,
        ambiguous: fallback.ambiguous,
      );
    },
  );
  ref.onDispose(controller.dispose);
  return controller;
});
