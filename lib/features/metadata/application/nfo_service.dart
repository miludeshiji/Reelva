import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:path/path.dart' as p;

import '../../../core/logging/app_logger.dart';
import '../../../core/database/app_database.dart';
import '../../library/infrastructure/media_library_repository.dart';
import '../../sources/domain/media_sidecar_adapter.dart';
import '../../sources/domain/media_source_adapter.dart';
import '../../sources/domain/source_models.dart';
import '../../sources/infrastructure/remote_http_client.dart';
import '../domain/directory_context_resolver.dart';
import '../domain/matching_file.dart';
import '../domain/metadata_file.dart';
import '../domain/nfo_document.dart';
import '../domain/tmdb_models.dart';
import '../domain/work_metadata.dart';

class NfoResult {
  const NfoResult({this.saved = 0, this.errors = const []});
  final int saved;
  final List<String> errors;
}

class NfoDirectoryContext {
  NfoDirectoryContext(this.directory, this.document, this.entries);
  final List<MediaEntry> entries;
  final String directory;
  final NfoDocument document;
  int? workId;
}

String sourceArtworkLocator(int sourceId, String entryId, {String? version}) =>
    Uri(
      scheme: 'reelva-art',
      host: '$sourceId',
      path: '/image',
      queryParameters: {'entry': entryId, 'v': ?version},
    ).toString();

/// 文件操作在数据库事务外执行，失败不撤销已确认的匹配与观看记录。
class NfoService {
  NfoService({
    required this.repository,
    required this.adapters,
    required this.http,
  });
  final MediaLibraryRepository repository;
  final Map<String, MediaSourceAdapter> adapters;
  final RemoteHttpClient http;
  Future<void> _writes = Future.value();

  String _metadataSignature(MetadataFile file) {
    final metadata = file.metadata;
    final episode = file.episode;
    return jsonEncode([
      metadata.type,
      metadata.tmdbId,
      metadata.title,
      metadata.originalTitle,
      metadata.overview,
      metadata.year,
      metadata.premiered?.toIso8601String(),
      metadata.posterPath,
      metadata.backdropPath,
      episode?.seasonNumber,
      episode?.episodeNumber,
      episode?.tmdbId,
      episode?.title,
      episode?.overview,
      episode?.airDate?.toIso8601String(),
    ]);
  }

  Future<bool> _metadataWasSaved(MetadataFile file) async {
    final db = repository.db;
    final saved =
        await (db.select(db.syncState)
              ..where((row) => row.key.equals('nfo_saved:${file.fileId}')))
            .getSingleOrNull();
    return saved?.value == _metadataSignature(file);
  }

  Future<void> _rememberSavedMetadata(MetadataFile file) => repository.db
      .into(repository.db.syncState)
      .insertOnConflictUpdate(
        SyncStateCompanion.insert(
          key: 'nfo_saved:${file.fileId}',
          value: _metadataSignature(file),
        ),
      );

  Future<NfoDocument> _read(
    MediaSourceConfig source,
    MediaSidecarAdapter adapter,
    MediaEntry entry,
  ) async => NfoDocument.parse(
    utf8.decode(await adapter.readBytes(source, entry.externalId)),
  );

