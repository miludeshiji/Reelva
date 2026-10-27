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
    String? stored = 'encrypted-v1';
    var revision = 1;
    server.listen((request) async {
      if (request.method == 'MKCOL') {
        request.response.statusCode = HttpStatus.created;
      } else if (request.method == 'PROPFIND') {
        request.response.statusCode = HttpStatus.multiStatus;
        request.response.write('<D:multistatus xmlns:D="DAV:"/>');
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
    final snapshot = (await transport.downloadApplicationData())!;
    expect(snapshot.body, 'encrypted-v1');
    expect(
      await transport.uploadApplicationData(
        'stale-overwrite',
        deviceId: validDeviceId,
        etag: '"0"',
      ),
      isFalse,
    );
    expect(
      await transport.uploadApplicationData(
        'encrypted-v2',
        deviceId: validDeviceId,
        etag: snapshot.etag,
      ),
      isTrue,
    );
    expect(
      await transport.uploadApplicationData(
        'stale-overwrite',
        deviceId: validDeviceId,
        etag: snapshot.etag,
      ),
      isFalse,
    );
    expect((await transport.downloadApplicationData())!.body, 'encrypted-v2');
  });

  for (final responseEtag in [null, 'W/"1"']) {
    test('缺少强 ETag 时读取旧配置并写入独立快照（ETag：$responseEtag）', () async {
      final files = <String, String>{'application-v1.json': 'legacy-config'};
      final writes = <String>[];
      server.listen((request) async {
        final name = request.uri.pathSegments.last;
        if (request.method == 'PROPFIND') {
          request.response.statusCode = HttpStatus.multiStatus;
          request.response.write('<D:multistatus xmlns:D="DAV:">');
          for (final file in files.keys) {
            request.response.write(
              '<D:response><D:href>/reelva-sync-v1/$file</D:href>'
              '<D:status>HTTP/1.1 200 OK</D:status></D:response>',
            );
          }
          request.response.write('</D:multistatus>');
        } else if (request.method == 'MKCOL') {
          request.response.statusCode = HttpStatus.methodNotAllowed;
        } else if (request.method == 'GET') {
          if (!files.containsKey(name)) {
            request.response.statusCode = HttpStatus.notFound;
          } else {
            if (responseEtag != null) {
              request.response.headers.set(
                HttpHeaders.etagHeader,
                responseEtag,
              );
            }
            request.response.write(files[name]);
          }
        } else if (request.method == 'PUT') {
          expect(name, 'application-$validDeviceId.json');
          expect(request.headers.value(HttpHeaders.ifMatchHeader), isNull);
          expect(request.headers.value(HttpHeaders.ifNoneMatchHeader), isNull);
          writes.add(name);
          final body = await utf8.decodeStream(request);
          files[name] = body;
          request.response.statusCode = HttpStatus.created;
        }
        await request.response.close();
      });
      final transport = WebDavSyncTransport(
        http: httpClient,
        configuration: SyncConfiguration(endpoint: serverUri),
      );
      final initial = (await transport.downloadApplicationData())!;
      expect(initial.body, 'legacy-config');
      expect(initial.etag, isNull);
      await transport.uploadApplicationData(
        'new-config',
        deviceId: validDeviceId,
        etag: initial.etag,
      );
      await transport.uploadApplicationData(
        'new-config',
        deviceId: validDeviceId,
        etag: initial.etag,
      );
      expect(writes.toSet(), hasLength(1));
      expect(files['application-v1.json'], 'legacy-config');
      final combined = (await transport.downloadApplicationData())!;
      expect(combined.body, 'legacy-config');
      expect(combined.updates, ['new-config']);
      // 新目录不再创建会被并发覆盖的固定文件。
      files.remove('application-v1.json');
      final snapshotsOnly = (await transport.downloadApplicationData())!;
      expect(snapshotsOnly.body, 'new-config');
      expect(snapshotsOnly.etag, isNull);
    });
  }

  test('没有强 ETag 的两台设备并发写入，各自配置快照均保留', () async {
    final files = <String, String>{};
    server.listen((request) async {
      final name = request.uri.pathSegments.last;
      if (request.method == 'PROPFIND') {
        request.response.statusCode = HttpStatus.multiStatus;
        request.response.write('<D:multistatus xmlns:D="DAV:">');
        for (final file in files.keys) {
          request.response.write(
            '<D:response><D:href>/reelva-sync-v1/$file</D:href>'
            '<D:status>HTTP/1.1 200 OK</D:status></D:response>',
          );
        }
        request.response.write('</D:multistatus>');
      } else if (request.method == 'MKCOL') {
        request.response.statusCode = HttpStatus.created;
      } else if (request.method == 'PUT') {
        // 模拟忽略条件头、也不返回 ETag 的服务。
        files[name] = await utf8.decodeStream(request);
        request.response.statusCode = HttpStatus.created;
      } else if (files.containsKey(name)) {
        request.response.write(files[name]);
      } else {
        request.response.statusCode = HttpStatus.notFound;
      }
      await request.response.close();
    });
    final a = WebDavSyncTransport(
      http: httpClient,
      configuration: SyncConfiguration(endpoint: serverUri),
    );
    final b = WebDavSyncTransport(
      http: httpClient,
      configuration: SyncConfiguration(endpoint: serverUri),
    );
    expect(await a.downloadApplicationData(), isNull);
    expect(await b.downloadApplicationData(), isNull);
    await Future.wait([
      a.uploadApplicationData('device-a-config', deviceId: validDeviceId),
      b.uploadApplicationData('device-b-config', deviceId: otherDeviceId),
    ]);
    expect(files, hasLength(2));
    final combined = (await a.downloadApplicationData())!;
    expect([
      combined.body,
      ...combined.updates,
    ], unorderedEquals(['device-a-config', 'device-b-config']));
    expect(await a.listBatches(), isEmpty);
  });

  test('目录中的配置快照下载失败时拒绝报告同步成功', () async {
    const file = 'application-$validDeviceId.json';
    server.listen((request) async {
      if (request.method == 'PROPFIND') {
        request.response.statusCode = HttpStatus.multiStatus;
        request.response.write(
          '<D:multistatus xmlns:D="DAV:"><D:response>'
          '<D:href>/reelva-sync-v1/$file</D:href><D:status>HTTP/1.1 200 OK</D:status>'
          '</D:response></D:multistatus>',
        );
      } else if (request.uri.pathSegments.last == file) {
        request.response.statusCode = HttpStatus.notFound;
      } else {
        request.response.statusCode = HttpStatus.notFound;
      }
      await request.response.close();
    });
    final transport = WebDavSyncTransport(
      http: httpClient,
      configuration: SyncConfiguration(endpoint: serverUri),
    );
    await expectLater(
      transport.downloadApplicationData(),
      throwsA(isA<SyncException>()),
    );
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
