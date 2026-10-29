import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../../../core/logging/app_logger.dart';
import '../application/playback_session.dart';
import '../domain/playback_resource.dart';
import '../domain/playback_snapshot.dart';
import '../domain/playback_statistics.dart';
import '../domain/player_engine.dart';
import '../domain/player_settings.dart';
import '../domain/player_shortcuts.dart';
import '../domain/subtitle_files.dart';
import 'android_media_documents.dart';
import 'mpv_player_configuration.dart';
import 'mpv_shortcut_commands.dart';

/// 初始化底层 media_kit 原生库（全局单次）
void initializeMediaKit({String? libmpv}) {
  MediaKit.ensureInitialized(libmpv: libmpv);
}

/// 创建基于 media_kit 的播放会话
PlaybackSession createMediaKitSession({
  Player? player,
  AndroidMediaDocuments? documents,
  PlayerSettings? settings,
}) {
  final engine = MediaKitPlayerEngine(
    player: player,
    documents: documents,
    settings: settings,
  );
  return PlaybackSession(
    engine: engine,
    videoBuilder: (context) => engine.buildVideoView(context),
    maxVolume: engine._settings.maxVolume.toDouble(),
  );
}

/// media_kit 播放器领域适配器
class MediaKitPlayerEngine implements PlayerEngine {
  MediaKitPlayerEngine({
    Player? player,
    AndroidMediaDocuments? documents,
    PlayerSettings? settings,
  }) : _settings =
           settings ?? PlayerSettings.defaultsFor(defaultTargetPlatform),
       _documents = documents ?? const AndroidMediaDocuments() {
    _player =
        player ?? Player(configuration: mediaKitPlayerConfiguration(_settings));
    _initSubscriptions();
  }

  late final Player _player;
  final PlayerSettings _settings;
  final AndroidMediaDocuments _documents;

  VideoController? _videoController;
  final StreamController<PlaybackSnapshot> _snapshotController =
      StreamController<PlaybackSnapshot>.broadcast();

  PlaybackSnapshot _snapshot = const PlaybackSnapshot();
  final List<StreamSubscription<dynamic>> _subscriptions = [];

  int? _activeDescriptor;
  Future<void> Function()? _activeRelease;
  StreamSubscription<String>? _resourceErrorSub;
  int _openEpoch = 0;
  bool _disposed = false;
  bool _isOpening = false;
  Duration? _pendingResumeAt;
  Duration? _recoverableErrorPosition;
  Future<void>? _disposeFuture;
  Future<void> _operationQueue = Future<void>.value();
  final _subtitleLeases =
      <Uri, ({PlaybackResource resource, int? descriptor, String trackId})>{};
  int _subtitleSelectionVersion = 0;
  bool _addingSubtitle = false;
  final _subtitleLogErrors = <String>{};

  @override
  PlaybackSnapshot get snapshot => _snapshot;

  @override
  Stream<PlaybackSnapshot> get snapshots => _snapshotController.stream;

