import 'package:flutter_test/flutter_test.dart';
import 'package:reelva/features/sources/domain/source_models.dart';

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
