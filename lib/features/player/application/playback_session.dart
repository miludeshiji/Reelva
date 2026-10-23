import 'package:flutter/widgets.dart';

import '../domain/player_engine.dart';

/// 播放会话模型（Flutter 视图与纯领域播放引擎的组合）
///
/// 将领域层 [PlayerEngine] 与隔离的 [videoBuilder] 视图构建器组装，
/// 供 UI 层展示播放画面与控件，彻底隔离底层 media_kit 与原生控制器实现。
class PlaybackSession {
  const PlaybackSession({required this.engine, required this.videoBuilder});

  /// 领域播放引擎实例
  final PlayerEngine engine;

  /// 视频画面渲染视图构建器
  final WidgetBuilder videoBuilder;
}
