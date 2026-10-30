import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reelva/features/danmaku/domain/danmaku.dart';
import 'package:reelva/features/danmaku/infrastructure/danmaku_api.dart';

import 'danmaku_fakes.dart';

class _Adapter implements HttpClientAdapter {
  _Adapter(this.handler);
  final ResponseBody Function(RequestOptions) handler;
  final requests = <RequestOptions>[];
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<dynamic>? cancelFuture,
  ) async {
    requests.add(options);
    return handler(options);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody _json(
  Object value, {
  int status = 200,
  Map<String, List<String>>? headers,
}) => ResponseBody.fromString(
  jsonEncode(value),
  status,
  headers: {
    'content-type': ['application/json'],
    ...?headers,
  },
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('签名仅使用路径，TMDB只查询指定身份并缓存搜索结果', () async {
    final store = MemoryDanmakuStore();
    final adapter = _Adapter(
      (_) => _json({
        'success': true,
        'animes': [
          {'animeId': 987654321, 'animeTitle': 'Example'},
        ],
      }),
    );
    final dio = Dio()..httpClientAdapter = adapter;
    final now = DateTime.utc(2026, 1, 1);
    final api = DanmakuApi(
      store: store,
      dio: dio,
      appId: 'id',
      appSecret: 'test-secret',
      now: () => now,
    );
    addTearDown(api.dispose);
    final results = await api.search(
      'Example',
      DanmakuSource.dandanplay,
      tmdbId: 123,
    );
    await api.search('Example', DanmakuSource.dandanplay, tmdbId: 123);
    expect(results.single.tmdbMatched, isTrue);
    expect(adapter.requests, hasLength(1));
    final request = adapter.requests.single;
    final stamp = now.millisecondsSinceEpoch ~/ 1000;
    expect(
      request.headers['X-Signature'],
      base64Encode(
        sha256
            .convert(utf8.encode('id$stamp/api/v2/search/episodestest-secret'))
            .bytes,
      ),
    );
    expect(request.queryParameters['anime'], isNull);
    expect(request.queryParameters['tmdbId'], 123);
  });
  test('弹幕302下载剥离签名，保留聚合参数并缓存正文', () async {
    final store = MemoryDanmakuStore();
    final adapter = _Adapter(
      (request) => request.uri.host == 'api.dandanplay.net'
          ? _json(
              {},
              status: 302,
              headers: {
                'location': ['https://cdn.example.test/comments?token=public'],
              },
            )
          : _json({
              'comments': [
                {'p': '0.25,1,16777215,[BiliBili]123', 'm': 'hello'},
              ],
            }),
    );
    final api = DanmakuApi(
      store: store,
      dio: Dio()..httpClientAdapter = adapter,
      appId: 'id',
      appSecret: 'test-secret',
    );
    addTearDown(api.dispose);
    final comments = await api.comments(testDanmakuEpisode);
    await api.comments(testDanmakuEpisode);
    expect(comments.single.timeMs, 250);
    expect(adapter.requests, hasLength(2));
    expect(adapter.requests.first.queryParameters['withRelated'], isTrue);
    expect(
      adapter.requests.last.headers.keys.where(
        (key) => key.toLowerCase().startsWith('x-'),
      ),
      isEmpty,
    );
  });
  test('拒绝降级HTTP的下载地址', () async {
    final adapter = _Adapter(
      (_) => _json(
        {},
        status: 302,
        headers: {
          'location': ['http://cdn.example.test/comments'],
        },
      ),
    );
    final api = DanmakuApi(
      store: MemoryDanmakuStore(),
      dio: Dio()..httpClientAdapter = adapter,
      appSecret: 'test-secret',
    );
    addTearDown(api.dispose);
    await expectLater(
      api.comments(testDanmakuEpisode),
      throwsA(isA<DanmakuException>()),
    );
    expect(adapter.requests, hasLength(1));
  });
  test('网络失败回退旧缓存，取消请求不回退', () async {
    final store = MemoryDanmakuStore();
    store.staleCache['danmaku:v1:${testDanmakuEpisode.cacheKey}'] =
        '{"comments":[{"p":"0,1,1,1","m":"cached"}]}';
    final adapter = _Adapter((_) => _json({}, status: 503));
    final api = DanmakuApi(
      store: store,
      dio: Dio()..httpClientAdapter = adapter,
      appSecret: 'test-secret',
    );
    addTearDown(api.dispose);
    expect((await api.comments(testDanmakuEpisode)).single.text, 'cached');
    store.cache.clear();
    final cancel = CancelToken()..cancel();
    await expectLater(
      api.comments(testDanmakuEpisode, cancelToken: cancel),
      throwsA(isA<DioException>()),
    );
  });
  test('B站搜索与分集请求保留原始CID，不拼接分集ID', () async {
    final adapter = _Adapter((request) {
      if (request.path.endsWith('/finger/spi')) {
        return _json({
          'code': 0,
          'data': {'b_3': 'test-visitor'},
        });
      }
      if (request.path.endsWith('/search/type')) {
        return _json({
          'code': 0,
          'data': {
            'result': [
              {
                'season_id': 12,
                'title': '<em>Example</em>',
                'pubtime': 1700000000,
              },
            ],
          },
        });
      }
      if (request.path.endsWith('/season')) {
        return _json({
          'code': 0,
          'result': {
            'title': 'Example',
            'episodes': [
              {'cid': 99887766, 'title': '1', 'long_title': 'First'},
            ],
          },
        });
      }
      return _json({
        'code': 0,
        'data': {
          'title': 'Video',
          'pages': [
            {'cid': 55667788, 'page': 2, 'part': 'Part 2'},
          ],
        },
      });
    });
    final api = DanmakuApi(
      store: MemoryDanmakuStore(),
      dio: Dio()..httpClientAdapter = adapter,
    );
    addTearDown(api.dispose);
    final shows = await api.search('Example', DanmakuSource.bilibili);
    expect(shows, hasLength(1));
    expect(shows.single.title, 'Example');
    final episodes = await api.episodes(shows.single);
    expect(episodes.single.id, '99887766');
    expect(episodes.single.number, 1);
    final video = (await api.search(
      'https://www.bilibili.com/video/BV1Abcdef123/?p=2',
      DanmakuSource.bilibili,
    )).single;
    expect((await api.episodes(video)).single.id, '55667788');
    expect(
      adapter.requests.every(
        (request) => request.headers['Referer'] == 'https://www.bilibili.com/',
      ),
      isTrue,
    );
    expect(
      adapter.requests.where((request) => request.path.endsWith('/finger/spi')),
      hasLength(1),
    );
    expect(adapter.requests.first.headers['Cookie'], isNull);
    expect(
      adapter.requests
          .skip(1)
          .every(
            (request) => request.headers['Cookie'] == 'buvid3=test-visitor',
          ),
      isTrue,
    );
  });
  test('B站访客初始化失败后可重新搜索，不缓存失败会话', () async {
    var attempts = 0;
    final adapter = _Adapter((request) {
      if (request.path.endsWith('/finger/spi')) {
        if (++attempts == 1) return _json({}, status: 503);
        return _json({
          'code': 0,
          'data': {'b_3': 'test-visitor'},
        });
      }
      return _json({
        'code': 0,
        'data': {'result': <Object>[]},
      });
    });
    final api = DanmakuApi(
      store: MemoryDanmakuStore(),
      dio: Dio()..httpClientAdapter = adapter,
    );
    addTearDown(api.dispose);
    await expectLater(
      api.search('Example', DanmakuSource.bilibili),
      throwsA(isA<DanmakuException>()),
    );
    expect(await api.search('Example', DanmakuSource.bilibili), isEmpty);
    expect(attempts, 2);
  });
  test('B站HTTP风控响应提示请求受限', () async {
    final adapter = _Adapter((request) {
      if (request.path.endsWith('/finger/spi')) {
        return _json({
          'code': 0,
          'data': {'b_3': 'test-visitor'},
        });
      }
      return _json({}, status: 412);
    });
    final api = DanmakuApi(
      store: MemoryDanmakuStore(),
      dio: Dio()..httpClientAdapter = adapter,
    );
    addTearDown(api.dispose);
    await expectLater(
      api.search('Example', DanmakuSource.bilibili),
      throwsA(
        isA<DanmakuException>().having(
          (error) => error.message,
          'message',
          contains('请求受限'),
        ),
      ),
    );
  });
  test('200业务错误不被当成空搜索结果', () async {
    final adapter = _Adapter(
      (_) => _json({'success': false, 'errorMessage': 'remote secret'}),
    );
    final api = DanmakuApi(
      store: MemoryDanmakuStore(),
      dio: Dio()..httpClientAdapter = adapter,
      appSecret: 'test-secret',
    );
    addTearDown(api.dispose);
    await expectLater(
      api.search('Example', DanmakuSource.dandanplay),
      throwsA(
        isA<DanmakuException>().having(
          (error) => error.message,
          'message',
          isNot(contains('remote secret')),
        ),
      ),
    );
  });
}
