import 'dart:typed_data';

import 'package:dart_smb2/dart_smb2.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reelva/features/player/domain/playback_resource.dart';
import 'package:reelva/features/sources/domain/source_models.dart';
import 'package:reelva/features/sources/infrastructure/remote_credentials_store.dart';
import 'package:reelva/features/sources/infrastructure/remote_http_client.dart';
import 'package:reelva/features/sources/infrastructure/remote_playback_bridge.dart';
import 'package:reelva/features/sources/infrastructure/smb_source_adapter.dart';

class _FakeRemoteCredentialsStore extends RemoteCredentialsStore {
  final Map<String, RemoteCredentials> store = {};
  int readCount = 0;

  @override
  Future<RemoteCredentials> read(String? reference) async {
    readCount++;
    if (reference == null || reference.isEmpty) {
      return const RemoteCredentials.anonymous();
    }
    final creds = store[reference];
    if (creds == null) {
      throw const MediaSourceException('未找到指定凭据记录', code: 'credential_missing');
    }
    return creds;
  }

  @override
  Future<void> write(String reference, RemoteCredentials credentials) async {
    store[reference] = credentials;
  }

  @override
  Future<void> delete(String reference) async {
    store.remove(reference);
  }
}

class _FakeRemotePlaybackBridge extends RemotePlaybackBridge {
  _FakeRemotePlaybackBridge() : super(http: RemoteHttpClient());

  String? lastDisplayName;
  RemoteByteReader? lastReader;
  int openReaderCount = 0;

  @override
  Future<PlaybackResource> openReader({
    required String displayName,
    required RemoteByteReader reader,
  }) async {
    openReaderCount++;
    lastDisplayName = displayName;
    lastReader = reader;

    return PlaybackResource(
      uri: Uri.parse('http://127.0.0.1:9999/reader-relay'),
      displayName: displayName,
      release: () async {
        await reader.close();
      },
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SMB Root Locator Parsing & Validation', () {
    test('标准 smb:// 路径正确解析 host, port, share 与根路径', () {
      final parsed = parseRootLocator('smb://127.0.0.1:1445/MEDIA');
      expect(parsed.host, '127.0.0.1:1445');
      expect(parsed.share, 'MEDIA');
      expect(parsed.rootPath, '/');
    });

    test('包含子目录的根定位符正确解析', () {
      final parsed = parseRootLocator(
        'smb://nas.local/video_share/Movies/SciFi',
      );
      expect(parsed.host, 'nas.local');
      expect(parsed.share, 'video_share');
      expect(parsed.rootPath, '/Movies/SciFi');
    });

    test('Windows UNC 格式与反斜杠自动规范化', () {
      final parsed = parseRootLocator(r'\\192.168.1.50\media\Videos');
      expect(parsed.host, '192.168.1.50');
      expect(parsed.share, 'media');
      expect(parsed.rootPath, '/Videos');
    });

    test('缺少主机名或共享名时抛出 invalid_smb_path', () {
      expect(
        () => parseRootLocator('smb:///MEDIA'),
        throwsA(
          isA<MediaSourceException>().having(
            (e) => e.code,
            'code',
            'invalid_smb_path',
          ),
        ),
      );

      expect(
        () => parseRootLocator('smb://127.0.0.1/'),
        throwsA(
          isA<MediaSourceException>().having(
            (e) => e.code,
            'code',
            'invalid_smb_path',
          ),
        ),
      );
    });

    test('URL 中携带用户名或密码时严格拒绝 (credentials_in_url)', () {
      expect(
        () => parseRootLocator('smb://admin:secret@127.0.0.1/share'),
        throwsA(
          isA<MediaSourceException>().having(
            (e) => e.code,
            'code',
            'credentials_in_url',
          ),
        ),
      );
    });

    test('URL 中携带 Query 参数时严格拒绝 (query_in_url)', () {
      expect(
        () => parseRootLocator('smb://127.0.0.1/share?token=123'),
        throwsA(
          isA<MediaSourceException>().having(
            (e) => e.code,
            'code',
            'query_in_url',
          ),
        ),
      );
    });

    test('URL 中携带 # 片段参数时严格拒绝 (fragment_not_allowed)', () {
      expect(
        () => parseRootLocator('smb://127.0.0.1/share#frag'),
        throwsA(
          isA<MediaSourceException>().having(
            (e) => e.code,
            'code',
            'fragment_not_allowed',
          ),
        ),
      );
    });

    test('URL 中包含相对点段 (. 或 ..) 时严格拒绝 (invalid_path_segments)', () {
      expect(
        () => parseRootLocator('smb://127.0.0.1/share/../secret'),
        throwsA(
          isA<MediaSourceException>().having(
            (e) => e.code,
            'code',
            'invalid_path_segments',
          ),
        ),
      );
    });

    test('包含编码分隔符 (%2F / %5C) 时严格拒绝 (invalid_path_separators)', () {
      expect(
        () => parseRootLocator('smb://127.0.0.1/share%2Fsub'),
        throwsA(
          isA<MediaSourceException>().having(
            (e) => e.code,
            'code',
            'invalid_path_separators',
          ),
        ),
      );
    });
  });

