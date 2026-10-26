import 'dart:async';
import 'dart:collection';

import '../../../core/logging/app_logger.dart';
import '../../player/domain/playback_resource.dart';
import '../../player/domain/playback_snapshot.dart';
import '../../player/domain/player_engine.dart';
import '../../player/domain/player_shortcuts.dart';
import '../infrastructure/playback_progress_repository.dart';

/// 在引擎边界统一保存进度，控件和生命周期操作沿用同一播放接口。
class ProgressPlayerEngine implements PlayerEngine {
  ProgressPlayerEngine({
    required this._inner,
    required PlaybackProgressRepository progressRepository,
    DateTime Function()? clock,
    this._throttleInterval = const Duration(seconds: 10),
  }) : _repository = progressRepository,
       _clock = clock ?? DateTime.now {
    _subscription = _inner.snapshots.listen(_onSnapshot);
  }

  final PlayerEngine _inner;
  final PlaybackProgressRepository _repository;
  final DateTime Function() _clock;
  final Duration _throttleInterval;
  late final StreamSubscription<PlaybackSnapshot> _subscription;
  final _snapshots = StreamController<PlaybackSnapshot>.broadcast();
  final _writes = Queue<_ProgressWrite>();

  int _epoch = 0;
  int? _fileId;
  bool _acceptProgress = false;
  bool _disposed = false;
  PlaybackSnapshot? _latest;
  DateTime? _lastAttemptAt;
  Duration _lastQueuedPosition = Duration.zero;
  String? _progressError;
  _ProgressWrite? _activeWrite;
  _ProgressWrite? _lastWritten;
  Future<void>? _saving;
  Future<void>? _disposeFuture;

  PlaybackSnapshot _enrich(PlaybackSnapshot value) => _progressError == null
      ? value
      : value.copyWith(progressErrorMessage: () => _progressError);

  @override
  PlaybackSnapshot get snapshot => _enrich(_inner.snapshot);

  @override
  Stream<PlaybackSnapshot> get snapshots => _snapshots.stream;

  static bool _hasProgress(PlaybackSnapshot value) =>
      value.duration > Duration.zero &&
      (value.status == PlaybackStatus.playing ||
          value.status == PlaybackStatus.paused ||
          value.status == PlaybackStatus.buffering ||
          value.status == PlaybackStatus.completed);

  void _onSnapshot(PlaybackSnapshot value) {
    if (_disposed) return;
    if (_acceptProgress && _hasProgress(value)) {
      final previousStatus = _latest?.status;
      _latest = value;
      final important =
          value.status == PlaybackStatus.completed ||
          (value.status == PlaybackStatus.paused &&
              previousStatus != PlaybackStatus.paused);
      final intervalElapsed =
          _lastAttemptAt == null ||
          _clock().difference(_lastAttemptAt!) >= _throttleInterval;
      final advanced =
          (value.position - _lastQueuedPosition).abs() >=
          const Duration(seconds: 1);
      if (important ||
          (value.status == PlaybackStatus.playing &&
              intervalElapsed &&
              advanced)) {
        unawaited(_saveLatest());
      }
    }
    _emit(value);
  }

  void _emit(PlaybackSnapshot value) {
    if (!_snapshots.isClosed) _snapshots.add(_enrich(value));
  }

  void _setError(String? message) {
    if (_progressError == message) return;
    _progressError = message;
    _emit(_inner.snapshot);
  }

  void _captureCurrent() {
    if (_acceptProgress && _hasProgress(_inner.snapshot)) {
      _latest = _inner.snapshot;
    }
  }

  @override
  Future<void> open(PlaybackResource resource, {Duration? resumeAt}) async {
    if (_disposed) return;
    _captureCurrent();
    final previousSave = _saveLatest();
    final epoch = ++_epoch;
    _acceptProgress = false;
    _fileId = null;
    _latest = null;
    await previousSave;
    if (_disposed || epoch != _epoch) return;

    var start = resumeAt;
    if (start == null && resource.libraryFileId != null) {
      try {
        final saved = await _repository.getProgress(resource.libraryFileId!);
        if (saved != null) {
          start =
              saved.isEffectivelyCompleted ||
                  saved.position < const Duration(seconds: 5) ||
                  (saved.duration > Duration.zero &&
                      saved.position >= saved.duration)
              ? Duration.zero
              : saved.position;
        }
      } catch (error, stack) {
        AppLogger.instance.error('读取观看进度失败', error: error, stackTrace: stack);
        _setError('读取观看进度失败，本次从头播放；请检查存储空间后重试');
      }
    }
    if (_disposed || epoch != _epoch) return;
    _lastAttemptAt = null;
    _lastQueuedPosition = start ?? Duration.zero;
    await _inner.open(resource, resumeAt: start);
    if (_disposed || epoch != _epoch) return;
    _fileId = resource.libraryFileId;
    _acceptProgress = true;
    _captureCurrent();
  }

  @override
  Future<void> play() => _disposed ? Future.value() : _inner.play();

  @override
  Future<void> pause() async {
    if (_disposed) return;
    final epoch = _epoch;
    await _inner.pause();
    if (_disposed || epoch != _epoch) return;
    _captureCurrent();
    await _saveLatest();
  }

