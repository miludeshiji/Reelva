import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../../player/domain/playback_resource.dart';
import '../domain/danmaku.dart';
import '../infrastructure/danmaku_api.dart';
import '../infrastructure/danmaku_store.dart';

class DanmakuController extends ChangeNotifier {
  DanmakuController({
    required this.api,
    required this.store,
    required this.queryLoader,
    this.localLoader,
    this.localPicker,
  });

  final DanmakuApi api;
  final DanmakuStore store;
  final Future<DanmakuQuery> Function(PlaybackResource) queryLoader;
  final Future<LocalDanmakuFile?> Function(PlaybackResource)? localLoader;
  final Future<LocalDanmakuFile?> Function()? localPicker;
  DanmakuSettings settings = const DanmakuSettings();
  DanmakuQuery? query;
  DanmakuEpisode? selected;
  String? localFileName;
  List<DanmakuComment> comments = const [];
  String message = '开启后自动搜索并挂载弹幕';
  bool loading = false;
  bool pickingLocal = false;
  double offsetSeconds = 0;
  PlaybackResource? _resource;
  LocalDanmakuFile? _manualLocal;
  DanmakuEpisode? _requestedEpisode;
  bool _hasLoadedSource = false;
  Future<void>? _initialization;
  DanmakuSettings _savedSettings = const DanmakuSettings();
  Future<void> _saveQueue = Future<void>.value();
  CancelToken? _cancel;
  int _generation = 0;
  bool _disposed = false;

  bool _current(int generation) => !_disposed && generation == _generation;
  void _changed() {
    if (!_disposed) notifyListeners();
  }

  Future<void> _initialize() => _initialization ??= () async {
    try {
      settings = _savedSettings = await store.readSettings();
    } catch (_) {
      /* 未保存过设置或平台存储不可用时保持默认关闭。 */
    }
  }();

  int _startRequest() {
    _cancel?.cancel();
    _cancel = CancelToken();
    return ++_generation;
  }

  Future<void> open(PlaybackResource? resource) async {
    if (_disposed) return;
    final generation = _startRequest();
    if (_resource != resource) _manualLocal = null;
    _resource = resource;
    query = null;
    selected = null;
    _requestedEpisode = null;
    _hasLoadedSource = false;
    localFileName = null;
    comments = const [];
    offsetSeconds = 0;
    loading = false;
    _changed();
    await _initialize();
    if (!_current(generation)) return;
    if (resource == null || !settings.enabled) {
      message = '开启后自动搜索并挂载弹幕';
      _changed();
      return;
    }
    loading = true;
    message = '正在匹配弹幕';
    _changed();
    try {
      final fallback = DanmakuQuery.fromResource(resource);
      query = fallback;
      await _readOffset(fallback, generation);
      if (!_current(generation)) return;
      final local = _manualLocal ?? await localLoader?.call(resource);
      if (!_current(generation)) return;
      if (local != null) {
        _applyLocal(local);
        return;
      }
      final resolved = await queryLoader(resource);
      if (!_current(generation)) return;
      query = resolved;
      if (resolved.versionKey != fallback.versionKey) {
        await _readOffset(resolved, generation);
        if (!_current(generation)) return;
      }
      DanmakuEpisode? binding;
      try {
        binding = await store.readBinding(resolved.contentKey);
      } catch (_) {
        /* 存储读取失败时仍可搜索在线弹幕。 */
      }
      if (!_current(generation)) return;
      if (binding != null) {
        _requestedEpisode = binding;
        await _load(binding, generation, manual: false);
      } else {
        await _automatic(resolved, generation);
      }
    } catch (error) {
      if (_current(generation)) message = _error(error);
    } finally {
      if (_current(generation)) {
        if (selected != null) _hasLoadedSource = true;
        loading = false;
        _changed();
      }
    }
  }

  Future<void> _readOffset(DanmakuQuery current, int generation) async {
    try {
      final offset = await store.readOffset(current.versionKey);
      if (_current(generation)) offsetSeconds = offset;
    } catch (_) {
      /* 偏移读取失败不影响弹幕加载。 */
    }
  }

  void _applyLocal(LocalDanmakuFile file) {
    selected = null;
    _requestedEpisode = null;
    _hasLoadedSource = true;
    localFileName = file.fileName;
    comments = List.unmodifiable(file.comments);
    message = comments.isEmpty
        ? '此文件没有支持的普通弹幕'
        : '已加载 ${comments.length} 条本地弹幕';
    _changed();
  }

