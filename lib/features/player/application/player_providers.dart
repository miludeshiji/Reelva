import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/logging/app_logger.dart';
import '../infrastructure/media_file_picker.dart';
import '../infrastructure/media_kit_player_engine.dart';
import 'playback_session.dart';

/// 跨平台本地文件选择器 Provider
final mediaFilePickerProvider = Provider<MediaFilePicker>((ref) {
  return const MediaFilePicker();
});

/// 播放会话 Provider（autoDispose，退出播放路由时兜底销毁引擎并捕获异步异常）
final playerSessionProvider = Provider.autoDispose<PlaybackSession>((ref) {
  final session = createMediaKitSession();
  ref.onDispose(() {
    session.engine.dispose().catchError((Object e, StackTrace st) {
      AppLogger.instance.error(
        'Provider.onDispose 释放播放引擎异常',
        error: e,
        stackTrace: st,
      );
    });
  });
  return session;
});
