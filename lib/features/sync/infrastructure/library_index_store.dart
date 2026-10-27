import 'dart:io';

import 'package:drift/drift.dart';
import 'package:path/path.dart' as p;

import '../../../core/database/app_database.dart';
import '../../sources/domain/source_models.dart';
import '../domain/sync_models.dart';

/// 只读本机索引生成快照；恢复时重新分配数据库编号，不枚举媒体源。
class LibraryIndexStore {
  LibraryIndexStore(this.db);
  final AppDatabase db;

  Future<Map<String, dynamic>?> capture(
    MediaSourceConfig source,
  ) => db.transaction(() async {
    final entries = await (db.select(
      db.mediaEntries,
    )..where((e) => e.sourceId.equals(source.id))).get();
    if (entries.isEmpty && source.lastScanAt == null) return null;
    final paths = {
      for (final e in entries) e.id: _path(source, e.relativeLocator),
    };
    entries.sort(
      (a, b) => (paths[a.id] ?? a.externalEntryId).compareTo(
        paths[b.id] ?? b.externalEntryId,
      ),
    );
    final entryIds = {
      for (var i = 0; i < entries.length; i++) entries[i].id: i + 1,
    };
    final files = await _related(
      entryIds.keys,
      (ids) =>
          (db.select(db.mediaFiles)..where((f) => f.entryId.isIn(ids))).get(),
    );
    files.sort((a, b) => entryIds[a.entryId]!.compareTo(entryIds[b.entryId]!));
    final fileIds = {for (var i = 0; i < files.length; i++) files[i].id: i + 1};
    final assignments = await _related(
      fileIds.keys,
      (ids) => (db.select(
        db.mediaAssignments,
      )..where((a) => a.fileId.isIn(ids))).get(),
    );
    assignments.sort(
      (a, b) => fileIds[a.fileId]!.compareTo(fileIds[b.fileId]!),
    );
    final episodes = await _related(
      assignments.map((a) => a.episodeId).whereType<int>(),
      (ids) => (db.select(db.episodes)..where((e) => e.id.isIn(ids))).get(),
    );
    final seasons = await _related(
      episodes.map((e) => e.seasonId),
      (ids) => (db.select(db.seasons)..where((s) => s.id.isIn(ids))).get(),
    );
    final episodeById = {for (final e in episodes) e.id: e};
    final seasonById = {for (final s in seasons) s.id: s};
    final orderedWorks = assignments
        .map(
          (a) =>
              a.workId ??
              seasonById[episodeById[a.episodeId]!.seasonId]!.seriesId,
        )
        .toSet()
        .toList();
    final workIds = {
      for (var i = 0; i < orderedWorks.length; i++) orderedWorks[i]: i + 1,
    };
    final works = await _related(
      workIds.keys,
      (ids) => (db.select(db.works)..where((w) => w.id.isIn(ids))).get(),
    );
    works.sort((a, b) => workIds[a.id]!.compareTo(workIds[b.id]!));
    seasons.sort((a, b) {
      final c = workIds[a.seriesId]!.compareTo(workIds[b.seriesId]!);
      return c != 0 ? c : a.seasonNumber.compareTo(b.seasonNumber);
    });
    final seasonIds = {
      for (var i = 0; i < seasons.length; i++) seasons[i].id: i + 1,
    };
    episodes.sort((a, b) {
      final c = seasonIds[a.seasonId]!.compareTo(seasonIds[b.seasonId]!);
      return c != 0 ? c : a.episodeNumber.compareTo(b.episodeNumber);
    });
    final episodeIds = {
      for (var i = 0; i < episodes.length; i++) episodes[i].id: i + 1,
    };
    final externalIds = await _related(
      workIds.keys,
      (ids) =>
          (db.select(db.externalIds)..where((e) => e.workId.isIn(ids))).get(),
    );
    externalIds.sort(
      (a, b) =>
          '${workIds[a.workId]}:${a.provider}:${a.providerEntityId}'.compareTo(
            '${workIds[b.workId]}:${b.provider}:${b.providerEntityId}',
          ),
    );
    final saved = await _related(
      files.map((f) => f.id),
      (ids) => (db.select(
        db.syncState,
      )..where((s) => s.key.isIn(ids.map((id) => 'nfo_saved:$id')))).get(),
    );
    return {
      'version': 1,
      'nativeRoot': paths.values.any((path) => path == null)
          ? source.rootLocator
          : null,
      'lastScanAt': source.lastScanAt?.millisecondsSinceEpoch,
      'entries': [
        for (final e in entries)
          {
            ...e.toJson()
              ..remove('sourceId')
              ..remove('externalEntryId')
              ..remove('relativeLocator')
              ..remove('lastSeenScanId'),
            'id': entryIds[e.id],
            'path': paths[e.id],
            if (paths[e.id] == null) 'nativeId': e.externalEntryId,
          },
      ],
      'files': [
        for (final f in files)
          {...f.toJson(), 'id': fileIds[f.id], 'entryId': entryIds[f.entryId]},
      ],
      'works': [
        for (final w in works)
          {
            ...w.toJson(),
            'id': workIds[w.id],
            'posterLocator': _portableArt(source, w.posterLocator),
            'backdropLocator': _portableArt(source, w.backdropLocator),
          },
      ],
      'seasons': [
        for (final s in seasons)
          {
            ...s.toJson(),
            'id': seasonIds[s.id],
            'seriesId': workIds[s.seriesId],
          },
      ],
      'episodes': [
        for (final e in episodes)
          {
            ...e.toJson(),
            'id': episodeIds[e.id],
            'seasonId': seasonIds[e.seasonId],
          },
      ],
      'assignments': [
        for (final a in assignments)
          {
            ...a.toJson(),
            'id': fileIds[a.fileId],
            'fileId': fileIds[a.fileId],
            'workId': workIds[a.workId],
            'episodeId': episodeIds[a.episodeId],
          },
      ],
      'externalIds': [
        for (var i = 0; i < externalIds.length; i++)
          {
            ...externalIds[i].toJson(),
            'id': i + 1,
            'workId': workIds[externalIds[i].workId],
          },
      ],
      'nfoSaved': {
        for (final row in saved)
          '${fileIds[int.parse(row.key.substring(10))]}': row.value,
      },
    };
  });