  group('SMB Path Resolution & Strict Root Containment', () {
    const rootLocator = 'smb://127.0.0.1:1445/MEDIA/Movies';
    final parsedRoot = parseRootLocator(rootLocator);

    test('空值或根定位符自身解析为 rootPath', () {
      expect(resolveWithinSharePath(parsedRoot, '', rootLocator), '/Movies');
      expect(
        resolveWithinSharePath(parsedRoot, rootLocator, rootLocator),
        '/Movies',
      );
      expect(
        resolveWithinSharePath(parsedRoot, '/Movies', rootLocator),
        '/Movies',
      );
    });

    test('共享内规范相对路径正确解析并满足包含约束', () {
      expect(
        resolveWithinSharePath(
          parsedRoot,
          '/Movies/Action/Film.mp4',
          rootLocator,
        ),
        '/Movies/Action/Film.mp4',
      );
      expect(
        resolveWithinSharePath(
          parsedRoot,
          'Movies/Action/Film.mp4',
          rootLocator,
        ),
        '/Movies/Action/Film.mp4',
      );
    });

    test('纯共享内路径包含字面量 %2f 时不被当作 URL 逃逸，作为字面字符允许', () {
      final resolved = resolveWithinSharePath(
        parsedRoot,
        '/Movies/Video 100%2fOk.mp4',
        rootLocator,
      );
      expect(resolved, '/Movies/Video 100%2fOk.mp4');
    });

    test('同主机同共享的完整 smb:// 定位符正确解析并完成单次 URL 解码', () {
      expect(
        resolveWithinSharePath(
          parsedRoot,
          'smb://127.0.0.1:1445/MEDIA/Movies/Comedy/Show.mkv',
          rootLocator,
        ),
        '/Movies/Comedy/Show.mkv',
      );

      expect(
        resolveWithinSharePath(
          parsedRoot,
          'smb://127.0.0.1:1445/MEDIA/Movies/Comedy%20Show/Episode%201.mkv',
          rootLocator,
        ),
        '/Movies/Comedy Show/Episode 1.mkv',
      );
    });

    test('试图逃离根目录的路径被严格拒绝 (path_escape)', () {
      expect(
        () => resolveWithinSharePath(
          parsedRoot,
          '/OtherFolder/secret.txt',
          rootLocator,
        ),
        throwsA(
          isA<MediaSourceException>().having(
            (e) => e.code,
            'code',
            'path_escape',
          ),
        ),
      );

      expect(
        () => resolveWithinSharePath(
          parsedRoot,
          '/Movies/../etc/passwd',
          rootLocator,
        ),
        throwsA(
          isA<MediaSourceException>().having(
            (e) => e.code,
            'code',
            'path_escape',
          ),
        ),
      );

      expect(
        () => resolveWithinSharePath(
          parsedRoot,
          'smb://evil.host:1445/MEDIA/Movies/file.mp4',
          rootLocator,
        ),
        throwsA(
          isA<MediaSourceException>().having(
            (e) => e.code,
            'code',
            'path_escape',
          ),
        ),
      );

      expect(
        () => resolveWithinSharePath(
          parsedRoot,
          'smb://127.0.0.1:1445/OTHER_SHARE/file.mp4',
          rootLocator,
        ),
        throwsA(
          isA<MediaSourceException>().having(
            (e) => e.code,
            'code',
            'path_escape',
          ),
        ),
      );
    });
  });

