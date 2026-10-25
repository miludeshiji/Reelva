import 'package:flutter/foundation.dart';

enum TrackAutoLoad {
  disabled('no'),
  exact('exact'),
  fuzzy('fuzzy');

  const TrackAutoLoad(this.mpvValue);
  final String mpvValue;
}

enum DitherDepth {
  auto('auto'),
  eight('8'),
  ten('10'),
  disabled('no');

  const DitherDepth(this.mpvValue);
  final String mpvValue;
}

enum AssStyleOverride {
  preserve('no'),
  compatible('yes'),
  force('force');

  const AssStyleOverride(this.mpvValue);
  final String mpvValue;
}

/// 本机播放器偏好；一个播放会话使用创建时的配置。
@immutable
class PlayerSettings {
  const PlayerSettings({
    this.hardwareDecoding = true,
    this.highQualityRendering = false,
    this.deband = false,
    this.ditherDepth = DitherDepth.auto,
    this.cacheEnabled = true,
    this.cacheSizeMb = 128,
    this.pitchCorrection = true,
    this.maxVolume = 200,
    this.audioAutoLoad = TrackAutoLoad.fuzzy,
    this.subtitleLanguages = 'zh,chi,chs,sc,zh-hans,en,eng',
    this.subtitleAutoLoad = TrackAutoLoad.fuzzy,
    this.subtitleFont = 'Noto Sans CJK SC',
    this.subtitleFontSize = 60,
    this.subtitleBorderSize = 8,
    this.subtitleBlur = 1,
    this.subtitleMarginY = 40,
    this.assStyleOverride = AssStyleOverride.compatible,
    this.blendSubtitles = true,
  });

  factory PlayerSettings.defaultsFor(TargetPlatform platform) => PlayerSettings(
    highQualityRendering: platform == TargetPlatform.windows,
    deband: platform == TargetPlatform.windows,
    cacheSizeMb: platform == TargetPlatform.windows ? 1024 : 128,
    subtitleFont: platform == TargetPlatform.windows
        ? 'Microsoft YaHei'
        : 'Noto Sans CJK SC',
  );

  static const cacheSizesMb = [32, 64, 128, 256, 512, 1024];
  static const volumeLimits = [100, 150, 200];

  final bool hardwareDecoding;
  final bool highQualityRendering;
  final bool deband;
  final DitherDepth ditherDepth;
  final bool cacheEnabled;
  final int cacheSizeMb;
  final bool pitchCorrection;
  final int maxVolume;
  final TrackAutoLoad audioAutoLoad;
  final String subtitleLanguages;
  final TrackAutoLoad subtitleAutoLoad;
  final String subtitleFont;
  final int subtitleFontSize;
  final int subtitleBorderSize;
  final int subtitleBlur;
  final int subtitleMarginY;
  final AssStyleOverride assStyleOverride;
  final bool blendSubtitles;

  PlayerSettings copyWith({
    bool? hardwareDecoding,
    bool? highQualityRendering,
    bool? deband,
    DitherDepth? ditherDepth,
    bool? cacheEnabled,
    int? cacheSizeMb,
    bool? pitchCorrection,
    int? maxVolume,
    TrackAutoLoad? audioAutoLoad,
    String? subtitleLanguages,
    TrackAutoLoad? subtitleAutoLoad,
    String? subtitleFont,
    int? subtitleFontSize,
    int? subtitleBorderSize,
    int? subtitleBlur,
    int? subtitleMarginY,
    AssStyleOverride? assStyleOverride,
    bool? blendSubtitles,
  }) => PlayerSettings(
    hardwareDecoding: hardwareDecoding ?? this.hardwareDecoding,
    highQualityRendering: highQualityRendering ?? this.highQualityRendering,
    deband: deband ?? this.deband,
    ditherDepth: ditherDepth ?? this.ditherDepth,
    cacheEnabled: cacheEnabled ?? this.cacheEnabled,
    cacheSizeMb: cacheSizeMb ?? this.cacheSizeMb,
    pitchCorrection: pitchCorrection ?? this.pitchCorrection,
    maxVolume: maxVolume ?? this.maxVolume,
    audioAutoLoad: audioAutoLoad ?? this.audioAutoLoad,
    subtitleLanguages: subtitleLanguages ?? this.subtitleLanguages,
    subtitleAutoLoad: subtitleAutoLoad ?? this.subtitleAutoLoad,
    subtitleFont: subtitleFont ?? this.subtitleFont,
    subtitleFontSize: subtitleFontSize ?? this.subtitleFontSize,
    subtitleBorderSize: subtitleBorderSize ?? this.subtitleBorderSize,
    subtitleBlur: subtitleBlur ?? this.subtitleBlur,
    subtitleMarginY: subtitleMarginY ?? this.subtitleMarginY,
    assStyleOverride: assStyleOverride ?? this.assStyleOverride,
    blendSubtitles: blendSubtitles ?? this.blendSubtitles,
  );

