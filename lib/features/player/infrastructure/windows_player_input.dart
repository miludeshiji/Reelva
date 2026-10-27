import 'package:flutter/services.dart';

/// 仅切换 Flutter 播放窗口的 IME 上下文，不改变系统输入法或键盘布局。
class WindowsPlayerInput {
  const WindowsPlayerInput();

  static const channel = MethodChannel('reelva/player_input');

  Future<void> setImeEnabled(bool enabled) =>
      channel.invokeMethod<void>('setImeEnabled', enabled);
}
