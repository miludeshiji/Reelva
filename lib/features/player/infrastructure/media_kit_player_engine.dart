import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../../../core/logging/app_logger.dart';
import '../application/playback_session.dart';
import '../domain/playback_resource.dart';
import '../domain/playback_snapshot.dart';
import '../domain/player_engine.dart';
import 'android_media_documents.dart';

/// 初始化底层 media_kit 原生库（全局单次）
void initializeMediaKit({String? libmpv}) {
  MediaKit.ensureInitialized(libmpv: libmpv);
}

/// 创建基于 media_kit 的播放会话
PlaybackSession createMediaKitSession({
  Player? player,
  AndroidMediaDocuments? documents,
}) {
  final engine = MediaKitPlayerEngine(player: player, documents: documents);
  return PlaybackSession(
    engine: engine,
    videoBuilder: (context) => engine.buildVideoView(context),
  );
}

/// media_kit 播放器领域适配器
class MediaKitPlayerEngine implements PlayerEngine {
  MediaKitPlayerEngine({Player? player, AndroidMediaDocuments? documents})
    : _player =
          player ??
          Player(
            configuration: const PlayerConfiguration(
              vo: 'null',
              osc: false,
              pitch: false,
              title: 'Reelva',
              logLevel: MPVLogLevel.error,
            ),
          ),
      _documents = documents ?? const AndroidMediaDocuments() {
    _initSubscriptions();
  }

  final Player _player;
  final AndroidMediaDocuments _documents;

  VideoController? _videoController;
  final StreamController<PlaybackSnapshot> _snapshotController =
      StreamController<PlaybackSnapshot>.broadcast();

  PlaybackSnapshot _snapshot = const PlaybackSnapshot();
  final List<StreamSubscription<dynamic>> _subscriptions = [];

  int? _activeDescriptor;
  int _openEpoch = 0;
  bool _disposed = false;
  bool _isOpening = false;
  Duration? _pendingResumeAt;
  Future<void>? _disposeFuture;
  Future<void> _operationQueue = Future<void>.value();

  @override
  PlaybackSnapshot get snapshot => _snapshot;

  @override
  Stream<PlaybackSnapshot> get snapshots => _snapshotController.stream;

  Widget buildVideoView(BuildContext context) {
    if (_disposed) return const SizedBox.shrink();
    _videoController ??= VideoController(
      _player,
      configuration: const VideoControllerConfiguration(
        enableHardwareAcceleration: true,
      ),
    );
    return Video(
      controller: _videoController!,
      controls: null,
      pauseUponEnteringBackgroundMode: false,
      resumeUponEnteringForegroundMode: false,
    );
  }

  Future<T> _enqueue<T>(Future<T> Function() action) {
    final completer = Completer<T>();
    _operationQueue = _operationQueue
        .catchError((Object e, StackTrace st) {
          AppLogger.instance.error('操作队列前置任务异常', error: e, stackTrace: st);
        })
        .then((_) async {
          try {
            final result = await action();
            completer.complete(result);
          } catch (e, st) {
            completer.completeError(e, st);
          }
        });
    return completer.future;
  }

  bool get _isEventIgnored =>
      _disposed ||
      _snapshot.status == PlaybackStatus.idle ||
      _snapshot.status == PlaybackStatus.resolving ||
      _snapshot.status == PlaybackStatus.error;

  PlaybackStatus _computeActiveStatus() {
    if (_isOpening) {
      return PlaybackStatus.opening;
    }
    if (_player.state.completed) {
      return PlaybackStatus.completed;
    }
    if (_player.state.playing) {
      return _player.state.buffering
          ? PlaybackStatus.buffering
          : PlaybackStatus.playing;
    }
    return PlaybackStatus.paused;
  }

  void _syncStatus() {
    if (_isEventIgnored) return;
    _updateSnapshot(_snapshot.copyWith(status: _computeActiveStatus()));
  }