  static List<Map<String, dynamic>> _rows(
    Map<String, dynamic> value,
    String key,
  ) => (value[key] as List<dynamic>).cast<Map<String, dynamic>>();

  static Future<List<T>> _related<T>(
    Iterable<int> ids,
    Future<List<T>> Function(List<int>) read,
  ) async {
    final values = ids.toSet().toList();
    final result = <T>[];
    for (var i = 0; i < values.length; i += 500) {
      result.addAll(
        await read(
          values.sublist(i, i + 500 > values.length ? values.length : i + 500),
        ),
      );
    }
    return result;
  }

  static void validate(Map<String, dynamic> value) {
    if (value['version'] != 1) throw const FormatException('索引版本无效');
    final entries = <int>{};
    for (final row in _rows(value, 'entries')) {
      final path = row['path'] as String?;
      if (path != null) _validatePath(path);
      final native = row['nativeId'] as String?;
      if (path == null &&
          (native == null || !native.startsWith('content://'))) {
        throw const FormatException();
      }
      final entry = MediaEntryData.fromJson({
        ...row,
        'sourceId': 1,
        'externalEntryId': path ?? native,
        'relativeLocator': path ?? native,
        'lastSeenScanId': 0,
      });
      if (!entries.add(entry.id)) throw const FormatException();
    }
    final files = <int>{};
    for (final row in _rows(value, 'files')) {
      final file = MediaFileData.fromJson(row);
      if (!entries.contains(file.entryId) || !files.add(file.id)) {
        throw const FormatException();
      }
    }
    final works = <int>{};
    for (final row in _rows(value, 'works')) {
      final work = WorkData.fromJson(row);
      for (final locator in [work.posterLocator, work.backdropLocator]) {
        if (locator == null) continue;
        final uri = Uri.parse(locator);
        if (uri.scheme != 'reelva-art' ||
            uri.host != '0' ||
            uri.path != '/image') {
          throw const FormatException();
        }
        _validatePath(uri.queryParameters['entry']!);
      }
      if (!works.add(work.id) ||
          !const [null, 'movie', 'series'].contains(work.type)) {
        throw const FormatException();
      }
    }
    final seasons = <int>{};
    for (final row in _rows(value, 'seasons')) {
      final season = SeasonData.fromJson(row);
      if (!works.contains(season.seriesId) || !seasons.add(season.id)) {
        throw const FormatException();
      }
    }
    final episodes = <int>{};
    for (final row in _rows(value, 'episodes')) {
      final episode = EpisodeData.fromJson(row);
      if (!seasons.contains(episode.seasonId) || !episodes.add(episode.id)) {
        throw const FormatException();
      }
    }
    final assigned = <int>{};
    for (final row in _rows(value, 'assignments')) {
      final assignment = MediaAssignmentData.fromJson(row);
      if (!files.contains(assignment.fileId) ||
          !assigned.add(assignment.fileId) ||
          (assignment.workId == null) == (assignment.episodeId == null) ||
          assignment.workId != null && !works.contains(assignment.workId) ||
          assignment.episodeId != null &&
              !episodes.contains(assignment.episodeId)) {
        throw const FormatException();
      }
    }
    for (final row in _rows(value, 'externalIds')) {
      if (!works.contains(ExternalIdData.fromJson(row).workId)) {
        throw const FormatException();
      }
    }
    (value['nfoSaved'] as Map<String, dynamic>).forEach((key, value) {
      if (!files.contains(int.parse(key)) || value is! String) {
        throw const FormatException();
      }
    });
    if (value['lastScanAt'] != null && value['lastScanAt'] is! int) {
      throw const FormatException();
    }
  }