  group('SMB Special Characters, Unicode & URI Encoding', () {
    test('正确处理 Unicode 目录与文件名，URI 编码合规', () {
      final parsedRoot = parseRootLocator('smb://127.0.0.1:1445/MEDIA');
      final path = resolveWithinSharePath(
        parsedRoot,
        '/影视/黑客帝国.4K.mp4',
        'smb://127.0.0.1:1445/MEDIA',
      );
      expect(path, '/影视/黑客帝国.4K.mp4');

      final shareRel = toShareRelativePath(path);
      expect(shareRel, '影视/黑客帝国.4K.mp4');

      final displayName = extractDisplayName(path);
      expect(displayName, '黑客帝国.4K.mp4');

      final logicalUri = buildLogicalUri(
        parsedRoot: parsedRoot,
        withinSharePath: path,
      );
      expect(logicalUri.scheme, 'smb');
      expect(logicalUri.host, '127.0.0.1');
      expect(logicalUri.port, 1445);
      expect(logicalUri.pathSegments, ['MEDIA', '影视', '黑客帝国.4K.mp4']);
    });

    test('字面量 #, %, 空格等字符正确保留在共享路径中并在 URI 中严格百分号编码', () {
      final parsedRoot = parseRootLocator('smb://nas.local/share');
      final path = resolveWithinSharePath(
        parsedRoot,
        '/Folder #1/Video 100% [2026].mp4',
        'smb://nas.local/share',
      );
      expect(path, '/Folder #1/Video 100% [2026].mp4');

      final shareRel = toShareRelativePath(path);
      expect(shareRel, 'Folder #1/Video 100% [2026].mp4');

      final displayName = extractDisplayName(path);
      expect(displayName, 'Video 100% [2026].mp4');

      final logicalUri = buildLogicalUri(
        parsedRoot: parsedRoot,
        withinSharePath: path,
      );
      expect(logicalUri.pathSegments, [
        'share',
        'Folder #1',
        'Video 100% [2026].mp4',
      ]);
      final uriString = logicalUri.toString();
      expect(uriString, contains('%23'));
      expect(uriString, contains('%25'));
      expect(uriString, contains('%20'));
      final reParsed = Uri.parse(uriString);
      expect(reParsed.pathSegments, [
        'share',
        'Folder #1',
        'Video 100% [2026].mp4',
      ]);
    });
  });