  Map<String, Object> toJson() => {
    'hardwareDecoding': hardwareDecoding,
    'highQualityRendering': highQualityRendering,
    'deband': deband,
    'ditherDepth': ditherDepth.name,
    'cacheEnabled': cacheEnabled,
    'cacheSizeMb': cacheSizeMb,
    'pitchCorrection': pitchCorrection,
    'maxVolume': maxVolume,
    'audioAutoLoad': audioAutoLoad.name,
    'subtitleLanguages': subtitleLanguages,
    'subtitleAutoLoad': subtitleAutoLoad.name,
    'subtitleFont': subtitleFont,
    'subtitleFontSize': subtitleFontSize,
    'subtitleBorderSize': subtitleBorderSize,
    'subtitleBlur': subtitleBlur,
    'subtitleMarginY': subtitleMarginY,
    'assStyleOverride': assStyleOverride.name,
    'blendSubtitles': blendSubtitles,
  };

  factory PlayerSettings.fromJson(
    Map<String, dynamic> json, {
    required PlayerSettings defaults,
  }) {
    final settings = defaults.copyWith(
      hardwareDecoding: json['hardwareDecoding'] as bool?,
      highQualityRendering: json['highQualityRendering'] as bool?,
      deband: json['deband'] as bool?,
      ditherDepth: json['ditherDepth'] == null
          ? null
          : DitherDepth.values.byName(json['ditherDepth'] as String),
      cacheEnabled: json['cacheEnabled'] as bool?,
      cacheSizeMb: json['cacheSizeMb'] as int?,
      pitchCorrection: json['pitchCorrection'] as bool?,
      maxVolume: json['maxVolume'] as int?,
      audioAutoLoad: json['audioAutoLoad'] == null
          ? null
          : TrackAutoLoad.values.byName(json['audioAutoLoad'] as String),
      subtitleLanguages: json['subtitleLanguages'] as String?,
      subtitleAutoLoad: json['subtitleAutoLoad'] == null
          ? null
          : TrackAutoLoad.values.byName(json['subtitleAutoLoad'] as String),
      subtitleFont: json['subtitleFont'] as String?,
      subtitleFontSize: json['subtitleFontSize'] as int?,
      subtitleBorderSize: json['subtitleBorderSize'] as int?,
      subtitleBlur: json['subtitleBlur'] as int?,
      subtitleMarginY: json['subtitleMarginY'] as int?,
      assStyleOverride: json['assStyleOverride'] == null
          ? null
          : AssStyleOverride.values.byName(json['assStyleOverride'] as String),
      blendSubtitles: json['blendSubtitles'] as bool?,
    );
    settings.validate();
    return settings;
  }

  void validate() {
    if (!cacheSizesMb.contains(cacheSizeMb) ||
        !volumeLimits.contains(maxVolume) ||
        subtitleFont.trim().isEmpty ||
        subtitleFont.length > 128 ||
        !validSubtitleLanguages(subtitleLanguages) ||
        subtitleFontSize < 16 ||
        subtitleFontSize > 80 ||
        subtitleBorderSize < 0 ||
        subtitleBorderSize > 10 ||
        subtitleBlur < 0 ||
        subtitleBlur > 3 ||
        subtitleMarginY < 0 ||
        subtitleMarginY > 100) {
      throw const FormatException('播放器设置包含无效值');
    }
  }

  static bool validSubtitleLanguages(String value) =>
      value.isEmpty ||
      RegExp(r'^[a-zA-Z0-9_-]+(,[a-zA-Z0-9_-]+)*$').hasMatch(value);
}