  Future<NfoDirectoryContext?> importDirectory(
    MediaSourceConfig source,
    String directory,
    List<MediaEntry> entries, {
    NfoDirectoryContext? inherited,
    void Function(String)? onError,
  }) async {
    final adapter = adapters[source.kind];
    if (adapter is! MediaSidecarAdapter) return inherited;
    var context = inherited;
    final show = _entry(entries, 'tvshow.nfo');
    if (show != null) {
      try {
        final document = await _read(source, adapter, show);
        if (document.kind != 'tvshow') {
          throw const MetadataException('tvshow.nfo 类型不正确');
        }
        context = NfoDirectoryContext(directory, document, entries);
      } catch (e, st) {
        AppLogger.instance.error('读取剧集 NFO 失败', error: e, stackTrace: st);
        onError?.call('剧集 NFO 读取失败，请检查文件内容或访问权限');
        return null;
      }
    }
    final indexed = await repository.metadataFiles(
      sourceId: source.id,
      matchedOnly: false,
      entryIds: entries
          .where(
            (entry) =>
                !entry.isDirectory &&
                source.extensions.contains(
                  p.extension(entry.name).replaceFirst('.', '').toLowerCase(),
                ),
          )
          .map((entry) => entry.externalId)
          .toList(),
    );
    final byId = {for (final file in indexed) file.entryId: file};
    final videos = entries
        .where((entry) => byId.containsKey(entry.externalId))
        .toList();
    for (final entry in videos) {
      final file = byId[entry.externalId]!;
      // 仅在上次写回后没有新的本机修改时，允许读取其他设备更新的 NFO。
      if (file.locked && !await _metadataWasSaved(file)) continue;
      try {
        final nfo =
            _entry(entries, '${p.basenameWithoutExtension(entry.name)}.nfo') ??
            (videos.length == 1 ? _entry(entries, 'movie.nfo') : null);
        NfoDocument? document;
        if (nfo != null) document = await _read(source, adapter, nfo);
        WorkMetadata? metadata;
        TmdbEpisode? episode;
        if (document?.kind == 'movie') {
          metadata = document!.metadata;
        } else if (document?.kind == 'episodedetails') {
          metadata = context?.document.metadata ?? document!.metadata;
          if (metadata.title.isEmpty) {
            throw const MetadataException('分集缺少所属电视剧信息');
          }
          episode = document!.episode;
        } else if (document == null && context != null) {
          final matching = MatchingFile(
            fileId: file.fileId,
            name: file.name,
            directoryNames: DirectoryContextResolver.resolve(
              kind: source.kind,
              rootLocator: source.rootLocator,
              locator: file.entryId,
            ),
          );
          if (matching.parsed.isMultiEpisode ||
              matching.parsed.isSpecialOrOva ||
              matching.parsed.isExtra) {
            continue;
          }
          final numbers = matching.seriesNumbers;
          if (numbers.season == null || numbers.episode == null) continue;
          metadata = context.document.metadata;
          episode = TmdbEpisode(
            seasonNumber: numbers.season!,
            episodeNumber: numbers.episode!,
          );
        }
        if (metadata == null) continue;
        final workId = await repository.applyMetadataToFiles(
          {file.fileId: episode},
          metadata,
          manual: file.locked,
          metadataSource: 'nfo',
          respectExistingMetadata: false,
          localWorkId: metadata.tmdbId == null
              ? context?.workId ??
                    (file.metadata.type == metadata.type &&
                            file.metadata.tmdbId == null
                        ? file.workId
                        : null)
              : null,
        );
        if (workId == null) continue;
        if (metadata.type == 'series') context?.workId = workId;
        final artDirectory = metadata.type == 'series' && context != null
            ? context.directory
            : directory;
        final artEntries = artDirectory == directory
            ? entries
            : context!.entries;
        await _indexArtwork(
          source,
          workId,
          artEntries,
          metadata.type == 'series' ? context?.document : document,
        );
        final imported = await repository.metadataFiles(fileIds: [file.fileId]);
        if (imported.isNotEmpty) await _rememberSavedMetadata(imported.single);
      } catch (e, st) {
        AppLogger.instance.error('导入媒体 NFO 失败', error: e, stackTrace: st);
        onError?.call('NFO 导入失败，请检查文件内容或访问权限');
      }
    }
    return context;
  }

