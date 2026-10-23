import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reelva/features/sources/domain/source_models.dart';
import 'package:reelva/features/sources/infrastructure/openlist_source_adapter.dart';
import 'package:reelva/features/sources/infrastructure/remote_credentials_store.dart';
import 'package:reelva/features/sources/infrastructure/remote_http_client.dart';
import 'package:reelva/features/sources/infrastructure/remote_playback_bridge.dart';

class _FakeRemoteHttpClient extends Fake implements RemoteHttpClient {
  _FakeRemoteHttpClient(this.handler);

  final Future<Response<dynamic>> Function(
    Uri uri, {
    Set<int> allowedStatusCodes,
    CancelToken? cancelToken,
    Object? data,
    Map<String, String> headers,
    String method,
    ResponseType responseType,
  })
  handler;

  @override
  Future<Response<dynamic>> request(
    Uri uri, {
    Set<int> allowedStatusCodes = const {},
    CancelToken? cancelToken,
    Object? data,
    Map<String, String> headers = const {},
    String method = 'GET',
    ResponseType responseType = ResponseType.json,
  }) {
    return handler(
      uri,
      allowedStatusCodes: allowedStatusCodes,
      cancelToken: cancelToken,
      data: data,
      headers: headers,
      method: method,
      responseType: responseType,
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  group('sanitizeAndValidateRootLocator - WebDAV', () {
    test('标准 https 地址规范化并添加末尾斜杠', () {
      final res = sanitizeAndValidateRootLocator(
        kind: 'webdav',
        rawInput: 'https://dav.example.com/media',
      );
      expect(res, 'https://dav.example.com/media/');
    });

    test('已带斜杠且含端口与 Unicode 路径正确保留', () {
      final res = sanitizeAndValidateRootLocator(
        kind: 'webdav',
        rawInput: 'http://192.168.1.50:5005/影视/高清/',
      );
      final uri = Uri.parse(res);
      expect(uri.pathSegments, ['影视', '高清', '']);
      expect(uri.port, 5005);
    });

    test('包含用户名密码的 URL 必须拒绝并提示使用下方凭据输入框', () {
      expect(
        () => sanitizeAndValidateRootLocator(
          kind: 'webdav',
          rawInput: 'https://user:secret123@dav.example.com/files/',
        ),
        throwsA(
          isA<MediaSourceException>().having(
            (e) => e.code,
            'code',
            'credentials_in_url',
          ),
        ),
      );
    });

    test('携带 Query 参数必须拒绝', () {
      expect(
        () => sanitizeAndValidateRootLocator(
          kind: 'webdav',
          rawInput: 'http://dav.example.com/dav/?token=xyz',
        ),
        throwsA(
          isA<MediaSourceException>().having(
            (e) => e.code,
            'code',
            'query_in_url',
          ),
        ),
      );
    });

    test('WebDAV 携带 Fragment 必须拒绝', () {
      expect(
        () => sanitizeAndValidateRootLocator(
          kind: 'webdav',
          rawInput: 'https://dav.example.com/dav/#frag',
        ),
        throwsA(
          isA<MediaSourceException>().having(
            (e) => e.code,
            'code',
            'fragment_not_allowed',
          ),
        ),
      );
    });

    test('解析规范化前包含未规范化的点段 (media/../etc/) 必须拦截拒绝', () {
      expect(
        () => sanitizeAndValidateRootLocator(
          kind: 'webdav',
          rawInput: 'https://dav.example.com/media/../etc/',
        ),
        throwsA(
          isA<MediaSourceException>().having(
            (e) => e.code,
            'code',
            'invalid_path_segments',
          ),
        ),
      );
    });

    test('解析规范化前包含编码点段 (media/%2e%2e/etc/) 必须拦截拒绝', () {
      expect(
        () => sanitizeAndValidateRootLocator(
          kind: 'webdav',
          rawInput: 'https://dav.example.com/media/%2e%2e/etc/',
        ),
        throwsA(
          isA<MediaSourceException>().having(
            (e) => e.code,
            'code',
            'invalid_path_segments',
          ),
        ),
      );
    });

    test('包含编码的分隔符 (%2F/%5C) 必须拒绝', () {
      expect(
        () => sanitizeAndValidateRootLocator(
          kind: 'webdav',
          rawInput: 'https://dav.example.com/media%2Fsecret/',
        ),
        throwsA(
          isA<MediaSourceException>().having(
            (e) => e.code,
            'code',
            'invalid_path_separators',
          ),
        ),
      );
    });

    test('非 http/https 协议必须抛出异常', () {
      expect(
        () => sanitizeAndValidateRootLocator(
          kind: 'webdav',
          rawInput: 'ftp://example.com/dav/',
        ),
        throwsA(
          isA<MediaSourceException>().having(
            (e) => e.code,
            'code',
            'invalid_url',
          ),
        ),
      );
    });
  });

  group('sanitizeAndValidateRootLocator - OpenList', () {
    test('支持标准 URL 且 fragment 中编码根目录路径', () {
      final res = sanitizeAndValidateRootLocator(
        kind: 'openlist',
        rawInput: 'https://alist.example.com/base#/Movies',
      );
      expect(res, 'https://alist.example.com/base#/Movies');
    });

    test('独立纯文本 openListRootPath "/100%25" 显式组件编码保留字面量百分号', () {
      final res = sanitizeAndValidateRootLocator(
        kind: 'openlist',
        rawInput: 'https://alist.example.com/base',
        openListRootPath: '/100%25',
      );
      expect(res, 'https://alist.example.com/base#/100%2525');
    });

    test('URL 中自身包含 Unicode 路径与 fragment (/电影#/100%) 正确保留', () {
      final res = sanitizeAndValidateRootLocator(
        kind: 'openlist',
        rawInput: 'https://alist.example.com/电影#/100%',
      );
      final uri = Uri.parse(res);
      expect(uri.pathSegments, ['电影']);
      expect(Uri.decodeComponent(uri.fragment), '/100%');
    });

    test('携带用户名密码或 Query 时必须明确拒绝', () {
      expect(
        () => sanitizeAndValidateRootLocator(
          kind: 'openlist',
          rawInput: 'http://user:pass@alist.example.com:5244/api#/Anime',
        ),
        throwsA(
          isA<MediaSourceException>().having(
            (e) => e.code,
            'code',
            'credentials_in_url',
          ),
        ),
      );

      expect(
        () => sanitizeAndValidateRootLocator(
          kind: 'openlist',
          rawInput: 'http://alist.example.com:5244/api?token=abc#/Anime',
        ),
        throwsA(
          isA<MediaSourceException>().having(
            (e) => e.code,
            'code',
            'query_in_url',
          ),
        ),
      );
    });

    test('根路径包含点段相对路径必须拒绝', () {
      expect(
        () => sanitizeAndValidateRootLocator(
          kind: 'openlist',
          rawInput: 'https://alist.example.com/base#/Movies/../secret',
        ),
        throwsA(
          isA<MediaSourceException>().having(
            (e) => e.code,
            'code',
            'invalid_path_segments',
          ),
        ),
      );
    });

    test('根路径包含编码点段 (%2e%2e) 必须拒绝', () {
      expect(
        () => sanitizeAndValidateRootLocator(
          kind: 'openlist',
          rawInput: 'https://alist.example.com/base',
          openListRootPath: '/Movies/%2e%2e/secret',
        ),
        throwsA(
          isA<MediaSourceException>().having(
            (e) => e.code,
            'code',
            'invalid_path_segments',
          ),
        ),
      );
    });

    test('OpenListSourceAdapter 解析 openListRootPath "/100%25" 选中的目标路径正确还原为 /100%25', () async {
      final locator = sanitizeAndValidateRootLocator(
        kind: 'openlist',
        rawInput: 'http://127.0.0.1:15244/base',
        openListRootPath: '/100%25',
      );
      expect(locator, 'http://127.0.0.1:15244/base#/100%2525');

      String? requestedPath;
      final fakeHttp = _FakeRemoteHttpClient((
        uri, {
        allowedStatusCodes = const {},
        cancelToken,
        data,
        headers = const {},
        method = 'GET',
        responseType = ResponseType.json,
      }) async {
        Map<dynamic, dynamic>? payload;
        if (data is Map) {
          payload = data;
        } else if (data is String) {
          try {
            payload = jsonDecode(data) as Map<dynamic, dynamic>?;
          } catch (_) {}
        }
        if (payload != null) {
          requestedPath = payload['path'] as String?;
        }
        return Response(
          requestOptions: RequestOptions(path: uri.toString()),
          statusCode: 200,
          data: {
            'code': 200,
            'message': 'success',
            'data': {'content': <Object?>[], 'total': 0},
          },
        );
      });

      final adapter = OpenListSourceAdapter(
        credentials: RemoteCredentialsStore(),
        http: fakeHttp,
        playback: RemotePlaybackBridge(http: fakeHttp),
      );
      final source = MediaSourceConfig(
        id: 1,
        kind: 'openlist',
        name: 'OpenList',
        rootLocator: locator,
      );

      await adapter.listEntries(source, source.rootLocator).toList();
      expect(requestedPath, '/100%25');
    });

    test('OpenListSourceAdapter 解析 /电影#/100% 选中的目标路径与 API 根基正确还原', () async {
      final locator = sanitizeAndValidateRootLocator(
        kind: 'openlist',
        rawInput: 'http://127.0.0.1:15244/电影#/100%',
      );

      String? requestedPath;
      Uri? requestedUri;
      final fakeHttp = _FakeRemoteHttpClient((
        uri, {
        allowedStatusCodes = const {},
        cancelToken,
        data,
        headers = const {},
        method = 'GET',
        responseType = ResponseType.json,
      }) async {
        requestedUri = uri;
        Map<dynamic, dynamic>? payload;
        if (data is Map) {
          payload = data;
        } else if (data is String) {
          try {
            payload = jsonDecode(data) as Map<dynamic, dynamic>?;
          } catch (_) {}
        }
        if (payload != null) {
          requestedPath = payload['path'] as String?;
        }
        return Response(
          requestOptions: RequestOptions(path: uri.toString()),
          statusCode: 200,
          data: {
            'code': 200,
            'message': 'success',
            'data': {'content': <Object?>[], 'total': 0},
          },
        );
      });

      final adapter = OpenListSourceAdapter(
        credentials: RemoteCredentialsStore(),
        http: fakeHttp,
        playback: RemotePlaybackBridge(http: fakeHttp),
      );
      final source = MediaSourceConfig(
        id: 1,
        kind: 'openlist',
        name: 'OpenList',
        rootLocator: locator,
      );

      await adapter.listEntries(source, source.rootLocator).toList();
      expect(requestedUri!.pathSegments, ['电影', 'api', 'fs', 'list']);
      expect(requestedPath, '/100%');
    });
  });

  group('sanitizeAndValidateRootLocator - SMB', () {
    test('标准 smb:// 协议路径规范化并接受 host:port', () {
      final res = sanitizeAndValidateRootLocator(
        kind: 'smb',
        rawInput: 'smb://127.0.0.1:1445/share/Media/',
      );
      expect(res, 'smb://127.0.0.1:1445/share/Media');
    });

    test('Windows 反斜杠与 UNC 格式规范化', () {
      final res = sanitizeAndValidateRootLocator(
        kind: 'smb',
        rawInput: r'\\192.168.1.10\video_share\Movies\',
      );
      expect(res, 'smb://192.168.1.10/video_share/Movies');
    });

    test('SMB 路径必须包含共享名 (Share)', () {
      expect(
        () => sanitizeAndValidateRootLocator(
          kind: 'smb',
          rawInput: 'smb://nas.local:1445/',
        ),
        throwsA(
          isA<MediaSourceException>().having(
            (e) => e.code,
            'code',
            'invalid_smb_path',
          ),
        ),
      );
    });

    test('SMB 包含用户名密码或 query 时必须拒绝', () {
      expect(
        () => sanitizeAndValidateRootLocator(
          kind: 'smb',
          rawInput: 'smb://admin:password@nas.local/media',
        ),
        throwsA(
          isA<MediaSourceException>().having(
            (e) => e.code,
            'code',
            'credentials_in_url',
          ),
        ),
      );

      expect(
        () => sanitizeAndValidateRootLocator(
          kind: 'smb',
          rawInput: 'smb://nas.local/media?query=1',
        ),
        throwsA(
          isA<MediaSourceException>().having(
            (e) => e.code,
            'code',
            'query_in_url',
          ),
        ),
      );
    });
  });
}
