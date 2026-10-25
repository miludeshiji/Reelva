import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../domain/player_settings.dart';

const subtitleFontAsset = 'assets/fonts/NotoSansCJKsc-Regular.otf';

PlayerConfiguration mediaKitPlayerConfiguration(PlayerSettings settings) =>
    PlayerConfiguration(
      vo: 'null',
      osc: false,
      pitch: false,
      title: 'Reelva',
      logLevel: MPVLogLevel.error,
      bufferSize: settings.cacheSizeMb * 1024 * 1024,
      libass: true,
      libassAndroidFont: subtitleFontAsset,
      libassAndroidFontName: 'Noto Sans CJK SC',
    );

VideoControllerConfiguration mediaKitVideoConfiguration(
  PlayerSettings settings,
) => VideoControllerConfiguration(
  // 解码可切换到软件，Flutter 视频纹理仍由 GPU 输出。
  hwdec: settings.hardwareDecoding ? null : 'no',
  enableHardwareAcceleration: true,
);

/// 只映射适用于嵌入式渲染的选项，保留 media_kit 对 VO/窗口/平台后端的管理。
Map<String, String> mpvPlayerProperties(PlayerSettings settings) => {
  'vd-lavc-dr': 'yes',
  'cache': settings.cacheEnabled ? 'yes' : 'no',
  'cache-on-disk': 'no',
  'demuxer-max-bytes': '${settings.cacheSizeMb * 1024 * 1024}',
  // 限制回退缓存，避免额外保留另一份大缓存。
  'demuxer-max-back-bytes':
      '${(settings.cacheSizeMb ~/ 4).clamp(8, 64) * 1024 * 1024}',
  'scale': settings.highQualityRendering ? 'ewa_lanczossharp' : 'bilinear',
  'dscale': settings.highQualityRendering ? 'mitchell' : 'bilinear',
  'cscale': settings.highQualityRendering ? 'catmull_rom' : 'bilinear',
  'correct-downscaling': settings.highQualityRendering ? 'yes' : 'no',
  'linear-downscaling': settings.highQualityRendering ? 'yes' : 'no',
  'sigmoid-upscaling': settings.highQualityRendering ? 'yes' : 'no',
  'deband': settings.deband ? 'yes' : 'no',
  'dither': settings.ditherDepth == DitherDepth.disabled ? 'no' : 'fruit',
  'dither-depth': settings.ditherDepth.mpvValue,
  'audio-pitch-correction': settings.pitchCorrection ? 'yes' : 'no',
  'audio-file-auto': settings.audioAutoLoad.mpvValue,
  'volume-max': '${settings.maxVolume}',
  'slang': settings.subtitleLanguages,
  'sub-auto': settings.subtitleAutoLoad.mpvValue,
  'sub-font': settings.subtitleFont,
  'sub-font-size': '${settings.subtitleFontSize}',
  'sub-border-size': '${settings.subtitleBorderSize}',
  'sub-blur': '${settings.subtitleBlur}',
  'sub-margin-y': '${settings.subtitleMarginY}',
  'sub-color': '#FFFFFF',
  'sub-border-color': '#000000',
  'sub-ass-override': settings.assStyleOverride.mpvValue,
  'blend-subtitles': settings.blendSubtitles ? 'video' : 'no',
};
