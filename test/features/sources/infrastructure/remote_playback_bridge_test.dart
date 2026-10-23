import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reelva/features/player/domain/playback_resource.dart';
import 'package:reelva/features/sources/infrastructure/remote_http_client.dart';
import 'package:reelva/features/sources/infrastructure/remote_playback_bridge.dart';

void main() {
  group('RemotePlaybackTarget', () {
    test('isExpired detects expiration based on date', () {
      final notExpired = RemotePlaybackTarget(
        uri: Uri.parse('http://example.com/video.mp4'),
        expiresAt: DateTime.now().add(const Duration(hours: 1)),
      );
      expect(notExpired.isExpired, isFalse);

      final expired = RemotePlaybackTarget(
        uri: Uri.parse('http://example.com/video.mp4'),
        expiresAt: DateTime.now().subtract(const Duration(minutes: 5)),
      );
      expect(expired.isExpired, isTrue);

      final noExpiration = RemotePlaybackTarget(
        uri: Uri.parse('http://example.com/video.mp4'),
      );
      expect(noExpiration.isExpired, isFalse);
    });
  });

  group('RemotePlaybackBridge probe validation regressions', () {
    late HttpServer upstreamServer;
    late Uri upstreamUri;
    late RemoteHttpClient httpClient;
    late RemotePlaybackBridge bridge;

    setUp(() async {
      upstreamServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      upstreamUri = Uri.parse('http://127.0.0.1:${upstreamServer.port}');
      httpClient = RemoteHttpClient();
      bridge = RemotePlaybackBridge(http: httpClient);
    });

    tearDown(() async {
      httpClient.close(force: true);
      await upstreamServer.close(force: true);
    });

    test(
      'rejects 206 missing Content-Range header with invalid_content_range',
      () async {
        upstreamServer.listen((req) async {
          req.response.statusCode = HttpStatus.partialContent;
          req.response.add([0]);
          await req.response.close();
        });

        await expectLater(
          bridge.open(
            displayName: 'Missing Content-Range',
            resolve:
                ({required bool refresh, CancelToken? cancelToken}) async =>
                    RemotePlaybackTarget(
                      uri: upstreamUri.resolve('/video.mp4'),
                    ),
          ),
          throwsA(
            isA<PlaybackResourceException>().having(
              (e) => e.code,
              'code',
              'invalid_content_range',
            ),
          ),
        );
      },
    );

    test('rejects 206 with non-positive total length', () async {
      upstreamServer.listen((req) async {
        req.response.statusCode = HttpStatus.partialContent;
        req.response.headers.set(HttpHeaders.contentRangeHeader, 'bytes 0-0/0');
        req.response.add([0]);
        await req.response.close();
      });

      await expectLater(
        bridge.open(
          displayName: 'Zero Total Length',
          resolve: ({required bool refresh, CancelToken? cancelToken}) async =>
              RemotePlaybackTarget(uri: upstreamUri.resolve('/video.mp4')),
        ),
        throwsA(
          isA<PlaybackResourceException>().having(
            (e) => e.code,
            'code',
            'invalid_content_range',
          ),
        ),
      );
    });

    test('rejects 206 with Content-Length != 1 on bytes 0-0 probe', () async {
      upstreamServer.listen((req) async {
        req.response.statusCode = HttpStatus.partialContent;
        req.response.headers.set(
          HttpHeaders.contentRangeHeader,
          'bytes 0-0/1000',
        );
        req.response.headers.set(HttpHeaders.contentLengthHeader, 50);
        req.response.add(List<int>.filled(50, 0));
        await req.response.close();
      });

      await expectLater(
        bridge.open(
          displayName: 'Bad Content-Length',
          resolve: ({required bool refresh, CancelToken? cancelToken}) async =>
              RemotePlaybackTarget(uri: upstreamUri.resolve('/video.mp4')),
        ),
        throwsA(
          isA<PlaybackResourceException>().having(
            (e) => e.code,
            'code',
            'invalid_content_length',
          ),
        ),
      );
    });

    test(
      'rejects 416 on probe unless Content-Range is exact bytes */0',
      () async {
        upstreamServer.listen((req) async {
          req.response.statusCode = HttpStatus.requestedRangeNotSatisfiable;
          req.response.headers.set(
            HttpHeaders.contentRangeHeader,
            'bytes */100',
          );
          await req.response.close();
        });

        await expectLater(
          bridge.open(
            displayName: 'Non-empty 416',
            resolve:
                ({required bool refresh, CancelToken? cancelToken}) async =>
                    RemotePlaybackTarget(
                      uri: upstreamUri.resolve('/video.mp4'),
                    ),
          ),
          throwsA(
            isA<PlaybackResourceException>().having(
              (e) => e.code,
              'code',
              'range_not_satisfiable',
            ),
          ),
        );
      },
    );
  });

  group('RemotePlaybackBridge open (HTTP) and special characters', () {
    late HttpServer upstreamServer;
    late Uri upstreamUri;
    late RemoteHttpClient httpClient;
    late RemotePlaybackBridge bridge;

    setUp(() async {
      upstreamServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      upstreamUri = Uri.parse('http://127.0.0.1:${upstreamServer.port}');
      httpClient = RemoteHttpClient();
      bridge = RemotePlaybackBridge(http: httpClient);
    });

    tearDown(() async {
      httpClient.close(force: true);
      await upstreamServer.close(force: true);
    });

    test(
      'supports display names containing #, %, spaces and unicode safely',
      () async {
        const fullSize = 100;

        upstreamServer.listen((req) async {
          req.response.statusCode = HttpStatus.partialContent;
          req.response.headers.set(
            HttpHeaders.contentRangeHeader,
            'bytes 0-0/$fullSize',
          );
          req.response.headers.set(HttpHeaders.contentLengthHeader, 1);
          req.response.add([0]);
          await req.response.close();
        });

        const complexName = 'Special #1 100% Movie [中文] 2026.mp4';
        final resource = await bridge.open(
          displayName: complexName,
          resolve: ({required bool refresh, CancelToken? cancelToken}) async =>
              RemotePlaybackTarget(uri: upstreamUri.resolve('/movie.mp4')),
        );

        final testClient = HttpClient();
        try {
          final headReq = await testClient.headUrl(resource.uri);
          final headResp = await headReq.close();
          expect(headResp.statusCode, HttpStatus.ok);
          await headResp.drain<void>();
        } finally {
          testClient.close(force: true);
          await resource.release?.call();
        }
      },
    );

    test(
      'fails seek with 416 not_seekable if server ignores Range with 200',
      () async {
        const fullSize = 200;
        final dummyData = List<int>.generate(fullSize, (i) => i % 50);

        upstreamServer.listen((req) async {
          // Probe 支持 Range
          final range = req.headers.value(HttpHeaders.rangeHeader);
          if (range == 'bytes=0-0') {
            req.response.statusCode = HttpStatus.partialContent;
            req.response.headers.set(
              HttpHeaders.contentRangeHeader,
              'bytes 0-0/$fullSize',
            );
            req.response.headers.set(HttpHeaders.contentLengthHeader, 1);
            req.response.add([0]);
            await req.response.close();
          } else {
            // 实际播放时无视 Range 头，错误地返回 200 全量数据
            req.response.statusCode = HttpStatus.ok;
            req.response.headers.set(HttpHeaders.contentLengthHeader, fullSize);
            req.response.add(dummyData);
            await req.response.close();
          }
        });

        final resource = await bridge.open(
          displayName: 'Flaky Server',
          resolve: ({required bool refresh, CancelToken? cancelToken}) async =>
              RemotePlaybackTarget(uri: upstreamUri.resolve('/flaky.mp4')),
        );

        String? emittedError;
        final sub = resource.errors?.listen((err) => emittedError = err);

        final testClient = HttpClient();
        try {
          final getReq = await testClient.getUrl(resource.uri);
          getReq.headers.set(HttpHeaders.rangeHeader, 'bytes=50-99');
          final getResp = await getReq.close();

          // 必须返回 416，严禁把 200 全量数据冒充 seek 成功
          expect(getResp.statusCode, HttpStatus.requestedRangeNotSatisfiable);
          await getResp.drain<void>();

          await pumpEventQueue();
          expect(emittedError, contains('not_seekable'));
        } finally {
          await sub?.cancel();
          testClient.close(force: true);
          await resource.release?.call();
        }
      },
    );

    test('rejects 206 where Content-Range end or total does not match requested range', () async {
      const fullSize = 500;

      upstreamServer.listen((req) async {
        final range = req.headers.value(HttpHeaders.rangeHeader);
        if (range == 'bytes=0-0') {
          req.response.statusCode = HttpStatus.partialContent;
          req.response.headers.set(
            HttpHeaders.contentRangeHeader,
            'bytes 0-0/$fullSize',
          );
          req.response.headers.set(HttpHeaders.contentLengthHeader, 1);
          req.response.add([0]);
          await req.response.close();
        } else {
          // 返回了错误的 end 范围 (请求 50-99，返回 50-70)
          req.response.statusCode = HttpStatus.partialContent;
          req.response.headers.set(
            HttpHeaders.contentRangeHeader,
            'bytes 50-70/$fullSize',
          );
          req.response.headers.set(HttpHeaders.contentLengthHeader, 21);
          req.response.add(List<int>.filled(21, 0));
          await req.response.close();
        }
      });

      final resource = await bridge.open(
        displayName: 'Mismatched Range',
        resolve: ({required bool refresh, CancelToken? cancelToken}) async =>
            RemotePlaybackTarget(uri: upstreamUri.resolve('/mismatch.mp4')),
      );

      String? emittedError;
      final sub = resource.errors?.listen((err) => emittedError = err);

      final testClient = HttpClient();
      try {
        final getReq = await testClient.getUrl(resource.uri);
        getReq.headers.set(HttpHeaders.rangeHeader, 'bytes=50-99');
        final getResp = await getReq.close();
        expect(getResp.statusCode, HttpStatus.badGateway);
        await getResp.drain<void>();

        await pumpEventQueue();
        expect(emittedError, '远程媒体分段范围不匹配');
      } finally {
        await sub?.cancel();
        testClient.close(force: true);
        await resource.release?.call();
      }
    });

    test('cancels cleanly when released during pending link refresh and creates no upstream request', () async {
      int upstreamRequestCount = 0;
      final refreshCompleter = Completer<RemotePlaybackTarget>();

      upstreamServer.listen((req) async {
        upstreamRequestCount++;
        final range = req.headers.value(HttpHeaders.rangeHeader);
        if (range == 'bytes=0-0') {
          // 探测请求正常返回 206
          req.response.statusCode = HttpStatus.partialContent;
          req.response.headers.set(
            HttpHeaders.contentRangeHeader,
            'bytes 0-0/1000',
          );
          req.response.headers.set(HttpHeaders.contentLengthHeader, 1);
          req.response.add([0]);
          await req.response.close();
        } else {
          // 实际 GET 返回 403 诱发 target refresh
          req.response.statusCode = HttpStatus.forbidden;
          await req.response.close();
        }
      });

      // 初始 target 未过期，允许 bridge.open 及 probe 正常完成初始化准备
      final resource = await bridge.open(
        displayName: 'Pending Refresh Test',
        resolve: ({required bool refresh, CancelToken? cancelToken}) async {
          if (refresh) {
            return refreshCompleter.future;
          }
          return RemotePlaybackTarget(uri: upstreamUri.resolve('/video.mp4'));
        },
      );

      final testClient = HttpClient();
      try {
        // 发起 GET 请求：由于 403 触发 resolve(refresh: true) 挂起在 refreshCompleter
        final getReq = await testClient.getUrl(resource.uri);
        final pendingGet = getReq.close();

        await pumpEventQueue();

        // 在刷新悬挂等待期间调用 release：必须安全取消并退出，绝不死锁或挂起
        await resource.release?.call();

        // 刷新随后完成
        refreshCompleter.complete(
          RemotePlaybackTarget(uri: upstreamUri.resolve('/video.mp4')),
        );

        try {
          final resp = await pendingGet;
          await resp.drain<void>();
        } catch (_) {}

        // 确认因为在 release 时及时取消并竞赛，未向 upstream 发起新的重试请求（仅 1 次 probe + 1 次 403 GET）
        expect(upstreamRequestCount, 2);
      } finally {
        testClient.close(force: true);
      }
    });

    test(
      'never leaks internal URLs, tokens, or raw exception strings',
      () async {
        upstreamServer.listen((req) async {
          req.response.statusCode = HttpStatus.internalServerError;
          req.response.write('Database password=secret123 failed');
          await req.response.close();
        });

        try {
          await bridge.open(
            displayName: 'Secret Movie',
            resolve:
                ({required bool refresh, CancelToken? cancelToken}) async =>
                    RemotePlaybackTarget(
                      uri: upstreamUri.resolve('/secret.mp4'),
                    ),
          );
          fail('Should throw PlaybackResourceException');
        } on PlaybackResourceException catch (e) {
          expect(e.message, isNot(contains('secret123')));
          expect(e.message, isNot(contains('Database')));
          expect(e.message, isNot(contains(upstreamUri.toString())));
        }
      },
    );
  });

  group('RemotePlaybackBridge openReader', () {
    test(
      'supports RemoteByteReader without prepare on concrete lease',
      () async {
        final dummyBytes = utf8.encode(
          'Hello World Stream from RemoteByteReader',
        );
        final reader = _FakeByteReader(dummyBytes, supportsRanges: true);

        final bridge = RemotePlaybackBridge();
        final resource = await bridge.openReader(
          displayName: 'Reader Movie',
          reader: reader,
        );

        // 具体租约不应有 prepare
        expect(resource.prepare, isNull);

        final testClient = HttpClient();
        try {
          final headReq = await testClient.headUrl(resource.uri);
          final headResp = await headReq.close();
          expect(headResp.statusCode, HttpStatus.ok);
          await headResp.drain<void>();

          // Range 请求 "World" (bytes 6-10)
          final getReq = await testClient.getUrl(resource.uri);
          getReq.headers.set(HttpHeaders.rangeHeader, 'bytes=6-10');
          final getResp = await getReq.close();
          expect(getResp.statusCode, HttpStatus.partialContent);
          final bytes = await getResp.fold<List<int>>(
            <int>[],
            (acc, chunk) => acc..addAll(chunk),
          );
          expect(utf8.decode(bytes), 'World');
        } finally {
          testClient.close(force: true);
          await resource.release?.call();
          expect(reader.isClosed, isTrue);
        }
      },
    );
  });
}

class _FakeByteReader implements RemoteByteReader {
  _FakeByteReader(this.data, {required this.supportsRanges});

  final List<int> data;
  @override
  final bool supportsRanges;
  bool isClosed = false;

  @override
  int get length => data.length;

  @override
  Stream<List<int>> read(int start, int? endExclusive) async* {
    final actualEnd = endExclusive != null
        ? endExclusive.clamp(0, data.length)
        : data.length;
    final actualStart = start.clamp(0, actualEnd);
    yield data.sublist(actualStart, actualEnd);
  }

  @override
  Future<void> close() async {
    isClosed = true;
  }
}
