import 'package:flutter/foundation.dart';

@immutable
class LibraryFileMatch {
  const LibraryFileMatch({
    required this.title,
    this.year,
    this.seasonNumber,
    this.episodeNumber,
    this.episodeTitle,
  });

  final String title;
  final int? year;
  final int? seasonNumber;
  final int? episodeNumber;
  final String? episodeTitle;
}

/// 媒体作品领域模型（电影或剧集）
@immutable
class LibraryWork {
  const LibraryWork({
    required this.id,
    this.type,
    required this.title,
    this.originalTitle,
    this.year,
    this.overview,
    this.posterPath,
    this.tmdbPosterPath,
    this.backdropPath,
    this.metadataSource = 'local',
    this.metadataLocked = false,
    this.versionCount = 0,
    this.available = true,
  });

  final int id;
  final String? type; // 'movie' 或 'series'，未确定时为 null
  final String title;
  final String? originalTitle;
  final int? year;
  final String? overview;
  final String? posterPath;
  final String? tmdbPosterPath;
  final String? backdropPath;
  final String metadataSource; // 'local'、'tmdb' 或 'nfo'
  final bool metadataLocked;
  final int versionCount;
  final bool available;

  LibraryWork copyWith({
    int? id,
    String? type,
    String? title,
    String? originalTitle,
    int? year,
    String? overview,
    String? posterPath,
    String? tmdbPosterPath,
    String? backdropPath,
    String? metadataSource,
    bool? metadataLocked,
    int? versionCount,
    bool? available,
  }) {
    return LibraryWork(
      id: id ?? this.id,
      type: type ?? this.type,
      title: title ?? this.title,
      originalTitle: originalTitle ?? this.originalTitle,
      year: year ?? this.year,
      overview: overview ?? this.overview,
      posterPath: posterPath ?? this.posterPath,
      tmdbPosterPath: tmdbPosterPath ?? this.tmdbPosterPath,
      backdropPath: backdropPath ?? this.backdropPath,
      metadataSource: metadataSource ?? this.metadataSource,
      metadataLocked: metadataLocked ?? this.metadataLocked,
      versionCount: versionCount ?? this.versionCount,
      available: available ?? this.available,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LibraryWork &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          type == other.type &&
          title == other.title &&
          originalTitle == other.originalTitle &&
          year == other.year &&
          overview == other.overview &&
          posterPath == other.posterPath &&
          tmdbPosterPath == other.tmdbPosterPath &&
          backdropPath == other.backdropPath &&
          metadataSource == other.metadataSource &&
          metadataLocked == other.metadataLocked &&
          versionCount == other.versionCount &&
          available == other.available;

  @override
  int get hashCode => Object.hash(
    id,
    type,
    title,
    originalTitle,
    year,
    overview,
    posterPath,
    tmdbPosterPath,
    backdropPath,
    metadataSource,
    metadataLocked,
    versionCount,
    available,
  );

  @override
  String toString() =>
      'LibraryWork(id: $id, type: $type, title: $title, year: $year, locked: $metadataLocked, versions: $versionCount, available: $available)';
}

/// 作品关联的具体文件版本或剧集单集版本
@immutable
class LibraryVersion {
  const LibraryVersion({
    required this.fileId,
    required this.fileName,
    required this.sourceName,
    required this.available,
    this.editionLabel,
    this.sourceError,
    this.episodeTitle,
    this.seasonNumber,
    this.episodeNumber,
  });

  final int fileId;
  final String fileName;
  final String sourceName;
  final bool available;
  final String? editionLabel;
  final String? sourceError;
  final String? episodeTitle;
  final int? seasonNumber;
  final int? episodeNumber;

  LibraryVersion copyWith({
    int? fileId,
    String? fileName,
    String? sourceName,
    bool? available,
    String? editionLabel,
    String? sourceError,
    String? episodeTitle,
    int? seasonNumber,
    int? episodeNumber,
  }) {
    return LibraryVersion(
      fileId: fileId ?? this.fileId,
      fileName: fileName ?? this.fileName,
      sourceName: sourceName ?? this.sourceName,
      available: available ?? this.available,
      editionLabel: editionLabel ?? this.editionLabel,
      sourceError: sourceError ?? this.sourceError,
      episodeTitle: episodeTitle ?? this.episodeTitle,
      seasonNumber: seasonNumber ?? this.seasonNumber,
      episodeNumber: episodeNumber ?? this.episodeNumber,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LibraryVersion &&
          runtimeType == other.runtimeType &&
          fileId == other.fileId &&
          fileName == other.fileName &&
          sourceName == other.sourceName &&
          available == other.available &&
          editionLabel == other.editionLabel &&
          sourceError == other.sourceError &&
          episodeTitle == other.episodeTitle &&
          seasonNumber == other.seasonNumber &&
          episodeNumber == other.episodeNumber;

  @override
  int get hashCode => Object.hash(
    fileId,
    fileName,
    sourceName,
    available,
    editionLabel,
    sourceError,
    episodeTitle,
    seasonNumber,
    episodeNumber,
  );

  @override
  String toString() =>
      'LibraryVersion(fileId: $fileId, fileName: $fileName, sourceName: $sourceName, s: $seasonNumber, e: $episodeNumber, edition: $editionLabel, available: $available)';
}

/// 作品及其所有可用版本的详情聚合模型
@immutable
class WorkDetails {
  const WorkDetails({required this.work, required this.versions});

  final LibraryWork work;
  final List<LibraryVersion> versions;

  int get episodeCount => versions
      .where((version) => version.episodeNumber != null)
      .map((version) => (version.seasonNumber ?? 1, version.episodeNumber!))
      .toSet()
      .length;

  WorkDetails copyWith({LibraryWork? work, List<LibraryVersion>? versions}) {
    return WorkDetails(
      work: work ?? this.work,
      versions: versions ?? this.versions,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is WorkDetails &&
          runtimeType == other.runtimeType &&
          work == other.work &&
          listEquals(versions, other.versions);

  @override
  int get hashCode => Object.hash(work, Object.hashAll(versions));

  @override
  String toString() => 'WorkDetails(work: $work, versions: ${versions.length})';
}
