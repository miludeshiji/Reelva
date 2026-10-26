import '../domain/player_shortcuts.dart';

/// 固定的播放器操作，不执行 input.conf 中的脚本、路径或任意命令。
List<List<String>> mpvShortcutCommands(
  PlayerShortcutAction action, {
  required bool android,
}) {
  if (action == PlayerShortcutAction.resetColors) {
    return [
      for (final property in [
        'brightness',
        'contrast',
        'gamma',
        'saturation',
        'hue',
      ])
        ['set', property, '0'],
    ];
  }
  return [
    switch (action) {
      PlayerShortcutAction.previousChapter => ['add', 'chapter', '-1'],
      PlayerShortcutAction.nextChapter => ['add', 'chapter', '1'],
      PlayerShortcutAction.previousFrame => ['frame-back-step'],
      PlayerShortcutAction.nextFrame => ['frame-step'],
      PlayerShortcutAction.abLoop => ['ab-loop'],
      PlayerShortcutAction.loopFile => [
        'cycle-values',
        'loop-file',
        'inf',
        'no',
      ],
      PlayerShortcutAction.audioEarlier => ['add', 'audio-delay', '-0.1'],
      PlayerShortcutAction.audioLater => ['add', 'audio-delay', '0.1'],
      PlayerShortcutAction.toggleSubtitles => ['cycle', 'sub-visibility'],
      PlayerShortcutAction.subtitlesEarlier => ['add', 'sub-delay', '-0.1'],
      PlayerShortcutAction.subtitlesLater => ['add', 'sub-delay', '0.1'],
      PlayerShortcutAction.subtitlesUp => ['add', 'sub-pos', '-1'],
      PlayerShortcutAction.subtitlesDown => ['add', 'sub-pos', '1'],
      PlayerShortcutAction.subtitlesSmaller => ['add', 'sub-scale', '-0.05'],
      PlayerShortcutAction.subtitlesLarger => ['add', 'sub-scale', '0.05'],
      PlayerShortcutAction.toggleHwdec => [
        'cycle-values',
        'hwdec',
        android ? 'auto-safe' : 'auto',
        'no',
      ],
      PlayerShortcutAction.toggleDeinterlace => ['cycle', 'deinterlace'],
      PlayerShortcutAction.cycleAspect => [
        'cycle-values',
        'video-aspect-override',
        '16:9',
        '4:3',
        '2.35:1',
        '-1',
      ],
      PlayerShortcutAction.rotateSmall => ['add', 'video-rotate', '1'],
      PlayerShortcutAction.rotateClockwise => [
        'cycle-values',
        'video-rotate',
        '0',
        '90',
        '180',
        '270',
      ],
      PlayerShortcutAction.rotateCounterclockwise => [
        'cycle-values',
        '!reverse',
        'video-rotate',
        '0',
        '90',
        '180',
        '270',
      ],
      PlayerShortcutAction.brightnessDown => ['add', 'brightness', '-1'],
      PlayerShortcutAction.brightnessUp => ['add', 'brightness', '1'],
      PlayerShortcutAction.contrastDown => ['add', 'contrast', '-1'],
      PlayerShortcutAction.contrastUp => ['add', 'contrast', '1'],
      PlayerShortcutAction.gammaDown => ['add', 'gamma', '-1'],
      PlayerShortcutAction.gammaUp => ['add', 'gamma', '1'],
      PlayerShortcutAction.saturationDown => ['add', 'saturation', '-1'],
      PlayerShortcutAction.saturationUp => ['add', 'saturation', '1'],
      PlayerShortcutAction.hueDown => ['add', 'hue', '-1'],
      PlayerShortcutAction.hueUp => ['add', 'hue', '1'],
      _ => throw ArgumentError.value(action, 'action', '该操作由应用管理'),
    },
  ];
}
