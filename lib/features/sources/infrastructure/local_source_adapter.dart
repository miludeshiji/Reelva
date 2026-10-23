import 'dart:io';

import 'package:file_selector/file_selector.dart' as file_selector;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../../../core/logging/app_logger.dart';
import '../../player/domain/playback_resource.dart';
import '../domain/media_source_adapter.dart';
import '../domain/source_models.dart';

/// 文件夹选择器函数签名（供测试注入）
typedef OpenDirectoryPicker = Future<String?> Function({
  String? initialDirectory,
  String? confirmButtonText,
});

/// Windows / 本地文件系统媒体源适配器
///
/// 遵循 MediaSourceAdapter 规范：
/// - 根目录 listEntries 传入 source.rootLocator；
/// - 子目录 listEntries 传入 entry.externalId；
/// - 遍历跳过链接与重解析点，避免循环；
/// - 采用异步 I/O，不阻塞主线程；
/// - 仅在 Windows 下对 externalId 进行 lowercase 规整以保证身份稳定；
/// - 严格校验相对路径不可逃出已授权根目录；
/// - stat 失败或 notFound 显式抛出异常，绝不回退空成功。
class LocalSourceAdapter implements MediaSourceAdapter {
  const LocalSourceAdapter({this.openDirectoryPicker, this.platformOverride});

  final OpenDirectoryPicker? openDirectoryPicker;
  final TargetPlatform? platformOverride;

  @override
  String get kind => 'local';

  bool get _isWindows =>
      platformOverride == TargetPlatform.windows ||
      (platformOverride == null && !kIsWeb && Platform.isWindows);

  p.Context get _pathContext => _isWindows ? p.windows : p.context;

  @override
  Future<DirectorySelection?> pickDirectory({String? initialLocator}) async {
    try {
      final picker = openDirectoryPicker ?? file_selector.getDirectoryPath;
      final path = await picker(
        initialDirectory: initialLocator,
        confirmButtonText: '选择此目录',
      );
      if (path == null || path.isEmpty) {
        return null;
      }

      final normalized = _pathContext.normalize(path);
      String name = _pathContext.basename(normalized);
      if (name.isEmpty) {
        name = normalized;
      }

      return DirectorySelection(
        kind: kind,
        rootLocator: normalized,
        name: name,
      );
    } on MediaSourceException {
      rethrow;
    } on PlatformException catch (e, st) {
      AppLogger.instance.error('选择目录平台异常', error: e, stackTrace: st);
      throw MediaSourceException(
        e.code == 'SECURITY_ERROR' ? '无权访问所选目录' : '选择目录失败',
        code: e.code,
      );
    } catch (e, st) {
      AppLogger.instance.error('选择目录失败', error: e, stackTrace: st);
      throw const MediaSourceException('选择目录失败', code: 'PICK_FAILED');
    }
  }

  @override
  Stream<MediaEntry> listEntries(
    MediaSourceConfig source,
    String directoryId,
  ) async* {
    final targetPath = _resolvePath(source.rootLocator, directoryId);
    final dir = Directory(targetPath);
    if (!await dir.exists()) {
      throw const MediaSourceException('目录不存在或无法访问', code: 'not_found');
    }

    Stream<FileSystemEntity> stream;
    try {
      stream = dir.list(recursive: false, followLinks: false);
    } catch (e, st) {
      AppLogger.instance.error('枚举目录失败: ${dir.path}', error: e, stackTrace: st);
      throw const MediaSourceException('无法打开目录', code: 'io_error');
    }

    try {
      await for (final entity in stream) {
        // 跳过符号链接和重解析点，防止死循环
        if (entity is Link) {
          continue;
        }

        final bool isDir = entity is Directory;
        if (!isDir && entity is! File) {
          continue;
        }

        final relPath = _computeRelativePath(source.rootLocator, entity.path);
        final locator = _normalizeRelativeLocator(relPath);
        final externalId = _normalizeExternalId(relPath);
        final name = _pathContext.basename(entity.path);

        FileStat stat;
        try {
          stat = await entity.stat();
        } catch (e, st) {
          AppLogger.instance.error(
            '获取条目状态失败: ${entity.path}',
            error: e,
            stackTrace: st,
          );
          throw const MediaSourceException('获取条目状态失败', code: 'stat_error');
        }

        if (stat.type == FileSystemEntityType.notFound) {
          throw const MediaSourceException('条目不存在或已被移除', code: 'not_found');
        }

        yield MediaEntry(
          externalId: externalId,
          locator: locator,
          name: name,
          isDirectory: isDir,
          size: isDir ? null : stat.size,
          modifiedAt: stat.modified,
        );
      }
    } on MediaSourceException {
      rethrow;
    } catch (e, st) {
      AppLogger.instance.error(
        '列出目录条目失败: ${dir.path}',
        error: e,
        stackTrace: st,
      );
      throw const MediaSourceException('读取目录内容失败', code: 'io_error');
    }
  }