  Future<void> restore(
    MediaSourceConfig source,
    Map<String, dynamic> value,
  ) => db.transaction(() async {
    validate(value);
    if (_rows(value, 'entries').any((row) => row['path'] == null) &&
        value['nativeRoot'] != source.rootLocator) {
      throw const SyncException('此 Android 索引使用原目录的文档标识，请选择原目录或手动扫描一次');
    }
    await (db.update(db.mediaEntries)
          ..where((e) => e.sourceId.equals(source.id)))
        .write(const MediaEntriesCompanion(available: Value(false)));
    final entryMap = <int, int>{};
    for (final raw in _rows(value, 'entries')) {
      final path = raw['path'] as String?;
      final locator = path == null
          ? raw['nativeId'] as String
          : _locator(source, path);
      if (path == null && source.kind != 'androidSaf') {
        throw const SyncException('此索引使用 Android 文档标识，需绑定对应的 Android 目录');
      }
      final externalId = source.kind == 'local' && Platform.isWindows
          ? locator.toLowerCase()
          : locator;
      final row = MediaEntryData.fromJson({
        ...raw,
        'sourceId': source.id,
        'externalEntryId': externalId,
        'relativeLocator': locator,
        'lastSeenScanId': source.scanRevision,
      });
      final existing =
          await (db.select(db.mediaEntries)..where(
                (e) =>
                    e.sourceId.equals(source.id) &
                    e.externalEntryId.equals(externalId),
              ))
              .getSingleOrNull();
      final companion = row
          .toCompanion(false)
          .copyWith(id: const Value.absent());
      if (existing == null) {
        entryMap[row.id] = await db.into(db.mediaEntries).insert(companion);
      } else {
        entryMap[row.id] = existing.id;
        await (db.update(
          db.mediaEntries,
        )..where((e) => e.id.equals(existing.id))).write(companion);
      }
    }
    final fileMap = <int, int>{};
    for (final raw in _rows(value, 'files')) {
      final row = MediaFileData.fromJson(raw);
      final entryId = entryMap[row.entryId]!;
      final existing = await (db.select(
        db.mediaFiles,
      )..where((f) => f.entryId.equals(entryId))).getSingleOrNull();
      final companion = row
          .copyWith(entryId: entryId)
          .toCompanion(false)
          .copyWith(id: const Value.absent());
      if (existing == null) {
        fileMap[row.id] = await db.into(db.mediaFiles).insert(companion);
      } else {
        fileMap[row.id] = existing.id;
        await (db.update(
          db.mediaFiles,
        )..where((f) => f.id.equals(existing.id))).write(companion);
      }
    }
    final workMap = <int, int>{};
    final external = _rows(
      value,
      'externalIds',
    ).map(ExternalIdData.fromJson).toList();
    final assignments = _rows(
      value,
      'assignments',
    ).map(MediaAssignmentData.fromJson).toList();
    final indexedEpisodes = {
      for (final row in _rows(value, 'episodes').map(EpisodeData.fromJson))
        row.id: row,
    };
    final indexedSeasons = {
      for (final row in _rows(value, 'seasons').map(SeasonData.fromJson))
        row.id: row,
    };
    int assignmentWork(MediaAssignmentData row) =>
        row.workId ??
        indexedSeasons[indexedEpisodes[row.episodeId]!.seasonId]!.seriesId;
    Future<WorkData?> localWork(MediaAssignmentData assignment) async {
      var workId = assignment.workId;
      if (workId == null) {
        final episode = await (db.select(
          db.episodes,
        )..where((e) => e.id.equals(assignment.episodeId!))).getSingle();
        workId = (await (db.select(
          db.seasons,
        )..where((s) => s.id.equals(episode.seasonId))).getSingle()).seriesId;
      }
      return (db.select(
        db.works,
      )..where((w) => w.id.equals(workId!))).getSingleOrNull();
    }

    final preservedWorks = <int>{};
    final workRows = {
      for (final row in _rows(value, 'works').map(WorkData.fromJson))
        row.id: row,
    };
    for (final raw in _rows(value, 'works')) {
      final row = WorkData.fromJson(raw);
      WorkData? existing;
      for (final id in external.where((e) => e.workId == row.id)) {
        final link =
            await (db.select(db.externalIds)..where(
                  (e) =>
                      e.provider.equals(id.provider) &
                      e.providerEntityId.equals(id.providerEntityId),
                ))
                .getSingleOrNull();
        if (link != null) {
          if (existing != null && existing.id != link.workId) {
            throw const SyncException('本机作品身份存在冲突，请先核对匹配结果');
          }
          existing = await (db.select(
            db.works,
          )..where((w) => w.id.equals(link.workId))).getSingle();
        }
      }
      if (existing == null) {
        final assignment = assignments
            .where((a) => assignmentWork(a) == row.id)
            .firstOrNull;
        if (assignment != null) {
          final local =
              await (db.select(
                    db.mediaAssignments,
                  )..where((a) => a.fileId.equals(fileMap[assignment.fileId]!)))
                  .getSingleOrNull();
          if (local != null) {
            final candidate = await localWork(local);
            final incomingIdentified = external.any((e) => e.workId == row.id);
            final candidateIdentified =
                candidate != null &&
                (await (db.select(
                      db.externalIds,
                    )..where((e) => e.workId.equals(candidate.id))).get())
                    .isNotEmpty;
            if (!incomingIdentified || !candidateIdentified) {
              existing = candidate;
            }
          }
        }
      }
      final restored = row.copyWith(
        posterLocator: Value(_restoreArt(source, row.posterLocator)),
        backdropLocator: Value(_restoreArt(source, row.backdropLocator)),
      );
      final companion = restored
          .toCompanion(false)
          .copyWith(id: const Value.absent());
      if (existing == null) {
        workMap[row.id] = await db.into(db.works).insert(companion);
      } else {
        workMap[row.id] = existing.id;
        if (!existing.updatedAt.isAfter(row.updatedAt) &&
            (!existing.metadataLocked || row.metadataLocked)) {
          await (db.update(
            db.works,
          )..where((w) => w.id.equals(existing!.id))).write(companion);
        } else {
          preservedWorks.add(row.id);
        }
      }
    }
    for (final row in external) {
      final existing =
          await (db.select(db.externalIds)..where(
                (e) =>
                    e.provider.equals(row.provider) &
                    e.providerEntityId.equals(row.providerEntityId),
              ))
              .getSingleOrNull();
      if (existing == null) {
        await db
            .into(db.externalIds)
            .insert(
              row
                  .copyWith(workId: workMap[row.workId]!)
                  .toCompanion(false)
                  .copyWith(id: const Value.absent()),
            );
      }
    }
    final seasonMap = <int, int>{};
    for (final raw in _rows(value, 'seasons')) {
      final row = SeasonData.fromJson(raw);
      final workId = workMap[row.seriesId]!;
      final existing =
          await (db.select(db.seasons)..where(
                (s) =>
                    s.seriesId.equals(workId) &
                    s.seasonNumber.equals(row.seasonNumber),
              ))
              .getSingleOrNull();
      final companion = row
          .copyWith(seriesId: workId)
          .toCompanion(false)
          .copyWith(id: const Value.absent());
      seasonMap[row.id] =
          existing?.id ?? await db.into(db.seasons).insert(companion);
      if (existing != null && !preservedWorks.contains(row.seriesId)) {
        await (db.update(
          db.seasons,
        )..where((s) => s.id.equals(existing.id))).write(companion);
      }
    }
    final episodeMap = <int, int>{};
    for (final raw in _rows(value, 'episodes')) {
      final row = EpisodeData.fromJson(raw);
      final seasonId = seasonMap[row.seasonId]!;
      final existing =
          await (db.select(db.episodes)..where(
                (e) =>
                    e.seasonId.equals(seasonId) &
                    e.episodeNumber.equals(row.episodeNumber),
              ))
              .getSingleOrNull();
      final companion = row
          .copyWith(seasonId: seasonId)
          .toCompanion(false)
          .copyWith(id: const Value.absent());
      episodeMap[row.id] =
          existing?.id ?? await db.into(db.episodes).insert(companion);
      if (existing != null &&
          !preservedWorks.contains(indexedSeasons[row.seasonId]!.seriesId)) {
        await (db.update(
          db.episodes,
        )..where((e) => e.id.equals(existing.id))).write(companion);
      }
    }
    final preservedFiles = <int>{};
    for (final row in assignments) {
      final fileId = fileMap[row.fileId]!;
      final existing = await (db.select(
        db.mediaAssignments,
      )..where((a) => a.fileId.equals(fileId))).getSingleOrNull();
      if (existing != null) {
        final currentWork = await localWork(existing);
        final incomingWork = workRows[assignmentWork(row)]!;
        if (currentWork != null &&
            currentWork.id != workMap[incomingWork.id] &&
            currentWork.metadataLocked &&
            currentWork.updatedAt.isAfter(incomingWork.updatedAt)) {
          preservedFiles.add(row.fileId);
          continue;
        }
      }
      final companion = row
          .copyWith(
            fileId: fileId,
            workId: Value(workMap[row.workId]),
            episodeId: Value(episodeMap[row.episodeId]),
          )
          .toCompanion(false)
          .copyWith(id: const Value.absent());
      if (existing == null) {
        await db.into(db.mediaAssignments).insert(companion);
      } else {
        await (db.update(
          db.mediaAssignments,
        )..where((a) => a.id.equals(existing.id))).write(companion);
      }
    }
    for (final saved in (value['nfoSaved'] as Map<String, dynamic>).entries) {
      if (preservedFiles.contains(int.parse(saved.key))) continue;
      final assignment = assignments
          .where((a) => a.fileId == int.parse(saved.key))
          .firstOrNull;
      if (assignment != null &&
          preservedWorks.contains(assignmentWork(assignment))) {
        continue;
      }
      await db
          .into(db.syncState)
          .insertOnConflictUpdate(
            SyncStateCompanion.insert(
              key: 'nfo_saved:${fileMap[int.parse(saved.key)]}',
              value: saved.value as String,
            ),
          );
    }
    await (db.update(
      db.mediaSources,
    )..where((s) => s.id.equals(source.id))).write(
      MediaSourcesCompanion(
        lastScanAt: Value(
          value['lastScanAt'] == null
              ? null
              : DateTime.fromMillisecondsSinceEpoch(value['lastScanAt'] as int),
        ),
      ),
    );
  });