  group('SMB Exception Classification & Secret Sanitization', () {
    test('所有 Smb2ErrorType 枚举类型均安全映射且严禁泄漏原始系统机密文本', () {
      const secretMarker = 'PASSWORD_LEAK_SECRET_TOKEN_xyz123';

      for (final type in Smb2ErrorType.values) {
        final rawException = Smb2Exception(
          'Detailed debug message containing $secretMarker',
          type: type,
        );

        final mapped = mapSmbException(rawException);

        expect(mapped.code, isNotNull);
        expect(mapped.code, isNotEmpty);

        expect(
          mapped.message,
          isNot(contains(secretMarker)),
          reason: 'Smb2ErrorType.${type.name} 泄漏了原始异常消息',
        );
        expect(
          mapped.toString(),
          isNot(contains(secretMarker)),
          reason: 'Smb2ErrorType.${type.name} toString 泄漏了原始异常消息',
        );
      }
    });

    test('具体关键错误类型映射至预期 code', () {
      expect(
        mapSmbException(
          const Smb2Exception('Auth failed', type: Smb2ErrorType.auth),
        ).code,
        'authentication_failed',
      );

      expect(
        mapSmbException(
          const Smb2Exception('Not found', type: Smb2ErrorType.notFound),
        ).code,
        'not_found',
      );

      expect(
        mapSmbException(
          const Smb2Exception('Cancelled', type: Smb2ErrorType.cancelled),
        ).code,
        'cancelled',
      );

      expect(
        mapSmbException(
          const Smb2Exception(
            'Access denied',
            type: Smb2ErrorType.accessDenied,
          ),
        ).code,
        'access_denied',
      );

      expect(
        mapSmbException(
          const Smb2Exception('Timeout', type: Smb2ErrorType.timeout),
        ).code,
        'timeout',
      );

      expect(
        mapSmbException(
          const Smb2Exception('Conn failed', type: Smb2ErrorType.connection),
        ).code,
        'connection_failed',
      );

      expect(
        mapSmbException(
          const Smb2Exception('Not dir', type: Smb2ErrorType.notADirectory),
        ).code,
        'not_a_directory',
      );

      expect(
        mapSmbException(
          const Smb2Exception('Is dir', type: Smb2ErrorType.isADirectory),
        ).code,
        'is_a_directory',
      );

      expect(
        mapSmbException(
          const Smb2Exception('In use', type: Smb2ErrorType.inUse),
        ).code,
        'resource_in_use',
      );

      expect(
        mapSmbException(
          const Smb2Exception('Disk full', type: Smb2ErrorType.diskFull),
        ).code,
        'disk_full',
      );

      expect(
        mapSmbException(
          const Smb2Exception('IO failed', type: Smb2ErrorType.io),
        ).code,
        'io_error',
      );

      expect(
        mapSmbException(
          const Smb2Exception('Unknown error', type: Smb2ErrorType.unknown),
        ).code,
        'smb_error',
      );
    });

    test(
      '权威 NT 认证状态即使底层为 connection 依然映射为 authentication_failed，无状态的 PDU 解析异常与网络拒绝保持 connection_failed',
      () {
        const logonFailureWithConnection = Smb2Exception(
          'Cannot connect: STATUS_LOGON_FAILURE',
          type: Smb2ErrorType.connection,
          ntStatus: 0xC000006D,
        );
        final mapped1 = mapSmbException(logonFailureWithConnection);
        expect(mapped1.code, 'authentication_failed');
        expect(mapped1.message, contains('认证失败'));

        const wrongPasswordWithConnection = Smb2Exception(
          'Session setup failed (0xC000006A)',
          type: Smb2ErrorType.connection,
        );
        final mapped2 = mapSmbException(wrongPasswordWithConnection);
        expect(mapped2.code, 'authentication_failed');
        expect(mapped2.message, contains('认证失败'));

        const unclassifiedPduError = Smb2Exception(
          'Cannot connect to //127.0.0.1:1445/MEDIA: smb2_service failed with : Failed to parse fixed part of command payload. Error data extends beyond end of PDU',
          type: Smb2ErrorType.connection,
        );
        final mapped3 = mapSmbException(unclassifiedPduError);
        expect(mapped3.code, 'connection_failed');
        expect(mapped3.message, '无法建立 SMB 会话，请检查网络、账号密码或服务端协议兼容性');

        const connRefused = Smb2Exception(
          'Cannot connect to //127.0.0.1:1445/MEDIA: socket connect failed with errno 111 (Connection refused)',
          type: Smb2ErrorType.connection,
          errno: 111,
        );
        final mappedNet = mapSmbException(connRefused);
        expect(mappedNet.code, 'connection_failed');
        expect(mappedNet.message, '无法建立 SMB 会话，请检查网络、账号密码或服务端协议兼容性');
      },
    );
  });