  @override
  Future<void> seek(Duration position) async {
    if (_disposed) return;
    final epoch = _epoch;
    await _inner.seek(position);
    if (_disposed || epoch != _epoch || !_acceptProgress) return;
    if (_hasProgress(_inner.snapshot)) {
      // 原生位置流可能晚于 seek Future；显式回到零秒也必须覆盖旧进度。
      final duration = _inner.snapshot.duration;
      final milliseconds = position.inMilliseconds.clamp(
        0,
        duration.inMilliseconds,
      );
      _latest = _inner.snapshot.copyWith(
        position: Duration(milliseconds: milliseconds),
      );
      await _saveLatest();
    }
  }

  @override
  Future<void> setRate(double rate) =>
      _disposed ? Future.value() : _inner.setRate(rate);

  @override
  Future<void> setVolume(double volume) =>
      _disposed ? Future.value() : _inner.setVolume(volume);

  @override
  Future<void> setAudioTrack(String id) =>
      _disposed ? Future.value() : _inner.setAudioTrack(id);

  @override
  Future<void> setSubtitleTrack(String id) =>
      _disposed ? Future.value() : _inner.setSubtitleTrack(id);

  @override
  Future<void> loadSubtitle(PlaybackResource resource) =>
      _disposed ? Future.value() : _inner.loadSubtitle(resource);

  @override
  Future<void> stop() async {
    if (_disposed) return;
    _captureCurrent();
    final save = _saveLatest();
    ++_epoch;
    _acceptProgress = false;
    // 先让原生播放器停止，保存使用已捕获的位置，不采纳 stop 的归零事件。
    await _inner.stop();
    await save;
  }

  @override
  Future<void> executeShortcut(PlayerShortcutAction action) async {
    if (_disposed) return;
    final epoch = _epoch;
    await _inner.executeShortcut(action);
    if (_disposed || epoch != _epoch) return;
    if (action == PlayerShortcutAction.previousChapter ||
        action == PlayerShortcutAction.nextChapter ||
        action == PlayerShortcutAction.previousFrame ||
        action == PlayerShortcutAction.nextFrame) {
      _captureCurrent();
      await _saveLatest();
    }
  }

  Future<void> forceSave() {
    if (_disposed) return _saving ?? Future.value();
    _captureCurrent();
    return _saveLatest();
  }

  Future<void> _saveLatest() {
    final fileId = _fileId;
    final value = _latest;
    if (fileId == null || value == null) return _saving ?? Future.value();
    final write = _ProgressWrite(
      fileId,
      value.position,
      value.duration,
      value.status == PlaybackStatus.completed ||
          value.position.inMilliseconds >= value.duration.inMilliseconds * 0.9,
    );
    final previous = _writes.isNotEmpty ? _writes.last : _activeWrite;
    if (write.sameAs(previous) ||
        (_saving == null &&
            _progressError == null &&
            write.sameAs(_lastWritten))) {
      return _saving ?? Future.value();
    }
    // 慢磁盘写入期间只保留同一文件的最新待写位置；不同文件按操作顺序保留。
    if (_writes.isNotEmpty && _writes.last.fileId == fileId) {
      _writes.removeLast();
    }
    _writes.add(write);
    _lastAttemptAt = _clock();
    _lastQueuedPosition = value.position;
    if (_saving == null) {
      final completer = Completer<void>();
      _saving = completer.future;
      unawaited(_drainWrites(completer));
    }
    return _saving!;
  }

  Future<void> _drainWrites(Completer<void> completer) async {
    try {
      while (_writes.isNotEmpty) {
        final write = _writes.removeFirst();
        _activeWrite = write;
        try {
          await _repository.saveProgress(
            fileId: write.fileId,
            position: write.position,
            duration: write.duration,
            completed: write.completed,
          );
          _lastWritten = write;
          _setError(null);
        } catch (error, stack) {
          AppLogger.instance.error('保存观看进度失败', error: error, stackTrace: stack);
          _setError('保存播放进度失败，请检查存储空间；下次保存时将重试');
        } finally {
          _activeWrite = null;
        }
      }
    } finally {
      _saving = null;
      completer.complete();
    }
  }

  @override
  Future<void> dispose() {
    if (_disposeFuture != null) return _disposeFuture!;
    _captureCurrent();
    final save = _saveLatest();
    _disposed = true;
    _acceptProgress = false;
    ++_epoch;
    return _disposeFuture = _dispose(save);
  }

  Future<void> _dispose(Future<void> save) async {
    await _subscription.cancel();
    try {
      await Future.wait([_inner.dispose(), save]);
    } finally {
      await _snapshots.close();
    }
  }
}

class _ProgressWrite {
  const _ProgressWrite(
    this.fileId,
    this.position,
    this.duration,
    this.completed,
  );

  final int fileId;
  final Duration position;
  final Duration duration;
  final bool completed;

  bool sameAs(_ProgressWrite? other) =>
      other != null &&
      fileId == other.fileId &&
      position == other.position &&
      duration == other.duration &&
      completed == other.completed;
}
