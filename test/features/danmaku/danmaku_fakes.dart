import 'dart:async';

import 'package:dio/dio.dart';
import 'package:reelva/features/danmaku/domain/danmaku.dart';
import 'package:reelva/features/danmaku/infrastructure/danmaku_api.dart';
import 'package:reelva/features/danmaku/infrastructure/danmaku_store.dart';

class MemoryDanmakuStore extends DanmakuStore {
  DanmakuSettings settings = const DanmakuSettings(enabled: true);
  final bindings = <String, DanmakuEpisode>{};
  final offsets = <String, double>{};
  final cache = <String, String>{};
  final staleCache = <String, String>{};
  bool failWrites = false;
  @override
  Future<DanmakuSettings> readSettings() async => settings;
  @override
  Future<void> saveSettings(DanmakuSettings value) async {
    if (failWrites) throw StateError('storage');
    settings = value;
  }

  @override
  Future<DanmakuEpisode?> readBinding(String identity) async =>
      bindings[identity];
  @override
  Future<void> saveBinding(String identity, DanmakuEpisode? episode) async {
    if (episode == null) {
      bindings.remove(identity);
    } else {
      bindings[identity] = episode;
    }
  }

  @override
  Future<double> readOffset(String identity) async => offsets[identity] ?? 0;
  @override
  Future<void> saveOffset(String identity, double value) async {
    if (failWrites) throw StateError('storage');
    offsets[identity] = value;
  }

  @override
  Future<String?> readCache(String key, {bool stale = false}) async =>
      stale ? staleCache[key] ?? cache[key] : cache[key];
  @override
  Future<void> writeCache(
    String key,
    String body, {
    Duration ttl = const Duration(hours: 6),
  }) async {
    cache[key] = body;
  }
}

const testDanmakuEpisode = DanmakuEpisode(
  source: DanmakuSource.dandanplay,
  id: '10001',
  title: 'Example',
  episodeTitle: '第1话',
  number: 1,
);
const testBilibiliEpisode = DanmakuEpisode(
  source: DanmakuSource.bilibili,
  id: '20001',
  title: 'Example',
  episodeTitle: '1',
  number: 1,
);
const testDanmakuQuery = DanmakuQuery(
  title: 'Example',
  fileName: 'Example.S01E01.mkv',
  contentKey: 'episode:1',
  versionKey: 'file:1',
  season: 1,
  episode: 1,
);

class FakeDanmakuApi extends DanmakuApi {
  FakeDanmakuApi(DanmakuStore store)
    : super(store: store, appSecret: 'test-secret');
  Future<List<DanmakuComment>> Function(DanmakuEpisode)? onComments;
  Future<List<DanmakuShow>> Function(DanmakuSource)? onSearch;
  int searchCount = 0;
  final loaded = <String>[];
  @override
  Future<List<DanmakuShow>> search(
    String keyword,
    DanmakuSource source, {
    int? tmdbId,
    bool movie = false,
    CancelToken? cancelToken,
  }) async {
    searchCount++;
    if (onSearch != null) return onSearch!(source);
    return [
      DanmakuShow(source: source, id: '1', title: 'Example', tmdbMatched: true),
    ];
  }

  @override
  Future<List<DanmakuEpisode>> episodes(
    DanmakuShow show, {
    CancelToken? cancelToken,
  }) async => [
    show.source == DanmakuSource.dandanplay
        ? testDanmakuEpisode
        : testBilibiliEpisode,
  ];
  @override
  Future<List<DanmakuComment>> comments(
    DanmakuEpisode episode, {
    CancelToken? cancelToken,
  }) async {
    loaded.add(episode.cacheKey);
    return onComments == null
        ? [const DanmakuComment(timeMs: 0, text: 'hello')]
        : onComments!(episode);
  }
}