  Widget buildVideoView(BuildContext context) {
    if (_disposed) return const SizedBox.shrink();
    _videoController ??= VideoController(
      _player,
      configuration: mediaKitVideoConfiguration(_settings),
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
    _subscriptions.add(_player.stream.videoParams.listen(_syncVideoSize));

    _subscriptions.add(
      _player.stream.position.listen((pos) {
        if (_disposed || _isOpening) return;
        final errorPosition = _recoverableErrorPosition;
        // media_kit 的错误流也包含可恢复的解码日志，实际进度推进才能证明恢复。
        if (_snapshot.status == PlaybackStatus.error &&
            errorPosition != null &&
            pos > errorPosition &&
            pos == _player.state.position &&
            _player.state.playing &&
            !_player.state.buffering &&
            !_player.state.completed) {
          AppLogger.instance.info('播放进度已推进，从可恢复错误中恢复', module: '播放器');
          _recoverableErrorPosition = null;
          _updateSnapshot(
            _snapshot.copyWith(
              status: _computeActiveStatus(),
              position: pos,
              duration: _player.state.duration,
              buffered: _player.state.buffer,
              errorMessage: () => null,
            ),
          );
          _syncTracks(_player.state.tracks, _player.state.track);
          _syncVideoSize(_player.state.videoParams);
          _checkResumeRange(_player.state.duration);
          return;
        }
        if (_isEventIgnored) return;
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
      _player.stream.log.listen((log) {
        // sub-add 的文件读取错误只属于外挂字幕；解码器错误仍走视频错误处理。
        if (_addingSubtitle &&
            log.level == 'error' &&
            (const ['file', 'stream', 'ffmpeg'].contains(log.prefix) ||
                (log.prefix == 'cplayer' &&
                    RegExp(
                      r'subtitle|external file',
                      caseSensitive: false,
                    ).hasMatch(log.text)))) {
          _subtitleLogErrors.add(log.text);
        }
      }),
    );
    _subscriptions.add(
      _player.stream.error.listen((err) {
        // 日志流会去重，错误流不会；重复选择坏字幕时仍需识别相同诊断。
        if (_addingSubtitle && _subtitleLogErrors.contains(err)) return;
        if (_isEventIgnored) return;
        AppLogger.instance.error('底层播放异常', error: err);
        _setPlaybackError(_safeErrorMessage(err), recoverable: true);
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

  void _syncVideoSize(VideoParams params) {
    if (_isEventIgnored || _isOpening) return;
    final width = params.dw ?? params.w ?? 0;
    final height = params.dh ?? params.h ?? 0;
    if (width <= 0 || height <= 0) return;
    final rotated = (params.rotate ?? 0) % 180 == 90;
    _updateSnapshot(
      _snapshot.copyWith(
        videoWidth: rotated ? height : width,
        videoHeight: rotated ? width : height,
      ),
    );
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

  void _setPlaybackError(String message, {bool recoverable = false}) {
    _recoverableErrorPosition = recoverable
        ? (_isOpening ? _snapshot.position : _player.state.position)
        : null;
    _updateSnapshot(
      _snapshot.copyWith(
        status: PlaybackStatus.error,
        errorMessage: () => message,
      ),
    );
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

  Future<void> _releaseActiveLease() async {
    final sub = _resourceErrorSub;
    _resourceErrorSub = null;
    await sub?.cancel();

    final release = _activeRelease;
    _activeRelease = null;
    if (release != null) {
      try {
        await release();
      } catch (e, st) {
        AppLogger.instance.error('释放播放资源失败', error: e, stackTrace: st);
      }
    }
  }

  Future<void> _releaseLease(PlaybackResource lease) async {
    final release = lease.release;
    if (release != null) {
      try {
        await release();
      } catch (e, st) {
        AppLogger.instance.error('释放未激活播放资源失败', error: e, stackTrace: st);
      }
    }
  }

  Future<void> _releaseSubtitles() async {
    final leases = _subtitleLeases.values.toList();
    _subtitleLeases.clear();
    for (final lease in leases) {
      if (lease.descriptor != null) await _closeDescriptor(lease.descriptor!);
      await _releaseLease(lease.resource);
    }
  }

  @override
  Future<void> open(PlaybackResource resource, {Duration? resumeAt}) {
    if (_disposed) return Future.value();
    final epoch = ++_openEpoch;
    final watch = Stopwatch()..start();
    AppLogger.instance.info(
      '开始打开媒体：请求=$epoch，fileId=${resource.libraryFileId}，续播=${resumeAt?.inSeconds ?? 0}s',
      module: '播放器',
    );
    _subtitleSelectionVersion = 0;
    _isOpening = true;
    _pendingResumeAt = resumeAt;
    _recoverableErrorPosition = null;

    final isResolving =
        resource.uri.isScheme('content') || resource.prepare != null;

    // 新 open 立即重置 UI 状态避免旧画面残留
    _updateSnapshot(
      _snapshot.copyWith(
        status: isResolving ? PlaybackStatus.resolving : PlaybackStatus.opening,
        position: resumeAt ?? Duration.zero,
        duration: Duration.zero,
        buffered: Duration.zero,
        videoWidth: 0,
        videoHeight: 0,
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

      // 切换前先停止前代播放，再安全关闭旧描述符与旧资源租约
      try {
        await _player.stop();
      } catch (e, st) {
        AppLogger.instance.error('停止旧媒体失败', error: e, stackTrace: st);
      }
      await _closeActiveDescriptor();
      await _releaseActiveLease();
      await _releaseSubtitles();

      if (_disposed || epoch != _openEpoch) {
        _isOpening = false;
        return;
      }

      PlaybackResource effectiveResource = resource;
      if (resource.prepare != null) {
        try {
          effectiveResource = await resource.prepare!();
          AppLogger.instance.info(
            '播放资源准备完成：请求=$epoch，耗时=${watch.elapsedMilliseconds}ms',
            module: '播放器',
          );
        } catch (e, st) {
          _isOpening = false;
          if (_disposed || epoch != _openEpoch) return;
          AppLogger.instance.error('准备播放资源失败', error: e, stackTrace: st);
          _setPlaybackError(_safeErrorMessage(e));
          return;
        }
      }

      // 检查在 prepare 期间是否已被后续 open 或 stop 取代
      if (_disposed || epoch != _openEpoch) {
        _isOpening = false;
        await _releaseLease(effectiveResource);
        return;
      }

      int? openedFd;
      String mediaTarget;
      if (effectiveResource.uri.isScheme('content')) {
        try {
          openedFd = await _documents.openRead(effectiveResource.uri);
        } catch (e, st) {
          _isOpening = false;
          await _releaseLease(effectiveResource);
          if (_disposed || epoch != _openEpoch) return;
          AppLogger.instance.error('打开媒体描述符失败', error: e, stackTrace: st);
          _setPlaybackError(_safeErrorMessage(e));
          return;
        }

        if (_disposed || epoch != _openEpoch) {
          _isOpening = false;
          await _closeDescriptor(openedFd);
          await _releaseLease(effectiveResource);
          return;
        }
        mediaTarget = 'fd://$openedFd';
      } else {
        mediaTarget = effectiveResource.uri.toString();
      }

      if (_disposed || epoch != _openEpoch) {
        _isOpening = false;
        if (openedFd != null) await _closeDescriptor(openedFd);
        await _releaseLease(effectiveResource);
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
        httpHeaders: effectiveResource.httpHeaders.isNotEmpty
            ? effectiveResource.httpHeaders
            : null,
        start: resumeAt,
      );

      try {
        final nativePlayer = _player.platform;
        if (nativePlayer is NativePlayer) {
          // 等待视频控制器就绪后应用，避免平台初始化覆盖用户偏好。
          for (final entry in mpvPlayerProperties(_settings).entries) {
            await nativePlayer.setProperty(
              entry.key,
              entry.key == 'sub-auto' &&
                      resource.discoverSubtitles != null &&
                      !resource.uri.isScheme('file')
                  ? 'no'
                  : entry.value,
            );
          }
        }
        // 先以 play: false 打开，等待底层就绪后再次确认 epoch
        await _player.open(media, play: false);
      } catch (e, st) {
        _isOpening = false;
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
        await _releaseLease(effectiveResource);
        if (_disposed || epoch != _openEpoch) {
          return;
        }
        _setPlaybackError(_safeErrorMessage(e));
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
        await _releaseLease(effectiveResource);
        return;
      }

      _activeDescriptor = openedFd;
      _activeRelease = effectiveResource.release;
      if (effectiveResource.errors != null) {
        _resourceErrorSub = effectiveResource.errors!.listen((err) {
          AppLogger.instance.error('播放资源错误流通知: $err');
          _setPlaybackError(err.isNotEmpty ? err : '媒体流传输异常');
        });
      }
      _isOpening = false;
      try {
        await _player.play();
      } catch (e, st) {
        AppLogger.instance.error('底层起播异常', error: e, stackTrace: st);
        try {
          await _player.stop();
        } catch (stopErr, stopSt) {
          AppLogger.instance.error(
            '起播异常后停止播放器失败',
            error: stopErr,
            stackTrace: stopSt,
          );
        }
        await _closeActiveDescriptor();
        await _releaseActiveLease();
        _setPlaybackError(_safeErrorMessage(e));
        return;
      }
      _syncStatus();
      _syncTracks(_player.state.tracks, _player.state.track);
      _syncVideoSize(_player.state.videoParams);
      _checkResumeRange(_player.state.duration);
      AppLogger.instance.info(
        '媒体已打开并请求播放：请求=$epoch，耗时=${watch.elapsedMilliseconds}ms',
        module: '播放器',
      );
      unawaited(_autoLoadSubtitles(resource, epoch));
    });
  }

  Future<void> _autoLoadSubtitles(PlaybackResource video, int epoch) async {
    final discover = video.discoverSubtitles;
    // 可直接访问的本地目录仍由 libmpv 枚举，保留其配套字幕等原有能力。
    if (discover == null ||
        video.uri.isScheme('file') ||
        _settings.subtitleAutoLoad == TrackAutoLoad.disabled) {
      return;
    }
    final selectionVersion = _subtitleSelectionVersion;
    try {
      final subtitles = (await discover())
          .where(
            (subtitle) => matchesSubtitle(
              video.fileName,
              subtitle.fileName,
              _settings.subtitleAutoLoad,
            ),
          )
          .toList();
      subtitles.sort((a, b) {
        final priority =
            subtitleLanguagePriority(
              a.displayName,
              _settings.subtitleLanguages,
            ).compareTo(
              subtitleLanguagePriority(
                b.displayName,
                _settings.subtitleLanguages,
              ),
            );
        return priority != 0
            ? priority
            : a.displayName.compareTo(b.displayName);
      });
      var selected = false;
      for (final subtitle in subtitles) {
        if (_disposed || epoch != _openEpoch) return;
        try {
          final loaded = await _loadSubtitle(
            subtitle,
            epoch,
            select: () =>
                !selected && selectionVersion == _subtitleSelectionVersion,
          );
          selected = selected || loaded;
        } catch (error, stackTrace) {
          AppLogger.instance.error(
            '自动加载字幕失败',
            error: error,
            stackTrace: stackTrace,
          );
        }
      }
    } catch (error, stackTrace) {
      AppLogger.instance.error(
        '发现同目录字幕失败',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  @override
  Future<void> loadSubtitle(PlaybackResource resource) {
    _subtitleSelectionVersion++;
    return _loadSubtitle(resource, _openEpoch, select: () => true).then((_) {});
  }

  Future<bool> _loadSubtitle(
    PlaybackResource resource,
    int epoch, {
    required bool Function() select,
  }) async {
    if (_disposed || epoch != _openEpoch || _isEventIgnored) return false;
    PlaybackResource? lease;
    int? descriptor;
    var retained = false;
    try {
      // 准备连接在队列外进行，避免字幕目录或网络访问阻塞播放控制。
      lease = resource.prepare == null ? resource : await resource.prepare!();
      if (_disposed || epoch != _openEpoch) return false;
      if (lease.uri.isScheme('content')) {
        descriptor = await _documents.openRead(lease.uri);
      }
      if (_disposed || epoch != _openEpoch) return false;
      final target = descriptor == null
          ? lease.uri.toString()
          : 'fd://$descriptor';
      return await _enqueue(() async {
        if (_disposed || epoch != _openEpoch || _isEventIgnored) return false;
        final previous = _subtitleLeases[resource.uri];
        if (previous != null) {
          if (identical(lease, previous.resource)) lease = null;
          if (select()) {
            await _player.setSubtitleTrack(
              SubtitleTrack(previous.trackId, null, null),
            );
          }
          return true;
        }
        final native = _player.platform;
        final String trackId;
        _addingSubtitle = true;
        try {
          if (native is NativePlayer) {
            final before = await _nativeSubtitleIds(native);
            await native.command([
              'sub-add',
              target,
              select() ? 'select' : 'auto',
              resource.displayName,
              subtitleLanguage(resource.displayName) ?? 'und',
            ]);
            final added = (await _nativeSubtitleIds(native)).difference(before);
            if (added.isEmpty) {
              throw const PlaybackResourceException('字幕文件无法识别或读取');
            }
            trackId = added.first;
          } else {
            final previousTrack = _player.state.track.subtitle;
            await _player.setSubtitleTrack(
              SubtitleTrack.uri(target, title: resource.displayName),
            );
            trackId = target;
            if (!select()) await _player.setSubtitleTrack(previousTrack);
          }
        } finally {
          // media_kit 的日志与错误控制器异步派发；先处理本次命令已发出的事件。
          await Future<void>.delayed(Duration.zero);
          _addingSubtitle = false;
        }
        _subtitleLeases[resource.uri] = (
          resource: lease!,
          descriptor: descriptor,
          trackId: trackId,
        );
        retained = true;
        _syncTracks(_player.state.tracks, _player.state.track);
        return true;
      });
    } catch (error, stackTrace) {
      if (_disposed || epoch != _openEpoch) return false;
      AppLogger.instance.error(
        '加载外挂字幕失败',
        error: error,
        stackTrace: stackTrace,
      );
      throw const PlaybackResourceException('加载字幕失败，请检查文件格式、连接或访问权限');
    } finally {
      if (!retained) {
        if (descriptor != null) await _closeDescriptor(descriptor);
        final toRelease = lease;
        if (toRelease != null) await _releaseLease(toRelease);
      }
    }
  }

  Future<Set<String>> _nativeSubtitleIds(NativePlayer native) async {
    final tracks =
        jsonDecode(await native.getProperty('track-list')) as List<dynamic>;
    return tracks
        .whereType<Map<String, dynamic>>()
        .where((track) => track['type'] == 'sub')
        .map((track) => track['id'].toString())
        .toSet();
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
        _setPlaybackError(_safeErrorMessage(e));
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
        _setPlaybackError(_safeErrorMessage(e));
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
        _setPlaybackError(_safeErrorMessage(e));
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
        _setPlaybackError(_safeErrorMessage(e));
      }
    });
  }

  @override
  Future<void> setVolume(double volume) {
    if (_disposed) return Future.value();
    return _enqueue(() async {
      if (_disposed) return;
      try {
        await _player.setVolume(
          volume.clamp(0.0, _settings.maxVolume.toDouble()),
        );
      } catch (e, st) {
        AppLogger.instance.error('底层设置音量异常', error: e, stackTrace: st);
        _setPlaybackError(_safeErrorMessage(e));
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
        _setPlaybackError(_safeErrorMessage(e));
      }
    });
  }

  @override
  Future<void> setSubtitleTrack(String id) {
    _subtitleSelectionVersion++;
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
        _setPlaybackError(_safeErrorMessage(e));
      }
    });
  }

  @override
  Future<Uint8List?> captureFrame() {
    if (_disposed) return Future.value();
    final epoch = _openEpoch;
    return _enqueue(() async {
      if (_disposed || epoch != _openEpoch) return null;
      final image = await _player.screenshot(
        format: 'image/png',
        includeLibassSubtitles: true,
      );
      return _disposed || epoch != _openEpoch ? null : image;
    });
  }

  @override
  Future<PlaybackStatistics> getStatistics() {
    if (_disposed) return Future.value(const PlaybackStatistics());
    return _enqueue(() async {
      final native = _player.platform;
      if (_disposed || native is! NativePlayer) {
        return const PlaybackStatistics();
      }
      final values = <String, String>{};
      for (final property in const [
        'video-format',
        'video-params/w',
        'video-params/h',
        'estimated-vf-fps',
        'container-fps',
        'video-params/pixelformat',
        'video-params/colormatrix',
        'video-params/primaries',
        'video-params/gamma',
        'hwdec-current',
        'video-bitrate',
        'frame-drop-count',
        'decoder-frame-drop-count',
        'audio-codec-name',
        'audio-params/samplerate',
        'audio-params/hr-channels',
        'audio-bitrate',
        'avsync',
        'demuxer-cache-duration',
        'demuxer-cache-state/fw-bytes',
        'cache-speed',
      ]) {
        final value = await native.getProperty(property);
        if (value.isNotEmpty) values[property] = value;
      }
      return PlaybackStatistics(
        videoCodec: values['video-format'],
        width: int.tryParse(values['video-params/w'] ?? ''),
        height: int.tryParse(values['video-params/h'] ?? ''),
        frameRate: double.tryParse(
          values['estimated-vf-fps'] ?? values['container-fps'] ?? '',
        ),
        pixelFormat: values['video-params/pixelformat'],
        colorMatrix: values['video-params/colormatrix'],
        colorPrimaries: values['video-params/primaries'],
        colorTransfer: values['video-params/gamma'],
        hardwareDecoder: values['hwdec-current'],
        videoBitrate: double.tryParse(values['video-bitrate'] ?? ''),
        droppedFrames: int.tryParse(values['frame-drop-count'] ?? ''),
        decoderDroppedFrames: int.tryParse(
          values['decoder-frame-drop-count'] ?? '',
        ),
        audioCodec: values['audio-codec-name'],
        audioSampleRate: int.tryParse(values['audio-params/samplerate'] ?? ''),
        audioChannels: values['audio-params/hr-channels'],
        audioBitrate: double.tryParse(values['audio-bitrate'] ?? ''),
        audioVideoSync: double.tryParse(values['avsync'] ?? ''),
        cacheSeconds: double.tryParse(values['demuxer-cache-duration'] ?? ''),
        cacheBytes: int.tryParse(values['demuxer-cache-state/fw-bytes'] ?? ''),
        cacheSpeed: double.tryParse(values['cache-speed'] ?? ''),
      );
    });
  }

  @override
  Future<void> executeShortcut(PlayerShortcutAction action) {
    if (_disposed) return Future.value();
    return _enqueue(() async {
      if (_disposed) return;
      final nativePlayer = _player.platform;
      if (nativePlayer is! NativePlayer) throw UnsupportedError('当前播放后端不支持此操作');
      for (final command in mpvShortcutCommands(
        action,
        android: defaultTargetPlatform == TargetPlatform.android,
      )) {
        await nativePlayer.command(command);
      }
    });
  }

  @override
  Future<void> stop() {
    if (_disposed) return Future.value();
    if (_snapshot.status != PlaybackStatus.idle) {
      AppLogger.instance.info('停止播放并释放资源', module: '播放器');
    }
    _openEpoch++;
    _isOpening = false;
    _pendingResumeAt = null;
    _recoverableErrorPosition = null;
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
      await _releaseActiveLease();
      await _releaseSubtitles();
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
    _recoverableErrorPosition = null;
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
      await _releaseActiveLease();
      await _releaseSubtitles();

      if (!_snapshotController.isClosed) {
        await _snapshotController.close();
      }
    });

    return _disposeFuture!;
  }

  static String _safeErrorMessage(Object? error) {
    if (error == null) return '播放发生未知异常';

    if (error is PlaybackResourceException) {
      return error.message;
    }

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
