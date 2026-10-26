import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

enum ShortcutGroup {
  playback('播放与定位'),
  audio('音频与倍速'),
  subtitles('字幕'),
  video('画面');

  const ShortcutGroup(this.label);
  final String label;
}

enum PlayerShortcutAction {
  togglePause(
    '播放 / 暂停',
    ShortcutGroup.playback,
    PlayerKeyBinding(LogicalKeyboardKey.space),
  ),
  toggleFullscreen(
    '切换全屏',
    ShortcutGroup.playback,
    PlayerKeyBinding(LogicalKeyboardKey.enter),
  ),
  exitFullscreen(
    '退出全屏',
    ShortcutGroup.playback,
    PlayerKeyBinding(LogicalKeyboardKey.escape),
  ),
  seekBack(
    '后退',
    ShortcutGroup.playback,
    PlayerKeyBinding(LogicalKeyboardKey.arrowLeft),
    repeatable: true,
  ),
  seekForward(
    '前进',
    ShortcutGroup.playback,
    PlayerKeyBinding(LogicalKeyboardKey.arrowRight),
    repeatable: true,
  ),
  seekBackLarge(
    '大幅后退',
    ShortcutGroup.playback,
    PlayerKeyBinding(LogicalKeyboardKey.arrowLeft, shift: true),
    repeatable: true,
  ),
  seekForwardLarge(
    '大幅前进',
    ShortcutGroup.playback,
    PlayerKeyBinding(LogicalKeyboardKey.arrowRight, shift: true),
    repeatable: true,
  ),
  previousChapter(
    '上一章节',
    ShortcutGroup.playback,
    PlayerKeyBinding(LogicalKeyboardKey.home),
  ),
  nextChapter(
    '下一章节',
    ShortcutGroup.playback,
    PlayerKeyBinding(LogicalKeyboardKey.end),
  ),
  previousFrame(
    '前一帧',
    ShortcutGroup.playback,
    PlayerKeyBinding(LogicalKeyboardKey.keyV),
    repeatable: true,
  ),
  nextFrame(
    '后一帧',
    ShortcutGroup.playback,
    PlayerKeyBinding(LogicalKeyboardKey.keyB),
    repeatable: true,
  ),
  abLoop(
    '设置 / 清除 A-B 循环',
    ShortcutGroup.playback,
    PlayerKeyBinding(LogicalKeyboardKey.keyL),
  ),
  loopFile(
    '单文件循环',
    ShortcutGroup.playback,
    PlayerKeyBinding(LogicalKeyboardKey.keyK, control: true),
  ),
  showTracks(
    '显示音轨与字幕信息',
    ShortcutGroup.playback,
    PlayerKeyBinding(LogicalKeyboardKey.f9),
  ),
  toggleStatistics(
    '显示 / 隐藏播放信息',
    ShortcutGroup.playback,
    PlayerKeyBinding(LogicalKeyboardKey.tab),
  ),
  showProgress(
    '显示播放进度',
    ShortcutGroup.playback,
    PlayerKeyBinding(LogicalKeyboardKey.backslash),
  ),
  volumeUp(
    '增加音量',
    ShortcutGroup.audio,
    PlayerKeyBinding(LogicalKeyboardKey.arrowUp),
    repeatable: true,
  ),
  volumeDown(
    '降低音量',
    ShortcutGroup.audio,
    PlayerKeyBinding(LogicalKeyboardKey.arrowDown),
    repeatable: true,
  ),
  volumeUpLarge(
    '大幅增加音量',
    ShortcutGroup.audio,
    PlayerKeyBinding(LogicalKeyboardKey.arrowUp, shift: true),
    repeatable: true,
  ),
  volumeDownLarge(
    '大幅降低音量',
    ShortcutGroup.audio,
    PlayerKeyBinding(LogicalKeyboardKey.arrowDown, shift: true),
    repeatable: true,
  ),
  toggleMute(
    '静音 / 取消静音',
    ShortcutGroup.audio,
    PlayerKeyBinding(LogicalKeyboardKey.keyF),
  ),
  cycleAudio(
    '切换音轨',
    ShortcutGroup.audio,
    PlayerKeyBinding(LogicalKeyboardKey.keyA),
  ),
  resetRate(
    '恢复正常倍速',
    ShortcutGroup.audio,
    PlayerKeyBinding(LogicalKeyboardKey.keyZ),
  ),
  slower(
    '播放速度 −0.1',
    ShortcutGroup.audio,
    PlayerKeyBinding(LogicalKeyboardKey.keyX),
    repeatable: true,
  ),
  faster(
    '播放速度 +0.1',
    ShortcutGroup.audio,
    PlayerKeyBinding(LogicalKeyboardKey.keyC),
    repeatable: true,
  ),
  halveRate(
    '播放速度 ×0.5',
    ShortcutGroup.audio,
    PlayerKeyBinding(LogicalKeyboardKey.keyX, control: true),
  ),
  doubleRate(
    '播放速度 ×2',
    ShortcutGroup.audio,
    PlayerKeyBinding(LogicalKeyboardKey.keyC, control: true),
  ),
  audioEarlier(
    '音频延迟 −0.1 秒',
    ShortcutGroup.audio,
    PlayerKeyBinding(LogicalKeyboardKey.arrowLeft, alt: true),
    repeatable: true,
  ),
  audioLater(
    '音频延迟 +0.1 秒',
    ShortcutGroup.audio,
    PlayerKeyBinding(LogicalKeyboardKey.arrowRight, alt: true),
    repeatable: true,
  ),
  cycleSubtitles(
    '切换字幕轨道',
    ShortcutGroup.subtitles,
    PlayerKeyBinding(LogicalKeyboardKey.keyS),
  ),
  toggleSubtitles(
    '显示 / 隐藏字幕',
    ShortcutGroup.subtitles,
    PlayerKeyBinding(LogicalKeyboardKey.keyD),
  ),
  subtitlesEarlier(
    '字幕延迟 −0.1 秒',
    ShortcutGroup.subtitles,
    PlayerKeyBinding(LogicalKeyboardKey.arrowLeft, control: true),
    repeatable: true,
  ),
  subtitlesLater(
    '字幕延迟 +0.1 秒',
    ShortcutGroup.subtitles,
    PlayerKeyBinding(LogicalKeyboardKey.arrowRight, control: true),
    repeatable: true,
  ),
  subtitlesUp(
    '字幕上移',
    ShortcutGroup.subtitles,
    PlayerKeyBinding(LogicalKeyboardKey.arrowUp, alt: true),
    repeatable: true,
  ),
  subtitlesDown(
    '字幕下移',
    ShortcutGroup.subtitles,
    PlayerKeyBinding(LogicalKeyboardKey.arrowDown, alt: true),
    repeatable: true,
  ),
  subtitlesSmaller(
    '字幕缩小 5%',
    ShortcutGroup.subtitles,
    PlayerKeyBinding(LogicalKeyboardKey.arrowUp, control: true),
    repeatable: true,
  ),
  subtitlesLarger(
    '字幕放大 5%',
    ShortcutGroup.subtitles,
    PlayerKeyBinding(LogicalKeyboardKey.arrowDown, control: true),
    repeatable: true,
  ),
  toggleHwdec(
    '切换硬解 / 软解',
    ShortcutGroup.video,
    PlayerKeyBinding(LogicalKeyboardKey.keyH),
  ),
  toggleDeinterlace(
    '切换反交错',
    ShortcutGroup.video,
    PlayerKeyBinding(LogicalKeyboardKey.keyJ),
  ),
  cycleAspect(
    '切换画面比例',
    ShortcutGroup.video,
    PlayerKeyBinding(LogicalKeyboardKey.keyK),
  ),
  rotateSmall(
    '顺时针旋转 1°',
    ShortcutGroup.video,
    PlayerKeyBinding(LogicalKeyboardKey.digit8),
    repeatable: true,
  ),
  rotateClockwise(
    '顺时针旋转 90°',
    ShortcutGroup.video,
    PlayerKeyBinding(LogicalKeyboardKey.digit9),
  ),
  rotateCounterclockwise(
    '逆时针旋转 90°',
    ShortcutGroup.video,
    PlayerKeyBinding(LogicalKeyboardKey.digit0),
  ),
  brightnessDown(
    '亮度 −1',
    ShortcutGroup.video,
    PlayerKeyBinding(LogicalKeyboardKey.keyQ),
    repeatable: true,
  ),
  brightnessUp(
    '亮度 +1',
    ShortcutGroup.video,
    PlayerKeyBinding(LogicalKeyboardKey.keyW),
    repeatable: true,
  ),
  contrastDown(
    '对比度 −1',
    ShortcutGroup.video,
    PlayerKeyBinding(LogicalKeyboardKey.keyE),
    repeatable: true,
  ),
  contrastUp(
    '对比度 +1',
    ShortcutGroup.video,
    PlayerKeyBinding(LogicalKeyboardKey.keyR),
    repeatable: true,
  ),
  gammaDown(
    '伽马 −1',
    ShortcutGroup.video,
    PlayerKeyBinding(LogicalKeyboardKey.keyT),
    repeatable: true,
  ),
  gammaUp(
    '伽马 +1',
    ShortcutGroup.video,
    PlayerKeyBinding(LogicalKeyboardKey.keyY),
    repeatable: true,
  ),
  saturationDown(
    '饱和度 −1',
    ShortcutGroup.video,
    PlayerKeyBinding(LogicalKeyboardKey.keyU),
    repeatable: true,
  ),
  saturationUp(
    '饱和度 +1',
    ShortcutGroup.video,
    PlayerKeyBinding(LogicalKeyboardKey.keyI),
    repeatable: true,
  ),
  hueDown(
    '色调 −1',
    ShortcutGroup.video,
    PlayerKeyBinding(LogicalKeyboardKey.keyO),
    repeatable: true,
  ),
  hueUp(
    '色调 +1',
    ShortcutGroup.video,
    PlayerKeyBinding(LogicalKeyboardKey.keyP),
    repeatable: true,
  ),
  resetColors(
    '重置画面均衡器',
    ShortcutGroup.video,
    PlayerKeyBinding(LogicalKeyboardKey.bracketLeft),
  );

