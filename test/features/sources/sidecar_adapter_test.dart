import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reelva/features/sources/domain/source_models.dart';
import 'package:reelva/features/sources/infrastructure/android_saf_source_adapter.dart';
import 'package:reelva/features/sources/infrastructure/remote_credentials_store.dart';
import 'package:reelva/features/sources/infrastructure/remote_http_client.dart';
import 'package:reelva/features/sources/infrastructure/remote_playback_bridge.dart';
import 'package:reelva/features/sources/infrastructure/webdav_source_adapter.dart';

class _Credentials extends RemoteCredentialsStore {
  @override
  Future<RemoteCredentials> read(String? reference) async =>
      const RemoteCredentials(username: 'viewer', password: 'test-password');
}

void main() {
  test('WebDAV 小文件读写使用源认证、路径编码和条件 PUT', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final http = RemoteHttpClient();
    final requests = <String>[];
    final payload = utf8.encode('<movie><title>电影</title></movie>');
    server.listen((request) async {
      expect(
        request.headers.value('Authorization'),
        'Basic ${base64Encode(utf8.encode('viewer:test-password'))}',
      );
      requests.add('${request.method}:/${request.uri.pathSegments.join('/')}');
      if (request.method == 'PUT') {
        expect(request.headers.value('If-Match'), '"old"');
        expect(
          await request.fold<List<int>>([], (all, bytes) => all..addAll(bytes)),
          payload,
        );
        request.response.statusCode = 204;
      } else {
        request.response.add(payload);
      }
      await request.response.close();
    });
    final source = MediaSourceConfig(
      id: 1,
      kind: 'webdav',
      name: 'DAV',
      rootLocator: 'http://127.0.0.1:${server.port}/dav/',
    );
    final adapter = WebDavSourceAdapter(
      credentials: _Credentials(),
      http: http,
      playback: RemotePlaybackBridge(http: http),
    );
    try {
      await adapter.writeBytes(
        source,
        '目录',
        '电影 % #.nfo',
        Uint8List.fromList(payload),
        expectedEtag: '"old"',
      );
      expect(await adapter.readBytes(source, '目录/电影 % #.nfo'), payload);
      expect(requests, ['PUT:/dav/目录/电影 % #.nfo', 'GET:/dav/目录/电影 % #.nfo']);
      await expectLater(
        adapter.readBytes(source, '目录/电影 % #.nfo', maxBytes: 2),
        throwsA(isA<MediaSourceException>()),
      );
      await expectLater(
        adapter.writeBytes(source, '目录', '../escape.nfo', Uint8List(0)),
        throwsA(isA<MediaSourceException>()),
      );
    } finally {
      http.close();
      await server.close(force: true);
    }
  });

  test('WebDAV 新文件使用 If-None-Match，冲突不假装保存成功', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final http = RemoteHttpClient();
    server.listen((request) async {
      expect(request.headers.value('If-None-Match'), '*');
      await request.drain<void>();
      request.response.statusCode = 412;
      await request.response.close();
    });
    final source = MediaSourceConfig(
      id: 1,
      kind: 'webdav',
      name: 'DAV',
      rootLocator: 'http://127.0.0.1:${server.port}/dav/',
    );
    final adapter = WebDavSourceAdapter(
      credentials: _Credentials(),
      http: http,
      playback: RemotePlaybackBridge(http: http),
    );
    try {
      await expectLater(
        adapter.writeBytes(
          source,
          source.rootLocator,
          'movie.nfo',
          Uint8List.fromList([65]),
          createOnly: true,
        ),
        throwsA(isA<MediaSourceException>()),
      );
    } finally {
      http.close();
      await server.close(force: true);
    }
  });

  test('SAF 传递真实授权树和父目录，写入拒绝会明确报错', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    const channel = MethodChannel('reelva/test_sidecars');
    const source = MediaSourceConfig(
      id: 1,
      kind: 'androidSaf',
      name: 'SAF',
      rootLocator: 'content://documents/tree/root',
    );
    const parent = 'content://documents/tree/root/document/opaque-parent';
    final calls = <MethodCall>[];
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'readSidecar') return Uint8List.fromList([65]);
      throw PlatformException(code: 'SECURITY_ERROR');
    });
    const adapter = AndroidSafSourceAdapter(channel: channel);
    try {
      expect(await adapter.readBytes(source, '$parent-file', maxBytes: 100), [
        65,
      ]);
      expect((calls.single.arguments as Map)['maxBytes'], 100);
      await expectLater(
        adapter.writeBytes(source, parent, 'movie.nfo', Uint8List(1)),
        throwsA(
          isA<MediaSourceException>().having(
            (e) => e.code,
            'code',
            'PERMISSION_DENIED',
          ),
        ),
      );
      expect((calls.last.arguments as Map)['treeUri'], source.rootLocator);
      expect((calls.last.arguments as Map)['directoryUri'], parent);
      await expectLater(
        adapter.writeBytes(source, parent, '../movie.nfo', Uint8List(1)),
        throwsA(isA<MediaSourceException>()),
      );
      expect(calls, hasLength(2));
    } finally {
      messenger.setMockMethodCallHandler(channel, null);
    }
  });
}
