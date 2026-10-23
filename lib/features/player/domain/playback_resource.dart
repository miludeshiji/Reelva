import 'package:flutter/foundation.dart';

/// 表示一个可供播放的媒体资源
///
/// 包含资源统一标识符（URI）、展示名称以及请求 HTTP 头。
/// [toString] 绝不输出 URI 及 headers，以防凭据或签名敏感信息泄漏。
@immutable
class PlaybackResource {
  const PlaybackResource({
    required this.uri,
    required this.displayName,
    this.httpHeaders = const {},
    this.libraryFileId,
  });

  final Uri uri;
  final String displayName;
  final Map<String, String> httpHeaders;
  final int? libraryFileId;

  PlaybackResource copyWith({
    Uri? uri,
    String? displayName,
    Map<String, String>? httpHeaders,
    int? Function()? libraryFileId,
  }) {
    return PlaybackResource(
      uri: uri ?? this.uri,
      displayName: displayName ?? this.displayName,
      httpHeaders: httpHeaders ?? this.httpHeaders,
      libraryFileId: libraryFileId != null
          ? libraryFileId()
          : this.libraryFileId,
    );
  }

  @override
  String toString() =>
      'PlaybackResource(displayName: $displayName'
      '${libraryFileId != null ? ', libraryFileId: $libraryFileId' : ''})';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PlaybackResource &&
          runtimeType == other.runtimeType &&
          uri == other.uri &&
          displayName == other.displayName &&
          libraryFileId == other.libraryFileId &&
          mapEquals(httpHeaders, other.httpHeaders);

  @override
  int get hashCode => Object.hash(
    uri,
    displayName,
    libraryFileId,
    Object.hashAll(httpHeaders.entries.map((e) => Object.hash(e.key, e.value))),
  );
}