  @override
  Future<MediaStat> stat(MediaSourceConfig source, String entryId) async {
    final targetPath = _resolvePath(source.rootLocator, entryId);
    final file = File(targetPath);
    if (await file.exists()) {
      try {
        final s = await file.stat();
        if (s.type == FileSystemEntityType.notFound) {
          throw const MediaSourceException('文件不存在', code: 'not_found');
        }
        return MediaStat(size: s.size, modifiedAt: s.modified);
      } catch (e, st) {
        if (e is MediaSourceException) rethrow;
        AppLogger.instance.error(
          '获取文件状态失败: ${file.path}',
          error: e,
          stackTrace: st,
        );
        throw const MediaSourceException('无法获取文件状态', code: 'io_error');
      }
    }

    final dir = Directory(targetPath);
    if (await dir.exists()) {
      try {
        final s = await dir.stat();
        if (s.type == FileSystemEntityType.notFound) {
          throw const MediaSourceException('目录不存在', code: 'not_found');
        }
        return MediaStat(size: null, modifiedAt: s.modified);
      } catch (e, st) {
        if (e is MediaSourceException) rethrow;
        AppLogger.instance.error(
          '获取目录状态失败: ${dir.path}',
          error: e,
          stackTrace: st,
        );
        throw const MediaSourceException('无法获取目录状态', code: 'io_error');
      }
    }

    throw const MediaSourceException('文件或目录不存在', code: 'not_found');
  }

  @override
  Future<PlaybackResource> resolvePlayback(
    MediaSourceConfig source,
    String entryId,
  ) async {
    final targetPath = _resolvePath(source.rootLocator, entryId);
    final file = File(targetPath);
    if (!await file.exists()) {
      throw const MediaSourceException('媒体文件不存在或源已离线', code: 'not_found');
    }

    final fileUri = Uri.file(file.path, windows: _isWindows);
    final segments = fileUri.pathSegments;
    final basename = segments.isNotEmpty && segments.last.isNotEmpty
        ? segments.last
        : _pathContext.basename(file.path);

    return PlaybackResource(
      uri: fileUri,
      displayName: basename.isNotEmpty ? basename : '视频',
    );
  }

  String _computeRelativePath(String root, String fullPath) {
    final context = _pathContext;
    final rel = context.relative(fullPath, from: root);
    if (rel.startsWith('..') || context.isAbsolute(rel)) {
      throw const MediaSourceException('访问路径逃出媒体源根目录', code: 'path_escape');
    }
    return rel;
  }

  String _normalizeRelativeLocator(String relativePath) {
    final posix = relativePath.replaceAll(r'\', '/');
    final normalized = p.posix.normalize(posix);
    if (normalized == '.' || normalized.isEmpty) {
      return '';
    }
    return normalized.startsWith('/') ? normalized.substring(1) : normalized;
  }

  String _normalizeExternalId(String relativePath) {
    final locator = _normalizeRelativeLocator(relativePath);
    return _isWindows ? locator.toLowerCase() : locator;
  }

  String _resolvePath(String root, String subPath) {
    if (subPath.isEmpty || subPath == root) {
      return root;
    }
    final context = _pathContext;
    final resolved = context.normalize(context.join(root, subPath));
    if (!context.equals(root, resolved) && !context.isWithin(root, resolved)) {
      throw const MediaSourceException('访问路径逃出媒体源根目录', code: 'path_escape');
    }
    return resolved;
  }
}
