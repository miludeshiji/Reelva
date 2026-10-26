import 'dart:async';

import 'package:media_kit/media_kit.dart';

/// 用于单元测试的 [PlatformPlayer] 测试替身
///
/// 实现底层 [PlatformPlayer] 边界，直接驱动官方 `Player(platformPlayer: ...)`
class TestPlatformPlayer extends PlatformPlayer {
  TestPlatformPlayer({super.configuration = const PlayerConfiguration()});

  Playable? lastOpened;
  Duration? lastResumeAt;
  Duration? lastSeek;
  double? lastRate;
  double? lastVolume;
  bool stopCalled = false;
  bool disposeCalled = false;

  AudioTrack? lastAudioTrack;
  SubtitleTrack? lastSubtitleTrack;
  Future<void> Function(AudioTrack track)? onSetAudioTrack;
  Future<void> Function(SubtitleTrack track)? onSetSubtitleTrack;
  final List<String> callLog = [];
  Future<void> Function(Playable playable)? onOpen;
  Future<void> Function()? onPlay;
  Future<void> Function()? onPause;
  Future<void> Function(Duration position)? onSeek;
  Future<void> Function(double rate)? onSetRate;
  Future<void> Function(double volume)? onSetVolume;
  Future<void> Function()? onStop;
  Future<void> Function()? onDispose;

  @override
  Future<void> open(Playable playable, {bool play = true}) async {
    callLog.add('player.open');
    lastOpened = playable;
    // media_kit NativePlayer.open 在加载新媒体前通过 stop 重置文件状态。
    state = state.copyWith(
      position: Duration.zero,
      duration: Duration.zero,
      completed: false,
      videoParams: const VideoParams(),
    );
    final handler = onOpen;
    if (handler != null) {
      await handler(playable);
    }
    state = state.copyWith(playing: play);
    playingController.add(play);
  }

  @override
  Future<void> play() async {
    callLog.add('player.play');
    final handler = onPlay;
    if (handler != null) {
      await handler();
    }
    state = state.copyWith(playing: true);
    playingController.add(true);
  }

  @override
  Future<void> pause() async {
    callLog.add('player.pause');
    final handler = onPause;
    if (handler != null) {
      await handler();
    }
    state = state.copyWith(playing: false);
    playingController.add(false);
  }

  @override
  Future<void> seek(Duration duration) async {
    callLog.add('player.seek');
    lastSeek = duration;
    final handler = onSeek;
    if (handler != null) {
      await handler(duration);
    }
    state = state.copyWith(position: duration);
    positionController.add(duration);
  }

  @override
  Future<void> setRate(double rate) async {
    callLog.add('player.setRate');
    lastRate = rate;
    final handler = onSetRate;
    if (handler != null) {
      await handler(rate);
    }
    state = state.copyWith(rate: rate);
    rateController.add(rate);
  }

  @override
  Future<void> setVolume(double volume) async {
    callLog.add('player.setVolume');
    lastVolume = volume;
    final handler = onSetVolume;
    if (handler != null) {
      await handler(volume);
    }
    state = state.copyWith(volume: volume);
    volumeController.add(volume);
  }

  @override
  Future<void> setAudioTrack(AudioTrack track) async {
    callLog.add('player.setAudioTrack');
    lastAudioTrack = track;
    final handler = onSetAudioTrack;
    if (handler != null) {
      await handler(track);
    }
    state = state.copyWith(track: state.track.copyWith(audio: track));
    trackController.add(state.track);
  }

  @override
  Future<void> setSubtitleTrack(SubtitleTrack track) async {
    callLog.add('player.setSubtitleTrack');
    lastSubtitleTrack = track;
    final handler = onSetSubtitleTrack;
    if (handler != null) {
      await handler(track);
    }
    state = state.copyWith(track: state.track.copyWith(subtitle: track));
    trackController.add(state.track);
  }

  @override
  Future<void> stop() async {
    callLog.add('player.stop');
    stopCalled = true;
    final handler = onStop;
    if (handler != null) {
      await handler();
    }
    state = state.copyWith(playing: false, position: Duration.zero);
    playingController.add(false);
    positionController.add(Duration.zero);
  }

  @override
  Future<void> dispose() async {
    callLog.add('player.dispose');
    disposeCalled = true;
    final handler = onDispose;
    if (handler != null) {
      await handler();
    }
    await super.dispose();
  }

  void emitDuration(Duration duration) {
    state = state.copyWith(duration: duration);
    durationController.add(duration);
  }

  void emitVideoParams(VideoParams params) {
    state = state.copyWith(videoParams: params);
    videoParamsController.add(params);
  }

  /// 重放旧文件排队的通知，保留当前文件的公开状态。
  void emitQueuedDuration(Duration duration) {
    durationController.add(duration);
  }

  void emitPosition(Duration position) {
    state = state.copyWith(position: position);
    positionController.add(position);
  }

  void emitQueuedPosition(Duration position) {
    positionController.add(position);
  }

  void emitBuffering(bool buffering) {
    state = state.copyWith(buffering: buffering);
    bufferingController.add(buffering);
  }

  void emitCompleted(bool completed) {
    state = state.copyWith(completed: completed);
    completedController.add(completed);
  }

  void emitError(String error) {
    errorController.add(error);
  }

  void emitLog(PlayerLog log) {
    logController.add(log);
  }

  void emitTracks(Tracks tracks) {
    state = state.copyWith(tracks: tracks);
    tracksController.add(tracks);
  }

  void emitTrack(Track track) {
    state = state.copyWith(track: track);
    trackController.add(track);
  }
}