  Future<void> pickLocal() async {
    final resource = _resource;
    final picker = localPicker;
    if (resource == null || picker == null || pickingLocal || _disposed) return;
    final generation = _startRequest();
    final previousMessage = loading ? '请选择弹幕来源或重新自动匹配' : message;
    pickingLocal = true;
    loading = true;
    message = '正在加载本地弹幕';
    _changed();
    try {
      await _initialize();
      if (!_current(generation)) return;
      final file = await picker();
      if (!_current(generation)) return;
      if (file == null) {
        message = previousMessage;
        return;
      }
      if (!settings.enabled) {
        await _applySettings(
          settings.copyWith(enabled: true),
          resumeOnEnable: false,
        );
        if (!_current(generation)) return;
      }
      if (query == null) {
        final fallback = DanmakuQuery.fromResource(resource);
        query = fallback;
        await _readOffset(fallback, generation);
        if (!_current(generation)) return;
      }
      _manualLocal = file;
      _applyLocal(file);
    } catch (error) {
      if (_current(generation)) message = _error(error);
    } finally {
      pickingLocal = false;
      if (_current(generation)) {
        loading = false;
      }
      _changed();
    }
  }

  Future<void> _automatic(DanmakuQuery query, int generation) async {
    final cancel = _cancel;
    String? failure;
    if (api.dandanConfigured && query.localPath != null) {
      try {
        final exact = await api.matchFile(query, cancelToken: cancel);
        if (!_current(generation)) return;
        if (exact != null) {
          await _load(exact, generation, manual: false, fallbackOnEmpty: true);
          if (comments.isNotEmpty) return;
        }
      } catch (error) {
        failure = _error(error);
      }
    }
    for (final source in DanmakuSource.values) {
      if (!_current(generation)) return;
      if (source == DanmakuSource.dandanplay && !api.dandanConfigured) continue;
      try {
        var shows = await api.search(
          query.title,
          source,
          tmdbId: source == DanmakuSource.dandanplay ? query.tmdbId : null,
          movie: query.movie,
          cancelToken: cancel,
        );
        if (!_current(generation)) return;
        if (shows.isEmpty &&
            source == DanmakuSource.dandanplay &&
            query.tmdbId != null) {
          shows = await api.search(query.title, source, cancelToken: cancel);
          if (!_current(generation)) return;
        }
        final original = query.originalTitle;
        if (shows.isEmpty && original != null && original != query.title) {
          shows = await api.search(original, source, cancelToken: cancel);
        }
        if (!_current(generation)) return;
        final matches = <DanmakuEpisode>[];
        // 只检查标题相符或具有 TMDB 关联的作品，避免逐个拉取无关搜索结果。
        final candidates = shows
            .where((show) => show.tmdbMatched || _sameTitle(query, show))
            .toList();
        if (candidates.length > 5) {
          failure = '找到多个作品，请搜索并选择正确的作品和分集';
          continue;
        }
        for (final show in candidates) {
          if (!_current(generation)) return;
          final episodes = await api.episodes(show, cancelToken: cancel);
          final match = matchDanmakuEpisode(query, show, episodes);
          if (match != null) matches.add(match);
        }
        if (!_current(generation)) return;
        if (matches.length == 1) {
          await _load(
            matches.single,
            generation,
            manual: false,
            fallbackOnEmpty: true,
          );
          if (comments.isNotEmpty) return;
        }
        if (matches.length > 1) failure = '找到多个匹配，请搜索并选择正确的作品和分集';
      } catch (error) {
        failure = _error(error);
      }
    }
    if (!_current(generation)) return;
    message = comments.isNotEmpty
        ? '已加载 ${comments.length} 条弹幕'
        : failure ?? '未找到唯一匹配，请搜索并选择弹幕来源';
  }

  bool _sameTitle(DanmakuQuery query, DanmakuShow show) {
    final title = normalizeDanmakuTitle(show.title);
    return [query.title, query.originalTitle].whereType<String>().any(
      (value) => title.contains(normalizeDanmakuTitle(value)),
    );
  }

  Future<bool> select(DanmakuEpisode episode) => _select(episode, manual: true);

  Future<bool> _select(DanmakuEpisode episode, {required bool manual}) async {
    final resource = _resource;
    if (resource == null || _disposed) return false;
    final generation = _startRequest();
    if (manual) _requestedEpisode = episode;
    loading = true;
    message = '正在加载 ${episode.label} 的弹幕';
    _changed();
    try {
      await _initialize();
      if (!_current(generation)) return false;
      if (!settings.enabled) {
        await _applySettings(
          settings.copyWith(enabled: true),
          resumeOnEnable: false,
        );
        if (!_current(generation)) return false;
      }
      final resolved = await queryLoader(resource);
      if (!_current(generation)) return false;
      final previous = query;
      query = resolved;
      if (previous?.versionKey != resolved.versionKey) {
        await _readOffset(resolved, generation);
        if (!_current(generation)) return false;
      }
      return await _load(episode, generation, manual: manual);
    } catch (error) {
      if (_current(generation)) message = _error(error);
      return false;
    } finally {
      if (_current(generation)) {
        loading = false;
        _changed();
      }
    }
  }