  void _initSubscriptions() {
    _subscriptions.add(_player.stream.playing.listen((_) => _syncStatus()));
    _subscriptions.add(_player.stream.buffering.listen((_) => _syncStatus()));
    _subscriptions.add(_player.stream.completed.listen((_) => _syncStatus()));

    _subscriptions.add(
      _player.stream.position.listen((pos) {
        if (_isEventIgnored || _isOpening) return;
        _updateSnapshot(
          _snapshot.copyWith(status: _computeActiveStatus(), position: pos),
        );
      }),
    );

    _subscriptions.add(
      _player.stream.duration.listen((dur) {
        if (_isEventIgnored || _isOpening) return;
        _updateSnapshot(
          _snapshot.copyWith(status: _computeActiveStatus(), duration: dur),
        );
        _checkResumeRange(dur);
      }),
    );

    _subscriptions.add(
      _player.stream.buffer.listen((buf) {
        if (_isEventIgnored || _isOpening) return;
        _updateSnapshot(_snapshot.copyWith(buffered: buf));
      }),
    );

    _subscriptions.add(
      _player.stream.tracks.listen((tracks) {
        if (_disposed) return;
        _syncTracks(tracks, _player.state.track);
      }),
    );

    _subscriptions.add(
      _player.stream.track.listen((track) {
        if (_disposed) return;
        _syncTracks(_player.state.tracks, track);
      }),
    );

    _subscriptions.add(
      _player.stream.volume.listen((vol) {
        if (_disposed) return;
        _updateSnapshot(_snapshot.copyWith(volume: vol));
      }),
    );

    _subscriptions.add(
      _player.stream.rate.listen((r) {
        if (_disposed) return;
        _updateSnapshot(_snapshot.copyWith(rate: r));
      }),
    );

    _subscriptions.add(
      _player.stream.error.listen((err) {
        if (_isEventIgnored) return;
        AppLogger.instance.error('底层播放异常', error: err);
        _updateSnapshot(
          _snapshot.copyWith(
            status: PlaybackStatus.error,
            errorMessage: () => _safeErrorMessage(err),
          ),
        );
      }),
    );
  }

  void _checkResumeRange(Duration dur) {
    if (dur <= Duration.zero) return;
    final resumeAt = _pendingResumeAt;
    if (resumeAt != null) {
      _pendingResumeAt = null;
      if (resumeAt >= dur || resumeAt < Duration.zero) {
        seek(Duration.zero);
      }
    }
  }

  void _syncTracks(Tracks tracks, Track track) {
    if (_disposed || _isEventIgnored || _isOpening) return;
    final audioList = tracks.audio.map((t) {
      return PlaybackTrack(
        id: t.id,
        label: _formatTrackLabel(t.id, t.title, t.language, isSubtitle: false),
      );
    }).toList();

    final subtitleList = tracks.subtitle.map((t) {
      return PlaybackTrack(
        id: t.id,
        label: _formatTrackLabel(t.id, t.title, t.language, isSubtitle: true),
      );
    }).toList();

    _updateSnapshot(
      _snapshot.copyWith(
        audioTracks: audioList,
        subtitleTracks: subtitleList,
        audioTrackId: () => track.audio.id,
        subtitleTrackId: () => track.subtitle.id,
      ),
    );
  }

  static String _formatTrackLabel(
    String id,
    String? title,
    String? language, {
    required bool isSubtitle,
  }) {
    if (id == 'auto') return '自动';
    if (id == 'no') return isSubtitle ? '关闭字幕' : '关闭音频';
    final parts = <String>[];
    if (title != null && title.trim().isNotEmpty) {
      parts.add(title.trim());
    }
    if (language != null && language.trim().isNotEmpty) {
      parts.add(language.trim());
    }
    if (parts.isEmpty) {
      return isSubtitle ? '字幕 $id' : '音轨 $id';
    }
    return parts.join(' - ');
  }

  void _updateSnapshot(PlaybackSnapshot next) {
    if (_disposed) return;
    if (_snapshot == next) return;
    _snapshot = next;
    if (!_snapshotController.isClosed) {
      _snapshotController.add(next);
    }
  }

  Future<void> _closeDescriptor(int fd) async {
    try {
      await _documents.close(fd);
    } catch (e, st) {
      AppLogger.instance.error('关闭文件描述符失败', error: e, stackTrace: st);
    }
  }

  Future<void> _closeActiveDescriptor() async {
    final fd = _activeDescriptor;
    _activeDescriptor = null;
    if (fd != null) {
      await _closeDescriptor(fd);
    }
  }

