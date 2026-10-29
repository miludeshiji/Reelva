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
  });

  final DanmakuApi api;
  final DanmakuStore store;
  final Future<DanmakuQuery> Function(PlaybackResource) queryLoader;
  DanmakuSettings settings = const DanmakuSettings();
  DanmakuQuery? query;
  DanmakuEpisode? selected;
  List<DanmakuComment> comments = const [];
  String message = '开启后自动搜索并挂载弹幕';
  bool loading = false;
  double offsetSeconds = 0;
  PlaybackResource? _resource;
  Future<void>? _initialization;
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
      settings = await store.readSettings();
    } catch (_) {
      /* 未保存过设置或平台存储不可用时保持默认关闭。 */
    }
  }();

  Future<void> open(PlaybackResource? resource) async {
    final generation = ++_generation;
    _cancel?.cancel();
    _cancel = CancelToken();
    _resource = resource;
    query = null;
    selected = null;
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
      final resolved = await queryLoader(resource);
      if (!_current(generation)) return;
      query = resolved;
      DanmakuEpisode? binding;
      try {
        binding = await store.readBinding(resolved.contentKey);
        final offset = await store.readOffset(resolved.versionKey);
        if (!_current(generation)) return;
        offsetSeconds = offset;
      } catch (_) {
        /* 存储读取失败时仍可搜索在线弹幕。 */
      }
      if (!_current(generation)) return;
      if (binding != null) {
        await _load(binding, generation, manual: false);
      } else {
        await _automatic(resolved, generation);
      }
    } catch (error) {
      if (_current(generation)) message = _error(error);
    } finally {
      if (_current(generation)) {
        loading = false;
        _changed();
      }
    }
  }

  Future<void> _automatic(DanmakuQuery query, int generation) async {
    String? failure;
    if (api.dandanConfigured && query.localPath != null) {
      try {
        final exact = await api.matchFile(query, cancelToken: _cancel);
        if (!_current(generation)) return;
        if (exact != null) {
          await _load(exact, generation, manual: false);
          if (comments.isNotEmpty) return;
        }
      } catch (error) {
        failure = _error(error);
      }
    }
    for (final source in DanmakuSource.values) {
      if (source == DanmakuSource.dandanplay && !api.dandanConfigured) continue;
      try {
        var shows = await api.search(
          query.title,
          source,
          tmdbId: source == DanmakuSource.dandanplay ? query.tmdbId : null,
          movie: query.movie,
          cancelToken: _cancel,
        );
        if (!_current(generation)) return;
        if (shows.isEmpty &&
            source == DanmakuSource.dandanplay &&
            query.tmdbId != null) {
          shows = await api.search(query.title, source, cancelToken: _cancel);
        }
        final original = query.originalTitle;
        if (shows.isEmpty && original != null && original != query.title) {
          shows = await api.search(original, source, cancelToken: _cancel);
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
          final episodes = await api.episodes(show, cancelToken: _cancel);
          final match = matchDanmakuEpisode(query, show, episodes);
          if (match != null) matches.add(match);
        }
        if (!_current(generation)) return;
        if (matches.length == 1) {
          await _load(matches.single, generation, manual: false);
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

  Future<void> select(DanmakuEpisode episode) async {
    final generation = ++_generation;
    _cancel?.cancel();
    _cancel = CancelToken();
    loading = true;
    _changed();
    try {
      if (!settings.enabled) {
        settings = settings.copyWith(enabled: true);
        await store.saveSettings(settings);
      }
      if (query == null && _resource != null) {
        final resolved = await queryLoader(_resource!);
        if (!_current(generation)) return;
        query = resolved;
        final offset = await store.readOffset(resolved.versionKey);
        if (!_current(generation)) return;
        offsetSeconds = offset;
      }
      if (_current(generation)) await _load(episode, generation, manual: true);
    } catch (error) {
      if (_current(generation)) message = _error(error);
    } finally {
      if (_current(generation)) {
        loading = false;
        _changed();
      }
    }
  }

  Future<void> _load(
    DanmakuEpisode episode,
    int generation, {
    required bool manual,
  }) async {
    final result = await api.comments(episode, cancelToken: _cancel);
    if (!_current(generation)) return;
    comments = List.unmodifiable(result);
    selected = episode;
    message = result.isEmpty ? '此来源暂无弹幕，可搜索其他来源' : '已加载 ${result.length} 条弹幕';
    _changed();
    if (manual && query != null) {
      try {
        await store.saveBinding(query!.contentKey, episode);
      } catch (_) {
        if (_current(generation)) message = '弹幕已挂载，关联保存失败';
      }
    }
  }

  Future<void> retryAutomatic() async {
    final current = query;
    if (current != null) {
      try {
        await store.saveBinding(current.contentKey, null);
      } catch (_) {
        message = '无法清除弹幕关联，请重试';
        _changed();
        return;
      }
    }
    await open(_resource);
  }

  Future<void> updateSettings(DanmakuSettings next) async {
    await _initialize();
    if (_disposed) return;
    final previous = settings;
    settings = next;
    if (!next.enabled) {
      ++_generation;
      _cancel?.cancel();
      loading = false;
    }
    _changed();
    final operation = _saveQueue.then((_) => store.saveSettings(next));
    _saveQueue = operation.then<void>((_) {}, onError: (Object error) {});
    try {
      await operation;
    } catch (_) {
      if (!_disposed && identical(settings, next)) {
        settings = previous;
        message = '弹幕设置保存失败，请重试';
        _changed();
      }
      return;
    }
    if (!_disposed &&
        next.enabled &&
        !previous.enabled &&
        identical(settings, next)) {
      await open(_resource);
    }
  }

  Future<void> updateOffset(double value) async {
    final current = query;
    if (current == null) return;
    final previous = offsetSeconds;
    offsetSeconds = value.clamp(-600, 600);
    final saved = offsetSeconds;
    _changed();
    final operation = _saveQueue.then(
      (_) => store.saveOffset(current.versionKey, saved),
    );
    _saveQueue = operation.then<void>((_) {}, onError: (Object error) {});
    try {
      await operation;
    } catch (_) {
      if (!_disposed && query == current && offsetSeconds == saved) {
        offsetSeconds = previous;
        message = '弹幕偏移保存失败，请重试';
        _changed();
      }
    }
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
