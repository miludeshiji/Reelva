import 'package:flutter/services.dart';

import '../../../core/logging/app_logger.dart';
import '../../player/domain/playback_resource.dart';
import '../domain/media_source_adapter.dart';
import '../domain/media_sidecar_adapter.dart';
import '../domain/source_models.dart';

/// Android Storage Access Framework (SAF) 媒体源适配器
///
/// 封装 Android 原生 SAF 文档树目录访问：
/// - 通过 ACTION_OPEN_DOCUMENT_TREE 获取用户指定目录授权并持久化读权限；
/// - listEntries 支持原生后台线程分页遍历；
/// - stat 查询文件元数据（大小、修改时间等）；
/// - resolvePlayback 返回可以直接通过原生文件描述符只读打开的 content:// PlaybackResource，
///   避免全文件复制；
/// - 枚举错误或权限撤销时不静默吞没为空列表，抛出安全的 [MediaSourceException]。
class AndroidSafSourceAdapter
    implements MediaSourceAdapter, MediaSidecarAdapter {
  const AndroidSafSourceAdapter({
    this.channel = const MethodChannel('reelva/media_documents'),
    this.pageSize = 100,
  });

  final MethodChannel channel;
  final int pageSize;

  @override
  String get kind => 'androidSaf';

  /// 同步索引只保存相对路径，使用文件时仅定位该路径，不扫描整棵树。
  Future<String> _resolveIndexedPath(
    MediaSourceConfig source,
    String locator,
  ) async {
    final uri = Uri.tryParse(locator);
    if (uri?.scheme != 'reelva-index') return locator;
    final parts = locator
        .substring(locator.indexOf(':') + 1)
        .split('/')
        .map(Uri.decodeComponent)
        .toList();
    if (uri!.hasAuthority ||
        uri.hasQuery ||
        uri.hasFragment ||
        parts.any(
          (s) =>
              s.isEmpty ||
              s == '.' ||
              s == '..' ||
              s.contains('/') ||
              s.contains(r'\') ||
              s.contains('\u0000'),
        )) {
      throw const MediaSourceException('索引路径无效', code: 'INVALID_ARGUMENT');
    }
    var directory = source.rootLocator;
    for (var i = 0; i < parts.length; i++) {
      MediaEntry? found;
      await for (final entry in listEntries(source, directory)) {
        if (entry.name == parts[i] &&
            (i == parts.length - 1 || entry.isDirectory)) {
          found = entry;
          break;
        }
      }
      if (found == null) {
        throw const MediaSourceException(
          '索引中的文件已不存在，请手动刷新媒体源',
          code: 'NOT_FOUND',
        );
      }
      directory = found.externalId;
    }
    return directory;
  }

  /// 文档 ID 不一定是路径，优先询问 provider；不支持路径查询时遍历授权树。
  Future<String?> findParentDirectory(
    MediaSourceConfig source,
    String documentId,
  ) async {
    final indexed = Uri.tryParse(documentId);
    if (indexed?.scheme == 'reelva-index') {
      final parts = indexed!.pathSegments;
      return parts.length <= 1
          ? source.rootLocator
          : Uri(
              scheme: 'reelva-index',
              pathSegments: parts.take(parts.length - 1),
            ).toString();
    }
    try {
      final parent = await channel.invokeMethod<String>('parentDocument', {
        'treeUri': source.rootLocator,
        'documentUri': documentId,
      });
      if (parent != null) return parent;
    } on PlatformException catch (e) {
      throw _mapPlatformException(e, defaultMessage: '读取字幕所在目录失败');
    }
    final directories = [source.rootLocator];
    final visited = <String>{};
    for (var index = 0; index < directories.length; index++) {
      final directory = directories[index];
      if (!visited.add(directory)) continue;
      await for (final entry in listEntries(source, directory)) {
        if (entry.externalId == documentId) return directory;
        if (entry.isDirectory) directories.add(entry.externalId);
      }
    }
    return null;
  }

  @override
  Future<DirectorySelection?> pickDirectory({String? initialLocator}) async {
    try {
      final arguments = <String, dynamic>{};
      if (initialLocator != null) {
        arguments['initialLocator'] = initialLocator;
      }
      final result = await channel.invokeMapMethod<String, dynamic>(
        'pickDirectory',
        arguments,
      );

      if (result == null) {
        return null;
      }

      final rootLocator = result['rootLocator'] as String?;
      final name = result['name'] as String?;

      if (rootLocator == null || rootLocator.isEmpty) {
        throw const MediaSourceException('未获取到有效的媒体源目录', code: 'INVALID_ROOT');
      }

      return DirectorySelection(
        kind: kind,
        rootLocator: rootLocator,
        name: name?.isNotEmpty == true ? name! : 'SAF 媒体源',
      );
    } on PlatformException catch (e, st) {
      AppLogger.instance.error(
        'SAF pickDirectory 平台错误 [code=${e.code}]: ${e.message}',
        error: e,
        stackTrace: st,
      );
      throw _mapPlatformException(e, defaultMessage: '选择媒体源目录失败');
    } catch (e, st) {
      if (e is MediaSourceException) rethrow;
      AppLogger.instance.error(
        'SAF pickDirectory 异常',
        error: e,
        stackTrace: st,
      );
      throw MediaSourceException('选择媒体源目录失败: $e');
    }
  }

  @override
  Stream<MediaEntry> listEntries(
    MediaSourceConfig source,
    String directoryId,
  ) async* {
    directoryId = await _resolveIndexedPath(source, directoryId);
    final treeUri = source.rootLocator;
    if (!treeUri.startsWith('content://')) {
      throw const MediaSourceException(
        '无效的 SAF 媒体源定位符',
        code: 'INVALID_LOCATOR',
      );
    }

    final parentUri = (directoryId.isEmpty || directoryId == treeUri)
        ? null
        : directoryId;

    int offset = 0;
    bool hasMore = true;

    while (hasMore) {
      Map<dynamic, dynamic>? response;
      try {
        final arguments = <String, dynamic>{
          'treeUri': treeUri,
          'offset': offset,
          'limit': pageSize,
        };
        if (parentUri != null) {
          arguments['parentUri'] = parentUri;
        }
        response = await channel.invokeMethod<Map<dynamic, dynamic>>(
          'listChildren',
          arguments,
        );
      } on PlatformException catch (e, st) {
        AppLogger.instance.error(
          'SAF listChildren 平台错误 [code=${e.code}]: ${e.message}',
          error: e,
          stackTrace: st,
        );
        throw _mapPlatformException(e, defaultMessage: '读取媒体源目录失败');
      } catch (e, st) {
        if (e is MediaSourceException) rethrow;
        AppLogger.instance.error(
          'SAF listChildren 异常',
          error: e,
          stackTrace: st,
        );
        throw MediaSourceException('读取媒体源目录失败: $e');
      }

      if (response == null) {
        throw const MediaSourceException('读取媒体源目录失败: 原生响应为空', code: 'IO_ERROR');
      }

      final rawEntries = response['entries'] as List<dynamic>?;
      if (rawEntries == null) {
        throw const MediaSourceException(
          '读取媒体源目录失败: 原生未返回条目列表',
          code: 'IO_ERROR',
        );
      }

      for (final raw in rawEntries) {
        if (raw is! Map) continue;
        final entryMap = raw.cast<String, dynamic>();
        final externalId = entryMap['externalId'] as String?;
        final locator = entryMap['locator'] as String?;
        final name = entryMap['name'] as String?;
        final isDirectory = entryMap['isDirectory'] as bool? ?? false;
        final size = entryMap['size'] as int?;
        final modifiedAtMillis = entryMap['modifiedAt'] as int?;
        final modifiedAt = modifiedAtMillis != null
            ? DateTime.fromMillisecondsSinceEpoch(modifiedAtMillis, isUtc: true)
            : null;

        if (externalId == null || locator == null || name == null) {
          continue;
        }

        yield MediaEntry(
          externalId: externalId,
          locator: locator,
          name: name,
          isDirectory: isDirectory,
          size: size,
          modifiedAt: modifiedAt,
        );
      }

      hasMore = response['hasMore'] as bool? ?? false;
      offset += rawEntries.length;

      // 防止异常情况下死循环
      if (rawEntries.isEmpty) {
        break;
      }
    }
  }

  @override
  Future<MediaStat> stat(MediaSourceConfig source, String entryId) async {
    entryId = await _resolveIndexedPath(source, entryId);
    try {
      final response = await channel.invokeMethod<Map<dynamic, dynamic>>(
        'statDocument',
        <String, dynamic>{'uri': entryId},
      );

      if (response == null) {
        throw const MediaSourceException('媒体文件或目录不存在', code: 'NOT_FOUND');
      }

      final size = response['size'] as int?;
      final modifiedAtMillis = response['modifiedAt'] as int?;
      final modifiedAt = modifiedAtMillis != null
          ? DateTime.fromMillisecondsSinceEpoch(modifiedAtMillis, isUtc: true)
          : null;

      return MediaStat(size: size, modifiedAt: modifiedAt);
    } on PlatformException catch (e, st) {
      AppLogger.instance.error(
        'SAF statDocument 平台错误 [code=${e.code}]: ${e.message}',
        error: e,
        stackTrace: st,
      );
      throw _mapPlatformException(e, defaultMessage: '查询条目状态失败');
    } catch (e, st) {
      if (e is MediaSourceException) rethrow;
      AppLogger.instance.error('SAF statDocument 异常', error: e, stackTrace: st);
      throw MediaSourceException('查询条目状态失败: $e');
    }
  }

  @override
  Future<String?> parentDirectory(MediaSourceConfig source, String entryId) =>
      findParentDirectory(source, entryId);

  @override
  Future<Uint8List> readBytes(
    MediaSourceConfig source,
    String entryId, {
    int maxBytes = 2 * 1024 * 1024,
  }) async {
    entryId = await _resolveIndexedPath(source, entryId);
    try {
      final bytes = await channel.invokeMethod<Uint8List>('readSidecar', {
        'treeUri': source.rootLocator,
        'uri': entryId,
        'maxBytes': maxBytes,
      });
      if (bytes == null) throw const MediaSourceException('读取元数据文件失败');
      return bytes;
    } on PlatformException catch (e) {
      throw _mapPlatformException(e, defaultMessage: '读取元数据文件失败');
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
    validateSidecarName(name);
    directoryId = await _resolveIndexedPath(source, directoryId);
    try {
      await channel.invokeMethod<void>('writeSidecar', {
        'treeUri': source.rootLocator,
        'directoryUri': directoryId,
        'name': name,
        'bytes': bytes,
        'createOnly': createOnly,
      });
    } on PlatformException catch (e) {
      throw _mapPlatformException(e, defaultMessage: '保存元数据文件失败，请检查目录写入权限');
    }
  }

  @override
  Future<PlaybackResource> resolvePlayback(
    MediaSourceConfig source,
    String entryId,
  ) async {
    entryId = await _resolveIndexedPath(source, entryId);
    final uri = Uri.tryParse(entryId);
    if (uri == null ||
        !uri.hasScheme ||
        uri.scheme.toLowerCase() != 'content') {
      throw const MediaSourceException('无效的媒体文件定位符', code: 'INVALID_URI');
    }

    String displayName = '视频';
    try {
      final response = await channel.invokeMethod<Map<dynamic, dynamic>>(
        'statDocument',
        <String, dynamic>{'uri': entryId},
      );
      if (response != null) {
        final name = response['name'] as String?;
        if (name != null && name.isNotEmpty) {
          displayName = name;
        }
      }
    } on PlatformException catch (e, st) {
      AppLogger.instance.error(
        'SAF resolvePlayback statDocument 平台错误 [code=${e.code}]: ${e.message}',
        error: e,
        stackTrace: st,
      );
      throw _mapPlatformException(e, defaultMessage: '解析媒体资源播放失败');
    } catch (e, st) {
      if (e is MediaSourceException) rethrow;
      AppLogger.instance.error(
        'SAF resolvePlayback 异常',
        error: e,
        stackTrace: st,
      );
      throw MediaSourceException('解析媒体资源播放失败: $e');
    }

    return PlaybackResource(uri: uri, displayName: displayName);
  }

  /// 检查媒体源目录是否仍具备持久权限
  Future<bool> checkPermission(String uri) async {
    try {
      final granted = await channel.invokeMethod<bool>(
        'checkPermission',
        <String, dynamic>{'uri': uri},
      );
      return granted ?? false;
    } catch (e, st) {
      AppLogger.instance.error('检查 SAF 权限状态失败: $uri', error: e, stackTrace: st);
      return false;
    }
  }

  static MediaSourceException _mapPlatformException(
    PlatformException e, {
    required String defaultMessage,
  }) {
    switch (e.code) {
      case 'SECURITY_ERROR':
        return const MediaSourceException(
          '媒体源目录或文件访问权限不足，请重新授权',
          code: 'PERMISSION_DENIED',
        );
      case 'FILE_NOT_FOUND':
        return const MediaSourceException('媒体文件或目录不存在或已移除', code: 'NOT_FOUND');
      case 'ACTIVITY_DESTROYED':
        return const MediaSourceException('操作已被系统取消', code: 'CANCELLED');
      case 'ALREADY_ACTIVE':
        return const MediaSourceException(
          '已有选择操作正在进行中',
          code: 'ALREADY_ACTIVE',
        );
      case 'INVALID_SCHEME':
      case 'INVALID_ARGUMENT':
        return const MediaSourceException(
          '媒体源路径格式无效',
          code: 'INVALID_ARGUMENT',
        );
      case 'QUERY_FAILED':
        return const MediaSourceException('读取目录内容失败', code: 'IO_ERROR');
      default:
        return MediaSourceException(defaultMessage, code: e.code);
    }
  }
}
