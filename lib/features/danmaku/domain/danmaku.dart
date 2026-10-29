import '../../metadata/domain/media_filename_parser.dart';
import '../../player/domain/playback_resource.dart';

enum DanmakuSource {
  dandanplay('弹弹play'),
  bilibili('哔哩哔哩');

  const DanmakuSource(this.label);
  final String label;
}

class DanmakuComment {
  const DanmakuComment({
    required this.timeMs,
    required this.text,
    this.mode = 1,
    this.color = 0xffffff,
    this.bilibili = false,
  });

  final int timeMs;
  final String text;
  final int mode;
  final int color;
  final bool bilibili;
}

class DanmakuShow {
  const DanmakuShow({
    required this.source,
    required this.id,
    required this.title,
    this.year,
    this.tmdbMatched = false,
  });

  final DanmakuSource source;
  final String id;
  final String title;
  final int? year;
  final bool tmdbMatched;
}

class DanmakuEpisode {
  const DanmakuEpisode({
    required this.source,
    required this.id,
    required this.title,
    required this.episodeTitle,
    this.number,
    this.shiftSeconds = 0,
  });

  final DanmakuSource source;
  final String id;
  final String title;
  final String episodeTitle;
  final int? number;
  final double shiftSeconds;

  String get cacheKey => '${source.name}:$id';
  String get label => '$title · $episodeTitle';

  Map<String, Object?> toJson() => {
    'source': source.name,
    'id': id,
    'title': title,
    'episodeTitle': episodeTitle,
    'number': number,
    'shiftSeconds': shiftSeconds,
  };

  factory DanmakuEpisode.fromJson(Map<String, dynamic> json) => DanmakuEpisode(
    source: DanmakuSource.values.byName(json['source'] as String),
    id: json['id'] as String,
    title: json['title'] as String,
    episodeTitle: json['episodeTitle'] as String,
    number: json['number'] as int?,
    shiftSeconds: (json['shiftSeconds'] as num?)?.toDouble() ?? 0,
  );
}

class DanmakuQuery {
  const DanmakuQuery({
    required this.title,
    required this.fileName,
    required this.contentKey,
    required this.versionKey,
    this.originalTitle,
    this.year,
    this.season,
    this.episode,
    this.tmdbId,
    this.movie = false,
    this.localPath,
    this.duration = Duration.zero,
    this.ambiguous = false,
  });

  factory DanmakuQuery.fromResource(PlaybackResource resource) {
    final parsed = MediaFilenameParser.parse(resource.fileName);
    final key = resource.libraryFileId == null
        ? resource.uri.replace(query: '', fragment: '').toString()
        : 'file:${resource.libraryFileId}';
    return DanmakuQuery(
      title: parsed.title,
      originalTitle: parsed.secondaryTitle,
      fileName: resource.fileName,
      contentKey: key,
      versionKey: key,
      year: parsed.year,
      season: parsed.seasonNumber,
      episode: parsed.episodeNumber,
      movie: parsed.type == 'movie',
      localPath: resource.uri.scheme == 'file'
          ? resource.uri.toFilePath()
          : null,
      ambiguous: parsed.isAmbiguous || parsed.isMultiEpisode || parsed.isExtra,
    );
  }

  final String title;
  final String? originalTitle;
  final String fileName;
  final String contentKey;
  final String versionKey;
  final int? year;
  final int? season;
  final int? episode;
  final int? tmdbId;
  final bool movie;
  final String? localPath;
  final Duration duration;
  final bool ambiguous;
}

class DanmakuSettings {
  const DanmakuSettings({
    this.enabled = false,
    this.fontSize = 24,
    this.opacity = 0.85,
    this.area = 0.5,
    this.duration = 8,
    this.density = 30,
    this.showTop = true,
    this.showBottom = true,
    this.showBilibili = true,
    this.showOther = true,
  });

  final bool enabled;
  final double fontSize;
  final double opacity;
  final double area;
  final double duration;
  final int density;
  final bool showTop;
  final bool showBottom;
  final bool showBilibili;
  final bool showOther;

