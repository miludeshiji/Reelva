import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:reelva/features/sources/infrastructure/remote_http_client.dart';
import 'package:reelva/features/sync/domain/sync_models.dart';
import 'package:reelva/features/sync/domain/sync_transport.dart';
import 'package:reelva/features/sync/infrastructure/sync_configuration_store.dart';
import 'package:reelva/features/sync/infrastructure/webdav_sync_transport.dart';

void main() {
  late HttpServer server;
  late Uri serverUri;
  late RemoteHttpClient httpClient;

  const validDeviceId = '0123456789abcdef0123456789abcdef';
  const otherDeviceId = 'abcdef0123456789abcdef0123456789';

  setUp(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    serverUri = Uri.parse('http://127.0.0.1:${server.port}/');
    httpClient = RemoteHttpClient();
  });

  tearDown(() async {
    httpClient.close(force: true);
    await server.close(force: true);
  });

  SyncBatch createSampleBatch({
    String deviceId = validDeviceId,
    int sequence = 1,
    int positionMs = 120000,
    int durationMs = 600000,
  }) {
    return SyncBatch(
      deviceId: deviceId,
      sequence: sequence,
      records: [
        SyncRecord(
          target: const SyncTarget(workType: 'movie', tmdbId: 42),
          kind: SyncRecordKind.progress,
          version: SyncVersion(stamp: 1700000000000, deviceId: deviceId),
          value: {
            'positionMs': positionMs,
            'durationMs': durationMs,
            'completed': false,
          },
        ),
      ],
    );
  }

  test('加密配置文件使用独立路径和 ETag 条件写入，不覆盖并发更新', () async {
    String? stored;
    var revision = 0;
    server.listen((request) async {
      if (request.method == 'MKCOL') {
        request.response.statusCode = HttpStatus.created;
      } else {
        expect(request.uri.path, '/reelva-sync-v1/application-v1.json');
        if (request.method == 'GET') {
          if (stored == null) {
            request.response.statusCode = HttpStatus.notFound;
          } else {
            request.response.headers.set(HttpHeaders.etagHeader, '"$revision"');
            request.response.write(stored);
          }
        } else {
          final creating =
              request.headers.value(HttpHeaders.ifNoneMatchHeader) == '*';
          if (creating && stored != null ||
              !creating &&
                  request.headers.value(HttpHeaders.ifMatchHeader) !=
                      '"$revision"') {
            request.response.statusCode = HttpStatus.preconditionFailed;
          } else {
            stored = await utf8.decodeStream(request);
            revision++;
            request.response.statusCode = HttpStatus.created;
          }
        }
      }
      await request.response.close();
    });
    final transport = WebDavSyncTransport(
      http: httpClient,
      configuration: SyncConfiguration(endpoint: serverUri),
    );
    expect(await transport.downloadApplicationData(), isNull);
    expect(await transport.uploadApplicationData('encrypted-v1'), isTrue);
    final snapshot = (await transport.downloadApplicationData())!;
    expect(snapshot.body, 'encrypted-v1');
    expect(
      await transport.uploadApplicationData('unconditional-overwrite'),
      isFalse,
    );
    expect(
      await transport.uploadApplicationData(
        'encrypted-v2',
        etag: snapshot.etag,
      ),
      isTrue,
    );
    expect(
      await transport.uploadApplicationData(
        'stale-overwrite',
        etag: snapshot.etag,
      ),
      isFalse,
    );
    expect((await transport.downloadApplicationData())!.body, 'encrypted-v2');
  });

  group('WebDavSyncTransport MKCOL & Directory Creation', () {
    test('calls MKCOL to create sync directory before first upload', () async {
      final requests = <String>[];

      server.listen((req) async {
        requests.add('${req.method} ${req.uri.path}');
        if (req.method == 'MKCOL') {
          req.response.statusCode = HttpStatus.created;
          await req.response.close();
        } else if (req.method == 'PUT') {
          req.response.statusCode = HttpStatus.created;
          await req.response.close();
        }
      });

      final config = SyncConfiguration(
        endpoint: serverUri,
        username: 'user',
        password: 'password123',
      );
      final transport = WebDavSyncTransport(
        http: httpClient,
        configuration: config,
      );

      final batch = createSampleBatch();
      await transport.upload(batch);

      expect(requests, [
        'MKCOL /reelva-sync-v1/',
        'PUT /reelva-sync-v1/${batch.fileName}',
      ]);
    });

    test(
      'treats 405 Method Not Allowed on MKCOL as directory already exists',
      () async {
        server.listen((req) async {
          if (req.method == 'MKCOL') {
            req.response.statusCode = HttpStatus.methodNotAllowed;
            await req.response.close();
          } else if (req.method == 'PUT') {
            req.response.statusCode = HttpStatus.created;
            await req.response.close();
          }
        });

        final config = SyncConfiguration(endpoint: serverUri);
        final transport = WebDavSyncTransport(
          http: httpClient,
          configuration: config,
        );

        final batch = createSampleBatch();
        await expectLater(transport.upload(batch), completes);
      },
    );

    test('fails explicitly on MKCOL 409 Conflict', () async {
      server.listen((req) async {
        if (req.method == 'MKCOL') {
          req.response.statusCode = HttpStatus.conflict;
          await req.response.close();
        }
      });

      final config = SyncConfiguration(endpoint: serverUri);
      final transport = WebDavSyncTransport(
        http: httpClient,
        configuration: config,
      );

      final batch = createSampleBatch();
      expect(
        () => transport.upload(batch),
        throwsA(
          isA<SyncException>().having(
            (e) => e.message,
            'message',
            contains('409 Conflict'),
          ),
        ),
      );
    });
  });

  group('WebDavSyncTransport listBatches', () {
    test(
      'returns empty list when sync directory does not exist (404)',
      () async {
        server.listen((req) async {
          expect(req.method, 'PROPFIND');
          req.response.statusCode = HttpStatus.notFound;
          await req.response.close();
        });

        final config = SyncConfiguration(endpoint: serverUri);
        final transport = WebDavSyncTransport(
          http: httpClient,
          configuration: config,
        );

        final batches = await transport.listBatches();
        expect(batches, isEmpty);
      },
    );

    test(
      'parses 207 Multi-Status XML and filters batches accurately',
      () async {
        server.listen((req) async {
          expect(req.method, 'PROPFIND');
          expect(req.headers.value('Depth'), '1');

          const xmlBody =
              '''<?xml version="1.0" encoding="utf-8"?>
<D:multistatus xmlns:D="DAV:">
  <!-- 目录自身 -->
  <D:response>
    <D:href>/reelva-sync-v1/</D:href>
    <D:propstat>
      <D:prop>
        <D:resourcetype><D:collection/></D:resourcetype>
      </D:prop>
      <D:status>HTTP/1.1 200 OK</D:status>
    </D:propstat>
  </D:response>
  <!-- 子目录 (应跳过) -->
  <D:response>
    <D:href>/reelva-sync-v1/subdir/</D:href>
    <D:propstat>
      <D:prop>
        <D:resourcetype><D:collection/></D:resourcetype>
      </D:prop>
      <D:status>HTTP/1.1 200 OK</D:status>
    </D:propstat>
  </D:response>
  <!-- 非批次文件 (应跳过) -->
  <D:response>
    <D:href>/reelva-sync-v1/readme.txt</D:href>
    <D:propstat>
      <D:prop>
        <D:resourcetype/>
      </D:prop>
      <D:status>HTTP/1.1 200 OK</D:status>
    </D:propstat>
  </D:response>
  <!-- 无效批次文件名 (序列非正整数，跳过) -->
  <D:response>
    <D:href>/reelva-sync-v1/$validDeviceId-0.json</D:href>
    <D:propstat>
      <D:prop>
        <D:resourcetype/>
      </D:prop>
      <D:status>HTTP/1.1 200 OK</D:status>
    </D:propstat>
  </D:response>
  <!-- 有效批次 1 -->
  <D:response>
    <D:href>/reelva-sync-v1/$validDeviceId-1.json</D:href>
    <D:propstat>
      <D:prop>
        <D:resourcetype/>
      </D:prop>
      <D:status>HTTP/1.1 200 OK</D:status>
    </D:propstat>
  </D:response>
  <!-- 有效批次 2 (不同设备) -->
  <D:response>
    <D:href>/reelva-sync-v1/$otherDeviceId-3.json</D:href>
    <D:propstat>
      <D:prop>
        <D:resourcetype/>
      </D:prop>
      <D:status>HTTP/1.1 200 OK</D:status>
    </D:propstat>
  </D:response>
</D:multistatus>''';

          req.response.statusCode = 207;
          req.response.headers.contentType = ContentType(
            'application',
            'xml',
            charset: 'utf-8',
          );
          req.response.write(xmlBody);
          await req.response.close();
        });

        final config = SyncConfiguration(endpoint: serverUri);
        final transport = WebDavSyncTransport(
          http: httpClient,
          configuration: config,
        );

        final batches = await transport.listBatches();
        expect(batches.length, 2);
        expect(
          batches,
          contains(const SyncRemoteBatch(deviceId: validDeviceId, sequence: 1)),
        );
        expect(
          batches,
          contains(const SyncRemoteBatch(deviceId: otherDeviceId, sequence: 3)),
        );
      },
    );
  });

  group('WebDavSyncTransport upload & 412 crash recovery', () {
    test('sends conditional PUT with If-None-Match: *', () async {
      String? ifNoneMatchHeader;
      String? contentTypeHeader;
      String? receivedBody;

      server.listen((req) async {
        if (req.method == 'MKCOL') {
          req.response.statusCode = HttpStatus.ok;
          await req.response.close();
        } else if (req.method == 'PUT') {
          ifNoneMatchHeader = req.headers.value(HttpHeaders.ifNoneMatchHeader);
          contentTypeHeader = req.headers.value(HttpHeaders.contentTypeHeader);
          receivedBody = await utf8.decodeStream(req);
          req.response.statusCode = HttpStatus.created;
          await req.response.close();
        }
      });

      final config = SyncConfiguration(endpoint: serverUri);
      final transport = WebDavSyncTransport(
        http: httpClient,
        configuration: config,
      );

      final batch = createSampleBatch();
      await transport.upload(batch);

      expect(ifNoneMatchHeader, '*');
      expect(contentTypeHeader, contains('application/json'));
      expect(receivedBody, isNotNull);
      final parsed = jsonDecode(receivedBody!) as Map<String, dynamic>;
      expect(parsed['deviceId'], validDeviceId);
      expect(parsed['sequence'], 1);
    });

    test('412 crash recovery: recovers successfully when remote batch is semantically identical', () async {
      final batch = createSampleBatch();

      server.listen((req) async {
        if (req.method == 'MKCOL') {
          req.response.statusCode = HttpStatus.ok;
          await req.response.close();
        } else if (req.method == 'PUT') {
          // 412 Precondition Failed
          req.response.statusCode = HttpStatus.preconditionFailed;
          await req.response.close();
        } else if (req.method == 'GET') {
          // 返回完全一致的远端批次
          req.response.statusCode = HttpStatus.ok;
          req.response.headers.contentType = ContentType.json;
          req.response.write(jsonEncode(batch.toJson()));
          await req.response.close();
        }
      });

      final config = SyncConfiguration(endpoint: serverUri);
      final transport = WebDavSyncTransport(
        http: httpClient,
        configuration: config,
      );

      // 上传遇到 412，比对远程批次发现内容一致，视为重试成功
      await expectLater(transport.upload(batch), completes);
    });

    test('412 crash recovery: throws SyncException when remote batch differs in content', () async {
      final batch = createSampleBatch(positionMs: 120000);
      final conflictingBatch = createSampleBatch(positionMs: 450000);

      server.listen((req) async {
        if (req.method == 'MKCOL') {
          req.response.statusCode = HttpStatus.ok;
          await req.response.close();
        } else if (req.method == 'PUT') {
          req.response.statusCode = HttpStatus.preconditionFailed;
          await req.response.close();
        } else if (req.method == 'GET') {
          // 返回冲突批次
          req.response.statusCode = HttpStatus.ok;
          req.response.headers.contentType = ContentType.json;
          req.response.write(jsonEncode(conflictingBatch.toJson()));
          await req.response.close();
        }
      });

      final config = SyncConfiguration(endpoint: serverUri);
      final transport = WebDavSyncTransport(
        http: httpClient,
        configuration: config,
      );

      expect(
        () => transport.upload(batch),
        throwsA(
          isA<SyncException>().having(
            (e) => e.message,
            'message',
            contains('内容不一致'),
          ),
        ),
      );
    });
  });

  group('WebDavSyncTransport download & validation', () {
    test('downloads and parses valid remote batch', () async {
      final expectedBatch = createSampleBatch(sequence: 5);

      server.listen((req) async {
        expect(req.method, 'GET');
        expect(req.uri.path, '/reelva-sync-v1/${expectedBatch.fileName}');
        req.response.statusCode = HttpStatus.ok;
        req.response.headers.contentType = ContentType.json;
        req.response.write(jsonEncode(expectedBatch.toJson()));
        await req.response.close();
      });

      final config = SyncConfiguration(endpoint: serverUri);
      final transport = WebDavSyncTransport(
        http: httpClient,
        configuration: config,
      );

      final downloaded = await transport.download(
        SyncRemoteBatch(
          deviceId: expectedBatch.deviceId,
          sequence: expectedBatch.sequence,
        ),
      );

      expect(downloaded.deviceId, expectedBatch.deviceId);
      expect(downloaded.sequence, expectedBatch.sequence);
      expect(downloaded.records.length, 1);
      expect(downloaded.records.first.target.id, 'movie:42');
      expect(downloaded.records.first.value['positionMs'], 120000);
    });

    test(
      'download throws SyncException when deviceId/sequence mismatch',
      () async {
        final wrongBatch = createSampleBatch(sequence: 99);

        server.listen((req) async {
          req.response.statusCode = HttpStatus.ok;
          req.response.headers.contentType = ContentType.json;
          req.response.write(jsonEncode(wrongBatch.toJson()));
          await req.response.close();
        });

        final config = SyncConfiguration(endpoint: serverUri);
        final transport = WebDavSyncTransport(
          http: httpClient,
          configuration: config,
        );

        expect(
          () => transport.download(
            const SyncRemoteBatch(deviceId: validDeviceId, sequence: 1),
          ),
          throwsA(
            isA<SyncException>().having(
              (e) => e.message,
              'message',
              contains('元数据不一致'),
            ),
          ),
        );
      },
    );

    test('download throws SyncException on HTTP 404', () async {
      server.listen((req) async {
        req.response.statusCode = HttpStatus.notFound;
        await req.response.close();
      });

      final config = SyncConfiguration(endpoint: serverUri);
      final transport = WebDavSyncTransport(
        http: httpClient,
        configuration: config,
      );

      expect(
        () => transport.download(
          const SyncRemoteBatch(deviceId: validDeviceId, sequence: 1),
        ),
        throwsA(isA<SyncException>()),
      );
    });
  });

  group('WebDavSyncTransport Safe Errors & Security', () {
    test(
      'sends Basic Auth header when username and password configured',
      () async {
        String? authHeader;

        server.listen((req) async {
          authHeader = req.headers.value(HttpHeaders.authorizationHeader);
          req.response.statusCode = HttpStatus.notFound;
          await req.response.close();
        });

        final config = SyncConfiguration(
          endpoint: serverUri,
          username: 'alice',
          password: 'mySecretPassword',
        );
        final transport = WebDavSyncTransport(
          http: httpClient,
          configuration: config,
        );

        await transport.listBatches();

        expect(authHeader, isNotNull);
        expect(authHeader, startsWith('Basic '));
        final decodedAuth = utf8.decode(
          base64Decode(authHeader!.substring('Basic '.length)),
        );
        expect(decodedAuth, 'alice:mySecretPassword');
      },
    );

    test('exceptions do not leak password or credentials', () async {
      server.listen((req) async {
        req.response.statusCode = HttpStatus.unauthorized;
        await req.response.close();
      });

      final config = SyncConfiguration(
        endpoint: serverUri,
        username: 'alice',
        password: 'superSecretPassword999',
      );
      final transport = WebDavSyncTransport(
        http: httpClient,
        configuration: config,
      );

      try {
        await transport.upload(createSampleBatch());
        fail('Should have thrown SyncException');
      } on SyncException catch (e) {
        expect(e.message, isNot(contains('superSecretPassword999')));
        expect(e.toString(), isNot(contains('superSecretPassword999')));
      }
    });
  });
}
