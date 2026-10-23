import '../../player/domain/playback_resource.dart';
import 'source_models.dart';

/// 媒体源适配器抽象接口
///
/// 封装特定平台或协议（如本地文件系统、Android SAF、WebDAV 等）的媒体源访问差异。
abstract interface class MediaSourceAdapter {
  /// 媒体源类型标识（如 'local'、'androidSaf'）
  String get kind;

  /// 打开系统/协议选择器选择根目录
  ///
  /// 用户取消返回 `null`；发生错误抛出 [MediaSourceException]。
  Future<DirectorySelection?> pickDirectory({String? initialLocator});

  /// 列出指定目录下的直接子条目（单层，不递归）
  ///
  /// 根目录时 [directoryId] 传入 `source.rootLocator`；
  /// 子目录时 [directoryId] 传入子目录 entry 的 `externalId`。
  Stream<MediaEntry> listEntries(MediaSourceConfig source, String directoryId);

  /// 查询特定条目的最新元信息与状态
  Future<MediaStat> stat(MediaSourceConfig source, String entryId);

  /// 将条目解析为播放器可直接播放的 [PlaybackResource]
  Future<PlaybackResource> resolvePlayback(
    MediaSourceConfig source,
    String entryId,
  );
}
