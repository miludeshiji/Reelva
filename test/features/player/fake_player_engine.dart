import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:reelva/features/player/application/playback_session.dart';
import 'package:reelva/features/player/domain/playback_resource.dart';
import 'package:reelva/features/player/domain/playback_snapshot.dart';
import 'package:reelva/features/player/domain/player_engine.dart';
import 'package:reelva/features/player/domain/player_shortcuts.dart';

/// 测试专用的虚假播放器引擎
///
/// 记录所有方法调用次数及最后参数，支持通过 [emit] 主动推送状态快照。
class FakePlayerEngine implements PlayerEngine {
  FakePlayerEngine({
    PlaybackSnapshot initialSnapshot = const PlaybackSnapshot(),
  }) : _snapshot = initialSnapshot;

  PlaybackSnapshot _snapshot;
  final StreamController<PlaybackSnapshot> _controller =
      StreamController<PlaybackSnapshot>.broadcast();

  bool isDisposed = false;
  int openCount = 0;
  int playCount = 0;
  int pauseCount = 0;
  int stopCount = 0;
  int seekCount = 0;
  int setRateCount = 0;
  int setVolumeCount = 0;
  final shortcutActions = <PlayerShortcutAction>[];
  int setAudioTrackCount = 0;
  int setSubtitleTrackCount = 0;
  int disposeCount = 0;

  PlaybackResource? lastOpenedResource;
  Duration? lastResumeAt;
  Duration? lastSeekPosition;
  double? lastRate;
  double? lastVolume;
  String? lastAudioTrackId;
  String? lastSubtitleTrackId;

  @override
  PlaybackSnapshot get snapshot => _snapshot;

  @override
  Stream<PlaybackSnapshot> get snapshots => _controller.stream;

  void emit(PlaybackSnapshot next) {
    _snapshot = next;
    if (!_controller.isClosed) {
      _controller.add(next);
    }
  }

  @override
  Future<void> open(PlaybackResource resource, {Duration? resumeAt}) async {
    openCount++;
    lastOpenedResource = resource;
    lastResumeAt = resumeAt;
    emit(
      _snapshot.copyWith(
        status: PlaybackStatus.playing,
        position: resumeAt ?? Duration.zero,
        errorMessage: () => null,
      ),
    );
  }

  @override
  Future<void> play() async {
    playCount++;
    emit(_snapshot.copyWith(status: PlaybackStatus.playing));
  }

  @override
  Future<void> pause() async {
    pauseCount++;
    emit(_snapshot.copyWith(status: PlaybackStatus.paused));
  }

  @override
  Future<void> seek(Duration position) async {
    seekCount++;
    lastSeekPosition = position;
    emit(_snapshot.copyWith(position: position));
  }

  @override
  Future<void> setRate(double rate) async {
    setRateCount++;
    lastRate = rate;
    emit(_snapshot.copyWith(rate: rate));
  }

  @override
  Future<void> setVolume(double volume) async {
    setVolumeCount++;
    lastVolume = volume;
    emit(_snapshot.copyWith(volume: volume));
  }

  @override
  Future<void> setAudioTrack(String id) async {
    setAudioTrackCount++;
    lastAudioTrackId = id;
    emit(_snapshot.copyWith(audioTrackId: () => id));
  }

  @override
  Future<void> setSubtitleTrack(String id) async {
    setSubtitleTrackCount++;
    lastSubtitleTrackId = id;
    emit(_snapshot.copyWith(subtitleTrackId: () => id));
  }

  @override
  Future<void> stop() async {
    stopCount++;
    emit(
      _snapshot.copyWith(status: PlaybackStatus.idle, position: Duration.zero),
    );
  }

  @override
  Future<void> executeShortcut(PlayerShortcutAction action) async =>
      shortcutActions.add(action);

  @override
  Future<void> dispose() async {
    disposeCount++;
    isDisposed = true;
    await _controller.close();
  }
}

/// 创建带有测试静态画面的虚假播放会话
PlaybackSession createFakeSession({
  FakePlayerEngine? engine,
  WidgetBuilder? videoBuilder,
}) {
  final eng = engine ?? FakePlayerEngine();
  return PlaybackSession(
    engine: eng,
    videoBuilder:
        videoBuilder ??
        (context) => Container(
          color: const Color(0xFF1E1E1E),
          alignment: Alignment.center,
          child: const Text(
            'FAKE VIDEO SURFACE',
            style: TextStyle(color: Color(0xFF888888)),
          ),
        ),
  );
}