  Future<bool> _load(
    DanmakuEpisode episode,
    int generation, {
    required bool manual,
    bool fallbackOnEmpty = false,
  }) async {
    final result = await api.comments(episode, cancelToken: _cancel);
    if (!_current(generation)) return false;
    comments = List.unmodifiable(result);
    _hasLoadedSource = !fallbackOnEmpty || result.isNotEmpty;
    selected = episode;
    localFileName = null;
    _manualLocal = null;
    message = result.isEmpty ? '此来源暂无弹幕，可搜索其他来源' : '已加载 ${result.length} 条弹幕';
    final contentKey = query?.contentKey;
    final saving = manual && contentKey != null
        ? _save(() => store.saveBinding(contentKey, episode))
        : null;
    _changed();
    if (saving != null) {
      try {
        await saving;
      } catch (_) {
        if (_current(generation)) message = '弹幕已挂载，关联保存失败';
      }
    }
    return _current(generation);
  }

  Future<void> retryCurrentSource() async {
    final episode = _requestedEpisode ?? selected;
    if (episode == null) {
      await open(_resource);
    } else {
      await _select(episode, manual: _requestedEpisode != null);
    }
  }

  Future<void> restoreAutomatic() async {
    final resource = _resource;
    if (resource == null || _disposed) return;
    final generation = _startRequest();
    loading = true;
    message = '正在恢复自动匹配';
    _changed();
    try {
      final resolved = await queryLoader(resource);
      if (!_current(generation)) return;
      await _save(() async {
        if (_current(generation)) {
          await store.saveBinding(resolved.contentKey, null);
        }
      });
      if (!_current(generation)) return;
      _manualLocal = null;
      await open(resource);
    } catch (_) {
      if (_current(generation)) {
        message = '无法清除弹幕关联，请重试';
        loading = false;
        _changed();
      }
    }
  }

  Future<void> toggleEnabled() async {
    await _initialize();
    await _applySettings(settings.copyWith(enabled: !settings.enabled));
  }

  Future<void> updateSettings(DanmakuSettings next) async {
    await _initialize();
    await _applySettings(next);
  }

  void _cancelRequest() {
    ++_generation;
    _cancel?.cancel();
    loading = false;
  }

  Future<void> _resumeLoading() async {
    if (_resource == null || loading || _hasLoadedSource) return;
    final episode = _requestedEpisode;
    if (episode == null) {
      await open(_resource);
    } else {
      await select(episode);
    }
  }

  Future<void> _applySettings(
    DanmakuSettings next, {
    bool resumeOnEnable = true,
  }) async {
    if (_disposed) return;
    final wasEnabled = settings.enabled;
    settings = next;
    if (wasEnabled && !next.enabled) _cancelRequest();
    final generation = _generation;
    final operation = _save(() async {
      await store.saveSettings(next);
      _savedSettings = next;
    });
    _changed();
    try {
      await operation;
    } catch (_) {
      if (!_disposed && identical(settings, next)) {
        settings = _savedSettings;
        if (next.enabled && !settings.enabled) _cancelRequest();
        message = '弹幕设置保存失败，请重试';
        _changed();
        if (!next.enabled && settings.enabled) await _resumeLoading();
      }
      return;
    }
    if (resumeOnEnable &&
        !wasEnabled &&
        settings.enabled &&
        _current(generation)) {
      await _resumeLoading();
    }
  }

  Future<void> updateOffset(double value) async {
    final current = query;
    if (current == null) return;
    final previous = offsetSeconds;
    offsetSeconds = value.clamp(-600, 600);
    final saved = offsetSeconds;
    _changed();
    try {
      await _save(() => store.saveOffset(current.versionKey, saved));
    } catch (_) {
      if (!_disposed && query == current && offsetSeconds == saved) {
        offsetSeconds = previous;
        message = '弹幕偏移保存失败，请重试';
        _changed();
      }
    }
  }

  Future<void> _save(Future<void> Function() write) {
    final operation = _saveQueue.then((_) => write());
    _saveQueue = operation.then<void>((_) {}, onError: (Object error) {});
    return operation;
  }

  String _error(Object error) =>
      error is DanmakuException ? error.message : '弹幕加载失败，请重试或更换来源';

  @override
  void dispose() {
    _disposed = true;
    ++_generation;
    _cancel?.cancel();
    super.dispose();
  }
}
