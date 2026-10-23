import 'dart:convert';

import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../sources/domain/source_models.dart';

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
        await (db.update(
          db.mediaSources,
        )..where((s) => s.id.equals(existing.id))).write(
          MediaSourcesCompanion(
            name: Value(name),
            enabled: const Value(true),
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

  Future<void> renameSource(int id, String name) async {
    await (db.update(db.mediaSources)..where((s) => s.id.equals(id))).write(
      MediaSourcesCompanion(name: Value(name)),
    );
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
        db.works,
        db.works.id.equalsExp(db.mediaAssignments.workId),
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
        db.works,
        db.works.id.equalsExp(db.mediaAssignments.workId),
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
}
