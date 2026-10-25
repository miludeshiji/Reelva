import 'media_filename_parser.dart';
import 'tmdb_models.dart';

/// 本次匹配的文件及其目录上下文，不扩大到同作品的其他文件。
class MatchingFile {
  const MatchingFile({
    required this.fileId,
    required this.name,
    this.directoryNames = const [],
    this.seasonNumber,
    this.episodeNumber,
  });

  final int fileId;
  final String name;
  final List<String> directoryNames;
  final int? seasonNumber;
  final int? episodeNumber;

  ParsedMediaFilename get parsed =>
      MediaFilenameParser.parse(name, directoryNames: directoryNames);

  ({int? season, int? episode}) get seriesNumbers {
    final parsedName = parsed;
    final numericMatch = RegExp(r'^(\d{1,3})\.[^./\\]+$').firstMatch(name);
    final number = int.tryParse(numericMatch?.group(1) ?? '');
    final numericEpisode = number != null && number > 0 ? number : null;
    final directorySeason = directoryNames.reversed
        .map(MediaFilenameParser.seasonFromName)
        .whereType<int>()
        .firstOrNull;
    return (
      season: numericEpisode != null
          ? directorySeason ?? seasonNumber ?? 1
          : parsedName.seasonNumber ?? seasonNumber,
      episode: parsedName.episodeNumber ?? episodeNumber ?? numericEpisode,
    );
  }
}

class PreparedFileMatch {
  const PreparedFileMatch({
    required this.file,
    this.seasonNumber,
    this.episodeNumber,
    this.episode,
    this.error,
  });

  final MatchingFile file;
  final int? seasonNumber;
  final int? episodeNumber;
  final TmdbEpisode? episode;
  final String? error;
}