  const PlayerShortcutAction(
    this.label,
    this.group,
    this.defaultBinding, {
    this.repeatable = false,
  });
  final String label;
  final ShortcutGroup group;
  final PlayerKeyBinding defaultBinding;
  final bool repeatable;
}

@immutable
class PlayerKeyBinding {
  const PlayerKeyBinding(
    this.key, {
    this.control = false,
    this.shift = false,
    this.alt = false,
    this.meta = false,
  });

  final LogicalKeyboardKey key;
  final bool control;
  final bool shift;
  final bool alt;
  final bool meta;

  static LogicalKeyboardKey normalize(LogicalKeyboardKey key) =>
      key == LogicalKeyboardKey.numpadEnter ? LogicalKeyboardKey.enter : key;

  static bool isModifier(LogicalKeyboardKey key) => const [
    LogicalKeyboardKey.controlLeft,
    LogicalKeyboardKey.controlRight,
    LogicalKeyboardKey.shiftLeft,
    LogicalKeyboardKey.shiftRight,
    LogicalKeyboardKey.altLeft,
    LogicalKeyboardKey.altRight,
    LogicalKeyboardKey.metaLeft,
    LogicalKeyboardKey.metaRight,
  ].contains(key);

  static PlayerKeyBinding? fromEvent(KeyEvent event) {
    if (isModifier(event.logicalKey)) return null;
    final keyboard = HardwareKeyboard.instance;
    return PlayerKeyBinding(
      normalize(event.logicalKey),
      control: keyboard.isControlPressed,
      shift: keyboard.isShiftPressed,
      alt: keyboard.isAltPressed,
      meta: keyboard.isMetaPressed,
    );
  }

