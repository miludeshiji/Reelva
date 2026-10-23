import 'package:flutter/foundation.dart';

/// 播放进度关联的目标类型（单个电影作品或剧集中的单集）
enum ProgressTargetType {
  work('work'),
  episode('episode');

  const ProgressTargetType(this.value);
  final String value;

  static ProgressTargetType parse(String value) {
    if (value == 'episode') return ProgressTargetType.episode;
    return ProgressTargetType.work;
  }
}

/// 播放进度领域模型
@immutable
class PlaybackProgress {
  const PlaybackProgress({
    this.id,
    required this.targetType,
    required this.targetId,
    this.workId,
    this.episodeId,
    this.lastFileId,
    required this.position,
    required this.duration,
    this.completed = false,
    required this.updatedAt,
  });

  /// 数据库自增主键（可选）
  final int? id;

  /// 目标类型：'work' 或 'episode'
  final ProgressTargetType targetType;

  /// 目标标识符（workId 或 episodeId）
  final int targetId;

  /// 关联的作品 ID（targetType == work 时非空）
  final int? workId;

  /// 关联的剧集 ID（targetType == episode 时非空）
  final int? episodeId;

  /// 最近一次播放的文件 ID
  final int? lastFileId;

  /// 当前播放进度
  final Duration position;

  /// 媒体总时长
  final Duration duration;

  /// 是否已标记完播
  final bool completed;

  /// 最后更新时间
  final DateTime updatedAt;

  /// 播放进度比例 [0.0..1.0]
  double get progressFraction {
    if (duration.inMilliseconds <= 0) return 0.0;
    final frac = position.inMilliseconds / duration.inMilliseconds;
    return frac.clamp(0.0, 1.0);
  }

  /// 是否视为完播（显式 completed 标记，或播放进度 >= 90% 且时长 > 0）
  bool get isEffectivelyCompleted =>
      completed ||
      (duration > Duration.zero &&
          position.inMilliseconds >= duration.inMilliseconds * 0.90);

  PlaybackProgress copyWith({
    int? id,
    ProgressTargetType? targetType,
    int? targetId,
    int? Function()? workId,
    int? Function()? episodeId,
    int? Function()? lastFileId,
    Duration? position,
    Duration? duration,
    bool? completed,
    DateTime? updatedAt,
  }) {
    return PlaybackProgress(
      id: id ?? this.id,
      targetType: targetType ?? this.targetType,
      targetId: targetId ?? this.targetId,
      workId: workId != null ? workId() : this.workId,
      episodeId: episodeId != null ? episodeId() : this.episodeId,
      lastFileId: lastFileId != null ? lastFileId() : this.lastFileId,
      position: position ?? this.position,
      duration: duration ?? this.duration,
      completed: completed ?? this.completed,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PlaybackProgress &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          targetType == other.targetType &&
          targetId == other.targetId &&
          workId == other.workId &&
          episodeId == other.episodeId &&
          lastFileId == other.lastFileId &&
          position == other.position &&
          duration == other.duration &&
          completed == other.completed &&
          updatedAt == other.updatedAt;

  @override
  int get hashCode => Object.hash(
    id,
    targetType,
    targetId,
    workId,
    episodeId,
    lastFileId,
    position,
    duration,
    completed,
    updatedAt,
  );

  @override
  String toString() =>
      'PlaybackProgress(targetType: $targetType, targetId: $targetId, '
      'pos: $position, dur: $duration, completed: $completed)';
}

/// 继续观看条目（供首页 Continue Watching 展架与外部呈现）
@immutable
class ContinueWatchingEntry {
  const ContinueWatchingEntry({
    required this.workId,
    required this.title,
    this.posterPath,
    this.fileId,
    required this.position,
    required this.duration,
    this.seasonNumber,
    this.episodeNumber,
    this.available = true,
  });

  /// 关联的作品 ID
  final int workId;

  /// 作品或视频主标题
  final String title;

  /// 海报路径
  final String? posterPath;

  /// 推荐播放的媒体文件 ID（优先 lastFile，若不可用则为同目标可用备选；全不可用时保留原文件或 null）
  final int? fileId;

  /// 已播放位置
  final Duration position;

  /// 视频总时长
  final Duration duration;

  /// 季号（电影为 null，剧集为相应季号）
  final int? seasonNumber;

  /// 集号（电影为 null，剧集为相应集号）
  final int? episodeNumber;

  /// 关联文件是否当前可用（如所在媒体源未停用且文件未删除）
  final bool available;

  /// 播放进度百分比 [0.0..1.0]
  double get progressFraction {
    if (duration.inMilliseconds <= 0) return 0.0;
    final frac = position.inMilliseconds / duration.inMilliseconds;
    return frac.clamp(0.0, 1.0);
  }

  ContinueWatchingEntry copyWith({
    int? workId,
    String? title,
    String? Function()? posterPath,
    int? Function()? fileId,
    Duration? position,
    Duration? duration,
    int? Function()? seasonNumber,
    int? Function()? episodeNumber,
    bool? available,
  }) {
    return ContinueWatchingEntry(
      workId: workId ?? this.workId,
      title: title ?? this.title,
      posterPath: posterPath != null ? posterPath() : this.posterPath,
      fileId: fileId != null ? fileId() : this.fileId,
      position: position ?? this.position,
      duration: duration ?? this.duration,
      seasonNumber: seasonNumber != null ? seasonNumber() : this.seasonNumber,
      episodeNumber: episodeNumber != null
          ? episodeNumber()
          : this.episodeNumber,
      available: available ?? this.available,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ContinueWatchingEntry &&
          runtimeType == other.runtimeType &&
          workId == other.workId &&
          title == other.title &&
          posterPath == other.posterPath &&
          fileId == other.fileId &&
          position == other.position &&
          duration == other.duration &&
          seasonNumber == other.seasonNumber &&
          episodeNumber == other.episodeNumber &&
          available == other.available;

  @override
  int get hashCode => Object.hash(
    workId,
    title,
    posterPath,
    fileId,
    position,
    duration,
    seasonNumber,
    episodeNumber,
    available,
  );

  @override
  String toString() =>
      'ContinueWatchingEntry(workId: $workId, title: $title, '
      'fileId: $fileId, pos: $position, dur: $duration, '
      'S: $seasonNumber, E: $episodeNumber, available: $available)';
}
