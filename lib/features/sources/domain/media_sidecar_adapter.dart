import 'dart:typed_data';

import 'source_models.dart';
import 'media_source_adapter.dart';

/// 随媒体目录保存的 NFO 和图片，共用源的授权与根目录边界。
abstract interface class MediaSidecarAdapter implements MediaSourceAdapter {
  Future<String?> parentDirectory(MediaSourceConfig source, String entryId);

  Future<Uint8List> readBytes(
    MediaSourceConfig source,
    String entryId, {
    int maxBytes = 2 * 1024 * 1024,
  });

  Future<void> writeBytes(
    MediaSourceConfig source,
    String directoryId,
    String name,
    Uint8List bytes, {
    String? expectedEtag,
    bool createOnly = false,
  });
}

/// 能读取已有 NFO 和图片，但不自动写回目录。
abstract interface class ReadOnlyMediaSidecarAdapter
    implements MediaSidecarAdapter {}

void validateSidecarName(String name) {
  if (name.isEmpty ||
      name == '.' ||
      name == '..' ||
      name.contains('/') ||
      name.contains(r'\') ||
      name.contains('\u0000')) {
    throw const MediaSourceException('元数据文件名称无效', code: 'invalid_name');
  }
}

Future<Uint8List> collectSidecarBytes(
  Stream<List<int>> stream,
  int maxBytes,
) async {
  final bytes = BytesBuilder(copy: false);
  await for (final chunk in stream) {
    if (bytes.length + chunk.length > maxBytes) {
      throw const MediaSourceException('元数据文件过大', code: 'file_too_large');
    }
    bytes.add(chunk);
  }
  return bytes.takeBytes();
}
