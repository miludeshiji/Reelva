import 'dart:convert';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../../player/domain/playback_resource.dart';
import '../../player/infrastructure/android_media_documents.dart';
import '../../player/infrastructure/media_file_picker.dart';
import '../../sources/domain/media_sidecar_adapter.dart';
import '../../sources/domain/source_models.dart';
import '../domain/danmaku.dart';
import 'danmaku_api.dart';

// 与 Android 文档读取的上限一致，允许包含原始消息数据的录播姬 XML。
const maxDanmakuFileBytes = 16 * 1024 * 1024;

class LocalDanmakuLoader {
  const LocalDanmakuLoader({
    this.androidDocuments = const AndroidMediaDocuments(),
    this.openFilePicker,
    this.platformOverride,
  });

  final AndroidMediaDocuments androidDocuments;
  final OpenFilePicker? openFilePicker;
  final TargetPlatform? platformOverride;

  Future<LocalDanmakuFile?> loadSibling(PlaybackResource resource) async {
    if (resource.uri.scheme != 'file') return null;
    final file = File(p.setExtension(resource.uri.toFilePath(), '.xml'));
    if (!await file.exists()) return null;
    return _readFile(file);
  }

  Future<LocalDanmakuFile?> loadFromSource({
    required MediaSidecarAdapter adapter,
    required MediaSourceConfig source,
    required String videoId,
    required String fileName,
  }) async {
    final directory = await adapter.parentDirectory(source, videoId);
    if (directory == null) return null;
    final expected = p.setExtension(fileName, '.xml').toLowerCase();
    await for (final entry in adapter.listEntries(source, directory)) {
      if (entry.isDirectory || entry.name.toLowerCase() != expected) continue;
      try {
        final bytes = await adapter.readBytes(
          source,
          entry.externalId,
          maxBytes: maxDanmakuFileBytes,
        );
        return await _parse(entry.name, bytes);
      } on MediaSourceException catch (error) {
        if (error.code == 'file_too_large') throw _tooLarge;
        throw const DanmakuException('无法读取同目录弹幕，请检查媒体源访问权限');
      }
    }
    return null;
  }

  Future<LocalDanmakuFile?> pick() async {
    final platform = platformOverride ?? defaultTargetPlatform;
    try {
      switch (platform) {
        case TargetPlatform.windows:
          final file = await (openFilePicker ?? openFile)(
            acceptedTypeGroups: const [
              XTypeGroup(label: '弹幕 XML', extensions: ['xml']),
            ],
          );
          if (file == null) return null;
          _validateName(file.name);
          return await _readFile(File(file.path));
        case TargetPlatform.android:
          final resource = await androidDocuments.pickDanmaku();
          if (resource == null) return null;
          _validateName(resource.fileName);
          final bytes = await androidDocuments.readBytes(
            resource.uri,
            maxBytes: maxDanmakuFileBytes,
          );
          return await _parse(resource.fileName, bytes);
        default:
          throw const DanmakuException('当前平台暂不支持选择本地弹幕');
      }
    } on MediaDocumentException catch (error) {
      if (error.code == 'FILE_TOO_LARGE') throw _tooLarge;
      throw DanmakuException(error.message);
    }
  }

  void _validateName(String name) {
    if (p.extension(name).toLowerCase() != '.xml') {
      throw const DanmakuException('请选择 B站或录播姬 XML 弹幕文件');
    }
  }

  Future<LocalDanmakuFile> _readFile(File file) async {
    try {
      if (await file.length() > maxDanmakuFileBytes) throw _tooLarge;
      final bytes = await collectSidecarBytes(
        file.openRead(),
        maxDanmakuFileBytes,
      );
      return await _parse(p.basename(file.path), bytes);
    } on FileSystemException {
      throw const DanmakuException('无法读取本地弹幕，请检查文件和访问权限');
    } on MediaSourceException catch (error) {
      if (error.code == 'file_too_large') throw _tooLarge;
      rethrow;
    }
  }

  Future<LocalDanmakuFile> _parse(String name, Uint8List bytes) async {
    if (bytes.length > maxDanmakuFileBytes) throw _tooLarge;
    try {
      return LocalDanmakuFile(
        fileName: name,
        comments: await compute(_parseLocalDanmaku, bytes),
      );
    } catch (_) {
      throw const DanmakuException('弹幕 XML 格式无效，请选择 B站或录播姬弹幕文件');
    }
  }

  static const _tooLarge = DanmakuException('弹幕文件过大，最多支持 16 MiB');
}

List<DanmakuComment> _parseLocalDanmaku(Uint8List bytes) =>
    parseDanmakuBody((DanmakuSource.bilibili, utf8.decode(bytes)));