  group('SmbByteReader Behavioral Tests via Callback Injection', () {
    test('长度与范围读取支持属性正确', () {
      final reader = SmbByteReader(
        fileSize: 1024 * 1024,
        readChunk: ({
          required int offset,
          required int length,
          Smb2CancelToken? cancelToken,
        }) async => Uint8List(length),
        closeHandle: () async {},
        disconnect: () async {},
      );

      expect(reader.length, 1024 * 1024);
      expect(reader.supportsRanges, isTrue);
    });

    test('真正进行有界随机中间偏移读取，不全量拉取前序字节', () async {
      final recordedCalls = <({int offset, int length})>[];
      final reader = SmbByteReader(
        fileSize: 10 * 1024 * 1024,
        readChunk:
            ({
              required int offset,
              required int length,
              Smb2CancelToken? cancelToken,
            }) async {
              recordedCalls.add((offset: offset, length: length));
              return Uint8List(length);
            },
        closeHandle: () async {},
        disconnect: () async {},
      );

      final stream = reader.read(5000000, 5000500);
      final received = <int>[];
      await for (final chunk in stream) {
        received.addAll(chunk);
      }

      expect(received.length, 500);
      expect(recordedCalls.length, 1);
      expect(recordedCalls.first.offset, 5000000);
      expect(recordedCalls.first.length, 500);
    });

    test('尾部范围读取精确限制在文件尺寸末尾', () async {
      final recordedCalls = <({int offset, int length})>[];
      const fileSize = 1000;
      final reader = SmbByteReader(
        fileSize: fileSize,
        readChunk:
            ({
              required int offset,
              required int length,
              Smb2CancelToken? cancelToken,
            }) async {
              recordedCalls.add((offset: offset, length: length));
              return Uint8List(length);
            },
        closeHandle: () async {},
        disconnect: () async {},
      );

      final stream = reader.read(950, null);
      final received = <int>[];
      await for (final chunk in stream) {
        received.addAll(chunk);
      }

      expect(received.length, 50);
      expect(recordedCalls.single.offset, 950);
      expect(recordedCalls.single.length, 50);
    });

    test('分块最大严格限制为 256 KiB 并进行有界分段', () async {
      final recordedCalls = <({int offset, int length})>[];
      const totalRequested = 600 * 1024;
      final reader = SmbByteReader(
        fileSize: 1024 * 1024,
        readChunk:
            ({
              required int offset,
              required int length,
              Smb2CancelToken? cancelToken,
            }) async {
              recordedCalls.add((offset: offset, length: length));
              return Uint8List(length);
            },
        closeHandle: () async {},
        disconnect: () async {},
      );

      final stream = reader.read(0, totalRequested);
      int totalBytes = 0;
      await for (final chunk in stream) {
        totalBytes += chunk.length;
      }

      expect(totalBytes, totalRequested);
      expect(recordedCalls.length, 3);
      expect(recordedCalls[0].length, 256 * 1024);
      expect(recordedCalls[0].offset, 0);
      expect(recordedCalls[1].length, 256 * 1024);
      expect(recordedCalls[1].offset, 256 * 1024);
      expect(recordedCalls[2].length, 88 * 1024);
      expect(recordedCalls[2].offset, 512 * 1024);
    });

    test('提前遇到 EOF 或短读时严格报错 unexpected_eof，绝不伪装成功', () async {
      final reader = SmbByteReader(
        fileSize: 1000,
        readChunk: ({
          required int offset,
          required int length,
          Smb2CancelToken? cancelToken,
        }) async => Uint8List(0),
        closeHandle: () async {},
        disconnect: () async {},
      );

      await expectLater(
        reader.read(0, 500).toList(),
        throwsA(
          isA<MediaSourceException>().having(
            (e) => e.code,
            'code',
            'unexpected_eof',
          ),
        ),
      );
    });

    test('请求范围超出边界时抛出 range_not_satisfiable', () async {
      final reader = SmbByteReader(
        fileSize: 500,
        readChunk: ({
          required int offset,
          required int length,
          Smb2CancelToken? cancelToken,
        }) async => Uint8List(0),
        closeHandle: () async {},
        disconnect: () async {},
      );

      await expectLater(
        reader.read(-1, 100).toList(),
        throwsA(
          isA<MediaSourceException>().having(
            (e) => e.code,
            'code',
            'range_not_satisfiable',
          ),
        ),
      );

      await expectLater(
        reader.read(600, 700).toList(),
        throwsA(
          isA<MediaSourceException>().having(
            (e) => e.code,
            'code',
            'range_not_satisfiable',
          ),
        ),
      );
    });

    test('readChunk 遇到取消异常时优雅终止流且不抛出错误', () async {
      final reader = SmbByteReader(
        fileSize: 1000,
        readChunk:
            ({
              required int offset,
              required int length,
              Smb2CancelToken? cancelToken,
            }) async {
              throw const Smb2Exception(
                'Cancelled',
                type: Smb2ErrorType.cancelled,
              );
            },
        closeHandle: () async {},
        disconnect: () async {},
      );

      final chunks = await reader.read(0, 500).toList();
      expect(chunks, isEmpty);
    });

    test('外部取消流订阅时正确退出并释放读取 token', () async {
      int chunkCount = 0;
      final reader = SmbByteReader(
        fileSize: 1024 * 1024,
        readChunk:
            ({
              required int offset,
              required int length,
              Smb2CancelToken? cancelToken,
            }) async {
              chunkCount++;
              return Uint8List(length);
            },
        closeHandle: () async {},
        disconnect: () async {},
      );

      await for (final _ in reader.read(0, 1024 * 1024)) {
        break;
      }
      expect(chunkCount, 1);
    });

    test('close 依序调用 closeHandle 后再调用 disconnect', () async {
      final operationOrder = <String>[];
      final reader = SmbByteReader(
        fileSize: 1000,
        readChunk: ({
          required int offset,
          required int length,
          Smb2CancelToken? cancelToken,
        }) async => Uint8List(length),
        closeHandle: () async {
          operationOrder.add('closeHandle');
        },
        disconnect: () async {
          operationOrder.add('disconnect');
        },
      );

      await reader.close();
      expect(operationOrder, ['closeHandle', 'disconnect']);

      await expectLater(
        reader.read(0, 10).toList(),
        throwsA(
          isA<MediaSourceException>().having(
            (e) => e.code,
            'code',
            'reader_closed',
          ),
        ),
      );
    });

    test('closeHandle 抛出异常时保证断开 disconnect 且记录日志', () async {
      final operationOrder = <String>[];
      final reader = SmbByteReader(
        fileSize: 1000,
        readChunk: ({
          required int offset,
          required int length,
          Smb2CancelToken? cancelToken,
        }) async => Uint8List(length),
        closeHandle: () async {
          operationOrder.add('closeHandle');
          throw const Smb2Exception(
            'Handle close failed',
            type: Smb2ErrorType.io,
          );
        },
        disconnect: () async {
          operationOrder.add('disconnect');
        },
      );

      await reader.close();
      expect(operationOrder, ['closeHandle', 'disconnect']);
    });
  });