  String get label {
    final name = switch (normalize(key)) {
      LogicalKeyboardKey.space => 'Space',
      LogicalKeyboardKey.enter => 'Enter',
      LogicalKeyboardKey.escape => 'Esc',
      LogicalKeyboardKey.arrowLeft => '←',
      LogicalKeyboardKey.arrowRight => '→',
      LogicalKeyboardKey.arrowUp => '↑',
      LogicalKeyboardKey.arrowDown => '↓',
      _ => key.keyLabel.toUpperCase(),
    };
    return [
      if (control) 'Ctrl',
      if (shift) 'Shift',
      if (alt) 'Alt',
      if (meta) 'Meta',
      name,
    ].join('+');
  }

  Map<String, Object> toJson() => {
    'keyId': normalize(key).keyId,
    'control': control,
    'shift': shift,
    'alt': alt,
    'meta': meta,
  };

  factory PlayerKeyBinding.fromJson(Map<String, dynamic> json) {
    final key = LogicalKeyboardKey.findKeyByKeyId(json['keyId'] as int);
    if (key == null || isModifier(key)) throw const FormatException('无效快捷键');
    return PlayerKeyBinding(
      normalize(key),
      control: json['control'] as bool? ?? false,
      shift: json['shift'] as bool? ?? false,
      alt: json['alt'] as bool? ?? false,
      meta: json['meta'] as bool? ?? false,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is PlayerKeyBinding &&
      normalize(key) == normalize(other.key) &&
      control == other.control &&
      shift == other.shift &&
      alt == other.alt &&
      meta == other.meta;

  @override
  int get hashCode => Object.hash(normalize(key), control, shift, alt, meta);
}

@immutable
class PlayerInputSettings {
  const PlayerInputSettings({
    this.bindings = const {},
    this.keyboardEnabled = true,
    this.clickToPause = true,
    this.doubleClickFullscreen = true,
    this.rightClickMenu = true,
    this.wheelVolume = true,
    this.horizontalWheelSeek = true,
    this.seekSeconds = 2,
    this.largeSeekSeconds = 60,
    this.volumeStep = 2,
    this.largeVolumeStep = 5,
    this.wheelVolumeStep = 2,
    this.wheelSeekSeconds = 2,
  });

  final Map<PlayerShortcutAction, PlayerKeyBinding?> bindings;
  final bool keyboardEnabled;
  final bool clickToPause;
  final bool doubleClickFullscreen;
  final bool rightClickMenu;
  final bool wheelVolume;
  final bool horizontalWheelSeek;
  final int seekSeconds;
  final int largeSeekSeconds;
  final int volumeStep;
  final int largeVolumeStep;
  final int wheelVolumeStep;
  final int wheelSeekSeconds;

  static const seekSteps = [1, 2, 5, 10, 30];
  static const largeSeekSteps = [10, 30, 60, 120, 300];
  static const volumeSteps = [1, 2, 5, 10, 20];

  PlayerKeyBinding? bindingFor(PlayerShortcutAction action) =>
      bindings.containsKey(action) ? bindings[action] : action.defaultBinding;

  PlayerShortcutAction? actionFor(PlayerKeyBinding binding) {
    if (!keyboardEnabled) return null;
    for (final action in PlayerShortcutAction.values) {
      if (bindingFor(action) == binding) return action;
    }
    return null;
  }

  PlayerInputSettings copyWith({
    Map<PlayerShortcutAction, PlayerKeyBinding?>? bindings,
    bool? keyboardEnabled,
    bool? clickToPause,
    bool? doubleClickFullscreen,
    bool? rightClickMenu,
    bool? wheelVolume,
    bool? horizontalWheelSeek,
    int? seekSeconds,
    int? largeSeekSeconds,
    int? volumeStep,
    int? largeVolumeStep,
    int? wheelVolumeStep,
    int? wheelSeekSeconds,
  }) => PlayerInputSettings(
    bindings: bindings == null ? this.bindings : Map.unmodifiable(bindings),
    keyboardEnabled: keyboardEnabled ?? this.keyboardEnabled,
    clickToPause: clickToPause ?? this.clickToPause,
    doubleClickFullscreen: doubleClickFullscreen ?? this.doubleClickFullscreen,
    rightClickMenu: rightClickMenu ?? this.rightClickMenu,
    wheelVolume: wheelVolume ?? this.wheelVolume,
    horizontalWheelSeek: horizontalWheelSeek ?? this.horizontalWheelSeek,
    seekSeconds: seekSeconds ?? this.seekSeconds,
    largeSeekSeconds: largeSeekSeconds ?? this.largeSeekSeconds,
    volumeStep: volumeStep ?? this.volumeStep,
    largeVolumeStep: largeVolumeStep ?? this.largeVolumeStep,
    wheelVolumeStep: wheelVolumeStep ?? this.wheelVolumeStep,
    wheelSeekSeconds: wheelSeekSeconds ?? this.wheelSeekSeconds,
  );

  Map<String, Object> toJson() => {
    'bindings': {
      for (final entry in bindings.entries)
        entry.key.name: entry.value?.toJson(),
    },
    'keyboardEnabled': keyboardEnabled,
    'clickToPause': clickToPause,
    'doubleClickFullscreen': doubleClickFullscreen,
    'rightClickMenu': rightClickMenu,
    'wheelVolume': wheelVolume,
    'horizontalWheelSeek': horizontalWheelSeek,
    'seekSeconds': seekSeconds,
    'largeSeekSeconds': largeSeekSeconds,
    'volumeStep': volumeStep,
    'largeVolumeStep': largeVolumeStep,
    'wheelVolumeStep': wheelVolumeStep,
    'wheelSeekSeconds': wheelSeekSeconds,
  };

  factory PlayerInputSettings.fromJson(Map<String, dynamic> json) {
    final rawBindings = json['bindings'] as Map<String, dynamic>? ?? {};
    final bindings = {
      for (final action in PlayerShortcutAction.values)
        if (rawBindings.containsKey(action.name))
          action: rawBindings[action.name] == null
              ? null
              : PlayerKeyBinding.fromJson(
                  rawBindings[action.name] as Map<String, dynamic>,
                ),
    };
    // 旧配置已将 Tab 用于其他功能时，保留用户绑定。
    if (!rawBindings.containsKey(PlayerShortcutAction.toggleStatistics.name) &&
        bindings.values.contains(
          PlayerShortcutAction.toggleStatistics.defaultBinding,
        )) {
      bindings[PlayerShortcutAction.toggleStatistics] = null;
    }
    final settings = const PlayerInputSettings().copyWith(
      bindings: bindings,
      keyboardEnabled: json['keyboardEnabled'] as bool?,
      clickToPause: json['clickToPause'] as bool?,
      doubleClickFullscreen: json['doubleClickFullscreen'] as bool?,
      rightClickMenu: json['rightClickMenu'] as bool?,
      wheelVolume: json['wheelVolume'] as bool?,
      horizontalWheelSeek: json['horizontalWheelSeek'] as bool?,
      seekSeconds: json['seekSeconds'] as int?,
      largeSeekSeconds: json['largeSeekSeconds'] as int?,
      volumeStep: json['volumeStep'] as int?,
      largeVolumeStep: json['largeVolumeStep'] as int?,
      wheelVolumeStep: json['wheelVolumeStep'] as int?,
      wheelSeekSeconds: json['wheelSeekSeconds'] as int?,
    );
    settings.validate();
    return settings;
  }

  void validate() {
    if (!seekSteps.contains(seekSeconds) ||
        !largeSeekSteps.contains(largeSeekSeconds) ||
        !volumeSteps.contains(volumeStep) ||
        !volumeSteps.contains(largeVolumeStep) ||
        !volumeSteps.contains(wheelVolumeStep) ||
        !seekSteps.contains(wheelSeekSeconds)) {
      throw const FormatException('无效快捷键步长');
    }
    final used = <PlayerKeyBinding>{};
    for (final action in PlayerShortcutAction.values) {
      final binding = bindingFor(action);
      if (binding != null &&
          (PlayerKeyBinding.isModifier(binding.key) || !used.add(binding))) {
        throw const FormatException('快捷键重复或无效');
      }
    }
  }
}