  Future<void> _indexArtwork(
    MediaSourceConfig source,
    int workId,
    List<MediaEntry> entries,
    NfoDocument? document,
  ) async {
    MediaEntry? image(String? name, List<String> defaults) =>
        (name == null ? null : _entry(entries, name)) ??
        defaults
            .map((name) => _entry(entries, name))
            .whereType<MediaEntry>()
            .firstOrNull;
    final poster = image(document?.poster, [
      'poster.jpg',
      'poster.png',
      'poster.webp',
    ]);
    final fanart = image(document?.fanart, [
      'fanart.jpg',
      'fanart.png',
      'fanart.webp',
    ]);
    String? remote(String? value) {
      final uri = Uri.tryParse(value ?? '');
      return uri != null &&
              uri.isScheme('https') &&
              uri.host.isNotEmpty &&
              uri.userInfo.isEmpty &&
              !uri.hasQuery &&
              !uri.hasFragment
          ? uri.toString()
          : null;
    }

    if (poster == null &&
        fanart == null &&
        remote(document?.poster) == null &&
        remote(document?.fanart) == null) {
      return;
    }
    await repository.setWorkArtwork(
      workId,
      poster: poster == null
          ? remote(document?.poster)
          : sourceArtworkLocator(
              source.id,
              poster.externalId,
              version:
                  poster.etag ??
                  '${poster.modifiedAt?.millisecondsSinceEpoch}:${poster.size}',
            ),
      fanart: fanart == null
          ? remote(document?.fanart)
          : sourceArtworkLocator(
              source.id,
              fanart.externalId,
              version:
                  fanart.etag ??
                  '${fanart.modifiedAt?.millisecondsSinceEpoch}:${fanart.size}',
            ),
    );
  }

  Future<NfoResult> export({
    int? workId,
    List<int>? fileIds,
    bool replaceIdentity = false,
  }) {
    final operation = _writes.then(
      (_) => _export(
        workId: workId,
        fileIds: fileIds,
        replaceIdentity: replaceIdentity,
      ),
    );
    _writes = operation.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return operation;
  }

  Future<NfoResult> _export({
    int? workId,
    List<int>? fileIds,
    required bool replaceIdentity,
  }) async {
    final files = await repository.metadataFiles(
      workId: workId,
      fileIds: fileIds,
    );
    final directories = <String, List<MediaEntry>>{};
    final writtenShows = <String>{};
    final errors = <String>[];
    var saved = 0;
    for (final file in files) {
      try {
        final source = await repository.getSource(file.sourceId);
        final adapter = adapters[source.kind];
        if (adapter is ReadOnlyMediaSidecarAdapter) continue;
        if (adapter is! MediaSidecarAdapter) {
          throw const MediaSourceException('媒体源不支持保存元数据');
        }
        final directory = await adapter.parentDirectory(source, file.entryId);
        if (directory == null) throw const MediaSourceException('无法确定视频所在目录');
        Future<List<MediaEntry>> listing(String dir) async =>
            directories['${source.id}:$dir'] ??= await adapters[source.kind]!
                .listEntries(source, dir)
                .toList();
        var artDirectory = directory;
        if (file.metadata.type == 'series') {
          artDirectory = await _seriesDirectory(
            source,
            adapter,
            directory,
            file,
            listing,
          );
          final showKey = '${source.id}:$artDirectory';
          if (!writtenShows.contains(showKey)) {
            final entries = await listing(artDirectory);
            final images = await _saveArtwork(
              source,
              adapter,
              artDirectory,
              entries,
              file.metadata,
              errors: errors,
              refresh: replaceIdentity,
            );
            await _writeNfo(
              source,
              adapter,
              artDirectory,
              'tvshow.nfo',
              NfoDocument(
                kind: 'tvshow',
                metadata: file.metadata,
                poster: images.$1,
                fanart: images.$2,
              ),
              entries,
              replaceIdentity,
            );
            writtenShows.add(showKey);
            directories.remove(showKey);
            await _indexArtwork(
              source,
              file.workId,
              await listing(artDirectory),
              null,
            );
          }
          if (file.episode == null) {
            throw const MediaSourceException('剧集尚未确认季集信息');
          }
          await _writeNfo(
            source,
            adapter,
            directory,
            '${p.basenameWithoutExtension(file.name)}.nfo',
            NfoDocument(
              kind: 'episodedetails',
              metadata: file.metadata,
              episode: file.episode,
            ),
            await listing(directory),
            replaceIdentity,
          );
        } else {
          final entries = await listing(directory);
          final videoCount = entries
              .where(
                (e) =>
                    !e.isDirectory &&
                    source.extensions.contains(
                      p.extension(e.name).replaceFirst('.', '').toLowerCase(),
                    ),
              )
              .length;
          final images = await _saveArtwork(
            source,
            adapter,
            directory,
            entries,
            file.metadata,
            errors: errors,
            refresh: replaceIdentity,
            prefix: videoCount > 1
                ? p.basenameWithoutExtension(file.name)
                : null,
          );
          final preferredName = '${p.basenameWithoutExtension(file.name)}.nfo';
          final name =
              _entry(entries, preferredName) == null &&
                  videoCount == 1 &&
                  _entry(entries, 'movie.nfo') != null
              ? 'movie.nfo'
              : preferredName;
          await _writeNfo(
            source,
            adapter,
            directory,
            name,
            NfoDocument(
              kind: 'movie',
              metadata: file.metadata,
              poster: images.$1,
              fanart: images.$2,
            ),
            entries,
            replaceIdentity,
          );
          directories.remove('${source.id}:$directory');
          await _indexArtwork(
            source,
            file.workId,
            await listing(directory),
            NfoDocument(
              kind: 'movie',
              metadata: file.metadata,
              poster: images.$1,
              fanart: images.$2,
            ),
          );
        }
        await _rememberSavedMetadata(file);
        saved++;
      } catch (e, st) {
        AppLogger.instance.error('保存媒体目录元数据失败', error: e, stackTrace: st);
        errors.add(
          e is MediaSourceException
              ? e.message
              : e is MetadataException
              ? e.message
              : '保存 NFO 或图片失败，请检查媒体源写入权限后重试',
        );
      }
    }
    return NfoResult(saved: saved, errors: errors);
  }

