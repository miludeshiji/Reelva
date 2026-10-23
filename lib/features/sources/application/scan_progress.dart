import 'package:flutter/foundation.dart';

/// 扫描进度状态对象
@immutable
class ScanProgress {
  const ScanProgress({
    this.visited = 0,
    this.videos = 0,
    this.running = false,
    this.cancelled = false,
    this.error,
  });

  final int visited;
  final int videos;
  final bool running;
  final bool cancelled;
  final String? error;

  ScanProgress copyWith({
    int? visited,
    int? videos,
    bool? running,
    bool? cancelled,
    String? error,
    bool clearError = false,
  }) {
    return ScanProgress(
      visited: visited ?? this.visited,
      videos: videos ?? this.videos,
      running: running ?? this.running,
      cancelled: cancelled ?? this.cancelled,
      error: clearError ? null : (error ?? this.error),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ScanProgress &&
          runtimeType == other.runtimeType &&
          visited == other.visited &&
          videos == other.videos &&
          running == other.running &&
          cancelled == other.cancelled &&
          error == other.error;

  @override
  int get hashCode => Object.hash(visited, videos, running, cancelled, error);

  @override
  String toString() =>
      'ScanProgress(visited: $visited, videos: $videos, running: $running, cancelled: $cancelled, error: $error)';
}
