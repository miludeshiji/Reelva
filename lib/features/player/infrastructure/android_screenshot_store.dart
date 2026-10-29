import 'package:flutter/services.dart';

/// 将视频帧保存到系统相册的 Reelva 目录。
class AndroidScreenshotStore {
  const AndroidScreenshotStore();

  static const channel = MethodChannel('reelva/player_screenshot');

  Future<void> save(Uint8List image, {required String name}) =>
      channel.invokeMethod<void>('save', {'data': image, 'name': name});
}