  Future<String> _seriesDirectory(
    MediaSourceConfig source,
    MediaSidecarAdapter adapter,
    String directory,
    MetadataFile file,
    Future<List<MediaEntry>> Function(String) listing,
  ) async {
    // 先寻找已有的整剧 NFO；分集可以位于任意层级的季或画质子目录。
    var ancestor = directory;
    final visited = <String>{};
    while (visited.add(ancestor)) {
      if (_entry(await listing(ancestor), 'tvshow.nfo') != null) {
        return ancestor;
      }
      final parent = await adapter.parentDirectory(source, ancestor);
      if (parent == null) break;
      ancestor = parent;
    }
    var current = directory;
    while (true) {
      final entries = await listing(current);
      if (_entry(entries, 'tvshow.nfo') != null) return current;
      final parent = await adapter.parentDirectory(source, current);
      final String name;
      if (source.kind == 'local') {
        name = p.basename(p.normalize(current));
      } else if (source.kind == 'webdav') {
        name =
            Uri.parse(current).pathSegments
                .where((part) => part.isNotEmpty)
                .lastOrNull ??
            '';
      } else if (source.kind == 'smb') {
        name = p.posix.basename(current);
      } else {
        final siblings = parent == null
            ? <MediaEntry>[]
            : await listing(parent);
        name =
            siblings
                .where((entry) => entry.externalId == current)
                .firstOrNull
                ?.name ??
            '';
      }
      final isGrouping = RegExp(
        r'^(?:s\d+|season[ ._-]*\d+|第.+季|(?:720|1080|2160)p(?:[ ._-].*)?|4k(?:[ ._-].*)?|hdr.*|hevc|x26[45])$',
        caseSensitive: false,
      ).hasMatch(name);
      if (!isGrouping) break;
      if (parent == null || parent == current) break;
      current = parent;
    }
    // 授权根可能包含多个作品，不能据此生成全库共用的 tvshow.nfo。
    if (current == source.rootLocator ||
        await adapter.parentDirectory(source, current) == null) {
      final all = await repository.metadataFiles(
        sourceId: source.id,
        matchedOnly: false,
      );
      if (all.any((item) => item.workId != file.workId)) {
        throw const MediaSourceException('源根目录包含多个作品，无法确定电视剧目录');
      }
    }
    return current;
  }

