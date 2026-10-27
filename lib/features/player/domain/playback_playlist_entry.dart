import 'package:flutter/foundation.dart';

/// 播放列表只保存库中文件身份；选集时再解析具体播放资源。
@immutable
class PlaybackPlaylistEntry {
  const PlaybackPlaylistEntry({
    required this.fileId,
    required this.title,
    required this.available,
    this.seasonNumber,
    this.episodeNumber,
  });

  final int fileId;
  final String title;
  final bool available;
  final int? seasonNumber;
  final int? episodeNumber;

  String? get episodeLabel => episodeNumber == null
      ? null
      : '第 ${seasonNumber ?? 1} 季 · 第 $episodeNumber 集';

  String get displayTitle =>
      episodeLabel == null ? title : '$episodeLabel · $title';
}
