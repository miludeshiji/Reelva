import 'package:flutter/services.dart';

/// 调整当前 Activity 的亮度，并在离开播放器时恢复原窗口设置。
class AndroidScreenBrightness {
  const AndroidScreenBrightness();

  static const channel = MethodChannel('reelva/screen_brightness');

  Future<double> read() async {
    final value = await channel.invokeMethod<double>('get');
    if (value == null) throw StateError('未读取到屏幕亮度');
    return value;
  }

  Future<void> set(double value) =>
      channel.invokeMethod<void>('set', {'brightness': value});

  Future<void> reset() => channel.invokeMethod<void>('reset');
}
