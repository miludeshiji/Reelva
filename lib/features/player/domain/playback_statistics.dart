import 'package:flutter/foundation.dart';

@immutable
class PlaybackStatistics {
  const PlaybackStatistics({
    this.videoCodec,
    this.width,
    this.height,
    this.frameRate,
    this.pixelFormat,
    this.colorMatrix,
    this.colorPrimaries,
    this.colorTransfer,
    this.hardwareDecoder,
    this.videoBitrate,
    this.droppedFrames,
    this.decoderDroppedFrames,
    this.audioCodec,
    this.audioSampleRate,
    this.audioChannels,
    this.audioBitrate,
    this.audioVideoSync,
    this.cacheSeconds,
    this.cacheBytes,
    this.cacheSpeed,
  });

  final String? videoCodec;
  final int? width;
  final int? height;
  final double? frameRate;
  final String? pixelFormat;
  final String? colorMatrix;
  final String? colorPrimaries;
  final String? colorTransfer;
  final String? hardwareDecoder;
  final double? videoBitrate;
  final int? droppedFrames;
  final int? decoderDroppedFrames;
  final String? audioCodec;
  final int? audioSampleRate;
  final String? audioChannels;
  final double? audioBitrate;
  final double? audioVideoSync;
  final double? cacheSeconds;
  final int? cacheBytes;
  final double? cacheSpeed;
}
