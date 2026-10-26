import 'dart:convert';

import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../metadata/domain/directory_context_resolver.dart';
import '../../metadata/domain/matching_file.dart';
import '../../metadata/domain/match_decision.dart';
import '../../metadata/domain/media_filename_parser.dart';
import '../../metadata/domain/tmdb_models.dart';
import '../../metadata/domain/work_metadata.dart';
import '../../metadata/domain/metadata_file.dart';
import '../../sources/domain/source_models.dart';
import '../domain/library_work.dart';

class MediaLibraryRepository {
  MediaLibraryRepository(this.db);

  final AppDatabase db;

  Stream<List<MediaSourceConfig>> watchSources() {
    final query = db.select(db.mediaSources)
      ..where((s) => s.enabled.equals(true))
      ..orderBy([
        (s) => OrderingTerm(expression: s.name, mode: OrderingMode.asc),
        (s) => OrderingTerm(expression: s.id, mode: OrderingMode.asc),
      ]);

    return query.watch().map((rows) => rows.map(_toSourceConfig).toList());
  }

  Future<MediaSourceConfig> getSource(int id) async {
    final row = await (db.select(
      db.mediaSources,
    )..where((s) => s.id.equals(id))).getSingleOrNull();
    if (row == null) {
      throw MediaSourceException(
        'Media source $id not found',
        code: 'source_not_found',
      );
    }
    return _toSourceConfig(row);
  }

  Future<MediaSourceConfig> upsertSource({
    required String kind,
    required String rootLocator,
    required String name,
    String? credentialRef,
    bool clearCredentialRef = false,
    List<String> extensions = defaultVideoExtensions,
    List<String> excludedDirectories = defaultExcludedDirectories,
  }) async {
    return db.transaction(() async {
      final existing =
          await (db.select(db.mediaSources)..where(
                (s) => s.kind.equals(kind) & s.rootLocator.equals(rootLocator),
              ))
              .getSingleOrNull();

      if (existing != null) {
        final nextCredRef = clearCredentialRef
            ? null
            : (credentialRef ?? existing.credentialRef);
        await (db.update(
          db.mediaSources,
        )..where((s) => s.id.equals(existing.id))).write(
          MediaSourcesCompanion(
            name: Value(name),
            enabled: const Value(true),
            credentialRef: Value(nextCredRef),
            extensions: Value(jsonEncode(extensions)),
            excludedDirectories: Value(jsonEncode(excludedDirectories)),
            errorMessage: const Value(null),
          ),
        );
        final refreshed = await (db.select(
          db.mediaSources,
        )..where((s) => s.id.equals(existing.id))).getSingle();
        return _toSourceConfig(refreshed);
      } else {
        final id = await db
            .into(db.mediaSources)
            .insert(
              MediaSourcesCompanion.insert(
                kind: kind,
                name: name,
                rootLocator: rootLocator,
                credentialRef: Value(credentialRef),
                extensions: Value(jsonEncode(extensions)),
                excludedDirectories: Value(jsonEncode(excludedDirectories)),
              ),
            );
        final inserted = await (db.select(
          db.mediaSources,
        )..where((s) => s.id.equals(id))).getSingle();
        return _toSourceConfig(inserted);
      }
    });
  }

  Future<MediaSourceConfig?> findSourceByRoot(
    String kind,
    String rootLocator,
  ) async {
    final row =
        await (db.select(db.mediaSources)..where(
              (s) => s.kind.equals(kind) & s.rootLocator.equals(rootLocator),
            ))
            .getSingleOrNull();
    if (row == null) return null;
    return _toSourceConfig(row);
  }

  Future<void> updateSourceCredentials(int id, String? credentialRef) async {
    await (db.update(db.mediaSources)..where((s) => s.id.equals(id))).write(
      MediaSourcesCompanion(credentialRef: Value(credentialRef)),
    );
  }

  Future<void> renameSource(int id, String name) async {
    await (db.update(db.mediaSources)..where((s) => s.id.equals(id))).write(
      MediaSourcesCompanion(name: Value(name)),
    );
  }

  /// 为浏览器中实际选中的文件补齐索引，不等待整个媒体源扫描结束。
  Future<Map<String, int>> indexSourceFiles(
    int sourceId,
    List<MediaEntry> entries,
  ) => db.transaction(() async {
    final source = await getSource(sourceId);
    if (!source.enabled) {
      throw const MediaSourceException('媒体源已停用');
    }
    await applyScanBatch(sourceId, source.scanRevision, entries);
    final rows =
        await (db.select(db.mediaEntries).join([
              innerJoin(
                db.mediaFiles,
                db.mediaFiles.entryId.equalsExp(db.mediaEntries.id),
              ),
            ])..where(
              db.mediaEntries.sourceId.equals(sourceId) &
                  db.mediaEntries.externalEntryId.isIn(
                    entries.map((e) => e.externalId),
                  ),
            ))
            .get();
    return {
      for (final row in rows)
        row.readTable(db.mediaEntries).externalEntryId: row
            .readTable(db.mediaFiles)
            .id,
    };
  });

  Future<WorkData?> _assignedWork(MediaAssignmentData assignment) async {
    if (assignment.workId != null) {
      return (db.select(
        db.works,
      )..where((w) => w.id.equals(assignment.workId!))).getSingleOrNull();
    }
    final row = await (db.select(db.works).join([
      innerJoin(db.seasons, db.seasons.seriesId.equalsExp(db.works.id)),
      innerJoin(db.episodes, db.episodes.seasonId.equalsExp(db.seasons.id)),
    ])..where(db.episodes.id.equals(assignment.episodeId!))).getSingleOrNull();
    return row?.readTable(db.works);
  }

  /// 按当前目录的文件身份批量监视已确认的作品与季集关联。
  Stream<Map<String, LibraryFileMatch>> watchSourceFileMatches(
    int sourceId,
    List<String> externalIds,
  ) {
    if (externalIds.isEmpty) return Stream.value({});
    final placeholders = List.filled(externalIds.length, '?').join(',');
    return db
        .customSelect(
          '''
      SELECT me.external_entry_id, w.title, w.year,
        s.season_number, ep.episode_number, ep.title AS episode_title
      FROM media_entries me
      JOIN media_files mf ON mf.entry_id = me.id
      JOIN media_assignments ma ON ma.file_id = mf.id
      LEFT JOIN episodes ep ON ep.id = ma.episode_id
      LEFT JOIN seasons s ON s.id = ep.season_id
      JOIN works w ON w.id = COALESCE(ma.work_id, s.series_id)
      WHERE me.source_id = ? AND me.is_directory = 0
        AND me.external_entry_id IN ($placeholders)
        AND (w.metadata_source != 'local' OR w.metadata_locked = 1)
      ''',
          variables: [
            Variable.withInt(sourceId),
            ...externalIds.map(Variable.withString),
          ],
          readsFrom: {
            db.mediaEntries,
            db.mediaFiles,
            db.mediaAssignments,
            db.works,
            db.seasons,
            db.episodes,
          },
        )
        .watch()
        .map(
          (rows) => {
            for (final row in rows)
              row.read<String>('external_entry_id'): LibraryFileMatch(
                title: row.read<String>('title'),
                year: row.readNullable<int>('year'),
                seasonNumber: row.readNullable<int>('season_number'),
                episodeNumber: row.readNullable<int>('episode_number'),
                episodeTitle: row.readNullable<String>('episode_title'),
              ),
          },
        );
  }

  Future<bool> isFileMetadataLocked(int fileId) async {
    final assignment = await (db.select(
      db.mediaAssignments,
    )..where((a) => a.fileId.equals(fileId))).getSingleOrNull();
    if (assignment == null) {
      throw const MetadataException('所选文件不存在，请刷新目录后重试');
    }
    return (await _assignedWork(assignment))?.metadataLocked ?? false;
  }

  Future<bool> _isProtectedWork(WorkData? work) async {
    if (work == null) return false;
    if (work.metadataLocked || work.metadataSource != 'local') return true;
    return await (db.select(db.externalIds)
              ..where(
                (id) => id.workId.equals(work.id) & id.provider.equals('tmdb'),
              )
              ..limit(1))
            .getSingleOrNull() !=
        null;
  }

  Future<bool> isFileMetadataProtected(int fileId) async {
    final assignment = await (db.select(
      db.mediaAssignments,
    )..where((row) => row.fileId.equals(fileId))).getSingleOrNull();
    return assignment == null ||
        await _isProtectedWork(await _assignedWork(assignment));
  }

