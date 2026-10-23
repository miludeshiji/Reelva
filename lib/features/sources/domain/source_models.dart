import 'package:flutter/foundation.dart';

const List<String> defaultVideoExtensions = [
  'mkv',
  'mp4',
  'avi',
  'mov',
  'm4v',
  'ts',
  'webm',
];

const List<String> defaultExcludedDirectories = [
  '.cache',
  r'$RECYCLE.BIN',
  'System Volume Information',
];

@immutable
class MediaSourceConfig {
  const MediaSourceConfig({
    required this.id,
    required this.kind,
    required this.name,
    required this.rootLocator,
    this.enabled = true,
    this.extensions = defaultVideoExtensions,
    this.excludedDirectories = defaultExcludedDirectories,
    this.scanRevision = 0,
    this.lastScanAt,
    this.errorMessage,
  });

  final int id;
  final String kind;
  final String name;
  final String rootLocator;
  final bool enabled;
  final List<String> extensions;
  final List<String> excludedDirectories;
  final int scanRevision;
  final DateTime? lastScanAt;
  final String? errorMessage;

  MediaSourceConfig copyWith({
    int? id,
    String? kind,
    String? name,
    String? rootLocator,
    bool? enabled,
    List<String>? extensions,
    List<String>? excludedDirectories,
    int? scanRevision,
    DateTime? lastScanAt,
    String? errorMessage,
    bool clearErrorMessage = false,
  }) {
    return MediaSourceConfig(
      id: id ?? this.id,
      kind: kind ?? this.kind,
      name: name ?? this.name,
      rootLocator: rootLocator ?? this.rootLocator,
      enabled: enabled ?? this.enabled,
      extensions: extensions ?? this.extensions,
      excludedDirectories: excludedDirectories ?? this.excludedDirectories,
      scanRevision: scanRevision ?? this.scanRevision,
      lastScanAt: lastScanAt ?? this.lastScanAt,
      errorMessage: clearErrorMessage
          ? null
          : (errorMessage ?? this.errorMessage),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MediaSourceConfig &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          kind == other.kind &&
          name == other.name &&
          rootLocator == other.rootLocator &&
          enabled == other.enabled &&
          listEquals(extensions, other.extensions) &&
          listEquals(excludedDirectories, other.excludedDirectories) &&
          scanRevision == other.scanRevision &&
          lastScanAt == other.lastScanAt &&
          errorMessage == other.errorMessage;

  @override
  int get hashCode => Object.hash(
    id,
    kind,
    name,
    rootLocator,
    enabled,
    Object.hashAll(extensions),
    Object.hashAll(excludedDirectories),
    scanRevision,
    lastScanAt,
    errorMessage,
  );

  @override
  String toString() =>
      'MediaSourceConfig(id: $id, kind: $kind, name: $name, rootLocator: $rootLocator, enabled: $enabled, scanRevision: $scanRevision, lastScanAt: $lastScanAt, errorMessage: $errorMessage)';
}

@immutable
class DirectorySelection {
  const DirectorySelection({
    required this.kind,
    required this.rootLocator,
    required this.name,
  });

  final String kind;
  final String rootLocator;
  final String name;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DirectorySelection &&
          runtimeType == other.runtimeType &&
          kind == other.kind &&
          rootLocator == other.rootLocator &&
          name == other.name;

  @override
  int get hashCode => Object.hash(kind, rootLocator, name);

  @override
  String toString() =>
      'DirectorySelection(kind: $kind, rootLocator: $rootLocator, name: $name)';
}

@immutable
class MediaEntry {
  const MediaEntry({
    required this.externalId,
    required this.locator,
    required this.name,
    required this.isDirectory,
    this.size,
    this.modifiedAt,
    this.etag,
  });

  final String externalId;
  final String locator;
  final String name;
  final bool isDirectory;
  final int? size;
  final DateTime? modifiedAt;
  final String? etag;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MediaEntry &&
          runtimeType == other.runtimeType &&
          externalId == other.externalId &&
          locator == other.locator &&
          name == other.name &&
          isDirectory == other.isDirectory &&
          size == other.size &&
          modifiedAt == other.modifiedAt &&
          etag == other.etag;

  @override
  int get hashCode => Object.hash(
    externalId,
    locator,
    name,
    isDirectory,
    size,
    modifiedAt,
    etag,
  );

  @override
  String toString() =>
      'MediaEntry(externalId: $externalId, locator: $locator, name: $name, isDirectory: $isDirectory, size: $size, modifiedAt: $modifiedAt, etag: $etag)';
}

@immutable
class MediaStat {
  const MediaStat({this.size, this.modifiedAt, this.etag});

  final int? size;
  final DateTime? modifiedAt;
  final String? etag;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MediaStat &&
          runtimeType == other.runtimeType &&
          size == other.size &&
          modifiedAt == other.modifiedAt &&
          etag == other.etag;

  @override
  int get hashCode => Object.hash(size, modifiedAt, etag);

  @override
  String toString() =>
      'MediaStat(size: $size, modifiedAt: $modifiedAt, etag: $etag)';
}

@immutable
class LibraryVideo {
  const LibraryVideo({
    required this.fileId,
    required this.sourceId,
    required this.externalId,
    required this.locator,
    required this.title,
    required this.fileName,
    required this.sourceName,
    required this.available,
    this.sourceError,
  });

  final int fileId;
  final int sourceId;
  final String externalId;
  final String locator;
  final String title;
  final String fileName;
  final String sourceName;
  final bool available;
  final String? sourceError;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LibraryVideo &&
          runtimeType == other.runtimeType &&
          fileId == other.fileId &&
          sourceId == other.sourceId &&
          externalId == other.externalId &&
          locator == other.locator &&
          title == other.title &&
          fileName == other.fileName &&
          sourceName == other.sourceName &&
          available == other.available &&
          sourceError == other.sourceError;

  @override
  int get hashCode => Object.hash(
    fileId,
    sourceId,
    externalId,
    locator,
    title,
    fileName,
    sourceName,
    available,
    sourceError,
  );

  @override
  String toString() =>
      'LibraryVideo(fileId: $fileId, sourceId: $sourceId, externalId: $externalId, locator: $locator, title: $title, fileName: $fileName, sourceName: $sourceName, available: $available, sourceError: $sourceError)';
}

class MediaSourceException implements Exception {
  const MediaSourceException(this.message, {this.code});

  final String message;
  final String? code;

  @override
  String toString() => code == null
      ? 'MediaSourceException: $message'
      : 'MediaSourceException($code): $message';
}
