import 'package:path/path.dart' as p;

import '../../../core/logging/app_logger.dart';
import '../../player/domain/playback_resource.dart';
import '../../player/domain/subtitle_files.dart';
import '../domain/media_source_adapter.dart';
import '../domain/source_models.dart';
import '../infrastructure/android_saf_source_adapter.dart';

/// 通过源本身枚举同目录字幕，保留各协议的授权和延迟资源准备链路。
Future<List<PlaybackResource>> discoverSourceSubtitles({
  required MediaSourceConfig source,
  required MediaSourceAdapter adapter,
  required String videoId,
}) async {
  final String? directory;
  if (adapter is AndroidSafSourceAdapter) {
    directory = await adapter.findParentDirectory(source, videoId);
  } else {
    final parent = p.posix.dirname(videoId.replaceAll(r'\', '/'));
    directory = parent == '.' ? source.rootLocator : parent;
  }
  if (directory == null) return [];
  final entries = await adapter
      .listEntries(source, directory)
      .where((entry) => !entry.isDirectory && isSubtitleFile(entry.name))
      .toList();
  final subtitles = <PlaybackResource>[];
  for (final entry in entries) {
    try {
      final resource = await adapter.resolvePlayback(source, entry.externalId);
      subtitles.add(
        resource.copyWith(
          displayName: entry.name,
          fileName: entry.name,
          sourceId: source.id,
        ),
      );
    } catch (error, stackTrace) {
      AppLogger.instance.error('解析源字幕失败', error: error, stackTrace: stackTrace);
    }
  }
  return subtitles;
}