  /// 直接从索引重新生成证据，已有 needs_review 文件也可使用新规则。
  Future<List<MatchingFile>> matchingFilesForWork(int workId) async {
    final rows = await db
        .customSelect(
          '''
      SELECT mf.id, me.name, me.relative_locator, ms.kind, ms.root_locator,
             s.season_number, ep.episode_number, mf.candidate_details
      FROM media_assignments ma
      JOIN media_files mf ON mf.id = ma.file_id
      JOIN media_entries me ON me.id = mf.entry_id
      JOIN media_sources ms ON ms.id = me.source_id
      LEFT JOIN episodes ep ON ep.id = ma.episode_id
      LEFT JOIN seasons s ON s.id = ep.season_id
      WHERE ms.enabled = 1 AND me.is_directory = 0
        AND (ma.work_id = ? OR s.series_id = ?)
      ORDER BY mf.id
    ''',
          variables: [Variable.withInt(workId), Variable.withInt(workId)],
        )
        .get();
    return rows.map((row) {
      Map<String, dynamic>? review;
      final raw = row.readNullable<String>('candidate_details');
      if (raw != null && raw.startsWith('{')) {
        final value = jsonDecode(raw);
        if (value is Map<String, dynamic>) review = value;
      }
      return MatchingFile(
        fileId: row.read<int>('id'),
        name: row.read<String>('name'),
        directoryNames: DirectoryContextResolver.resolve(
          kind: row.read<String>('kind'),
          rootLocator: row.read<String>('root_locator'),
          locator: row.read<String>('relative_locator'),
        ),
        seasonNumber: row.readNullable<int>('season_number'),
        episodeNumber: row.readNullable<int>('episode_number'),
        reviewReason: MatchReason.values
            .where((reason) => reason.name == review?['reason'])
            .firstOrNull,
        suggestions: (review?['candidates'] as List<dynamic>? ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(TmdbWork.fromJson)
            .toList(),
      );
    }).toList();
  }

  Future<void> recordMatchingReview(
    List<int> fileIds,
    MatchDecision decision,
  ) => db.transaction(() async {
    for (final fileId in fileIds) {
      if (await isFileMetadataProtected(fileId)) continue;
      await (db.update(
        db.mediaFiles,
      )..where((row) => row.id.equals(fileId))).write(
        MediaFilesCompanion(
          parseState: decision.reason == MatchReason.extraMedia
              ? const Value('extra')
              : const Value.absent(),
          candidateDetails: Value(
            jsonEncode({
              'reason': decision.reason?.name,
              'candidates': decision.candidates
                  .take(3)
                  .map((work) => work.toJson())
                  .toList(),
            }),
          ),
        ),
      );
    }
  });

  static String _localScope(List<String> directories) {
    final index = directories.lastIndexWhere(
      (directory) =>
          !MediaFilenameParser.isContextDirectory(directory) &&
          !MediaFilenameParser.isExtraName(directory) &&
          MediaFilenameParser.seasonFromName(directory) == null,
    );
    return directories.take(index + 1).join('/');
  }

  Future<bool> _sameLocalScope(
    WorkData candidate,
    MediaEntryData entry,
    MediaSourceEntry source,
  ) async {
    if (await _isProtectedWork(candidate)) return false;
    final scope = _localScope(
      DirectoryContextResolver.resolve(
        kind: source.kind,
        rootLocator: source.rootLocator,
        locator: entry.relativeLocator,
      ),
    );
    final candidates = await db
        .customSelect(
          '''
      SELECT me.relative_locator FROM media_assignments ma
      JOIN media_files mf ON mf.id = ma.file_id
      JOIN media_entries me ON me.id = mf.entry_id
      LEFT JOIN episodes ep ON ep.id = ma.episode_id
      LEFT JOIN seasons s ON s.id = ep.season_id
      WHERE me.source_id = ? AND (ma.work_id = ? OR s.series_id = ?)
    ''',
          variables: [
            Variable.withInt(source.id),
            Variable.withInt(candidate.id),
            Variable.withInt(candidate.id),
          ],
        )
        .get();
    return candidates.any(
      (row) =>
          _localScope(
            DirectoryContextResolver.resolve(
              kind: source.kind,
              rootLocator: source.rootLocator,
              locator: row.read<String>('relative_locator'),
            ),
          ) ==
          scope,
    );
  }

  /// 仅重绑明确选中的文件，保留其他版本、季集关联与观看历史。
  Future<int?> applyMetadataToFiles(
    Map<int, TmdbEpisode?> files,
    WorkMetadata metadata, {
    bool manual = true,
    String metadataSource = 'tmdb',
    int? localWorkId,
    bool respectExistingMetadata = true,
  }) => db.transaction(() async {
    final assignments = <int, MediaAssignmentData>{};
    for (final fileId in files.keys) {
      final row =
          await (db.select(db.mediaAssignments).join([
                innerJoin(
                  db.mediaFiles,
                  db.mediaFiles.id.equalsExp(db.mediaAssignments.fileId),
                ),
                innerJoin(
                  db.mediaEntries,
                  db.mediaEntries.id.equalsExp(db.mediaFiles.entryId),
                ),
                innerJoin(
                  db.mediaSources,
                  db.mediaSources.id.equalsExp(db.mediaEntries.sourceId),
                ),
              ])..where(
                db.mediaAssignments.fileId.equals(fileId) &
                    db.mediaSources.enabled.equals(true),
              ))
              .getSingleOrNull();
      if (row == null) {
        throw const MetadataException('所选文件已不可用，请刷新目录后重试');
      }
      final assignment = row.readTable(db.mediaAssignments);
      if (!manual &&
          (respectExistingMetadata
              ? await _isProtectedWork(await _assignedWork(assignment))
              : (await _assignedWork(assignment))?.metadataLocked == true)) {
        continue;
      }
      final episode = files[fileId];
      if (metadata.type == 'series' &&
          (episode == null ||
              episode.seasonNumber < 0 ||
              episode.episodeNumber < 1)) {
        throw const MetadataException('请为所选文件确认正确的季号和集号');
      }
      assignments[fileId] = assignment;
    }
    if (assignments.isEmpty) return null;

    var workId = metadata.tmdbId == null
        ? localWorkId
        : await _getWorkIdByExternalId(
            'tmdb',
            '${metadata.type}:${metadata.tmdbId}',
          );
    workId ??= await db
        .into(db.works)
        .insert(
          WorksCompanion.insert(
            title: metadata.title,
            type: Value(metadata.type),
          ),
        );
    workId = await applyMetadata(
      workId,
      metadata,
      manual: manual,
      metadataSource: metadataSource,
    );
    final targetEpisodes = <(int, int), int>{};
    final targets = <int, int?>{};
    for (final fileId in assignments.keys) {
      final episode = metadata.type == 'series' ? files[fileId] : null;
      int? episodeId;
      if (episode != null) {
        final key = (episode.seasonNumber, episode.episodeNumber);
        episodeId = targetEpisodes[key];
        if (episodeId == null) {
          var season =
              await (db.select(db.seasons)..where(
                    (s) =>
                        s.seriesId.equals(workId!) &
                        s.seasonNumber.equals(episode.seasonNumber),
                  ))
                  .getSingleOrNull();
          final seasonId =
              season?.id ??
              await db
                  .into(db.seasons)
                  .insert(
                    SeasonsCompanion.insert(
                      seriesId: workId,
                      seasonNumber: episode.seasonNumber,
                    ),
                  );
          final existing =
              await (db.select(db.episodes)..where(
                    (e) =>
                        e.seasonId.equals(seasonId) &
                        e.episodeNumber.equals(episode.episodeNumber),
                  ))
                  .getSingleOrNull();
          episodeId =
              existing?.id ??
              await db
                  .into(db.episodes)
                  .insert(
                    EpisodesCompanion.insert(
                      seasonId: seasonId,
                      episodeNumber: episode.episodeNumber,
                      title: Value(episode.title),
                      overview: Value(episode.overview),
                      airDate: Value(episode.airDate),
                      tmdbId: Value(episode.tmdbId),
                    ),
                  );
          targetEpisodes[key] = episodeId;
        }
      }
      targets[fileId] = episodeId;
      await (db.update(
        db.mediaAssignments,
      )..where((a) => a.fileId.equals(fileId))).write(
        MediaAssignmentsCompanion(
          workId: Value(episodeId == null ? workId : null),
          episodeId: Value(episodeId),
        ),
      );
      await (db.update(db.mediaFiles)..where((f) => f.id.equals(fileId))).write(
        MediaFilesCompanion(
          parseState: const Value('parsed'),
          candidateType: Value(metadata.type),
          candidateSeasonNumber: Value(episode?.seasonNumber),
          candidateEpisodeNumber: Value(episode?.episodeNumber),
          candidateDetails: const Value(null),
        ),
      );
    }
    if (metadata.type == 'series') {
      await applyEpisodeMetadata(
        workId,
        files.values.whereType<TmdbEpisode>().toList(),
        manual: manual,
      );
    }
    for (final assignment in assignments.values) {
      await _copyMatchingProgress(
        assignment,
        workId: workId,
        episodeId: targets[assignment.fileId],
      );
    }
    for (final assignment in assignments.values) {
      await _cleanMatchingOrphan(assignment);
    }
    return workId;
  });

  Future<void> _copyMatchingProgress(
    MediaAssignmentData previous, {
    required int workId,
    required int? episodeId,
  }) async {
    final oldType = previous.workId != null ? 'work' : 'episode';
    final oldId = previous.workId ?? previous.episodeId!;
    final newType = episodeId == null ? 'work' : 'episode';
    final newId = episodeId ?? workId;
    if (oldType == newType && oldId == newId) return;
    final progress =
        await (db.select(db.playbackProgresses)..where(
              (p) => p.targetType.equals(oldType) & p.targetId.equals(oldId),
            ))
            .getSingleOrNull();
    if (progress == null || progress.lastFileId != previous.fileId) return;
    final target =
        await (db.select(db.playbackProgresses)..where(
              (p) => p.targetType.equals(newType) & p.targetId.equals(newId),
            ))
            .getSingleOrNull();
    if (target == null || progress.updatedAt.isAfter(target.updatedAt)) {
      await db
          .into(db.playbackProgresses)
          .insertOnConflictUpdate(
            progress
                .toCompanion(true)
                .copyWith(
                  id: const Value.absent(),
                  targetType: Value(newType),
                  targetId: Value(newId),
                  workId: Value(episodeId == null ? workId : null),
                  episodeId: Value(episodeId),
                ),
          );
    }
    final remaining =
        await (db.select(db.mediaAssignments)..where(
              (a) => oldType == 'work'
                  ? a.workId.equals(oldId)
                  : a.episodeId.equals(oldId),
            ))
            .get();
    if (remaining.isEmpty) {
      await (db.delete(
        db.playbackProgresses,
      )..where((p) => p.id.equals(progress.id))).go();
    }
  }

  Future<void> _cleanMatchingOrphan(MediaAssignmentData previous) async {
    var oldWorkId = previous.workId;
    if (previous.episodeId != null) {
      final episode = await (db.select(
        db.episodes,
      )..where((e) => e.id.equals(previous.episodeId!))).getSingleOrNull();
      if (episode == null) return;
      final assignments = await (db.select(
        db.mediaAssignments,
      )..where((a) => a.episodeId.equals(episode.id))).get();
      final history = await (db.select(
        db.playbackProgresses,
      )..where((p) => p.episodeId.equals(episode.id))).get();
      if (assignments.isNotEmpty || history.isNotEmpty) return;
      final season = await (db.select(
        db.seasons,
      )..where((s) => s.id.equals(episode.seasonId))).getSingle();
      oldWorkId = season.seriesId;
      await (db.delete(
        db.episodes,
      )..where((e) => e.id.equals(episode.id))).go();
      final episodes = await (db.select(
        db.episodes,
      )..where((e) => e.seasonId.equals(season.id))).get();
      if (episodes.isEmpty) {
        await (db.delete(
          db.seasons,
        )..where((s) => s.id.equals(season.id))).go();
      }
    }
    if (oldWorkId != null) {
      final history = await (db.select(
        db.playbackProgresses,
      )..where((p) => p.workId.equals(oldWorkId!))).get();
      if (history.isEmpty) await _deleteWorkIfOrphan(oldWorkId);
    }
  }

  Future<void> disableSource(int id) async {
    await (db.update(db.mediaSources)..where((s) => s.id.equals(id))).write(
      const MediaSourcesCompanion(enabled: Value(false)),
    );
  }

  Future<int> beginScan(int sourceId) async {
    return db.transaction(() async {
      final source = await (db.select(
        db.mediaSources,
      )..where((s) => s.id.equals(sourceId))).getSingleOrNull();
      if (source == null) {
        throw MediaSourceException(
          'Media source $sourceId not found',
          code: 'source_not_found',
        );
      }

      final nextRevision = source.scanRevision + 1;
      await (db.update(db.mediaSources)..where((s) => s.id.equals(sourceId)))
          .write(MediaSourcesCompanion(scanRevision: Value(nextRevision)));
      return nextRevision;
    });
  }

  Future<void> applyScanBatch(
    int sourceId,
    int scanId,
    List<MediaEntry> entries,
  ) async {
    if (entries.isEmpty) return;

    await db.transaction(() async {
      for (final entry in entries) {
        final incomingMs = entry.modifiedAt?.millisecondsSinceEpoch;

        final existing =
            await (db.select(db.mediaEntries)..where(
                  (e) =>
                      e.sourceId.equals(sourceId) &
                      e.externalEntryId.equals(entry.externalId),
                ))
                .getSingleOrNull();

        int entryId;
        if (existing != null) {
          entryId = existing.id;
          final existingMs = existing.modifiedAt;

          final statChanged =
              existing.size != entry.size ||
              existingMs != incomingMs ||
              existing.etag != entry.etag ||
              existing.name != entry.name ||
              existing.relativeLocator != entry.locator ||
              existing.isDirectory != entry.isDirectory;

          if (statChanged) {
            await (db.update(
              db.mediaEntries,
            )..where((e) => e.id.equals(existing.id))).write(
              MediaEntriesCompanion(
                relativeLocator: Value(entry.locator),
                name: Value(entry.name),
                isDirectory: Value(entry.isDirectory),
                size: Value(entry.size),
                modifiedAt: Value(incomingMs),
                etag: Value(entry.etag),
                available: const Value(true),
                lastSeenScanId: Value(scanId),
              ),
            );
          } else {
            await (db.update(
              db.mediaEntries,
            )..where((e) => e.id.equals(existing.id))).write(
              MediaEntriesCompanion(
                available: const Value(true),
                lastSeenScanId: Value(scanId),
              ),
            );
          }
        } else {
          entryId = await db
              .into(db.mediaEntries)
              .insert(
                MediaEntriesCompanion.insert(
                  sourceId: sourceId,
                  externalEntryId: entry.externalId,
                  relativeLocator: entry.locator,
                  name: entry.name,
                  isDirectory: entry.isDirectory,
                  size: Value(entry.size),
                  modifiedAt: Value(incomingMs),
                  etag: Value(entry.etag),
                  available: const Value(true),
                  lastSeenScanId: Value(scanId),
                ),
              );
        }

        if (!entry.isDirectory) {
          final existingFile = await (db.select(
            db.mediaFiles,
          )..where((f) => f.entryId.equals(entryId))).getSingleOrNull();
          if (existingFile == null) {
            await _createFileAndWorkForEntry(entryId, entry.name);
          }
        }
      }
    });
  }

  Future<void> finishScan(int sourceId, int scanId) async {
    await db.transaction(() async {
      final source = await (db.select(
        db.mediaSources,
      )..where((s) => s.id.equals(sourceId))).getSingleOrNull();
      if (source == null) return;
      if (source.scanRevision != scanId) {
        // Obsolete scan ID, skip marking unseen
        return;
      }

      await (db.update(db.mediaEntries)..where(
            (e) =>
                e.sourceId.equals(sourceId) &
                e.lastSeenScanId.equals(scanId).not(),
          ))
          .write(const MediaEntriesCompanion(available: Value(false)));

      await (db.update(
        db.mediaSources,
      )..where((s) => s.id.equals(sourceId))).write(
        MediaSourcesCompanion(
          lastScanAt: Value(DateTime.now()),
          errorMessage: const Value(null),
        ),
      );
    });
    await recognizePendingFiles();
  }

  Future<void> failScan(int sourceId, String message) async {
    await (db.update(db.mediaSources)..where((s) => s.id.equals(sourceId)))
        .write(MediaSourcesCompanion(errorMessage: Value(message)));
  }

  Stream<List<LibraryVideo>> watchLibrary({int limit = 100}) {
    final query = db.select(db.mediaFiles).join([
      innerJoin(
        db.mediaEntries,
        db.mediaEntries.id.equalsExp(db.mediaFiles.entryId),
      ),
      innerJoin(
        db.mediaSources,
        db.mediaSources.id.equalsExp(db.mediaEntries.sourceId),
      ),
      innerJoin(
        db.mediaAssignments,
        db.mediaAssignments.fileId.equalsExp(db.mediaFiles.id),
      ),
      leftOuterJoin(
        db.episodes,
        db.episodes.id.equalsExp(db.mediaAssignments.episodeId),
      ),
      leftOuterJoin(db.seasons, db.seasons.id.equalsExp(db.episodes.seasonId)),
      leftOuterJoin(
        db.works,
        db.works.id.equalsExp(db.mediaAssignments.workId) |
            db.works.id.equalsExp(db.seasons.seriesId),
      ),
    ]);

    query.where(
      db.mediaSources.enabled.equals(true) &
          db.mediaEntries.isDirectory.equals(false),
    );
    query.orderBy([
      OrderingTerm(expression: db.mediaEntries.name, mode: OrderingMode.asc),
      OrderingTerm(expression: db.mediaFiles.id, mode: OrderingMode.asc),
    ]);
    query.limit(limit);

    return query.watch().map((rows) {
      return rows.map((row) {
        final file = row.readTable(db.mediaFiles);
        final entry = row.readTable(db.mediaEntries);
        final source = row.readTable(db.mediaSources);
        final work = row.readTableOrNull(db.works);

        return LibraryVideo(
          fileId: file.id,
          sourceId: source.id,
          externalId: entry.externalEntryId,
          locator: entry.relativeLocator,
          title: work?.title ?? _titleWithoutExtension(entry.name),
          fileName: entry.name,
          sourceName: source.name,
          available: entry.available,
          sourceError: source.errorMessage,
        );
      }).toList();
    });
  }

  Future<LibraryVideo?> getVideo(int fileId) async {
    final query = db.select(db.mediaFiles).join([
      innerJoin(
        db.mediaEntries,
        db.mediaEntries.id.equalsExp(db.mediaFiles.entryId),
      ),
      innerJoin(
        db.mediaSources,
        db.mediaSources.id.equalsExp(db.mediaEntries.sourceId),
      ),
      innerJoin(
        db.mediaAssignments,
        db.mediaAssignments.fileId.equalsExp(db.mediaFiles.id),
      ),
      leftOuterJoin(
        db.episodes,
        db.episodes.id.equalsExp(db.mediaAssignments.episodeId),
      ),
      leftOuterJoin(db.seasons, db.seasons.id.equalsExp(db.episodes.seasonId)),
      leftOuterJoin(
        db.works,
        db.works.id.equalsExp(db.mediaAssignments.workId) |
            db.works.id.equalsExp(db.seasons.seriesId),
      ),
    ]);

    query.where(db.mediaFiles.id.equals(fileId));

    final row = await query.getSingleOrNull();
    if (row == null) return null;

    final file = row.readTable(db.mediaFiles);
    final entry = row.readTable(db.mediaEntries);
    final source = row.readTable(db.mediaSources);
    final work = row.readTableOrNull(db.works);

    final isAvailable = entry.available && source.enabled && !entry.isDirectory;
    final sourceError = !source.enabled
        ? (source.errorMessage ?? 'Source is disabled')
        : (entry.isDirectory ? 'Entry is a directory' : source.errorMessage);

    return LibraryVideo(
      fileId: file.id,
      sourceId: source.id,
      externalId: entry.externalEntryId,
      locator: entry.relativeLocator,
      title: work?.title ?? _titleWithoutExtension(entry.name),
      fileName: entry.name,
      sourceName: source.name,
      available: isAvailable,
      sourceError: sourceError,
    );
  }

  Future<void> _createFileAndWorkForEntry(int entryId, String fileName) async {
    final container = _extractContainer(fileName);
    final fileId = await db
        .into(db.mediaFiles)
        .insert(
          MediaFilesCompanion.insert(
            entryId: entryId,
            container: Value(container),
            parseState: const Value('pending'),
          ),
        );

    final title = _titleWithoutExtension(fileName);
    final workId = await db
        .into(db.works)
        .insert(
          WorksCompanion.insert(
            title: title,
            metadataSource: const Value('local'),
            metadataLocked: const Value(false),
          ),
        );

    await db
        .into(db.mediaAssignments)
        .insert(
          MediaAssignmentsCompanion.insert(
            fileId: fileId,
            workId: Value(workId),
            episodeId: const Value(null),
            preferred: const Value(false),
          ),
        );
  }

  MediaSourceConfig _toSourceConfig(MediaSourceEntry row) {
    return MediaSourceConfig(
      id: row.id,
      kind: row.kind,
      name: row.name,
      rootLocator: row.rootLocator,
      credentialRef: row.credentialRef,
      enabled: row.enabled,
      extensions: _parseStringList(row.extensions, defaultVideoExtensions),
      excludedDirectories: _parseStringList(
        row.excludedDirectories,
        defaultExcludedDirectories,
      ),
      scanRevision: row.scanRevision,
      lastScanAt: row.lastScanAt,
      errorMessage: row.errorMessage,
    );
  }

  static List<String> _parseStringList(String jsonStr, List<String> fallback) {
    try {
      final decoded = jsonDecode(jsonStr);
      if (decoded is List) {
        return decoded.map((e) => e.toString()).toList();
      }
    } catch (_) {}
    return fallback;
  }

  static String? _extractContainer(String fileName) {
    final dot = fileName.lastIndexOf('.');
    if (dot <= 0 || dot == fileName.length - 1) return null;
    return fileName.substring(dot + 1).toLowerCase();
  }

  static String _titleWithoutExtension(String fileName) {
    final dot = fileName.lastIndexOf('.');
    if (dot <= 0) return fileName;
    return fileName.substring(0, dot);
  }
  // =========================================================================
  // M3 扩展：自动识别、作品分页列表、多版本与元数据管理
  // =========================================================================

  /// 扫描或导入后保守识别待处理的媒体文件。
  ///
  /// 保留用户已锁定或非本地来源的既有匹配；对于高置信度的电影自动归并版本，
  /// 对于高置信度的剧集建立季集层级；对于多集、未知集号或结构模糊的文件显式保留待审查状态。
  Future<void> recognizePendingFiles() async {
    await db.transaction(() async {
      final pendingFiles = await (db.select(db.mediaFiles).join([
        innerJoin(
          db.mediaEntries,
          db.mediaEntries.id.equalsExp(db.mediaFiles.entryId),
        ),
        innerJoin(
          db.mediaAssignments,
          db.mediaAssignments.fileId.equalsExp(db.mediaFiles.id),
        ),
        leftOuterJoin(
          db.works,
          db.works.id.equalsExp(db.mediaAssignments.workId),
        ),
        innerJoin(
          db.mediaSources,
          db.mediaSources.id.equalsExp(db.mediaEntries.sourceId),
        ),
      ])..where(db.mediaFiles.parseState.equals('pending'))).get();

      if (pendingFiles.isEmpty) return;

      for (final row in pendingFiles) {
        final file = row.readTable(db.mediaFiles);
        final entry = row.readTable(db.mediaEntries);
        final currentWork = await _assignedWork(
          row.readTable(db.mediaAssignments),
        );

        // 如果用户已经锁定或者已有非本地来源匹配，则绝不自动覆盖
        if (await _isProtectedWork(currentWork)) {
          await (db.update(db.mediaFiles)..where((f) => f.id.equals(file.id)))
              .write(const MediaFilesCompanion(parseState: Value('parsed')));
          continue;
        }

        final source = row.readTable(db.mediaSources);
        final parsed = MediaFilenameParser.parse(
          entry.name,
          directoryNames: DirectoryContextResolver.resolve(
            kind: source.kind,
            rootLocator: source.rootLocator,
            locator: entry.relativeLocator,
          ),
        );
        if (parsed.isExtra) {
          await recordMatchingReview([
            file.id,
          ], const MatchDecision(reason: MatchReason.extraMedia));
          continue;
        }
        // 情况 1: 具备明确季号与单集号的剧集（即便缺少年份，也必须完整建立剧集/季/集层级；缺年份仅影响向 TMDB 自动匹配置信度，不影响本地层级结构）
        if (parsed.type == 'series' &&
            parsed.seasonNumber != null &&
            parsed.episodeNumber != null &&
            !parsed.isMultiEpisode &&
            !parsed.isSpecialOrOva &&
            !parsed.isExtra) {
          final allCandidateSeries =
              await (db.select(db.works)..where(
                    (w) =>
                        w.type.equals('series') & w.title.equals(parsed.title),
                  ))
                  .get();

          final candidateSeries = <WorkData>[];
          for (final candidate in allCandidateSeries) {
            if (await _sameLocalScope(candidate, entry, source)) {
              candidateSeries.add(candidate);
            }
          }

          WorkData? seriesWork;
          if (parsed.year != null) {
            final matched = candidateSeries
                .where((w) => w.year == parsed.year)
                .toList();
            if (matched.length == 1) {
              seriesWork = matched.first;
            } else if (matched.isEmpty) {
              final nullYearMatched = candidateSeries
                  .where((w) => w.year == null)
                  .toList();
              if (nullYearMatched.length == 1 && candidateSeries.length == 1) {
                seriesWork = nullYearMatched.first;
                // 仅在 target 未锁定且为 local 时补写年份
                if (!seriesWork.metadataLocked &&
                    seriesWork.metadataSource == 'local') {
                  await (db.update(db.works)
                        ..where((w) => w.id.equals(seriesWork!.id)))
                      .write(WorksCompanion(year: Value(parsed.year)));
                }
              }
            }
          } else {
            final nullYearMatched = candidateSeries
                .where((w) => w.year == null)
                .toList();
            if (nullYearMatched.length == 1 && candidateSeries.length == 1) {
              seriesWork = nullYearMatched.first;
            }
          }

          int seriesId;
          if (seriesWork != null) {
            seriesId = seriesWork.id;
          } else {
            seriesId = await db
                .into(db.works)
                .insert(
                  WorksCompanion.insert(
                    title: parsed.title,
                    type: const Value('series'),
                    year: Value(parsed.year),
                    metadataSource: const Value('local'),
                    metadataLocked: const Value(false),
                  ),
                );
          }

          final seasonRow =
              await (db.select(db.seasons)..where(
                    (s) =>
                        s.seriesId.equals(seriesId) &
                        s.seasonNumber.equals(parsed.seasonNumber!),
                  ))
                  .getSingleOrNull();

          int seasonId;
          if (seasonRow != null) {
            seasonId = seasonRow.id;
          } else {
            seasonId = await db
                .into(db.seasons)
                .insert(
                  SeasonsCompanion.insert(
                    seriesId: seriesId,
                    seasonNumber: parsed.seasonNumber!,
                  ),
                );
          }

          final episodeRow =
              await (db.select(db.episodes)..where(
                    (e) =>
                        e.seasonId.equals(seasonId) &
                        e.episodeNumber.equals(parsed.episodeNumber!),
                  ))
                  .getSingleOrNull();

          int episodeId;
          if (episodeRow != null) {
            episodeId = episodeRow.id;
            if (parsed.episodeTitle != null && episodeRow.title == null) {
              await (db.update(db.episodes)
                    ..where((e) => e.id.equals(episodeId)))
                  .write(EpisodesCompanion(title: Value(parsed.episodeTitle)));
            }
          } else {
            episodeId = await db
                .into(db.episodes)
                .insert(
                  EpisodesCompanion.insert(
                    seasonId: seasonId,
                    episodeNumber: parsed.episodeNumber!,
                    title: Value(parsed.episodeTitle),
                  ),
                );
          }

          await (db.update(
            db.mediaAssignments,
          )..where((a) => a.fileId.equals(file.id))).write(
            MediaAssignmentsCompanion(
              workId: const Value(null),
              episodeId: Value(episodeId),
              editionLabel: Value(parsed.editionLabel),
            ),
          );

          if (currentWork != null && currentWork.id != seriesId) {
            await _migrateWorkProgressToEpisode(
              fromWorkId: currentWork.id,
              toEpisodeId: episodeId,
            );
            await _deleteWorkIfOrphan(currentWork.id);
          }

          await (db.update(db.mediaFiles)..where((f) => f.id.equals(file.id)))
              .write(const MediaFilesCompanion(parseState: Value('parsed')));
          continue;
        }

        // 情况 2: 高置信度电影（type == 'movie' 且年份明确）
        if (parsed.type == 'movie' && parsed.year != null) {
          final allExistingMovies =
              await (db.select(db.works)..where(
                    (w) =>
                        w.type.equals('movie') &
                        w.title.equals(parsed.title) &
                        w.year.equals(parsed.year!),
                  ))
                  .get();

          final existingMovies = <WorkData>[];
          for (final candidate in allExistingMovies) {
            if (await _sameLocalScope(candidate, entry, source)) {
              existingMovies.add(candidate);
            }
          }

          // 仅在存在唯一同名同年作品时自动归并多版本
          if (existingMovies.length == 1) {
            final existingMovie = existingMovies.first;
            if (currentWork == null || existingMovie.id != currentWork.id) {
              await (db.update(
                db.mediaAssignments,
              )..where((a) => a.fileId.equals(file.id))).write(
                MediaAssignmentsCompanion(
                  workId: Value(existingMovie.id),
                  episodeId: const Value(null),
                  editionLabel: Value(parsed.editionLabel),
                ),
              );

              if (currentWork != null) {
                await _migrateWorkProgress(
                  fromWorkId: currentWork.id,
                  toWorkId: existingMovie.id,
                );
                await _deleteWorkIfOrphan(currentWork.id);
              }
            }
            await (db.update(db.mediaFiles)..where((f) => f.id.equals(file.id)))
                .write(const MediaFilesCompanion(parseState: Value('parsed')));
            continue;
          } else if (existingMovies.isEmpty &&
              allExistingMovies.length <= 1 &&
              currentWork != null) {
            await (db.update(
              db.works,
            )..where((w) => w.id.equals(currentWork.id))).write(
              WorksCompanion(
                type: const Value('movie'),
                title: Value(parsed.title),
                year: Value(parsed.year),
                metadataSource: const Value('local'),
              ),
            );
            if (parsed.editionLabel != null) {
              await (db.update(
                db.mediaAssignments,
              )..where((a) => a.fileId.equals(file.id))).write(
                MediaAssignmentsCompanion(
                  editionLabel: Value(parsed.editionLabel),
                ),
              );
            }
            await (db.update(db.mediaFiles)..where((f) => f.id.equals(file.id)))
                .write(const MediaFilesCompanion(parseState: Value('parsed')));
            continue;
          }
          // 若存在多个同名同年候选（如不同TMDB身份或冲突候选），保留本地独立候选不自动合并，亦不抛出异常，留给人工匹配
        }

        // 情况 3: 多集文件、未知集号特辑、无年份电影候选或模糊文件
        // 严禁伪造集号为 0/1，严禁直接给 series 作品挂 work_id，显式标记 needs_review
        await (db.update(
          db.mediaFiles,
        )..where((f) => f.id.equals(file.id))).write(
          MediaFilesCompanion(
            parseState: const Value('needs_review'),
            candidateType: Value(parsed.type),
            candidateSeasonNumber: Value(parsed.seasonNumber),
            candidateEpisodeNumber: Value(parsed.episodeNumber),
            candidateDetails: Value(
              parsed.isMultiEpisode
                  ? 'multi_episode:${parsed.episodeNumbers.join(",")}'
                  : (parsed.isSpecialOrOva ? 'special_or_ova' : null),
            ),
          ),
        );

        if (currentWork != null &&
            !currentWork.metadataLocked &&
            parsed.title.isNotEmpty &&
            currentWork.title != parsed.title) {
          await (db.update(
            db.works,
          )..where((w) => w.id.equals(currentWork.id))).write(
            WorksCompanion(
              title: Value(parsed.title),
              year: Value(parsed.year ?? currentWork.year),
            ),
          );
        }

        continue;
      }
    });
  }

  /// 监视媒体作品列表，DB 层级分页。
  ///
  /// 首次发射前触发识别，包含启用源的不可用文件，排除全源停用的作品。
  Stream<List<LibraryWork>> watchWorks({
    int limit = 100,
    String search = '',
    String? type,
    bool recentlyAdded = false,
    bool unmatchedOnly = false,
    bool matchedOnly = false,
  }) async* {
    await recognizePendingFiles();
    yield* _watchWorksInternal(
      limit: limit,
      search: search,
      type: type,
      recentlyAdded: recentlyAdded,
      unmatchedOnly: unmatchedOnly,
      matchedOnly: matchedOnly,
    );
  }

  static const _workBaseSelectSql = '''
    SELECT 
      w.id,
      w.type,
      w.title,
      w.original_title,
      w.year,
      w.overview,
      w.poster_path,
      w.backdrop_path,
      w.poster_locator,
      w.backdrop_locator,
      w.metadata_source,
      w.metadata_locked,
      (
        SELECT COUNT(DISTINCT ma.file_id)
        FROM media_assignments ma
        JOIN media_files mf ON mf.id = ma.file_id
        JOIN media_entries me ON me.id = mf.entry_id
        JOIN media_sources ms ON ms.id = me.source_id
        WHERE ms.enabled = 1 AND me.is_directory = 0 AND (
          ma.work_id = w.id OR
          ma.episode_id IN (
            SELECT e2.id FROM episodes e2
            JOIN seasons s2 ON s2.id = e2.season_id
            WHERE s2.series_id = w.id
          )
        )
      ) as version_count,
      (
        SELECT MAX(CASE WHEN me.available = 1 AND ms.enabled = 1 AND me.is_directory = 0 THEN 1 ELSE 0 END)
        FROM media_assignments ma
        JOIN media_files mf ON mf.id = ma.file_id
        JOIN media_entries me ON me.id = mf.entry_id
        JOIN media_sources ms ON ms.id = me.source_id
        WHERE ms.enabled = 1 AND me.is_directory = 0 AND (
          ma.work_id = w.id OR
          ma.episode_id IN (
            SELECT e2.id FROM episodes e2
            JOIN seasons s2 ON s2.id = e2.season_id
            WHERE s2.series_id = w.id
          )
        )
      ) as is_available
    FROM works w
  ''';

  static LibraryWork _workFromRow(QueryRow row) {
    final availableVal = row.readNullable<int>('is_available') ?? 0;
    return LibraryWork(
      id: row.read<int>('id'),
      type: row.readNullable<String>('type'),
      title: row.read<String>('title'),
      originalTitle: row.readNullable<String>('original_title'),
      year: row.readNullable<int>('year'),
      overview: row.readNullable<String>('overview'),
      posterPath:
          row.readNullable<String>('poster_locator') ??
          row.readNullable<String>('poster_path'),
      tmdbPosterPath: row.readNullable<String>('poster_path'),
      backdropPath:
          row.readNullable<String>('backdrop_locator') ??
          row.readNullable<String>('backdrop_path'),
      metadataSource: row.read<String>('metadata_source'),
      metadataLocked: (row.read<int>('metadata_locked')) == 1,
      versionCount: row.read<int>('version_count'),
      available: availableVal == 1,
    );
  }

  Stream<List<LibraryWork>> _watchWorksInternal({
    required int limit,
    required String search,
    required String? type,
    required bool recentlyAdded,
    required bool unmatchedOnly,
    required bool matchedOnly,
  }) {
    final variables = <Variable<Object>>[];
    var filters = '';
    if (unmatchedOnly) {
      filters += " AND w.metadata_source = 'local' AND w.metadata_locked = 0";
    } else if (matchedOnly) {
      filters += " AND (w.metadata_source != 'local' OR w.metadata_locked = 1)";
    }
    if (search.isNotEmpty) {
      final pattern =
          '%${search.replaceAll(r'\', r'\\').replaceAll('%', r'\%').replaceAll('_', r'\_')}%';
      filters += r" AND (w.title LIKE ? ESCAPE '\' OR w.original_title LIKE ? ESCAPE '\')";
      variables.addAll([
        Variable.withString(pattern),
        Variable.withString(pattern),
      ]);
    }
    if (type != null) {
      filters += ' AND w.type = ?';
      variables.add(Variable.withString(type));
    }
    variables.add(Variable.withInt(limit));
    final orderBy = recentlyAdded
        ? 'w.created_at DESC, w.id DESC'
        : 'w.title COLLATE NOCASE ASC, w.id ASC';
    final queryStr =
        '''
      $_workBaseSelectSql
      WHERE EXISTS (
        SELECT 1 FROM media_assignments ma
        JOIN media_files mf ON mf.id = ma.file_id
        JOIN media_entries me ON me.id = mf.entry_id
        JOIN media_sources ms ON ms.id = me.source_id
        WHERE ms.enabled = 1 AND me.is_directory = 0
          ${unmatchedOnly ? "AND mf.parse_state != 'extra'" : ''} AND (
          ma.work_id = w.id OR
          ma.episode_id IN (
            SELECT e2.id FROM episodes e2
            JOIN seasons s2 ON s2.id = e2.season_id
            WHERE s2.series_id = w.id
          )
        )
      )
      $filters
      ORDER BY $orderBy
      LIMIT ?
    ''';

    return db
        .customSelect(
          queryStr,
          variables: variables,
          readsFrom: <TableInfo<Table, dynamic>>{
            db.works,
            db.mediaAssignments,
            db.mediaFiles,
            db.mediaEntries,
            db.mediaSources,
            db.seasons,
            db.episodes,
          },
        )
        .watch()
        .map((rows) => rows.map(_workFromRow).toList());
  }

  /// 监视最近添加的媒体作品列表，DB 层级分页。
  ///
  /// 按 created_at DESC, id DESC 排序，首次发射前触发识别。
  Stream<List<LibraryWork>> watchRecentWorks({int limit = 20}) async* {
    await recognizePendingFiles();
    yield* _watchRecentWorksInternal(limit);
  }

  Stream<List<LibraryWork>> _watchRecentWorksInternal(int limit) {
    const queryStr =
        '''
      $_workBaseSelectSql
      WHERE EXISTS (
        SELECT 1 FROM media_assignments ma
        JOIN media_files mf ON mf.id = ma.file_id
        JOIN media_entries me ON me.id = mf.entry_id
        JOIN media_sources ms ON ms.id = me.source_id
        WHERE ms.enabled = 1 AND me.is_directory = 0 AND (
          ma.work_id = w.id OR
          ma.episode_id IN (
            SELECT e2.id FROM episodes e2
            JOIN seasons s2 ON s2.id = e2.season_id
            WHERE s2.series_id = w.id
          )
        )
      )
      ORDER BY w.created_at DESC, w.id DESC
      LIMIT ?
    ''';

    return db
        .customSelect(
          queryStr,
          variables: [Variable.withInt(limit)],
          readsFrom: <TableInfo<Table, dynamic>>{
            db.works,
            db.mediaAssignments,
            db.mediaFiles,
            db.mediaEntries,
            db.mediaSources,
            db.seasons,
            db.episodes,
          },
        )
        .watch()
        .map((rows) => rows.map(_workFromRow).toList());
  }

  /// 监视指定作品的详情与版本列表。
  Stream<WorkDetails?> watchWorkDetails(int workId) async* {
    await recognizePendingFiles();
    yield* _watchWorkDetailsInternal(workId);
  }

  Stream<WorkDetails?> _watchWorkDetailsInternal(int workId) {
    const workQueryStr =
        '''
      $_workBaseSelectSql
      WHERE w.id = ?
    ''';

    const versionsQueryStr = '''
      SELECT 
        mf.id as file_id,
        me.name as file_name,
        ms.name as source_name,
        (CASE WHEN me.available = 1 AND ms.enabled = 1 AND me.is_directory = 0 THEN 1 ELSE 0 END) as is_available,
        ma.edition_label,
        (CASE 
          WHEN ms.enabled = 0 THEN COALESCE(ms.error_message, 'Source is disabled')
          WHEN me.is_directory = 1 THEN 'Entry is a directory'
          ELSE ms.error_message 
        END) as source_error,
        ep.title as episode_title,
        s.season_number,
        ep.episode_number
      FROM media_assignments ma
      JOIN media_files mf ON mf.id = ma.file_id
      JOIN media_entries me ON me.id = mf.entry_id
      JOIN media_sources ms ON ms.id = me.source_id
      LEFT JOIN episodes ep ON ep.id = ma.episode_id
      LEFT JOIN seasons s ON s.id = ep.season_id
      WHERE ms.enabled = 1 AND me.is_directory = 0 AND (
        ma.work_id = ? OR
        s.series_id = ?
      )
      ORDER BY 
        COALESCE(s.season_number, 0) ASC,
        COALESCE(ep.episode_number, 0) ASC,
        ma.preferred DESC,
        me.name ASC,
        mf.id ASC
    ''';

    final reads = <TableInfo<Table, dynamic>>{
      db.works,
      db.mediaAssignments,
      db.mediaFiles,
      db.mediaEntries,
      db.mediaSources,
      db.seasons,
      db.episodes,
    };

    return db
        .customSelect(
          workQueryStr,
          variables: [Variable.withInt(workId)],
          readsFrom: reads,
        )
        .watchSingleOrNull()
        .asyncMap((workRow) async {
          if (workRow == null) return null;

          final work = _workFromRow(workRow);

          final versionRows = await db
              .customSelect(
                versionsQueryStr,
                variables: [Variable.withInt(workId), Variable.withInt(workId)],
                readsFrom: reads,
              )
              .get();

          final versions = versionRows.map((v) {
            final isAvail = (v.readNullable<int>('is_available') ?? 0) == 1;
            return LibraryVersion(
              fileId: v.read<int>('file_id'),
              fileName: v.read<String>('file_name'),
              sourceName: v.read<String>('source_name'),
              available: isAvail,
              editionLabel: v.readNullable<String>('edition_label'),
              sourceError: v.readNullable<String>('source_error'),
              episodeTitle: v.readNullable<String>('episode_title'),
              seasonNumber: v.readNullable<int>('season_number'),
              episodeNumber: v.readNullable<int>('episode_number'),
            );
          }).toList();

          return WorkDetails(work: work, versions: versions);
        });
  }

  /// 一次性获取指定作品的详情。
  Future<WorkDetails?> getWorkDetails(int workId) async {
    await recognizePendingFiles();
    return _watchWorkDetailsInternal(workId).first;
  }

  /// 获取未匹配的本地作品（无元数据锁且源为 local）。
  Future<List<LibraryWork>> unmatchedWorks() async {
    await recognizePendingFiles();
    const queryStr =
        '''
      $_workBaseSelectSql
      WHERE w.metadata_locked = 0 
        AND w.metadata_source = 'local'
        AND EXISTS (
          SELECT 1 FROM media_assignments ma
          JOIN media_files mf ON mf.id = ma.file_id
          JOIN media_entries me ON me.id = mf.entry_id
          JOIN media_sources ms ON ms.id = me.source_id
          WHERE ms.enabled = 1 AND me.is_directory = 0 AND mf.parse_state != 'extra' AND (
            ma.work_id = w.id OR
            ma.episode_id IN (
              SELECT e2.id FROM episodes e2
              JOIN seasons s2 ON s2.id = e2.season_id
              WHERE s2.series_id = w.id
            )
          )
        )
      ORDER BY w.title COLLATE NOCASE ASC, w.id ASC
    ''';

    final rows = await db
        .customSelect(
          queryStr,
          readsFrom: <TableInfo<Table, dynamic>>{
            db.works,
            db.mediaAssignments,
            db.mediaFiles,
            db.mediaEntries,
            db.mediaSources,
            db.seasons,
            db.episodes,
          },
        )
        .get();

    return rows.map(_workFromRow).toList();
  }

  /// 检查指定作品关联的文件是否包含多集文件。
  Future<bool> hasMultiEpisodeFiles(int workId) async {
    return (await matchingFilesForWork(workId))
        .any((file) => file.parsed.isMultiEpisode);
  }

  /// 应用作品元数据，自动归并相同 TMDB ID 的作品并正确保留季集与播放进度。
  ///
  /// 返回最终的规范作品 ID。
  Future<int> applyMetadata(
    int workId,
    WorkMetadata metadata, {
    bool manual = false,
    TmdbEpisode? episode,
    String metadataSource = 'tmdb',
  }) async {
    return await db.transaction(() async {
      final currentWork = await (db.select(
        db.works,
      )..where((w) => w.id.equals(workId))).getSingleOrNull();
      if (currentWork == null) {
        throw const MetadataException('作品已被更新，请重新加载', code: 'work_not_found');
      }

      // 锁定状态下的自动调用（含异步迟到结果）绝不覆盖
      if (currentWork.metadataLocked && !manual) {
        return currentWork.id;
      }

      // 检查类型兼容性：电影 vs 剧集不兼容
      final existingSeasons = await (db.select(
        db.seasons,
      )..where((s) => s.seriesId.equals(workId))).get();
      if (existingSeasons.isNotEmpty && metadata.type == 'movie') {
        throw ArgumentError(
          'Incompatible media type: cannot match series work to movie',
        );
      }

      // 支持 manual 的 null/movie 候选 + episode -> series
      if (metadata.type == 'series' && currentWork.type != 'series') {
        if (episode == null) {
          throw ArgumentError(
            'Episode is required when matching non-series work to series',
          );
        }
        if (!manual) {
          throw ArgumentError(
            'Manual matching is required when matching non-series work to series',
          );
        }

        final directAssignments = await (db.select(
          db.mediaAssignments,
        )..where((a) => a.workId.equals(workId))).get();
        if (directAssignments.isNotEmpty) {
          final fileIds = directAssignments.map((a) => a.fileId).toList();
          final files = await (db.select(
            db.mediaFiles,
          )..where((f) => f.id.isIn(fileIds))).get();
          if (files.any(
            (f) => f.candidateDetails?.startsWith('multi_episode') == true,
          )) {
            throw const MetadataException(
              '当前包含多集文件，暂不支持单集手动绑定',
              code: 'multi_episode_unsupported',
            );
          }
        }

        // 1. 先根据 tmdb series 身份复用 canonical，否则创建合法 series 作品
        final providerEntityId = '${metadata.type}:${metadata.tmdbId}';
        final existingCanonicalId = metadata.tmdbId == null
            ? null
            : await _getWorkIdByExternalId('tmdb', providerEntityId);

        final int targetSeriesId;
        if (existingCanonicalId != null) {
          targetSeriesId = existingCanonicalId;
        } else {
          targetSeriesId = await db
              .into(db.works)
              .insert(
                WorksCompanion.insert(
                  type: const Value('series'),
                  title: metadata.title,
                ),
              );
        }

        // 2. 复用/创建其真实 season 与 episode
        SeasonData? season =
            await (db.select(db.seasons)..where(
                  (s) =>
                      s.seriesId.equals(targetSeriesId) &
                      s.seasonNumber.equals(episode.seasonNumber),
                ))
                .getSingleOrNull();

        final int seasonId;
        if (season == null) {
          seasonId = await db
              .into(db.seasons)
              .insert(
                SeasonsCompanion.insert(
                  seriesId: targetSeriesId,
                  seasonNumber: episode.seasonNumber,
                  title: Value('Season ${episode.seasonNumber}'),
                ),
              );
        } else {
          seasonId = season.id;
        }

        EpisodeData? epRow =
            await (db.select(db.episodes)..where(
                  (e) =>
                      e.seasonId.equals(seasonId) &
                      e.episodeNumber.equals(episode.episodeNumber),
                ))
                .getSingleOrNull();

        final int episodeId;
        if (epRow == null) {
          episodeId = await db
              .into(db.episodes)
              .insert(
                EpisodesCompanion.insert(
                  seasonId: seasonId,
                  episodeNumber: episode.episodeNumber,
                  title: Value(episode.title),
                  overview: Value(episode.overview),
                  airDate: Value(episode.airDate),
                  tmdbId: Value(episode.tmdbId),
                ),
              );
        } else {
          episodeId = epRow.id;
          if (episode.title != null ||
              episode.overview != null ||
              episode.airDate != null) {
            await (db.update(
              db.episodes,
            )..where((e) => e.id.equals(episodeId))).write(
              EpisodesCompanion(
                title: Value(episode.title ?? epRow.title),
                overview: Value(episode.overview ?? epRow.overview),
                airDate: Value(episode.airDate ?? epRow.airDate),
              ),
            );
          }
        }

        // 3. 将当前 work_id 文件关联一次性改为 episode_id 并清空 work_id，保留 assignment 其他字段
        final fileIds = directAssignments.map((a) => a.fileId).toList();
        await (db.update(
          db.mediaAssignments,
        )..where((a) => a.workId.equals(workId))).write(
          MediaAssignmentsCompanion(
            workId: const Value(null),
            episodeId: Value(episodeId),
          ),
        );

        // 4. 用已有 _migrateWorkProgressToEpisode 迁移进度，再清理孤儿旧作品
        await _migrateWorkProgressToEpisode(
          fromWorkId: workId,
          toEpisodeId: episodeId,
        );
        await db.customStatement('DELETE FROM external_ids WHERE work_id = ?', [
          workId,
        ]);
        if (workId != targetSeriesId) {
          await _deleteWorkIfOrphan(workId);
        }

        // 5. 将对应文件 parse_state 设 parsed
        if (fileIds.isNotEmpty) {
          await (db.update(db.mediaFiles)..where((f) => f.id.isIn(fileIds)))
              .write(const MediaFilesCompanion(parseState: Value('parsed')));
        }

        // 6. 之后复用既有 applyMetadata 应用元数据、manual 锁和外部 ID（可递归对 targetSeriesId 调用，仍在外层事务）
        return await applyMetadata(
          targetSeriesId,
          metadata,
          manual: true,
          metadataSource: metadataSource,
        );
      }

      if (currentWork.type != null && currentWork.type != metadata.type) {
        throw ArgumentError(
          'Incompatible media type: work is ${currentWork.type}, cannot match to ${metadata.type}',
        );
      }

      final providerEntityId = '${metadata.type}:${metadata.tmdbId}';
      final existingCanonicalId = metadata.tmdbId == null
          ? null
          : await _getWorkIdByExternalId('tmdb', providerEntityId);

      int targetWorkId = workId;

      if (existingCanonicalId != null && existingCanonicalId != workId) {
        targetWorkId = existingCanonicalId;

        // A) 检查目标规范作品当前的真实锁定状态
        final canonicalWork = await (db.select(
          db.works,
        )..where((w) => w.id.equals(targetWorkId))).getSingleOrNull();
        final isCanonicalLocked = canonicalWork?.metadataLocked ?? false;

        // 将当前作品文件版本归并入 canonicalWork
        if (metadata.type == 'movie') {
          await db.customStatement(
            'UPDATE media_assignments SET work_id = ? WHERE work_id = ?',
            [targetWorkId, workId],
          );
        } else {
          for (final season in existingSeasons) {
            final canonicalSeason =
                await (db.select(db.seasons)..where(
                      (s) =>
                          s.seriesId.equals(targetWorkId) &
                          s.seasonNumber.equals(season.seasonNumber),
                    ))
                    .getSingleOrNull();

            if (canonicalSeason == null) {
              await (db.update(db.seasons)
                    ..where((s) => s.id.equals(season.id)))
                  .write(SeasonsCompanion(seriesId: Value(targetWorkId)));
            } else {
              final seasonEps = await (db.select(
                db.episodes,
              )..where((e) => e.seasonId.equals(season.id))).get();
              for (final ep in seasonEps) {
                final canonicalEp =
                    await (db.select(db.episodes)..where(
                          (e) =>
                              e.seasonId.equals(canonicalSeason.id) &
                              e.episodeNumber.equals(ep.episodeNumber),
                        ))
                        .getSingleOrNull();

                if (canonicalEp == null) {
                  await (db.update(
                    db.episodes,
                  )..where((e) => e.id.equals(ep.id))).write(
                    EpisodesCompanion(seasonId: Value(canonicalSeason.id)),
                  );
                } else {
                  await db.customStatement(
                    'UPDATE media_assignments SET episode_id = ? WHERE episode_id = ?',
                    [canonicalEp.id, ep.id],
                  );
                  await _migrateEpisodeProgress(
                    fromEpId: ep.id,
                    toEpId: canonicalEp.id,
                  );
                  await (db.delete(
                    db.episodes,
                  )..where((e) => e.id.equals(ep.id))).go();
                }
              }
              await (db.delete(
                db.seasons,
              )..where((s) => s.id.equals(season.id))).go();
            }
          }
        }

        await _migrateWorkProgress(fromWorkId: workId, toWorkId: targetWorkId);

        // B) 清理被归并作品的旧 TMDB 外部绑定，绝不把可能错误的旧 ID 挂到规范作品上
        await db.customStatement('DELETE FROM external_ids WHERE work_id = ?', [
          workId,
        ]);
        await (db.delete(db.works)..where((w) => w.id.equals(workId))).go();

        // A) 自动把 local work 并入已加锁规范作品时，严禁覆盖 target 元数据或改变其锁定状态
        if (isCanonicalLocked && !manual) {
          return targetWorkId;
        }

        final lockValue = manual ? true : isCanonicalLocked;
        await (db.update(
          db.works,
        )..where((w) => w.id.equals(targetWorkId))).write(
          WorksCompanion(
            type: Value(metadata.type),
            title: Value(metadata.title),
            originalTitle: Value(metadata.originalTitle),
            year: Value(metadata.year),
            overview: Value(metadata.overview),
            posterPath: Value(metadata.posterPath),
            backdropPath: Value(metadata.backdropPath),
            metadataSource: Value(metadataSource),
            premiered: Value(metadata.premiered),
            posterLocator: const Value(null),
            backdropLocator: const Value(null),
            metadataLocked: Value(lockValue),
            updatedAt: Value(DateTime.now()),
          ),
        );
      } else {
        // B) 手动重绑：若该作品先前已绑定旧 TMDB ID，先清理旧绑定，只保留新绑定
        await db.customStatement(
          'DELETE FROM external_ids WHERE work_id = ? AND provider = ?',
          [targetWorkId, 'tmdb'],
        );
        if (metadata.tmdbId != null) {
          await _linkWorkExternalId(targetWorkId, 'tmdb', providerEntityId);
        }

        final lockValue = manual ? true : currentWork.metadataLocked;
        await (db.update(
          db.works,
        )..where((w) => w.id.equals(targetWorkId))).write(
          WorksCompanion(
            type: Value(metadata.type),
            title: Value(metadata.title),
            originalTitle: Value(metadata.originalTitle),
            year: Value(metadata.year),
            overview: Value(metadata.overview),
            posterPath: Value(metadata.posterPath),
            backdropPath: Value(metadata.backdropPath),
            metadataSource: Value(metadataSource),
            premiered: Value(metadata.premiered),
            posterLocator: const Value(null),
            backdropLocator: const Value(null),
            metadataLocked: Value(lockValue),
            updatedAt: Value(DateTime.now()),
          ),
        );
      }
      return targetWorkId;
    });
  }

  /// 手动编辑本地元数据并显式加锁。

  Future<List<MetadataFile>> metadataFiles({
    int? sourceId,
    int? workId,
    List<int>? fileIds,
    List<String>? entryIds,
    bool matchedOnly = true,
  }) async {
    if (fileIds != null && fileIds.isEmpty ||
        entryIds != null && entryIds.isEmpty) {
      return [];
    }
    final rows = await db
        .customSelect(
          '''
      SELECT mf.id AS file_id, me.source_id, me.external_entry_id, me.name,
        w.id AS work_id, w.type, w.title, w.original_title, w.overview, w.year,
        w.poster_path, w.backdrop_path, w.premiered, w.metadata_source, w.metadata_locked,
        s.season_number, ep.episode_number, ep.title AS episode_title,
        ep.overview AS episode_overview, ep.air_date, ep.tmdb_id AS episode_tmdb_id,
        ei.provider_entity_id
      FROM media_files mf JOIN media_entries me ON me.id = mf.entry_id
      JOIN media_sources ms ON ms.id = me.source_id
      JOIN media_assignments ma ON ma.file_id = mf.id
      LEFT JOIN episodes ep ON ep.id = ma.episode_id
      LEFT JOIN seasons s ON s.id = ep.season_id
      JOIN works w ON w.id = COALESCE(ma.work_id, s.series_id)
      LEFT JOIN external_ids ei ON ei.work_id = w.id AND ei.provider = 'tmdb'
      WHERE ms.enabled = 1 AND me.available = 1
        ${sourceId == null ? '' : 'AND me.source_id = ?'}
        ${workId == null ? '' : 'AND w.id = ?'}
        ${fileIds == null ? '' : 'AND mf.id IN (${List.filled(fileIds.length, '?').join(',')})'}
        ${entryIds == null ? '' : 'AND me.external_entry_id IN (${List.filled(entryIds.length, '?').join(',')})'}
        ${matchedOnly ? "AND (w.metadata_source != 'local' OR w.metadata_locked = 1)" : ''}
      ORDER BY me.source_id, me.external_entry_id
    ''',
          variables: [
            if (sourceId != null) Variable.withInt(sourceId),
            if (workId != null) Variable.withInt(workId),
            for (final id in fileIds ?? <int>[]) Variable.withInt(id),
            for (final id in entryIds ?? <String>[]) Variable.withString(id),
          ],
        )
        .get();
    return rows.map((row) {
      final season = row.readNullable<int>('season_number');
      return MetadataFile(
        fileId: row.read<int>('file_id'),
        sourceId: row.read<int>('source_id'),
        entryId: row.read<String>('external_entry_id'),
        name: row.read<String>('name'),
        workId: row.read<int>('work_id'),
        metadataSource: row.read<String>('metadata_source'),
        locked: row.read<int>('metadata_locked') == 1,
        metadata: WorkMetadata(
          type: row.readNullable<String>('type') ?? 'movie',
          title: row.read<String>('title'),
          originalTitle: row.readNullable<String>('original_title'),
          overview: row.readNullable<String>('overview'),
          year: row.readNullable<int>('year'),
          posterPath: row.readNullable<String>('poster_path'),
          backdropPath: row.readNullable<String>('backdrop_path'),
          premiered: row.readNullable<DateTime>('premiered'),
          tmdbId: int.tryParse(
            row.readNullable<String>('provider_entity_id')?.split(':').last ??
                '',
          ),
        ),
        episode: season == null
            ? null
            : TmdbEpisode(
                seasonNumber: season,
                episodeNumber: row.read<int>('episode_number'),
                title: row.readNullable<String>('episode_title'),
                overview: row.readNullable<String>('episode_overview'),
                airDate: row.readNullable<DateTime>('air_date'),
                tmdbId: row.readNullable<int>('episode_tmdb_id'),
              ),
      );
    }).toList();
  }

  Future<void> setWorkArtwork(
    int workId, {
    String? poster,
    String? fanart,
  }) async {
    await (db.update(db.works)..where((w) => w.id.equals(workId))).write(
      WorksCompanion(
        posterLocator: poster == null ? const Value.absent() : Value(poster),
        backdropLocator: fanart == null ? const Value.absent() : Value(fanart),
      ),
    );
  }

  Future<void> editMetadata(
    int workId, {
    required String title,
    int? year,
    String? overview,
    String? posterPath,
  }) async {
    final cleanTitle = title.trim();
    if (cleanTitle.isEmpty) {
      throw ArgumentError('Title cannot be empty');
    }

    if (year != null && (year < 1888 || year > 2100)) {
      throw ArgumentError('Year must be between 1888 and 2100');
    }

    final currentWork = await (db.select(
      db.works,
    )..where((w) => w.id.equals(workId))).getSingleOrNull();
    if (currentWork == null) {
      throw ArgumentError('Work with id $workId not found');
    }

    await (db.update(db.works)..where((w) => w.id.equals(workId))).write(
      WorksCompanion(
        title: Value(cleanTitle),
        year: Value(year),
        overview: Value(overview),
        posterPath: Value(posterPath),
        metadataSource: const Value('local'),
        metadataLocked: const Value(true),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  /// 应用剧集分集元数据，仅更新本地已存在的季集行。
  Future<void> applyEpisodeMetadata(
    int workId,
    List<TmdbEpisode> episodes, {
    bool manual = false,
  }) async {
    await db.transaction(() async {
      final work = await (db.select(
        db.works,
      )..where((w) => w.id.equals(workId))).getSingleOrNull();
      if (work == null) return;
      if (work.metadataLocked && !manual) return;

      final existingEpisodes = await (db.select(db.episodes).join([
        innerJoin(db.seasons, db.seasons.id.equalsExp(db.episodes.seasonId)),
      ])..where(db.seasons.seriesId.equals(workId))).get();

      final localEpMap = <String, int>{};
      for (final row in existingEpisodes) {
        final season = row.readTable(db.seasons);
        final ep = row.readTable(db.episodes);
        localEpMap['${season.seasonNumber}:${ep.episodeNumber}'] = ep.id;
      }

      for (final tmdbEp in episodes) {
        final key = '${tmdbEp.seasonNumber}:${tmdbEp.episodeNumber}';
        final epId = localEpMap[key];
        if (epId != null) {
          await (db.update(db.episodes)..where((e) => e.id.equals(epId))).write(
            EpisodesCompanion(
              title: Value(tmdbEp.title),
              overview: Value(tmdbEp.overview),
              airDate: Value(tmdbEp.airDate),
              tmdbId: Value(tmdbEp.tmdbId),
            ),
          );
        }
      }
    });
  }

  // --- 内部迁移辅助方法 ---

  Future<void> _migrateWorkProgress({
    required int fromWorkId,
    required int toWorkId,
  }) async {
    final existingTo =
        await (db.select(db.playbackProgresses)..where(
              (p) => p.targetType.equals('work') & p.targetId.equals(toWorkId),
            ))
            .getSingleOrNull();

    final existingFrom =
        await (db.select(db.playbackProgresses)..where(
              (p) =>
                  p.targetType.equals('work') & p.targetId.equals(fromWorkId),
            ))
            .getSingleOrNull();

    if (existingFrom != null) {
      if (existingTo == null) {
        await (db.update(
          db.playbackProgresses,
        )..where((p) => p.id.equals(existingFrom.id))).write(
          PlaybackProgressesCompanion(
            targetId: Value(toWorkId),
            workId: Value(toWorkId),
          ),
        );
      } else {
        if (existingFrom.updatedAt.isAfter(existingTo.updatedAt)) {
          await (db.delete(
            db.playbackProgresses,
          )..where((p) => p.id.equals(existingTo.id))).go();
          await (db.update(
            db.playbackProgresses,
          )..where((p) => p.id.equals(existingFrom.id))).write(
            PlaybackProgressesCompanion(
              targetId: Value(toWorkId),
              workId: Value(toWorkId),
            ),
          );
        } else {
          await (db.delete(
            db.playbackProgresses,
          )..where((p) => p.id.equals(existingFrom.id))).go();
        }
      }
    }
  }

  Future<void> _migrateWorkProgressToEpisode({
    required int fromWorkId,
    required int toEpisodeId,
  }) async {
    final fromProgress =
        await (db.select(db.playbackProgresses)..where(
              (p) =>
                  p.targetType.equals('work') & p.targetId.equals(fromWorkId),
            ))
            .getSingleOrNull();

    if (fromProgress != null) {
      final toProgress =
          await (db.select(db.playbackProgresses)..where(
                (p) =>
                    p.targetType.equals('episode') &
                    p.targetId.equals(toEpisodeId),
              ))
              .getSingleOrNull();
      if (toProgress == null) {
        await (db.update(
          db.playbackProgresses,
        )..where((p) => p.id.equals(fromProgress.id))).write(
          PlaybackProgressesCompanion(
            targetType: const Value('episode'),
            targetId: Value(toEpisodeId),
            workId: const Value(null),
            episodeId: Value(toEpisodeId),
          ),
        );
      } else {
        // E) 冲突时保留较新 updatedAt 记录，不丢弃来源历史
        if (fromProgress.updatedAt.isAfter(toProgress.updatedAt)) {
          await (db.delete(
            db.playbackProgresses,
          )..where((p) => p.id.equals(toProgress.id))).go();
          await (db.update(
            db.playbackProgresses,
          )..where((p) => p.id.equals(fromProgress.id))).write(
            PlaybackProgressesCompanion(
              targetType: const Value('episode'),
              targetId: Value(toEpisodeId),
              workId: const Value(null),
              episodeId: Value(toEpisodeId),
            ),
          );
        } else {
          await (db.delete(
            db.playbackProgresses,
          )..where((p) => p.id.equals(fromProgress.id))).go();
        }
      }
    }
  }

  Future<void> _migrateEpisodeProgress({
    required int fromEpId,
    required int toEpId,
  }) async {
    final fromProg =
        await (db.select(db.playbackProgresses)..where(
              (p) =>
                  p.targetType.equals('episode') & p.targetId.equals(fromEpId),
            ))
            .getSingleOrNull();

    if (fromProg != null) {
      final toProg =
          await (db.select(db.playbackProgresses)..where(
                (p) =>
                    p.targetType.equals('episode') & p.targetId.equals(toEpId),
              ))
              .getSingleOrNull();

      if (toProg == null) {
        await (db.update(
          db.playbackProgresses,
        )..where((p) => p.id.equals(fromProg.id))).write(
          PlaybackProgressesCompanion(
            targetId: Value(toEpId),
            episodeId: Value(toEpId),
          ),
        );
      } else {
        if (fromProg.updatedAt.isAfter(toProg.updatedAt)) {
          await (db.delete(
            db.playbackProgresses,
          )..where((p) => p.id.equals(toProg.id))).go();
          await (db.update(
            db.playbackProgresses,
          )..where((p) => p.id.equals(fromProg.id))).write(
            PlaybackProgressesCompanion(
              targetId: Value(toEpId),
              episodeId: Value(toEpId),
            ),
          );
        } else {
          await (db.delete(
            db.playbackProgresses,
          )..where((p) => p.id.equals(fromProg.id))).go();
        }
      }
    }
  }

  Future<void> _deleteWorkIfOrphan(int workId) async {
    final hasAssignments = await (db.select(
      db.mediaAssignments,
    )..where((a) => a.workId.equals(workId))).get();
    if (hasAssignments.isNotEmpty) return;

    final hasSeasons = await (db.select(
      db.seasons,
    )..where((s) => s.seriesId.equals(workId))).get();
    if (hasSeasons.isNotEmpty) return;

    await (db.delete(
      db.playbackProgresses,
    )..where((p) => p.workId.equals(workId))).go();
    await (db.delete(db.works)..where((w) => w.id.equals(workId))).go();
  }

  Future<int?> _getWorkIdByExternalId(
    String provider,
    String providerEntityId,
  ) async {
    final row = await db
        .customSelect(
          'SELECT work_id FROM external_ids WHERE provider = ? AND provider_entity_id = ? AND work_id IS NOT NULL',
          variables: [
            Variable.withString(provider),
            Variable.withString(providerEntityId),
          ],
        )
        .getSingleOrNull();
    return row?.readNullable<int>('work_id');
  }

  Future<void> _linkWorkExternalId(
    int workId,
    String provider,
    String providerEntityId,
  ) async {
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    await db.customStatement(
      '''
      INSERT INTO external_ids (work_id, provider, provider_entity_id, created_at)
      VALUES (?, ?, ?, ?)
      ON CONFLICT(provider, provider_entity_id) DO UPDATE SET
        work_id = excluded.work_id,
        created_at = excluded.created_at
      ''',
      [workId, provider, providerEntityId, nowMs],
    );
  }
}