  group('SmbSourceAdapter Behavioral Integration Flows', () {
    late _FakeRemoteCredentialsStore credentialsStore;
    late _FakeRemotePlaybackBridge playbackBridge;

    setUp(() {
      credentialsStore = _FakeRemoteCredentialsStore();
      playbackBridge = _FakeRemotePlaybackBridge();
    });

    test('pickDirectory 明确抛出 remote_configuration_required', () async {
      final adapter = SmbSourceAdapter(
        credentials: credentialsStore,
        playback: playbackBridge,
      );

      expect(
        () => adapter.pickDirectory(),
        throwsA(
          isA<MediaSourceException>().having(
            (e) => e.code,
            'code',
            'remote_configuration_required',
          ),
        ),
      );
    });

    test('resolvePlayback 返回轻量逻辑描述符，未 prepare 前不触发 openReader', () async {
      await credentialsStore.write(
        'smb_cred_1',
        const RemoteCredentials(
          username: 'reelva_smoke',
          password: 'smoke_fixture_only',
          domain: 'WORKGROUP',
        ),
      );

      const source = MediaSourceConfig(
        id: 1,
        kind: 'smb',
        name: 'SMB Smoke',
        rootLocator: 'smb://127.0.0.1:1445/MEDIA',
        credentialRef: 'smb_cred_1',
      );

      final adapter = SmbSourceAdapter(
        credentials: credentialsStore,
        playback: playbackBridge,
      );

      final resource = await adapter.resolvePlayback(
        source,
        '/Example.Movie.2025.1080p.mp4',
      );

      expect(playbackBridge.openReaderCount, 0);
      expect(resource.displayName, 'Example.Movie.2025.1080p.mp4');
      expect(resource.uri.scheme, 'smb');
      expect(resource.uri.host, '127.0.0.1');
      expect(resource.uri.port, 1445);
      expect(resource.prepare, isNotNull);
    });
  });
}