  static void _validatePath(String path) {
    if (path.isEmpty ||
        path.startsWith('/') ||
        path.contains(r'\') ||
        path.split('/').any((s) => s.isEmpty || s == '.' || s == '..') ||
        path.contains('\u0000')) {
      throw const FormatException('索引路径无效');
    }
  }

  static String? _path(MediaSourceConfig source, String locator) {
    final uri = Uri.tryParse(locator);
    if (uri?.scheme == 'reelva-index') return uri!.pathSegments.join('/');
    if (source.kind == 'androidSaf') {
      final root = Uri.parse(source.rootLocator).pathSegments;
      final doc = uri?.pathSegments;
      final rootIndex = root.indexOf('tree');
      final docIndex = doc?.indexOf('document') ?? -1;
      if (rootIndex < 0 || docIndex < 0) return null;
      final rootId = root[rootIndex + 1];
      final documentId = doc![docIndex + 1];
      return documentId.startsWith('$rootId/')
          ? documentId.substring(rootId.length + 1)
          : null;
    }
    if (source.kind == 'smb') {
      final rootPath = Uri.parse(source.rootLocator).pathSegments
          .skip(1)
          .where((s) => s.isNotEmpty)
          .join('/');
      final prefix = rootPath.isEmpty ? '/' : '/$rootPath/';
      return locator.startsWith(prefix)
          ? locator.substring(prefix.length)
          : null;
    }
    return locator.replaceAll(r'\', '/');
  }

  static String _locator(MediaSourceConfig source, String path) {
    _validatePath(path);
    if (source.kind == 'androidSaf') {
      return Uri(
        scheme: 'reelva-index',
        pathSegments: path.split('/'),
      ).toString();
    }
    if (source.kind == 'smb') {
      final root = Uri.parse(source.rootLocator).pathSegments
          .skip(1)
          .where((s) => s.isNotEmpty)
          .join('/');
      return root.isEmpty ? '/$path' : '/$root/$path';
    }
    return p.posix.normalize(path);
  }

  static String? _portableArt(MediaSourceConfig source, String? locator) {
    if (locator == null) return null;
    final uri = Uri.tryParse(locator);
    if (uri?.scheme != 'reelva-art' || uri!.host != '${source.id}') return null;
    final entry = uri.queryParameters['entry'];
    final path = entry == null ? null : _path(source, entry);
    return path == null
        ? null
        : uri
              .replace(
                host: '0',
                queryParameters: {...uri.queryParameters, 'entry': path},
              )
              .toString();
  }

  static String? _restoreArt(MediaSourceConfig source, String? locator) {
    if (locator == null) return null;
    final uri = Uri.parse(locator);
    return uri
        .replace(
          host: '${source.id}',
          queryParameters: {
            ...uri.queryParameters,
            'entry': _locator(source, uri.queryParameters['entry']!),
          },
        )
        .toString();
  }
}
