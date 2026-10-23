import 'package:flutter/foundation.dart';

/// TMDB 影视条目数据模型（兼作候选条目与详情）
@immutable
class TmdbWork {
  final int id;
  final String type; // 'movie' 或 'series'
  final String title;
  final String? originalTitle;
  final String? overview;
  final String? posterPath;
  final String? backdropPath;
  final int? year;
  final List<String> aliases;

  const TmdbWork({
    required this.id,
    required this.type,
    required this.title,
    this.originalTitle,
    this.overview,
    this.posterPath,
    this.backdropPath,
    this.year,
    this.aliases = const [],
  });

  /// 构造海报完整绝对 URL
  String? posterUrl({String size = 'w500'}) {
    if (posterPath == null || posterPath!.trim().isEmpty) return null;
    final path = posterPath!.startsWith('/') ? posterPath! : '/$posterPath';
    return 'https://image.tmdb.org/t/p/$size$path';
  }

  /// 构造背景图完整绝对 URL
  String? backdropUrl({String size = 'w780'}) {
    if (backdropPath == null || backdropPath!.trim().isEmpty) return null;
    final path = backdropPath!.startsWith('/')
        ? backdropPath!
        : '/$backdropPath';
    return 'https://image.tmdb.org/t/p/$size$path';
  }

  TmdbWork copyWith({
    int? id,
    String? type,
    String? title,
    String? originalTitle,
    String? overview,
    String? posterPath,
    String? backdropPath,
    int? year,
    List<String>? aliases,
  }) {
    return TmdbWork(
      id: id ?? this.id,
      type: type ?? this.type,
      title: title ?? this.title,
      originalTitle: originalTitle ?? this.originalTitle,
      overview: overview ?? this.overview,
      posterPath: posterPath ?? this.posterPath,
      backdropPath: backdropPath ?? this.backdropPath,
      year: year ?? this.year,
      aliases: aliases ?? this.aliases,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'type': type,
      'title': title,
      if (originalTitle != null) 'originalTitle': originalTitle,
      if (overview != null) 'overview': overview,
      if (posterPath != null) 'posterPath': posterPath,
      if (backdropPath != null) 'backdropPath': backdropPath,
      if (year != null) 'year': year,
      if (aliases.isNotEmpty) 'aliases': aliases,
    };
  }

  factory TmdbWork.fromJson(Map<String, dynamic> json, {String? typeOverride}) {
    final rawType =
        typeOverride ??
        (json['type'] as String?) ??
        (json['media_type'] as String?) ??
        (json['title'] != null ? 'movie' : 'series');
    final type = rawType == 'tv' ? 'series' : rawType;

    final title = (json['title'] as String?) ?? (json['name'] as String?) ?? '';

    final originalTitle =
        (json['original_title'] as String?) ??
        (json['original_name'] as String?) ??
        (json['originalTitle'] as String?);

    final dateStr =
        (json['release_date'] as String?) ??
        (json['first_air_date'] as String?) ??
        '';
    int? year = json['year'] as int?;
    if (year == null && dateStr.length >= 4) {
      year = int.tryParse(dateStr.substring(0, 4));
    }

    final rawAliases = json['aliases'];
    List<String> aliases = const [];
    if (rawAliases is List) {
      aliases = rawAliases.map((e) => e.toString()).toList();
    }

    return TmdbWork(
      id: json['id'] as int,
      type: type,
      title: title,
      originalTitle: originalTitle,
      overview: json['overview'] as String?,
      posterPath:
          (json['poster_path'] as String?) ?? (json['posterPath'] as String?),
      backdropPath:
          (json['backdrop_path'] as String?) ??
          (json['backdropPath'] as String?),
      year: year,
      aliases: aliases,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TmdbWork &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          type == other.type;

  @override
  int get hashCode => id.hashCode ^ type.hashCode;

  @override
  String toString() =>
      'TmdbWork(id: $id, type: $type, title: $title, year: $year)';
}

/// TMDB 剧集分集数据模型
@immutable
class TmdbEpisode {
  final int seasonNumber;
  final int episodeNumber;
  final String? title;
  final String? overview;
  final DateTime? airDate;

  const TmdbEpisode({
    required this.seasonNumber,
    required this.episodeNumber,
    this.title,
    this.overview,
    this.airDate,
  });

  TmdbEpisode copyWith({
    int? seasonNumber,
    int? episodeNumber,
    String? title,
    String? overview,
    DateTime? airDate,
  }) {
    return TmdbEpisode(
      seasonNumber: seasonNumber ?? this.seasonNumber,
      episodeNumber: episodeNumber ?? this.episodeNumber,
      title: title ?? this.title,
      overview: overview ?? this.overview,
      airDate: airDate ?? this.airDate,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'seasonNumber': seasonNumber,
      'episodeNumber': episodeNumber,
      if (title != null) 'title': title,
      if (overview != null) 'overview': overview,
      if (airDate != null) 'airDate': airDate!.toIso8601String(),
    };
  }

  factory TmdbEpisode.fromJson(Map<String, dynamic> json) {
    final seasonNumber =
        (json['season_number'] as int?) ?? (json['seasonNumber'] as int?);
    final episodeNumber =
        (json['episode_number'] as int?) ?? (json['episodeNumber'] as int?);
    if (seasonNumber == null || episodeNumber == null) {
      throw const MetadataException(
        'TMDB 分集数据缺少有效的季号或集号',
        code: 'invalid_response',
      );
    }

    DateTime? airDate;
    final airDateStr =
        (json['air_date'] as String?) ?? (json['airDate'] as String?);
    if (airDateStr != null && airDateStr.isNotEmpty) {
      airDate = DateTime.tryParse(airDateStr);
    }

    return TmdbEpisode(
      seasonNumber: seasonNumber,
      episodeNumber: episodeNumber,
      title: (json['name'] as String?) ?? (json['title'] as String?),
      overview: json['overview'] as String?,
      airDate: airDate,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TmdbEpisode &&
          runtimeType == other.runtimeType &&
          seasonNumber == other.seasonNumber &&
          episodeNumber == other.episodeNumber;

  @override
  int get hashCode => seasonNumber.hashCode ^ episodeNumber.hashCode;

  @override
  String toString() => 'TmdbEpisode(S${seasonNumber}E$episodeNumber: $title)';
}

/// 元数据安全异常类
///
/// 严禁在 toString 或 message 中暴露原始 HTTP 报文、Token、API Key 或敏感 URL。
class MetadataException implements Exception {
  final String message;
  final String code;

  const MetadataException(this.message, {this.code = 'unknown'});

  @override
  String toString() => 'MetadataException($code): $message';
}
