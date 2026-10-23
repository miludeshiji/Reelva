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
    this.errorMessage,
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

  /// 用户友好的安全中文错误信息（不包含敏感凭据或裸 URL）
  final String? errorMessage;

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
    String? Function()? errorMessage,
  }) {
    return PlaybackSnapshot(
      status: status ?? this.status,
      position: position ?? this.position,
      duration: duration ?? this.duration,
      buffered: buffered ?? this.buffered,
      volume: volume ?? this.volume,
      rate: rate ?? this.rate,
      errorMessage: errorMessage != null ? errorMessage() : this.errorMessage,
    );
  }

  @override
  String toString() {
    return 'PlaybackSnapshot(status: $status, pos: $position, dur: $duration, '
        'buf: $buffered, vol: $volume, rate: $rate'
        '${errorMessage != null ? ', err: $errorMessage' : ''})';
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
          errorMessage == other.errorMessage;

  @override
  int get hashCode => Object.hash(
    status,
    position,
    duration,
    buffered,
    volume,
    rate,
    errorMessage,
  );
}
