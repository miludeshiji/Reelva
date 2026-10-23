import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reelva/features/metadata/domain/tmdb_models.dart';

import 'metadata_test_helpers.dart';

import 'package:reelva/features/metadata/infrastructure/tmdb_client.dart';
import 'package:reelva/features/metadata/infrastructure/tmdb_token_store.dart';

class FakeFlutterSecureStorage extends FlutterSecureStorage {
  final Map<String, String> _data = {};

  @override
  Future<String?> read({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async => _data[key];

  @override
  Future<void> write({
    required String key,
    required String? value,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (value == null) {
      _data.remove(key);
    } else {
      _data[key] = value;
    }
  }

  @override
  Future<void> delete({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async => _data.remove(key);
}

class FakeHttpClientAdapter implements HttpClientAdapter {
  ResponseBody Function(RequestOptions options)? handler;
  final List<RequestOptions> requested = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requested.add(options);
    if (handler != null) {
      return handler!(options);
    }
    return ResponseBody.fromString(
      '{}',
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  group('TmdbClient', () {
    late FakeFlutterSecureStorage fakeStorage;
    late TmdbTokenStore tokenStore;
    late MemoryTmdbCache memoryCache;
    late Dio dio;
    late FakeHttpClientAdapter fakeAdapter;
    late TmdbClient client;

    const validV3Key = '1234567890abcdef1234567890abcdef';

    setUp(() async {
      fakeStorage = FakeFlutterSecureStorage();
      tokenStore = TmdbTokenStore(storage: fakeStorage);
      await tokenStore.save(validV3Key);

      memoryCache = MemoryTmdbCache();
      dio = Dio();
      fakeAdapter = FakeHttpClientAdapter();
      dio.httpClientAdapter = fakeAdapter;

      client = TmdbClient(
        tokenStore: tokenStore,
        cache: memoryCache,
        dio: dio,
        requestInterval: const Duration(milliseconds: 1),
      );
    });

    test('searchMovie parses results and caches fresh response', () async {
      fakeAdapter.handler = (options) {
        expect(options.path, equals('/search/movie'));
        expect(options.queryParameters['query'], equals('Inception'));
        expect(options.queryParameters['year'], equals(2010));
        expect(options.queryParameters['api_key'], equals(validV3Key));

        return ResponseBody.fromString(
          jsonEncode({
            'page': 1,
            'results': [
              {
                'id': 27205,
                'title': 'Inception',
                'original_title': 'Inception',
                'overview': 'A thief who steals corporate secrets...',
                'release_date': '2010-07-15',
                'poster_path': '/qmDpIHrmpJINaRKAfWQfftjCdyi.jpg',
                'backdrop_path': '/s3TBrRGB1jav7cUUtEgC0M7nqqc.jpg',
              },
            ],
          }),
          200,
          headers: {
            Headers.contentTypeHeader: [Headers.jsonContentType],
          },
        );
      };

      final results = await client.searchMovie('Inception', year: 2010);
      expect(results.length, equals(1));
      expect(results.first.id, equals(27205));
      expect(results.first.title, equals('Inception'));
      expect(results.first.year, equals(2010));
      expect(results.first.type, equals('movie'));
      expect(fakeAdapter.requested.length, equals(1));

      // Second call should hit memoryCache and NOT call fakeAdapter
      final cachedResults = await client.searchMovie('Inception', year: 2010);
      expect(cachedResults.length, equals(1));
      expect(cachedResults.first.id, equals(27205));
      expect(fakeAdapter.requested.length, equals(1)); // Still 1!
    });

    test(
      'searchTv parses series results and maps first_air_date to year',
      () async {
        fakeAdapter.handler = (options) {
          expect(options.path, equals('/search/tv'));
          expect(options.queryParameters['query'], equals('Breaking Bad'));
          expect(options.queryParameters['first_air_date_year'], equals(2008));

          return ResponseBody.fromString(
            jsonEncode({
              'page': 1,
              'results': [
                {
                  'id': 1396,
                  'name': 'Breaking Bad',
                  'original_name': 'Breaking Bad',
                  'overview': 'A high school chemistry teacher...',
                  'first_air_date': '2008-01-20',
                  'poster_path': '/ggFHVNu6YYI5L9pCfOacjizRGt.jpg',
                },
              ],
            }),
            200,
            headers: {
              Headers.contentTypeHeader: [Headers.jsonContentType],
            },
          );
        };

        final results = await client.searchTv('Breaking Bad', year: 2008);
        expect(results.length, equals(1));
        expect(results.first.id, equals(1396));
        expect(results.first.title, equals('Breaking Bad'));
        expect(results.first.type, equals('series'));
        expect(results.first.year, equals(2008));
      },
    );

    test('getMovieDetails extracts alternative_titles aliases', () async {
      fakeAdapter.handler = (options) {
        expect(options.path, equals('/movie/27205'));
        expect(
          options.queryParameters['append_to_response'],
          equals('alternative_titles'),
        );

        return ResponseBody.fromString(
          jsonEncode({
            'id': 27205,
            'title': '盗梦空间',
            'original_title': 'Inception',
            'overview': '多重梦境...',
            'release_date': '2010-07-16',
            'poster_path': '/inception.jpg',
            'alternative_titles': {
              'titles': [
                {'title': '潜行凶间', 'iso_3166_1': 'HK'},
                {'title': '奠基', 'iso_3166_1': 'CN'},
              ],
            },
          }),
          200,
          headers: {
            Headers.contentTypeHeader: [Headers.jsonContentType],
          },
        );
      };

      final details = await client.getMovieDetails(27205);
      expect(details.id, equals(27205));
      expect(details.title, equals('盗梦空间'));
      expect(details.originalTitle, equals('Inception'));
      expect(details.aliases, containsAll(['潜行凶间', '奠基']));
    });

    test('getTvSeasonEpisodes parses episodes list', () async {
      fakeAdapter.handler = (options) {
        expect(options.path, equals('/tv/1396/season/1'));

        return ResponseBody.fromString(
          jsonEncode({
            'season_number': 1,
            'episodes': [
              {
                'id': 62085,
                'name': 'Pilot',
                'season_number': 1,
                'episode_number': 1,
                'overview': 'When Walter White...',
                'air_date': '2008-01-20',
              },
              {
                'id': 62086,
                'name': "Cat's in the Bag...",
                'season_number': 1,
                'episode_number': 2,
                'overview': 'Walt and Jesse...',
                'air_date': '2008-01-27',
              },
            ],
          }),
          200,
          headers: {
            Headers.contentTypeHeader: [Headers.jsonContentType],
          },
        );
      };

      final episodes = await client.getTvSeasonEpisodes(1396, 1);
      expect(episodes.length, equals(2));
      expect(episodes[0].seasonNumber, equals(1));
      expect(episodes[0].episodeNumber, equals(1));
      expect(episodes[0].title, equals('Pilot'));
      expect(episodes[1].episodeNumber, equals(2));
    });
    test('TmdbEpisode.fromJson throws invalid_response when season/episode number missing', () {
      expect(
        () => TmdbEpisode.fromJson(const {'name': 'Missing Numbers'}),
        throwsA(
          isA<MetadataException>().having(
            (e) => e.code,
            'code',
            'invalid_response',
          ),
        ),
      );
    });

    test(
      'rate limit 429: respects retry-after header and retries successfully',
      () async {
        int attempts = 0;
        fakeAdapter.handler = (options) {
          attempts++;
          if (attempts == 1) {
            return ResponseBody.fromString(
              '{"status_message": "Rate limit exceeded"}',
              429,
              headers: {
                Headers.contentTypeHeader: [Headers.jsonContentType],
                'retry-after': ['1'],
              },
            );
          }
          return ResponseBody.fromString(
            jsonEncode({
              'page': 1,
              'results': [
                {'id': 100, 'title': 'Retry Success', 'year': 2022},
              ],
            }),
            200,
            headers: {
              Headers.contentTypeHeader: [Headers.jsonContentType],
            },
          );
        };

        final results = await client.searchMovie('Test');
        expect(attempts, equals(2));
        expect(results.first.title, equals('Retry Success'));
      },
    );

    test(
      'rate limit 429: throws safe MetadataException when retries exhausted',
      () async {
        fakeAdapter.handler = (options) {
          return ResponseBody.fromString(
            '{"status_message": "Rate limit exceeded"}',
            429,
            headers: {
              Headers.contentTypeHeader: [Headers.jsonContentType],
              'retry-after': ['1'],
            },
          );
        };

        expect(
          () => client.searchMovie('Exhausted'),
          throwsA(
            isA<MetadataException>().having(
              (e) => e.code,
              'code',
              'rate_limit',
            ),
          ),
        );
      },
    );
    test(
      'rate limit 429: retry-after > 10s throws immediately without retry',
      () async {
        int attempts = 0;
        fakeAdapter.handler = (options) {
          attempts++;
          return ResponseBody.fromString(
            '{"status_message": "Rate limit exceeded"}',
            429,
            headers: {
              Headers.contentTypeHeader: [Headers.jsonContentType],
              'retry-after': ['60'], // 60 seconds > 10 seconds!
            },
          );
        };

        await expectLater(
          () => client.searchMovie('LongCooldown'),
          throwsA(
            isA<MetadataException>().having(
              (e) => e.code,
              'code',
              'rate_limit',
            ),
          ),
        );
        expect(attempts, equals(1)); // Did not retry!
      },
    );

    test('maps 401/403 to safe unauthorized MetadataException', () async {
      fakeAdapter.handler = (options) {
        return ResponseBody.fromString(
          '{"status_message": "Invalid API key"}',
          401,
          headers: {
            Headers.contentTypeHeader: [Headers.jsonContentType],
          },
        );
      };

      expect(
        () => client.searchMovie('UnauthorizedTest'),
        throwsA(
          isA<MetadataException>().having(
            (e) => e.code,
            'code',
            'unauthorized',
          ),
        ),
      );
    });

    test(
      'offline without cache throws safe offline MetadataException',
      () async {
        fakeAdapter.handler = (options) {
          throw DioException(
            requestOptions: options,
            type: DioExceptionType.connectionError,
            error: 'Connection refused',
          );
        };

        expect(
          () => client.searchMovie('OfflineTest'),
          throwsA(
            isA<MetadataException>().having((e) => e.code, 'code', 'offline'),
          ),
        );
      },
    );

    test(
      'offline with stale cache falls back to cached data gracefully',
      () async {
        // 预先向缓存写入已过期条目
        const cacheKey = 'search:movie:zh-CN:StaleMovie::1';
        await memoryCache.put(
          key: cacheKey,
          payloadJson: jsonEncode({
            'results': [
              {'id': 999, 'title': 'Stale Movie Title', 'year': 2020},
            ],
          }),
          ttl: const Duration(days: -1), // Expired!
        );

        // 模拟断网抛出连接异常
        fakeAdapter.handler = (options) {
          throw DioException(
            requestOptions: options,
            type: DioExceptionType.connectionError,
          );
        };

        final results = await client.searchMovie('StaleMovie');
        expect(results.length, equals(1));
        expect(results.first.id, equals(999));
        expect(results.first.title, equals('Stale Movie Title'));
      },
    );

    test('missing key without cache throws no_key MetadataException', () async {
      await tokenStore.delete(); // Delete token

      expect(
        () => client.searchMovie('NoKeyMovie'),
        throwsA(
          isA<MetadataException>().having((e) => e.code, 'code', 'no_key'),
        ),
      );
    });

    test('bearer token uses Authorization header instead of api_key query param', () async {
      const jwtBearer =
          'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTYifQ.signature';
      await tokenStore.save(jwtBearer);

      fakeAdapter.handler = (options) {
        expect(options.headers['Authorization'], equals('Bearer $jwtBearer'));
        expect(options.queryParameters.containsKey('api_key'), isFalse);

        return ResponseBody.fromString(
          jsonEncode({'results': <Map<String, dynamic>>[]}),
          200,
          headers: {
            Headers.contentTypeHeader: [Headers.jsonContentType],
          },
        );
      };

      await client.searchMovie('BearerTest');
      expect(fakeAdapter.requested.length, equals(1));
    });
    test('dispose closes underlying dio', () {
      client.dispose();
      expect(() => client.searchMovie('AfterClose'), throwsA(anything));
    });
  });
}
