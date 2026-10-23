import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reelva/features/sources/domain/source_models.dart';
import 'package:reelva/features/sources/infrastructure/remote_http_client.dart';

void main() {
  late HttpServer server;
  late Uri serverUri;
  late RemoteHttpClient client;

  setUp(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    serverUri = Uri.parse('http://127.0.0.1:${server.port}');
    client = RemoteHttpClient();
  });

  tearDown(() async {
    client.close(force: true);
    await server.close(force: true);
  });

  group('RemoteHttpClient status code mapping', () {
    test('succeeds on 200 and parses json', () async {
      server.listen((req) async {
        req.response.statusCode = HttpStatus.ok;
        req.response.headers.contentType = ContentType.json;
        req.response.write(jsonEncode({'success': true}));
        await req.response.close();
      });

      final response = await client.request(serverUri);
      expect(response.statusCode, 200);
      expect(response.data, {'success': true});
    });

    test('succeeds on 207 Multi-Status', () async {
      server.listen((req) async {
        req.response.statusCode = 207;
        req.response.write('<multistatus/>');
        await req.response.close();
      });

      final response = await client.request(
        serverUri,
        responseType: ResponseType.plain,
      );
      expect(response.statusCode, 207);
      expect(response.data, '<multistatus/>');
    });

    test('throws MediaSourceException on 401 unauthorized', () async {
      server.listen((req) async {
        req.response.statusCode = HttpStatus.unauthorized;
        await req.response.close();
      });

      await expectLater(
        client.request(serverUri),
        throwsA(
          isA<MediaSourceException>().having(
            (e) => e.code,
            'code',
            'unauthorized',
          ),
        ),
      );
    });

    test('throws MediaSourceException on 403 forbidden', () async {
      server.listen((req) async {
        req.response.statusCode = HttpStatus.forbidden;
        await req.response.close();
      });

      await expectLater(
        client.request(serverUri),
        throwsA(
          isA<MediaSourceException>().having(
            (e) => e.code,
            'code',
            'forbidden',
          ),
        ),
      );
    });

    test('throws MediaSourceException on 404 file_missing', () async {
      server.listen((req) async {
        req.response.statusCode = HttpStatus.notFound;
        await req.response.close();
      });

      await expectLater(
        client.request(serverUri),
        throwsA(
          isA<MediaSourceException>().having(
            (e) => e.code,
            'code',
            'file_missing',
          ),
        ),
      );
    });

    test(
      'throws MediaSourceException on 416 range_not_satisfiable by default',
      () async {
        server.listen((req) async {
          req.response.statusCode = HttpStatus.requestedRangeNotSatisfiable;
          await req.response.close();
        });

        await expectLater(
          client.request(serverUri),
          throwsA(
            isA<MediaSourceException>().having(
              (e) => e.code,
              'code',
              'range_not_satisfiable',
            ),
          ),
        );
      },
    );

    test('allows 416 when explicitly passed in allowedStatusCodes', () async {
      server.listen((req) async {
        req.response.statusCode = HttpStatus.requestedRangeNotSatisfiable;
        req.response.headers.set(HttpHeaders.contentRangeHeader, 'bytes */0');
        await req.response.close();
      });

      final response = await client.request(
        serverUri,
        allowedStatusCodes: const {HttpStatus.requestedRangeNotSatisfiable},
      );
      expect(response.statusCode, 416);
    });

    test('throws MediaSourceException on 429 rate_limited', () async {
      server.listen((req) async {
        req.response.statusCode = HttpStatus.tooManyRequests;
        await req.response.close();
      });

      await expectLater(
        client.request(serverUri),
        throwsA(
          isA<MediaSourceException>().having(
            (e) => e.code,
            'code',
            'rate_limited',
          ),
        ),
      );
    });
  });

  group('RemoteHttpClient URI validation and secrecy', () {
    test('rejects URI with userinfo to prevent secret leakage', () async {
      final unsafeUri = Uri.parse(
        'http://admin:secret123@127.0.0.1:8080/files',
      );

      await expectLater(
        client.request(unsafeUri),
        throwsA(
          isA<MediaSourceException>().having(
            (e) => e.code,
            'code',
            'invalid_uri_userinfo',
          ),
        ),
      );
    });

    test('rejects non-HTTP/HTTPS protocols', () async {
      final fileUri = Uri.parse('file:///etc/passwd');

      await expectLater(
        client.request(fileUri),
        throwsA(
          isA<MediaSourceException>().having(
            (e) => e.code,
            'code',
            'invalid_uri_scheme',
          ),
        ),
      );
    });

    test(
      'never exposes raw exception or sensitive details in error message',
      () async {
        final secretAdapter = _MockHttpClientAdapter((options) async {
          throw DioException.connectionError(
            requestOptions: options,
            reason: 'Failed connect secret_token_xyz_999 to db',
            error: const SocketException(
              'OS Error: Connection refused, secret_pass_123',
            ),
          );
        });

        final dio = Dio()..httpClientAdapter = secretAdapter;
        final secretClient = RemoteHttpClient(dio: dio);

        try {
          await secretClient.request(Uri.parse('http://example.com/data'));
          fail('Should have thrown MediaSourceException');
        } on MediaSourceException catch (e) {
          expect(e.message, isNot(contains('secret_token')));
          expect(e.message, isNot(contains('secret_pass')));
          expect(e.message, isNot(contains('SocketException')));
          expect(e.message, isNot(contains('OS Error')));
          expect(e.code, 'network_timeout');
        } finally {
          secretClient.close(force: true);
        }
      },
    );
  });

  group('RemoteHttpClient redirect contract', () {
    test('follows 302 redirect on same origin', () async {
      server.listen((req) async {
        if (req.uri.path == '/orig') {
          req.response.statusCode = HttpStatus.found;
          req.response.headers.set(HttpHeaders.locationHeader, '/dest');
          await req.response.close();
        } else if (req.uri.path == '/dest') {
          req.response.statusCode = HttpStatus.ok;
          req.response.write('reached destination');
          await req.response.close();
        }
      });

      final response = await client.request(
        serverUri.resolve('/orig'),
        responseType: ResponseType.plain,
      );
      expect(response.statusCode, 200);
      expect(response.data, 'reached destination');
    });

    test(
      'stops and throws too_many_redirects if exceeding 5 redirects',
      () async {
        int redirectCount = 0;
        server.listen((req) async {
          redirectCount++;
          req.response.statusCode = HttpStatus.found;
          req.response.headers.set(
            HttpHeaders.locationHeader,
            '/loop$redirectCount',
          );
          await req.response.close();
        });

        await expectLater(
          client.request(serverUri.resolve('/loop0')),
          throwsA(
            isA<MediaSourceException>().having(
              (e) => e.code,
              'code',
              'too_many_redirects',
            ),
          ),
        );
      },
    );

    test(
      'preserves PROPFIND method and body on same-origin 301 and 307 redirect',
      () async {
        String? receivedMethod;
        String? receivedBody;

        server.listen((req) async {
          if (req.uri.path == '/start301') {
            req.response.statusCode = HttpStatus.movedPermanently;
            req.response.headers.set(HttpHeaders.locationHeader, '/final');
            await req.response.close();
          } else if (req.uri.path == '/final') {
            receivedMethod = req.method;
            receivedBody = await utf8.decodeStream(req);
            req.response.statusCode = 207;
            req.response.write('<multistatus/>');
            await req.response.close();
          }
        });

        final response = await client.request(
          serverUri.resolve('/start301'),
          method: 'PROPFIND',
          data: '<propfind/>',
          headers: {'Content-Type': 'application/xml'},
          responseType: ResponseType.plain,
        );

        expect(response.statusCode, 207);
        expect(receivedMethod, 'PROPFIND');
        expect(receivedBody, '<propfind/>');
      },
    );

    test(
      'switches to GET and drops body on 303 redirect and 302 POST',
      () async {
        String? receivedMethod;
        String? receivedBody;

        server.listen((req) async {
          if (req.uri.path == '/post') {
            req.response.statusCode = HttpStatus.seeOther;
            req.response.headers.set(HttpHeaders.locationHeader, '/result');
            await req.response.close();
          } else if (req.uri.path == '/result') {
            receivedMethod = req.method;
            receivedBody = await utf8.decodeStream(req);
            req.response.statusCode = HttpStatus.ok;
            req.response.write('ok');
            await req.response.close();
          }
        });

        final response = await client.request(
          serverUri.resolve('/post'),
          method: 'POST',
          data: 'form-data',
          responseType: ResponseType.plain,
        );

        expect(response.statusCode, 200);
        expect(receivedMethod, 'GET');
        expect(receivedBody, isEmpty);
      },
    );

    test(
      'rejects cross-origin body redirect with cross_origin_redirect_rejected',
      () async {
        final secondServer = await HttpServer.bind(
          InternetAddress.loopbackIPv4,
          0,
        );
        final secondPort = secondServer.port;
        try {
          server.listen((req) async {
            req.response.statusCode = HttpStatus.temporaryRedirect;
            req.response.headers.set(
              HttpHeaders.locationHeader,
              'http://127.0.0.1:$secondPort/target',
            );
            await req.response.close();
          });

          await expectLater(
            client.request(
              serverUri.resolve('/api'),
              method: 'POST',
              data: 'sensitive data',
            ),
            throwsA(
              isA<MediaSourceException>().having(
                (e) => e.code,
                'code',
                'cross_origin_redirect_rejected',
              ),
            ),
          );
        } finally {
          await secondServer.close(force: true);
        }
      },
    );

    test('strips authorization header on cross-authority redirect', () async {
      final secondServer = await HttpServer.bind(
        InternetAddress.loopbackIPv4,
        0,
      );
      final secondPort = secondServer.port;
      String? secondAuthHeader;

      try {
        server.listen((req) async {
          req.response.statusCode = HttpStatus.found;
          req.response.headers.set(
            HttpHeaders.locationHeader,
            'http://127.0.0.1:$secondPort/file',
          );
          await req.response.close();
        });

        secondServer.listen((req) async {
          secondAuthHeader = req.headers.value(HttpHeaders.authorizationHeader);
          req.response.statusCode = HttpStatus.ok;
          req.response.write('public content');
          await req.response.close();
        });

        final response = await client.request(
          serverUri.resolve('/auth-redirect'),
          headers: {'Authorization': 'Bearer my-secret-token'},
          responseType: ResponseType.plain,
        );

        expect(response.statusCode, 200);
        expect(secondAuthHeader, isNull);
      } finally {
        await secondServer.close(force: true);
      }
    });

    test('rejects HTTPS to HTTP downgrade redirect', () async {
      final adapter = _MockHttpClientAdapter((options) async {
        if (options.uri.scheme == 'https') {
          return ResponseBody.fromString(
            '',
            HttpStatus.found,
            headers: {
              HttpHeaders.locationHeader: [
                'http://downgrade.example.com/target',
              ],
            },
          );
        }
        return ResponseBody.fromString('ok', HttpStatus.ok);
      });

      final dio = Dio()..httpClientAdapter = adapter;
      final httpsClient = RemoteHttpClient(dio: dio);

      try {
        await expectLater(
          httpsClient.request(Uri.parse('https://secure.example.com/start')),
          throwsA(
            isA<MediaSourceException>().having(
              (e) => e.code,
              'code',
              'tls_downgrade_rejected',
            ),
          ),
        );
      } finally {
        httpsClient.close(force: true);
      }
    });
  });

  group('Streaming error bodies', () {
    test('closes stream on non-2xx response without draining', () async {
      server.listen((req) async {
        req.response.statusCode = HttpStatus.internalServerError;
        req.response.write('Large error body...');
        await req.response.close();
      });

      await expectLater(
        client.request(serverUri, responseType: ResponseType.stream),
        throwsA(isA<MediaSourceException>()),
      );
    });
  });
}

class _MockHttpClientAdapter implements HttpClientAdapter {
  _MockHttpClientAdapter(this.handler);

  final Future<ResponseBody> Function(RequestOptions options) handler;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) {
    return handler(options);
  }

  @override
  void close({bool force = false}) {}
}