  @override
  Future<void> open(PlaybackResource resource, {Duration? resumeAt}) {
    if (_disposed) return Future.value();
    final epoch = ++_openEpoch;
    _isOpening = true;
    _pendingResumeAt = resumeAt;

    // 新 open 立即重置 UI 状态避免旧画面残留
    _updateSnapshot(
      _snapshot.copyWith(
        status: resource.uri.isScheme('content')
            ? PlaybackStatus.resolving
            : PlaybackStatus.opening,
        position: resumeAt ?? Duration.zero,
        duration: Duration.zero,
        buffered: Duration.zero,
        errorMessage: () => null,
        audioTracks: const [],
        subtitleTracks: const [],
        audioTrackId: () => null,
        subtitleTrackId: () => null,
      ),
    );

    return _enqueue(() async {
      if (_disposed || epoch != _openEpoch) {
        _isOpening = false;
        return;
      }

      // 切换前先停止前代播放，再安全关闭旧描述符（保证底层已停用 FD）
      try {
        await _player.stop();
      } catch (e, st) {
        AppLogger.instance.error('停止旧媒体失败', error: e, stackTrace: st);
      }
      await _closeActiveDescriptor();

      if (_disposed || epoch != _openEpoch) {
        _isOpening = false;
        return;
      }

      int? openedFd;
      String mediaTarget;
      if (resource.uri.isScheme('content')) {
        try {
          openedFd = await _documents.openRead(resource.uri);
        } catch (e, st) {
          _isOpening = false;
          if (_disposed || epoch != _openEpoch) return;
          AppLogger.instance.error('打开媒体描述符失败', error: e, stackTrace: st);
          _updateSnapshot(
            _snapshot.copyWith(
              status: PlaybackStatus.error,
              errorMessage: () => _safeErrorMessage(e),
            ),
          );
          return;
        }

        if (_disposed || epoch != _openEpoch) {
          _isOpening = false;
          await _closeDescriptor(openedFd);
          return;
        }
        mediaTarget = 'fd://$openedFd';
      } else {
        mediaTarget = resource.uri.toString();
      }

      if (_disposed || epoch != _openEpoch) {
        _isOpening = false;
        if (openedFd != null) await _closeDescriptor(openedFd);
        return;
      }

      _updateSnapshot(
        _snapshot.copyWith(
          status: PlaybackStatus.opening,
          errorMessage: () => null,
        ),
      );

      final media = Media(
        mediaTarget,
        httpHeaders: resource.httpHeaders.isNotEmpty
            ? resource.httpHeaders
            : null,
        start: resumeAt,
      );

      try {
        // 先以 play: false 打开，等待底层就绪后再次确认 epoch
        await _player.open(media, play: false);
      } catch (e, st) {
        _isOpening = false;
        if (_disposed || epoch != _openEpoch) {
          if (openedFd != null) await _closeDescriptor(openedFd);
          return;
        }
        AppLogger.instance.error('打开底层媒体失败', error: e, stackTrace: st);
        try {
          await _player.stop();
        } catch (stopErr, stopSt) {
          AppLogger.instance.error(
            '异常后停止播放器失败',
            error: stopErr,
            stackTrace: stopSt,
          );
        }
        if (openedFd != null) await _closeDescriptor(openedFd);
        _updateSnapshot(
          _snapshot.copyWith(
            status: PlaybackStatus.error,
            errorMessage: () => _safeErrorMessage(e),
          ),
        );
        return;
      }

      if (_disposed || epoch != _openEpoch) {
        _isOpening = false;
        try {
          await _player.stop();
        } catch (stopErr, stopSt) {
          AppLogger.instance.error(
            '取消过时请求停止失败',
            error: stopErr,
            stackTrace: stopSt,
          );
        }
        if (openedFd != null) await _closeDescriptor(openedFd);
        return;
      }

      _activeDescriptor = openedFd;
      _isOpening = false;
      try {
        await _player.play();
      } catch (e, st) {
        AppLogger.instance.error('底层起播异常', error: e, stackTrace: st);
        _updateSnapshot(
          _snapshot.copyWith(
            status: PlaybackStatus.error,
            errorMessage: () => _safeErrorMessage(e),
          ),
        );
        return;
      }
      _syncStatus();
      _syncTracks(_player.state.tracks, _player.state.track);
      _checkResumeRange(_player.state.duration);
    });
  }

