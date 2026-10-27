import 'package:flutter/foundation.dart';

import 'playback_playlist_entry.dart';

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
    this.prepare,
    this.release,
    this.errors,
    this.sourceId,
    this.discoverSubtitles,
    this.playlist = const [],
  });

  final Uri uri;
  final String displayName;
  final Map<String, String> httpHeaders;
  final int? libraryFileId;
  final int? sourceId;
  final List<PlaybackPlaylistEntry> playlist;

  /// 按需枚举源目录中的外挂字幕，不随视频准备过程分配字幕租约。
  final Future<List<PlaybackResource>> Function()? discoverSubtitles;

  /// 延迟准备具体播放资源租约的回调
  ///
  /// 允许媒体源适配器返回轻量级逻辑描述符，在引擎真正起播/重试时按需分配底层中继或服务。
  final Future<PlaybackResource> Function()? prepare;

  /// 释放具体播放资源租约的回调
  final Future<void> Function()? release;

  /// 播放期间底层的错误通知流（使用安全的展示文本）
  final Stream<String>? errors;

  PlaybackResource copyWith({
    Uri? uri,
    String? displayName,
    Map<String, String>? httpHeaders,
    int? Function()? libraryFileId,
    Future<PlaybackResource> Function()? prepare,
    Future<void> Function()? release,
    Stream<String>? errors,
    int? sourceId,
    Future<List<PlaybackResource>> Function()? discoverSubtitles,
    List<PlaybackPlaylistEntry>? playlist,
  }) {
    return PlaybackResource(
      uri: uri ?? this.uri,
      displayName: displayName ?? this.displayName,
      httpHeaders: httpHeaders ?? this.httpHeaders,
      libraryFileId: libraryFileId != null
          ? libraryFileId()
          : this.libraryFileId,
      prepare: prepare ?? this.prepare,
      release: release ?? this.release,
      errors: errors ?? this.errors,
      sourceId: sourceId ?? this.sourceId,
      discoverSubtitles: discoverSubtitles ?? this.discoverSubtitles,
      playlist: playlist ?? this.playlist,
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
          sourceId == other.sourceId &&
          listEquals(playlist, other.playlist) &&
          discoverSubtitles == other.discoverSubtitles &&
          prepare == other.prepare &&
          release == other.release &&
          errors == other.errors &&
          mapEquals(httpHeaders, other.httpHeaders);

  @override
  int get hashCode => Object.hash(
    uri,
    displayName,
    libraryFileId,
    sourceId,
    Object.hashAll(playlist),
    discoverSubtitles,
    prepare,
    release,
    errors,
    Object.hashAll(httpHeaders.entries.map((e) => Object.hash(e.key, e.value))),
  );
}

/// 播放资源领域异常
///
/// 用于在资源准备、流媒体解析或连接中断时向播放器引擎暴露安全的错误信息。
@immutable
class PlaybackResourceException implements Exception {
  const PlaybackResourceException(this.message, {this.code});

  final String message;
  final String? code;

  @override
  String toString() => code == null
      ? 'PlaybackResourceException: $message'
      : 'PlaybackResourceException($code): $message';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PlaybackResourceException &&
          runtimeType == other.runtimeType &&
          message == other.message &&
          code == other.code;

  @override
  int get hashCode => Object.hash(message, code);
}
