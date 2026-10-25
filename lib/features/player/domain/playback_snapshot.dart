import 'package:flutter/foundation.dart';

/// 播放器运行状态枚举
enum PlaybackStatus {
  /// 空闲状态（初始或已停止）
  idle,

  /// 正在解析（如解析 content:// 或预解析地址）
  resolving,

  /// 正在打开媒体
  opening,

  /// 正在缓冲网络/文件数据
  buffering,

  /// 正常播放中
  playing,

  /// 已暂停
  paused,

  /// 播放已结束
  completed,

  /// 发生不可恢复或终态播放错误
  error,
}

/// 媒体轨道描述值对象（音频/字幕）
@immutable
class PlaybackTrack {
  const PlaybackTrack({required this.id, required this.label});

  /// 轨道唯一标识（如底层索引、'auto' 或 'no'/'off'）
  final String id;

  /// 用户可读的友好轨道名称（如 "英语 (aac)" 或 "简体中文"）
  final String label;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PlaybackTrack &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          label == other.label;

  @override
  int get hashCode => Object.hash(id, label);

  @override
  String toString() => 'PlaybackTrack(id: $id, label: $label)';
}

/// 播放器瞬时状态快照（不可变）
@immutable
class PlaybackSnapshot {
  const PlaybackSnapshot({
    this.status = PlaybackStatus.idle,
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.buffered = Duration.zero,
    this.volume = 100.0,
    this.rate = 1.0,
    this.videoWidth = 0,
    this.videoHeight = 0,
    this.errorMessage,
    this.audioTracks = const [],
    this.subtitleTracks = const [],
    this.audioTrackId,
    this.subtitleTrackId,
    this.progressErrorMessage,
  });

  /// 当前播放状态
  final PlaybackStatus status;

  /// 当前播放进度
  final Duration position;

  /// 媒体总时长
  final Duration duration;

  /// 当前已缓冲时长
  final Duration buffered;

  /// 播放音量，范围 0..100
  final double volume;

  /// 播放倍速，默认 1.0
  final double rate;

  /// 按像素比例和旋转信息修正后的视频显示尺寸；未知时为 0。
  final int videoWidth;
  final int videoHeight;

  /// 用户友好的安全中文错误信息（不包含敏感凭据或裸 URL）
  final String? errorMessage;

  /// 可用音频轨道列表
  final List<PlaybackTrack> audioTracks;

  /// 可用字幕轨道列表
  final List<PlaybackTrack> subtitleTracks;

  /// 当前选中的音频轨道 ID
  final String? audioTrackId;

  /// 当前选中的字幕轨道 ID
  final String? subtitleTrackId;

  /// 播放进度保存/恢复非致命错误提示信息（如存储异常）
  final String? progressErrorMessage;

  /// 便捷判断当前是否正处于活跃播放或缓冲播放状态
  ///
  /// 涵盖 [PlaybackStatus.playing] 与活跃缓冲 [PlaybackStatus.buffering]，
  /// 方便 UI 控制栏在网络卡顿时呈现暂停控件允许用户主动暂停。
  bool get isPlaying =>
      status == PlaybackStatus.playing || status == PlaybackStatus.buffering;

  /// 返回一个更新指定字段的新快照
  PlaybackSnapshot copyWith({
    PlaybackStatus? status,
    Duration? position,
    Duration? duration,
    Duration? buffered,
    double? volume,
    double? rate,
    int? videoWidth,
    int? videoHeight,
    String? Function()? errorMessage,
    List<PlaybackTrack>? audioTracks,
    List<PlaybackTrack>? subtitleTracks,
    String? Function()? audioTrackId,
    String? Function()? subtitleTrackId,
    String? Function()? progressErrorMessage,
  }) {
    return PlaybackSnapshot(
      status: status ?? this.status,
      position: position ?? this.position,
      duration: duration ?? this.duration,
      buffered: buffered ?? this.buffered,
      volume: volume ?? this.volume,
      rate: rate ?? this.rate,
      videoWidth: videoWidth ?? this.videoWidth,
      videoHeight: videoHeight ?? this.videoHeight,
      errorMessage: errorMessage != null ? errorMessage() : this.errorMessage,
      audioTracks: audioTracks ?? this.audioTracks,
      subtitleTracks: subtitleTracks ?? this.subtitleTracks,
      audioTrackId: audioTrackId != null ? audioTrackId() : this.audioTrackId,
      subtitleTrackId: subtitleTrackId != null
          ? subtitleTrackId()
          : this.subtitleTrackId,
      progressErrorMessage: progressErrorMessage != null
          ? progressErrorMessage()
          : this.progressErrorMessage,
    );
  }

  @override
  String toString() {
    return 'PlaybackSnapshot(status: $status, pos: $position, dur: $duration, '
        'buf: $buffered, vol: $volume, rate: $rate'
        '${errorMessage != null ? ', err: $errorMessage' : ''}'
        '${audioTracks.isNotEmpty ? ', audioTracks: $audioTracks' : ''}'
        '${subtitleTracks.isNotEmpty ? ', subtitleTracks: $subtitleTracks' : ''}'
        '${audioTrackId != null ? ', audioTrackId: $audioTrackId' : ''}'
        '${subtitleTrackId != null ? ', subtitleTrackId: $subtitleTrackId' : ''}'
        '${progressErrorMessage != null ? ', progressErr: $progressErrorMessage' : ''})';
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PlaybackSnapshot &&
          runtimeType == other.runtimeType &&
          status == other.status &&
          position == other.position &&
          duration == other.duration &&
          buffered == other.buffered &&
          volume == other.volume &&
          rate == other.rate &&
          videoWidth == other.videoWidth &&
          videoHeight == other.videoHeight &&
          errorMessage == other.errorMessage &&
          listEquals(audioTracks, other.audioTracks) &&
          listEquals(subtitleTracks, other.subtitleTracks) &&
          audioTrackId == other.audioTrackId &&
          subtitleTrackId == other.subtitleTrackId &&
          progressErrorMessage == other.progressErrorMessage;

  @override
  int get hashCode => Object.hash(
    status,
    position,
    duration,
    buffered,
    volume,
    rate,
    videoWidth,
    videoHeight,
    errorMessage,
    Object.hashAll(audioTracks),
    Object.hashAll(subtitleTracks),
    audioTrackId,
    subtitleTrackId,
    progressErrorMessage,
  );
}