  @override
  Future<void> play() {
    if (_disposed || _snapshot.status == PlaybackStatus.error) {
      return Future.value();
    }
    return _enqueue(() async {
      if (_disposed || _snapshot.status == PlaybackStatus.error) return;
      try {
        await _player.play();
      } catch (e, st) {
        AppLogger.instance.error('底层恢复播放异常', error: e, stackTrace: st);
        _updateSnapshot(
          _snapshot.copyWith(
            status: PlaybackStatus.error,
            errorMessage: () => _safeErrorMessage(e),
          ),
        );
      }
    });
  }

  @override
  Future<void> pause() {
    if (_disposed || _snapshot.status == PlaybackStatus.error) {
      return Future.value();
    }
    return _enqueue(() async {
      if (_disposed || _snapshot.status == PlaybackStatus.error) return;
      try {
        await _player.pause();
      } catch (e, st) {
        AppLogger.instance.error('底层暂停播放异常', error: e, stackTrace: st);
        _updateSnapshot(
          _snapshot.copyWith(
            status: PlaybackStatus.error,
            errorMessage: () => _safeErrorMessage(e),
          ),
        );
      }
    });
  }

  @override
  Future<void> seek(Duration position) {
    if (_disposed || _snapshot.status == PlaybackStatus.error) {
      return Future.value();
    }
    return _enqueue(() async {
      if (_disposed || _snapshot.status == PlaybackStatus.error) return;
      try {
        await _player.seek(position);
      } catch (e, st) {
        AppLogger.instance.error('底层跳转进度异常', error: e, stackTrace: st);
        _updateSnapshot(
          _snapshot.copyWith(
            status: PlaybackStatus.error,
            errorMessage: () => _safeErrorMessage(e),
          ),
        );
      }
    });
  }

  @override
  Future<void> setRate(double rate) {
    if (_disposed) return Future.value();
    return _enqueue(() async {
      if (_disposed) return;
      try {
        await _player.setRate(rate);
      } catch (e, st) {
        AppLogger.instance.error('底层设置倍速异常', error: e, stackTrace: st);
        _updateSnapshot(
          _snapshot.copyWith(
            status: PlaybackStatus.error,
            errorMessage: () => _safeErrorMessage(e),
          ),
        );
      }
    });
  }

  @override
  Future<void> setVolume(double volume) {
    if (_disposed) return Future.value();
    return _enqueue(() async {
      if (_disposed) return;
      try {
        await _player.setVolume(volume);
      } catch (e, st) {
        AppLogger.instance.error('底层设置音量异常', error: e, stackTrace: st);
        _updateSnapshot(
          _snapshot.copyWith(
            status: PlaybackStatus.error,
            errorMessage: () => _safeErrorMessage(e),
          ),
        );
      }
    });
  }

  @override
  Future<void> setAudioTrack(String id) {
    if (_disposed) return Future.value();
    return _enqueue(() async {
      if (_disposed) return;
      try {
        final AudioTrack track;
        if (id == 'auto') {
          track = AudioTrack.auto();
        } else if (id == 'no' || id == 'off') {
          track = AudioTrack.no();
        } else {
          track = _player.state.tracks.audio.firstWhere(
            (t) => t.id == id,
            orElse: () => AudioTrack(id, null, null),
          );
        }
        await _player.setAudioTrack(track);
      } catch (e, st) {
        AppLogger.instance.error('底层设置音频轨道异常', error: e, stackTrace: st);
        _updateSnapshot(
          _snapshot.copyWith(
            status: PlaybackStatus.error,
            errorMessage: () => _safeErrorMessage(e),
          ),
        );
      }
    });
  }

