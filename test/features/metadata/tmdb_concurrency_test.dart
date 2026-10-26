import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reelva/features/metadata/domain/tmdb_models.dart';
import 'package:reelva/features/metadata/infrastructure/tmdb_client.dart';
import 'package:reelva/features/metadata/infrastructure/tmdb_token_store.dart';

import 'metadata_test_helpers.dart';
import 'tmdb_client_test.dart'
    show FakeFlutterSecureStorage, FakeHttpClientAdapter;

ResponseBody _response({int status = 200, int? retryAfter}) =>
    ResponseBody.fromString(
      '{"results":[]}',
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
        if (retryAfter != null) 'retry-after': ['$retryAfter'],
      },
    );

void main() {
  late TmdbTokenStore tokens;
  late FakeHttpClientAdapter adapter;

  setUp(() async {
    tokens = TmdbTokenStore(storage: FakeFlutterSecureStorage());
    await tokens.save('1234567890abcdef1234567890abcdef');
    adapter = FakeHttpClientAdapter();
  });

  TmdbClient client({
    Duration interval = const Duration(milliseconds: 300),
    DateTime Function()? now,
    Future<void> Function(Duration)? delay,
  }) {
    final dio = Dio()..httpClientAdapter = adapter;
    final result = TmdbClient(
      dio: dio,
      tokenStore: tokens,
      cache: MemoryTmdbCache(),
      requestInterval: interval,
      now: now,
      delay: delay,
    );
    addTearDown(result.dispose);
    return result;
  }

  test('四个 HTTP 请求可同时等待响应，启动仍保持全局 300ms 间隔', () async {
    var now = DateTime.utc(2026);
    final waits = <({Duration duration, Completer<void> gate})>[];
    final api = client(
      now: () => now,
      delay: (duration) {
        final gate = Completer<void>();
        waits.add((duration: duration, gate: gate));
        return gate.future;
      },
    );
    final started = [for (var n = 0; n < 6; n++) Completer<void>()];
    final responses = <Completer<ResponseBody>>[];
    final times = <DateTime>[];
    var active = 0;
    var peak = 0;
    adapter.handler = (_) async {
      active++;
      if (active > peak) peak = active;
      times.add(now);
      final response = Completer<ResponseBody>();
      responses.add(response);
      started[responses.length - 1].complete();
      try {
        return await response.future;
      } finally {
        active--;
      }
    };
    final results = [for (var n = 0; n < 6; n++) api.searchMovie('Movie $n')];
    await started[0].future.timeout(const Duration(seconds: 2));
    Future<void> startNext(int index) async {
      await pumpEventQueue();
      expect(waits, hasLength(index));
      final wait = waits.last;
      expect(wait.duration, const Duration(milliseconds: 300));
      now = now.add(wait.duration);
      wait.gate.complete();
      await started[index].future.timeout(const Duration(seconds: 2));
    }

    for (var n = 1; n < 4; n++) {
      await startNext(n);
    }
    expect(responses, hasLength(4));
    expect(active, 4);
    for (var n = 1; n < times.length; n++) {
      expect(
        times[n].difference(times[n - 1]),
        const Duration(milliseconds: 300),
      );
    }
    responses[0].complete(_response());
    await startNext(4);
    expect(peak, 4);
    responses[1].complete(_response());
    await startNext(5);
    for (final response in responses.where(
      (response) => !response.isCompleted,
    )) {
      response.complete(_response());
    }
    await Future.wait(results);
    expect(peak, 4);
  });

  test('相同查询并发只发送一次，完成后继续命中缓存', () async {
    final api = client(interval: Duration.zero);
    final started = Completer<void>();
    final response = Completer<ResponseBody>();
    adapter.handler = (_) {
      started.complete();
      return response.future;
    };
    final requests = [
      for (var n = 0; n < 8; n++) api.searchMovie('Same Movie'),
    ];
    await started.future.timeout(const Duration(seconds: 2));
    expect(adapter.requested, hasLength(1));
    response.complete(_response());
    await Future.wait(requests);
    await api.searchMovie('Same Movie');
    expect(adapter.requested, hasLength(1));
  });

  test('429 更新共享冷却，已经等待启动的其他请求也遵守 Retry-After', () async {
    final api = client(interval: const Duration(milliseconds: 200));
    final started = Completer<void>();
    final response = Completer<ResponseBody>();
    DateTime? otherStarted;
    var attempts = 0;
    adapter.handler = (options) {
      if (options.queryParameters['query'] == 'Limited' && attempts++ == 0) {
        started.complete();
        return response.future;
      }
      if (options.queryParameters['query'] == 'Other') {
        otherStarted = DateTime.now();
      }
      return _response();
    };
    final limited = api.searchMovie('Limited');
    final other = api.searchMovie('Other');
    await started.future.timeout(const Duration(seconds: 2));
    await Future<void>.delayed(Duration.zero);
    final failedAt = DateTime.now();
    response.complete(_response(status: 429, retryAfter: 1));
    await Future.wait([limited, other]);
    expect(
      otherStarted!.difference(failedAt),
      greaterThanOrEqualTo(const Duration(milliseconds: 950)),
    );
    expect(adapter.requested, hasLength(3));
  });

  test('401 阻止排队请求，后续显式重试或更新凭据可以重新请求', () async {
    final api = client(interval: const Duration(milliseconds: 20));
    var authorized = false;
    adapter.handler = (_) => _response(status: authorized ? 200 : 401);
    final errors = await Future.wait([
      for (var n = 0; n < 6; n++)
        api
            .searchMovie('Movie $n')
            .then<Object?>(
              (_) => null,
              onError: (Object error, StackTrace stack) => error,
            ),
    ]);
    expect(adapter.requested, hasLength(1));
    expect(
      errors,
      everyElement(
        isA<MetadataException>().having(
          (error) => error.code,
          'code',
          'unauthorized',
        ),
      ),
    );
    authorized = true;
    await api.searchMovie('Retry Movie');
    expect(adapter.requested, hasLength(2));
    await tokens.save('fedcba0987654321fedcba0987654321');
    await api.searchMovie('Fresh Movie');
    expect(adapter.requested, hasLength(3));
  });

  test('过长共享冷却让排队请求及时报限流，保留冷却而不等待 60 秒', () async {
    final api = client(interval: const Duration(milliseconds: 20));
    adapter.handler = (_) => _response(status: 429, retryAfter: 60);
    final errors = await Future.wait([
      for (var n = 0; n < 4; n++)
        api
            .searchMovie('Movie $n')
            .then<Object?>(
              (_) => null,
              onError: (Object error, StackTrace stack) => error,
            ),
    ]).timeout(const Duration(seconds: 2));
    expect(adapter.requested, hasLength(1));
    expect(
      errors,
      everyElement(
        isA<MetadataException>().having(
          (error) => error.code,
          'code',
          'rate_limit',
        ),
      ),
    );
  });
}
