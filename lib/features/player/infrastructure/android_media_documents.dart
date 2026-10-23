import 'package:flutter/services.dart';

import '../domain/playback_resource.dart';

/// 媒体文档操作相关异常
class MediaDocumentException implements Exception {
  const MediaDocumentException(this.message, {this.code});

  final String message;
  final String? code;

  @override
  String toString() => 'MediaDocumentException($code): $message';
}

/// Android 原生媒体文档桥接器
///
/// 通过 SAF (Storage Access Framework) ACTION_OPEN_DOCUMENT 选择媒体文件，
/// 打开可读 ParcelFileDescriptor 并供底层播放器安全访问，避免 content:// 生命周期问题。
class AndroidMediaDocuments {
  const AndroidMediaDocuments({
    this.channel = const MethodChannel('reelva/media_documents'),
  });

  final MethodChannel channel;

  /// 调用原生选择器选择单个视频文档
  ///
  /// 若用户取消返回 `null`；若成功返回对应的 [PlaybackResource]。
  Future<PlaybackResource?> pick() async {
    try {
      final result = await channel.invokeMapMethod<String, dynamic>(
        'pickVideo',
      );
      if (result == null) {
        return null;
      }
      final uriString = result['uri'] as String?;
      final name = result['name'] as String?;
      if (uriString == null ||
          uriString.isEmpty ||
          name == null ||
          name.isEmpty) {
        throw const MediaDocumentException('无效的媒体文档信息', code: 'INVALID_DATA');
      }
      return PlaybackResource(uri: Uri.parse(uriString), displayName: name);
    } on PlatformException catch (e) {
      throw _mapPlatformException(e, defaultMessage: '选择媒体文档失败');
    }
  }

  /// 以只读模式打开指定 content URI 对应的文件描述符
  ///
  /// 返回原生 OS 文件描述符编号 (int)。
  Future<int> openRead(Uri uri) async {
    try {
      final descriptor = await channel.invokeMethod<int>('openRead', {
        'uri': uri.toString(),
      });
      if (descriptor == null) {
        throw const MediaDocumentException('无法打开媒体文件描述符', code: 'OPEN_FAILED');
      }
      return descriptor;
    } on PlatformException catch (e) {
      throw _mapPlatformException(e, defaultMessage: '打开媒体文档失败');
    }
  }

  /// 幂等关闭由本应用打开的文件描述符
  Future<void> close(int descriptor) async {
    try {
      await channel.invokeMethod<void>('close', {'descriptor': descriptor});
    } on PlatformException catch (e) {
      throw _mapPlatformException(e, defaultMessage: '关闭媒体描述符失败');
    }
  }

  static MediaDocumentException _mapPlatformException(
    PlatformException e, {
    required String defaultMessage,
  }) {
    switch (e.code) {
      case 'SECURITY_ERROR':
        return MediaDocumentException('无权访问所选媒体资源', code: e.code);
      case 'FILE_NOT_FOUND':
        return MediaDocumentException('媒体文件不存在或已失效', code: e.code);
      case 'ALREADY_ACTIVE':
        return MediaDocumentException('媒体选择器已在运行中', code: e.code);
      case 'ACTIVITY_DESTROYED':
        return MediaDocumentException('操作在完成前已被取消或界面已销毁', code: e.code);
      case 'INVALID_SCHEME':
      case 'INVALID_ARGUMENT':
        return MediaDocumentException('不支持的媒体资源格式', code: e.code);
      case 'IO_ERROR':
        return MediaDocumentException('读取媒体资源发生错误', code: e.code);
      case 'CLOSE_FAILED':
        return MediaDocumentException('关闭媒体描述符失败', code: e.code);
      default:
        return MediaDocumentException(defaultMessage, code: e.code);
    }
  }
}
