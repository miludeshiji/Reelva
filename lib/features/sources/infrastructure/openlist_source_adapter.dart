import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:path/path.dart' as p;

import '../../player/domain/playback_resource.dart';
import '../domain/media_sidecar_adapter.dart';
import '../domain/openlist_models.dart';
import '../domain/source_models.dart';
import 'openlist_service.dart';
import 'remote_http_client.dart';
import 'remote_playback_bridge.dart';

/// 网盘只读取媒体、字幕及现有目录元数据，不主动上传或覆盖网盘文件。
class OpenListSourceAdapter implements ReadOnlyMediaSidecarAdapter {
  OpenListSourceAdapter({
    required this.service,
    required this.http,
    required this.playback,
  });

  final OpenListService service;
  final RemoteHttpClient http;
  final RemotePlaybackBridge playback;
  final Map<int, Set<String>> _listingTasks = {};

  Future<void> cancelListings(int sourceId) async {
    for (final task in _listingTasks[sourceId]?.toList() ?? <String>[]) {
      await service.cancel(task);
    }
  }

  @override
  String get kind => 'openlist';

  @override
  Future<DirectorySelection?> pickDirectory({String? initialLocator}) async {
    throw const MediaSourceException(
      '请通过网盘登录页面选择目录',
      code: 'remote_configuration_required',
    );
  }

  @override
  Stream<MediaEntry> listEntries(MediaSourceConfig source, String directoryId) {
    final root = OpenListRoot.parse(source.rootLocator);
    final path = root.resolve(directoryId, source.rootLocator);
    final task = service.newTaskId();
    late final StreamController<MediaEntry> controller;
    var cancelled = false;
    controller = StreamController<MediaEntry>(
      onListen: () async {
        (_listingTasks[source.id] ??= {}).add(task);
        try {
          final entries = await service.list(
            root.accountId,
            path,
            refresh: true,
            taskId: task,
          );
          for (final entry in entries) {
            if (cancelled) break;
            if (p.posix.dirname(entry.path) != path) {
              throw const MediaSourceException(
                '网盘返回了目录外的条目',
                code: 'invalid_response',
              );
            }
            final relative = root.relative(entry.path);
            controller.add(
              MediaEntry(
                externalId: relative,
                locator: relative,
                name: entry.name,
                isDirectory: entry.isDirectory,
                size: entry.size,
                modifiedAt: entry.modifiedAt,
              ),
            );
          }
        } catch (error, stack) {
          if (!cancelled) controller.addError(error, stack);
        } finally {
          _listingTasks[source.id]?.remove(task);
          if (_listingTasks[source.id]?.isEmpty ?? false) {
            _listingTasks.remove(source.id);
          }
          if (!cancelled) await controller.close();
        }
      },
      onCancel: () async {
        cancelled = true;
        await service.cancel(task);
      },
    );
    return controller.stream;
  }

  @override
  Future<MediaStat> stat(MediaSourceConfig source, String entryId) async {
    final root = OpenListRoot.parse(source.rootLocator);
    final entry = await service.stat(
      root.accountId,
      root.resolve(entryId, source.rootLocator),
    );
    return MediaStat(size: entry.size, modifiedAt: entry.modifiedAt);
  }

  Future<RemotePlaybackTarget> _target(
    MediaSourceConfig source,
    String entryId, {
    CancelToken? cancelToken,
  }) async {
    final root = OpenListRoot.parse(source.rootLocator);
    final task = service.newTaskId();
    var finished = false;
    unawaited(
      cancelToken?.whenCancel.then<void>((_) async {
        if (!finished) {
          try {
            await service.cancel(task);
          } on MediaSourceException {
            // 播放桥接已停止等待，内核关闭时无需再报告取消错误。
          }
        }
      }),
    );
    final Map<String, dynamic> data;
    try {
      if (cancelToken?.isCancelled ?? false) {
        throw const MediaSourceException('播放准备已取消', code: 'cancelled');
      }
      data = await service.link(
        root.accountId,
        root.resolve(entryId, source.rootLocator),
        taskId: task,
      );
      if (cancelToken?.isCancelled ?? false) {
        throw const MediaSourceException('播放准备已取消', code: 'cancelled');
      }
    } finally {
      finished = true;
    }
    final url = data['url'];
    final uri = url is String ? Uri.tryParse(url) : null;
    if (uri == null ||
        (uri.scheme != 'https' && uri.scheme != 'http') ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty) {
      throw const MediaSourceException('网盘未返回可用下载地址', code: 'invalid_response');
    }
    final rawHeaders = data['headers'];
    final headers = <String, String>{};
    if (rawHeaders is Map) {
      for (final entry in rawHeaders.entries) {
        if (entry.key is! String || entry.value is! String) {
          throw const MediaSourceException(
            '网盘下载请求头无效',
            code: 'invalid_response',
          );
        }
        headers[entry.key as String] = entry.value as String;
      }
    }
    return RemotePlaybackTarget(uri: uri, headers: headers);
  }

  @override
  Future<PlaybackResource> resolvePlayback(
    MediaSourceConfig source,
    String entryId,
  ) async {
    final root = OpenListRoot.parse(source.rootLocator);
    final path = root.resolve(entryId, source.rootLocator);
    return PlaybackResource(
      uri: Uri(scheme: 'openlist', host: root.accountId, path: path),
      displayName: p.posix.basename(path),
      prepare: () => playback.open(
        displayName: p.posix.basename(path),
        resolve: ({required bool refresh, CancelToken? cancelToken}) async {
          if (cancelToken?.isCancelled ?? false) {
            throw const MediaSourceException('播放准备已取消', code: 'cancelled');
          }
          return _target(source, entryId, cancelToken: cancelToken);
        },
      ),
    );
  }

  @override
  Future<String?> parentDirectory(
    MediaSourceConfig source,
    String entryId,
  ) async {
    final root = OpenListRoot.parse(source.rootLocator);
    root.resolve(entryId, source.rootLocator);
    if (entryId == source.rootLocator || entryId.isEmpty) return null;
    final directory = p.posix.dirname(entryId);
    return directory == '.' ? source.rootLocator : directory;
  }

  @override
  Future<Uint8List> readBytes(
    MediaSourceConfig source,
    String entryId, {
    int maxBytes = 2 * 1024 * 1024,
  }) async {
    var target = await _target(source, entryId);
    for (var attempt = 0; ; attempt++) {
      try {
        final response = await http.request(
          target.uri,
          headers: target.headers,
          responseType: ResponseType.stream,
        );
        final body = response.data as ResponseBody;
        return await collectSidecarBytes(body.stream, maxBytes);
      } on MediaSourceException catch (error) {
        if (attempt != 0 ||
            (error.code != 'unauthorized' && error.code != 'forbidden')) {
          rethrow;
        }
        target = await _target(source, entryId);
      }
    }
  }

  @override
  Future<void> writeBytes(
    MediaSourceConfig source,
    String directoryId,
    String name,
    Uint8List bytes, {
    String? expectedEtag,
    bool createOnly = false,
  }) async {
    throw const MediaSourceException(
      '网盘媒体源仅支持读取目录元数据',
      code: 'read_only_source',
    );
  }
}
