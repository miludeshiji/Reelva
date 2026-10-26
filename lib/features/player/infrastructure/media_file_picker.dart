import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../domain/playback_resource.dart';
import '../domain/subtitle_files.dart';
import 'android_media_documents.dart';

/// 媒体选择操作失败异常
class MediaPickerException implements Exception {
  const MediaPickerException(this.message, {this.code});

  final String message;
  final String? code;

  @override
  String toString() => 'MediaPickerException($code): $message';
}

/// 打开文件选择器的函数类型定义（供测试与依赖注入使用）
typedef OpenFilePicker = Future<XFile?> Function({
  List<XTypeGroup> acceptedTypeGroups,
  String? initialDirectory,
  String? confirmButtonText,
});

/// 跨平台本地媒体文件选择器
///
/// Windows 平台调用官方 `file_selector` 打开文件对话框并返回 `file://` URI；
/// Android 平台通过 [AndroidMediaDocuments] SAF 机制获取单次只读授权的 `content://` URI；
/// 其余平台显式抛出 [UnsupportedError]。
class MediaFilePicker {
  const MediaFilePicker({
    this.androidDocuments = const AndroidMediaDocuments(),
    this.platformOverride,
    this.openFilePicker,
  });

  final AndroidMediaDocuments androidDocuments;
  final TargetPlatform? platformOverride;
  final OpenFilePicker? openFilePicker;

  static const List<XTypeGroup> _videoTypeGroups = [
    XTypeGroup(
      label: 'video',
      extensions: <String>[
        'mp4',
        'mkv',
        'avi',
        'mov',
        'webm',
        'flv',
        'wmv',
        'm4v',
        'ts',
        'm2ts',
        'mpg',
        'mpeg',
        '3gp',
        'rmvb',
      ],
    ),
  ];

  /// 打开平台对应的媒体文件选择对话框
  ///
  /// 用户取消选择返回 `null`；发生错误时抛出 [MediaPickerException]；
  /// 不支持的平台抛出 [UnsupportedError]。
  Future<PlaybackResource?> pick() async {
    final platform = platformOverride ?? defaultTargetPlatform;
    switch (platform) {
      case TargetPlatform.windows:
        return _pickWindows();
      case TargetPlatform.android:
        return _pickAndroid();
      case TargetPlatform.fuchsia:
      case TargetPlatform.iOS:
      case TargetPlatform.linux:
      case TargetPlatform.macOS:
        throw UnsupportedError('当前平台暂不支持选择媒体文件');
    }
  }

  Future<PlaybackResource?> pickSubtitle() async {
    try {
      final platform = platformOverride ?? defaultTargetPlatform;
      final PlaybackResource? resource;
      switch (platform) {
        case TargetPlatform.windows:
          final file = await (openFilePicker ?? openFile)(
            acceptedTypeGroups: const [
              XTypeGroup(label: '字幕', extensions: subtitleExtensions),
            ],
          );
          resource = file == null
              ? null
              : PlaybackResource(
                  uri: Uri.file(file.path, windows: true),
                  displayName: file.name,
                );
        case TargetPlatform.android:
          resource = await androidDocuments.pickSubtitle();
        default:
          throw UnsupportedError('当前平台暂不支持选择字幕文件');
      }
      if (resource != null && !isSubtitleFile(resource.displayName)) {
        throw const MediaPickerException('请选择支持的字幕文件（SRT、ASS、SSA、VTT、SMI、SUP）');
      }
      return resource;
    } on MediaPickerException {
      rethrow;
    } on MediaDocumentException catch (e) {
      throw MediaPickerException(e.message, code: e.code);
    } on PlatformException catch (e) {
      throw MediaPickerException('选择字幕文件失败', code: e.code);
    }
  }

  Future<PlaybackResource?> _pickWindows() async {
    try {
      final picker = openFilePicker ?? openFile;
      final file = await picker(acceptedTypeGroups: _videoTypeGroups);
      if (file == null) {
        return null;
      }
      final fileUri = Uri.file(file.path, windows: true);
      final segments = fileUri.pathSegments;
      final basename = segments.isNotEmpty && segments.last.isNotEmpty
          ? segments.last
          : (file.name.isNotEmpty ? file.name : '视频');
      return PlaybackResource(uri: fileUri, displayName: basename);
    } on MediaPickerException {
      rethrow;
    } on PlatformException catch (e) {
      throw MediaPickerException(
        e.code == 'SECURITY_ERROR' ? '无权访问所选文件' : '选择媒体文件失败',
        code: e.code,
      );
    } catch (_) {
      throw const MediaPickerException('选择媒体文件失败', code: 'PICK_FAILED');
    }
  }

  Future<PlaybackResource?> _pickAndroid() async {
    try {
      return await androidDocuments.pick();
    } on MediaDocumentException catch (e) {
      throw MediaPickerException(e.message, code: e.code);
    } catch (_) {
      throw const MediaPickerException('选择媒体文档失败', code: 'PICK_FAILED');
    }
  }
}
