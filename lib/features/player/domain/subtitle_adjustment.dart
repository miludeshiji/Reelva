import 'player_shortcuts.dart';

enum SubtitleAdjustmentAction {
  earlier(PlayerShortcutAction.subtitlesEarlier),
  later(PlayerShortcutAction.subtitlesLater),
  smaller(PlayerShortcutAction.subtitlesSmaller, changesStyle: true),
  larger(PlayerShortcutAction.subtitlesLarger, changesStyle: true),
  up(PlayerShortcutAction.subtitlesUp, changesStyle: true),
  down(PlayerShortcutAction.subtitlesDown, changesStyle: true),
  reset(null);

  const SubtitleAdjustmentAction(this.shortcut, {this.changesStyle = false});

  final PlayerShortcutAction? shortcut;
  final bool changesStyle;
}

/// 当前视频的原生字幕校准值。只有可调样式的轨道才提供大小和位置。
class SubtitleAdjustment {
  const SubtitleAdjustment({
    required this.mediaEpoch,
    required this.delay,
    this.scale,
    this.position,
  });

  final int mediaEpoch;
  final double delay;
  final double? scale;
  final double? position;
}

typedef AdjustSubtitle = Future<SubtitleAdjustment?> Function({
  SubtitleAdjustmentAction? action,
  int? mediaEpoch,
});
