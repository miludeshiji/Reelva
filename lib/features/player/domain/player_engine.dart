import 'playback_resource.dart';
import 'playback_snapshot.dart';
import 'player_shortcuts.dart';

/// 播放器引擎领域抽象接口
///
/// 定义纯领域播放能力，屏蔽具体底层多媒体引擎实现与 UI 框架依赖。
abstract interface class PlayerEngine {
  /// 获取当前最新的播放状态快照
  PlaybackSnapshot get snapshot;

  /// 状态快照变更流，用于监听播放状态迁移与进度变化
  Stream<PlaybackSnapshot> get snapshots;

  /// 打开指定的播放资源
  ///
  /// 可选传入 [resumeAt] 指定初始起播位置。
  Future<void> open(PlaybackResource resource, {Duration? resumeAt});

  /// 恢复播放
  Future<void> play();

  /// 暂停播放
  Future<void> pause();

  /// 跳转至指定播放进度位置
  Future<void> seek(Duration position);

  /// 设置播放倍速（通常为 0.25..4.0）
  Future<void> setRate(double rate);

  /// 设置播放音量百分比，上限由会话配置决定。
  Future<void> setVolume(double volume);

  /// 切换音频轨道
  Future<void> setAudioTrack(String id);

  /// 切换字幕轨道
  Future<void> setSubtitleTrack(String id);

  /// 执行逐帧、章节、字幕同步及画面调整等原生播放操作。
  Future<void> executeShortcut(PlayerShortcutAction action);

  /// 停止播放并将状态重置为空闲
  Future<void> stop();

  /// 释放引擎所有资源（解构底层播放器、取消事件监听、关闭已分配文件句柄）
  Future<void> dispose();
}