  Future<void> _writeNfo(
    MediaSourceConfig source,
    MediaSidecarAdapter adapter,
    String directory,
    String name,
    NfoDocument document,
    List<MediaEntry> entries,
    bool replaceIdentity,
  ) async {
    final existing = _entry(entries, name);
    String? text;
    if (existing != null) {
      text = utf8.decode(await adapter.readBytes(source, existing.externalId));
      final old = NfoDocument.parse(text);
      final oldId = document.kind == 'episodedetails'
          ? old.episode?.tmdbId
          : old.metadata.tmdbId;
      final newId = document.kind == 'episodedetails'
          ? document.episode?.tmdbId
          : document.metadata.tmdbId;
      if (!replaceIdentity &&
          (old.kind != document.kind ||
              oldId != null && newId != null && oldId != newId)) {
        throw const MediaSourceException('已有 NFO 指向其他作品，请先确认匹配后重试');
      }
    }
    final output = document.encode(existing: text);
    if (text == output) return;
    await adapter.writeBytes(
      source,
      directory,
      name,
      Uint8List.fromList(utf8.encode(output)),
      expectedEtag: existing?.etag,
      createOnly: existing == null,
    );
  }

  Future<(String?, String?)> _saveArtwork(
    MediaSourceConfig source,
    MediaSidecarAdapter adapter,
    String directory,
    List<MediaEntry> entries,
    WorkMetadata metadata, {
    String? prefix,
    required List<String> errors,
    bool refresh = false,
  }) async {
    Future<String?> save(String type, String? path) async {
      final base = prefix == null ? type : '$prefix-$type';
      final existing = entries
          .where(
            (e) =>
                !e.isDirectory &&
                p.basenameWithoutExtension(e.name).toLowerCase() ==
                    base.toLowerCase() &&
                const [
                  '.jpg',
                  '.jpeg',
                  '.png',
                  '.webp',
                ].contains(p.extension(e.name).toLowerCase()),
          )
          .firstOrNull;
      if (existing != null && (!refresh || path == null)) return existing.name;
      if (path == null ||
          !RegExp(
            r'^/[A-Za-z0-9._-]+\.(?:jpg|jpeg|png|webp)$',
            caseSensitive: false,
          ).hasMatch(path)) {
        return null;
      }
      final response = await http.request(
        Uri.https('image.tmdb.org', '/t/p/original$path'),
        responseType: ResponseType.stream,
      );
      final bytes = await collectSidecarBytes(
        (response.data as ResponseBody).stream,
        16 * 1024 * 1024,
      );
      if (bytes.length < 12 ||
          !(bytes[0] == 0xff && bytes[1] == 0xd8 ||
              bytes[0] == 0x89 && bytes[1] == 0x50 ||
              ascii.decode(bytes.sublist(0, 4), allowInvalid: true) ==
                  'RIFF')) {
        throw const MediaSourceException('下载的海报不是有效图片');
      }
      final name = existing?.name ?? '$base${p.extension(path)}';
      await adapter.writeBytes(
        source,
        directory,
        name,
        bytes,
        expectedEtag: existing?.etag,
        createOnly: existing == null,
      );
      return name;
    }

    Future<String?> attempt(String type, String? path) async {
      try {
        return await save(type, path);
      } catch (e, st) {
        AppLogger.instance.error('保存目录图片失败', error: e, stackTrace: st);
        errors.add('部分海报或背景图未保存，可稍后重试导出');
        return path == null ? null : 'https://image.tmdb.org/t/p/original$path';
      }
    }

    return (
      await attempt('poster', metadata.posterPath),
      await attempt('fanart', metadata.backdropPath),
    );
  }

  static MediaEntry? _entry(List<MediaEntry> entries, String name) => entries
      .where(
        (entry) =>
            !entry.isDirectory &&
            entry.name.toLowerCase() == name.toLowerCase(),
      )
      .firstOrNull;
}