  @override
  Future<void> setSubtitleTrack(String id) {
    if (_disposed) return Future.value();
    return _enqueue(() async {
      if (_disposed) return;
      try {
        final SubtitleTrack track;
        if (id == 'auto') {
          track = SubtitleTrack.auto();
        } else if (id == 'no' || id == 'off') {
          track = SubtitleTrack.no();
        } else {
          track = _player.state.tracks.subtitle.firstWhere(
            (t) => t.id == id,
            orElse: () => SubtitleTrack(id, null, null),
          );
        }
        await _player.setSubtitleTrack(track);
      } catch (e, st) {
        AppLogger.instance.error('底层设置字幕轨道异常', error: e, stackTrace: st);
        _updateSnapshot(
          _snapshot.copyWith(
            status: PlaybackStatus.error,
            errorMessage: () => _safeErrorMessage(e),
          ),
        );
      }
    });
  }

  @override
  Future<void> stop() {
    if (_disposed) return Future.value();
    _openEpoch++;
    _isOpening = false;
    _pendingResumeAt = null;
    _updateSnapshot(
      PlaybackSnapshot(
        status: PlaybackStatus.idle,
        volume: _snapshot.volume,
        rate: _snapshot.rate,
      ),
    );

    return _enqueue(() async {
      try {
        await _player.stop();
      } catch (e, st) {
        AppLogger.instance.error('底层停止播放异常', error: e, stackTrace: st);
      }
      await _closeActiveDescriptor();
    });
  }

  @override
  Future<void> dispose() {
    if (_disposeFuture != null) {
      return _disposeFuture!;
    }
    _disposed = true;
    _isOpening = false;
    _pendingResumeAt = null;
    _openEpoch++;

    _disposeFuture = _enqueue(() async {
      for (final sub in _subscriptions) {
        await sub.cancel();
      }
      _subscriptions.clear();

      try {
        await _player.dispose();
      } catch (e, st) {
        AppLogger.instance.error('释放底层播放器异常', error: e, stackTrace: st);
      }

      await _closeActiveDescriptor();

      if (!_snapshotController.isClosed) {
        await _snapshotController.close();
      }
    });

    return _disposeFuture!;
  }

  static String _safeErrorMessage(Object? error) {
    if (error == null) return '播放发生未知异常';

    if (error is MediaDocumentException) {
      switch (error.code) {
        case 'SECURITY_ERROR':
          return '没有权限访问该媒体文件';
        case 'FILE_NOT_FOUND':
          return '无法打开媒体文件，文件可能已被移动或删除';
        case 'INVALID_SCHEME':
        case 'INVALID_ARGUMENT':
          return '媒体格式不受支持或资源地址无效';
        case 'IO_ERROR':
          return '读取媒体文件发生 I/O 错误';
        default:
          return '访问媒体文档发生异常，请重试';
      }
    }

    final raw = error.toString().toLowerCase();
    if (raw.contains('404') || raw.contains('not found')) {
      return '媒体资源不存在或已失效 (404)';
    }
    if (raw.contains('403') ||
        raw.contains('401') ||
        raw.contains('forbidden') ||
        raw.contains('unauthorized')) {
      return '访问媒体资源被拒绝或权限不足';
    }
    if (raw.contains('connection refused') ||
        raw.contains('network') ||
        raw.contains('failed to connect') ||
        raw.contains('resolve') ||
        raw.contains('host') ||
        raw.contains('socket') ||
        raw.contains('enotfound') ||
        raw.contains('connection reset')) {
      return '网络连接失败，请检查网络设置或媒体地址';
    }
    if (raw.contains('timeout') || raw.contains('timed out')) {
      return '媒体加载超时，请检查网络连接';
    }
    if (raw.contains('format') ||
        raw.contains('demux') ||
        raw.contains('codec') ||
        raw.contains('unsupported') ||
        raw.contains('no demuxer') ||
        raw.contains('could not read header') ||
        raw.contains('invalid data') ||
        raw.contains('corrupt')) {
      return '媒体格式不受支持或文件已损坏';
    }
    if (raw.contains('permission') ||
        raw.contains('access denied') ||
        raw.contains('security')) {
      return '没有权限访问该媒体文件';
    }
    if (raw.contains('no such file') ||
        raw.contains('cannot open file') ||
        raw.contains('file not found')) {
      return '无法打开媒体文件，文件可能已被移动或删除';
    }

    return '媒体播放发生异常，请重试';
  }
}