  DanmakuSettings copyWith({
    bool? enabled,
    double? fontSize,
    double? opacity,
    double? area,
    double? duration,
    int? density,
    bool? showTop,
    bool? showBottom,
    bool? showBilibili,
    bool? showOther,
  }) => DanmakuSettings(
    enabled: enabled ?? this.enabled,
    fontSize: fontSize ?? this.fontSize,
    opacity: opacity ?? this.opacity,
    area: area ?? this.area,
    duration: duration ?? this.duration,
    density: density ?? this.density,
    showTop: showTop ?? this.showTop,
    showBottom: showBottom ?? this.showBottom,
    showBilibili: showBilibili ?? this.showBilibili,
    showOther: showOther ?? this.showOther,
  );

  Map<String, Object> toJson() => {
    'enabled': enabled,
    'fontSize': fontSize,
    'opacity': opacity,
    'area': area,
    'duration': duration,
    'density': density,
    'showTop': showTop,
    'showBottom': showBottom,
    'showBilibili': showBilibili,
    'showOther': showOther,
  };

  factory DanmakuSettings.fromJson(Map<String, dynamic> json) =>
      DanmakuSettings(
        enabled: json['enabled'] as bool? ?? false,
        fontSize: ((json['fontSize'] as num?)?.toDouble() ?? 24).clamp(12, 48),
        opacity: ((json['opacity'] as num?)?.toDouble() ?? 0.85).clamp(0.1, 1),
        area: ((json['area'] as num?)?.toDouble() ?? 0.5).clamp(0.25, 1),
        duration: ((json['duration'] as num?)?.toDouble() ?? 8).clamp(4, 16),
        density: ((json['density'] as num?)?.toInt() ?? 30).clamp(5, 60),
        showTop: json['showTop'] as bool? ?? true,
        showBottom: json['showBottom'] as bool? ?? true,
        showBilibili: json['showBilibili'] as bool? ?? true,
        showOther: json['showOther'] as bool? ?? true,
      );
}

String normalizeDanmakuTitle(String value) => value.toLowerCase().replaceAll(
  RegExp(r'[\s\p{P}\p{S}]+', unicode: true),
  '',
);

int? danmakuEpisodeNumber(String title) {
  final match = RegExp(r'^(?:第\s*)?(\d+)(?:\s*[话話集]|(?:\s|$))')
      .firstMatch(title.trim());
  return match == null ? null : int.tryParse(match[1]!);
}

(String, int) _showSeason(String title) {
  final match = RegExp(
    r'\s*(?:第\s*([0-9一二三四五六七八九十两]+)\s*[季期]|season\s*(\d+)|(\d+)(?:st|nd|rd|th)\s+season)\s*$',
    caseSensitive: false,
  ).firstMatch(title);
  if (match == null) return (title, 1);
  final number = match[1] ?? match[2] ?? match[3]!;
  var season = int.tryParse(number);
  if (season == null) {
    const digits = {
      '一': 1,
      '二': 2,
      '两': 2,
      '三': 3,
      '四': 4,
      '五': 5,
      '六': 6,
      '七': 7,
      '八': 8,
      '九': 9,
    };
    final parts = number.split('十');
    season = parts.length == 2
        ? (digits[parts[0]] ?? 1) * 10 + (digits[parts[1]] ?? 0)
        : digits[number];
  }
  return (title.substring(0, match.start).trim(), season ?? 1);
}

/// TMDB 的一部电视剧可能关联多个季度；季号和集号均明确才自动挂载。
DanmakuEpisode? matchDanmakuEpisode(
  DanmakuQuery query,
  DanmakuShow show,
  List<DanmakuEpisode> episodes,
) {
  if (query.ambiguous) return null;
  final (showTitle, season) = _showSeason(show.title);
  if (query.season == 0 || (query.season != null && query.season != season)) {
    return null;
  }
  final title = normalizeDanmakuTitle(showTitle);
  final titleMatches = [
    query.title,
    query.originalTitle,
  ].whereType<String>().any((value) => normalizeDanmakuTitle(value) == title);
  if (!show.tmdbMatched && !titleMatches) return null;
  if (query.movie) {
    if (query.year != null && show.year == null && !show.tmdbMatched) {
      return null;
    }
    if (query.year != null && show.year != null && query.year != show.year) {
      return null;
    }
    return episodes.length == 1 ? episodes.single : null;
  }
  if (query.episode == null) return null;
  final matches = episodes
      .where((episode) => episode.number == query.episode)
      .toList();
  return matches.length == 1 ? matches.single : null;
}
