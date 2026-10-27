import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reelva/features/sources/domain/source_models.dart';
import 'package:reelva/features/sources/infrastructure/android_saf_source_adapter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channelName = 'reelva/media_documents';
  const channel = MethodChannel(channelName);

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  const testConfig = MediaSourceConfig(
    id: 1,
    kind: 'androidSaf',
    name: '测试 SAF 媒体源',
    rootLocator:
        'content://com.android.externalstorage.documents/tree/primary%3AMovies',
  );

  test('同步索引按需解析目标路径，不遍历其他目录，且拒绝越界路径', () async {
    final directories = <String?>[];
    const folder = 'content://provider/tree/root/document/folder';
    const video = 'content://provider/tree/root/document/video';
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          final args = call.arguments as Map<dynamic, dynamic>;
          if (call.method == 'listChildren') {
            directories.add(args['parentUri'] as String?);
            return {
              'entries': args['parentUri'] == null
                  ? [
                      {
                        'externalId': folder,
                        'locator': folder,
                        'name': 'Movies',
                        'isDirectory': true,
                      },
                      {
                        'externalId': 'content://provider/other',
                        'locator': 'content://provider/other',
                        'name': 'Other',
                        'isDirectory': true,
                      },
                    ]
                  : [
                      {
                        'externalId': video,
                        'locator': video,
                        'name': 'Movie.mkv',
                        'isDirectory': false,
                      },
                    ],
              'hasMore': false,
            };
          }
          expect(call.method, 'statDocument');
          expect(args['uri'], video);
          return {'name': 'Movie.mkv'};
        });
    const adapter = AndroidSafSourceAdapter(channel: channel);
    final resource = await adapter.resolvePlayback(
      testConfig,
      Uri(
        scheme: 'reelva-index',
        pathSegments: ['Movies', 'Movie.mkv'],
      ).toString(),
    );
    expect(resource.uri.toString(), video);
    expect(directories, [null, folder]);
    await expectLater(
      adapter.resolvePlayback(testConfig, 'reelva-index:../outside.mkv'),
      throwsA(isA<MediaSourceException>()),
    );
    expect(directories, hasLength(2));
  });

  group('AndroidSafSourceAdapter pickDirectory 测试', () {
    test('用户取消选择时安全返回 null', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            expect(call.method, 'pickDirectory');
            return null;
          });

      const adapter = AndroidSafSourceAdapter(channel: channel);
      final selection = await adapter.pickDirectory();

      expect(selection, isNull);
    });

    test('成功选择目录时返回规范的 DirectorySelection', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            expect(call.method, 'pickDirectory');
            expect(call.arguments, <String, dynamic>{
              'initialLocator': 'content://initial/tree',
            });
            return <String, dynamic>{
              'rootLocator': 'content://com.android.externalstorage.documents/tree/primary%3AMovies',
              'name': 'Movies',
            };
          });

      const adapter = AndroidSafSourceAdapter(channel: channel);
      final selection = await adapter.pickDirectory(
        initialLocator: 'content://initial/tree',
      );

      expect(selection, isNotNull);
      expect(selection!.kind, 'androidSaf');
      expect(
        selection.rootLocator,
        'content://com.android.externalstorage.documents/tree/primary%3AMovies',
      );
      expect(selection.name, 'Movies');
    });

    test('原生返回空 rootLocator 时抛出 MediaSourceException', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            return <String, dynamic>{'rootLocator': '', 'name': 'Movies'};
          });

      const adapter = AndroidSafSourceAdapter(channel: channel);
      expect(
        () => adapter.pickDirectory(),
        throwsA(
          isA<MediaSourceException>().having(
            (e) => e.code,
            'code',
            'INVALID_ROOT',
          ),
        ),
      );
    });

    test('权限拒绝时不泄露底层敏感路径', () async {
      const secretVault = 'secret_private_vault_token_4918';
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            throw PlatformException(
              code: 'SECURITY_ERROR',
              message: 'Permission denied for /storage/$secretVault/tree',
            );
          });

      const adapter = AndroidSafSourceAdapter(channel: channel);
      try {
        await adapter.pickDirectory();
        fail('Should throw MediaSourceException');
      } on MediaSourceException catch (e) {
        expect(e.code, 'PERMISSION_DENIED');
        expect(e.message, contains('权限不足'));
        expect(e.toString(), isNot(contains(secretVault)));
      }
    });
  });

  group('AndroidSafSourceAdapter listEntries 分页与遍历测试', () {
    test('非法 scheme 根路径立即抛出异常', () async {
      const adapter = AndroidSafSourceAdapter(channel: channel);
      const invalidConfig = MediaSourceConfig(
        id: 2,
        kind: 'androidSaf',
        name: '非法配置',
        rootLocator: '/storage/emulated/0/Movies',
      );

      expect(
        () => adapter
            .listEntries(invalidConfig, invalidConfig.rootLocator)
            .toList(),
        throwsA(
          isA<MediaSourceException>().having(
            (e) => e.code,
            'code',
            'INVALID_LOCATOR',
          ),
        ),
      );
    });

    test('根目录多页遍历正常合并并正确识别文件与目录', () async {
      final methodCalls = <MethodCall>[];

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            methodCalls.add(call);
            final args = call.arguments as Map<dynamic, dynamic>;
            final offset = args['offset'] as int;

            if (offset == 0) {
              return <String, dynamic>{
                'hasMore': true,
                'total': 3,
                'entries': [
                  {
                    'externalId': 'content://tree/primary%3AMovies/document/primary%3AMovies%2FfolderA',
                    'locator': 'content://tree/primary%3AMovies/document/primary%3AMovies%2FfolderA',
                    'name': 'folderA',
                    'isDirectory': true,
                    'size': null,
                    'modifiedAt': 1700000000000,
                  },
                  {
                    'externalId': 'content://tree/primary%3AMovies/document/primary%3AMovies%2Fmovie1.mp4',
                    'locator': 'content://tree/primary%3AMovies/document/primary%3AMovies%2Fmovie1.mp4',
                    'name': 'movie1.mp4',
                    'isDirectory': false,
                    'size': 104857600,
                    'modifiedAt': 1700001000000,
                  },
                ],
              };
            } else {
              return <String, dynamic>{
                'hasMore': false,
                'total': 3,
                'entries': [
                  {
                    'externalId': 'content://tree/primary%3AMovies/document/primary%3AMovies%2Fmovie2.mkv',
                    'locator': 'content://tree/primary%3AMovies/document/primary%3AMovies%2Fmovie2.mkv',
                    'name': 'movie2.mkv',
                    'isDirectory': false,
                    'size': 209715200,
                    'modifiedAt': 1700002000000,
                  },
                ],
              };
            }
          });

      const adapter = AndroidSafSourceAdapter(channel: channel, pageSize: 2);
      final entries = await adapter
          .listEntries(testConfig, testConfig.rootLocator)
          .toList();

      expect(entries.length, 3);
      expect(entries[0].name, 'folderA');
      expect(entries[0].isDirectory, isTrue);
      expect(entries[0].externalId, contains('folderA'));

      expect(entries[1].name, 'movie1.mp4');
      expect(entries[1].isDirectory, isFalse);
      expect(entries[1].size, 104857600);

      expect(entries[2].name, 'movie2.mkv');
      expect(entries[2].isDirectory, isFalse);
      expect(entries[2].size, 209715200);

      expect(methodCalls.length, 2);
      expect(methodCalls[0].arguments['offset'], 0);
      expect(methodCalls[1].arguments['offset'], 2);
      expect(methodCalls[0].arguments['parentUri'], isNull);
    });

    test('子目录遍历传递正确 parentUri', () async {
      const childDirId =
          'content://tree/primary%3AMovies/document/primary%3AMovies%2Fsubfolder';
      MethodCall? capturedCall;

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            capturedCall = call;
            return <String, dynamic>{
              'hasMore': false,
              'total': 1,
              'entries': [
                {
                  'externalId': 'content://tree/primary%3AMovies/document/primary%3AMovies%2Fsubfolder%2Fclip.mp4',
                  'locator': 'content://tree/primary%3AMovies/document/primary%3AMovies%2Fsubfolder%2Fclip.mp4',
                  'name': 'clip.mp4',
                  'isDirectory': false,
                  'size': 5242880,
                  'modifiedAt': 1700003000000,
                },
              ],
            };
          });

      const adapter = AndroidSafSourceAdapter(channel: channel);
      final entries = await adapter
          .listEntries(testConfig, childDirId)
          .toList();

      expect(entries.length, 1);
      expect(entries.first.name, 'clip.mp4');
      expect(capturedCall, isNotNull);
      expect(capturedCall!.arguments['parentUri'], childDirId);
    });

    test('遍历错误时绝对不能静默返回成功空列表，必须抛出 MediaSourceException', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            throw PlatformException(
              code: 'SECURITY_ERROR',
              message: 'Permission revoked for tree',
            );
          });

      const adapter = AndroidSafSourceAdapter(channel: channel);
      expect(
        () => adapter.listEntries(testConfig, testConfig.rootLocator).toList(),
        throwsA(
          isA<MediaSourceException>().having(
            (e) => e.code,
            'code',
            'PERMISSION_DENIED',
          ),
        ),
      );
    });

    test('原生返回 null 或损坏响应必须抛出异常', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async => null);

      const adapter = AndroidSafSourceAdapter(channel: channel);
      expect(
        () => adapter.listEntries(testConfig, testConfig.rootLocator).toList(),
        throwsA(
          isA<MediaSourceException>().having((e) => e.code, 'code', 'IO_ERROR'),
        ),
      );
    });
  });

  group('AndroidSafSourceAdapter stat 元数据查询测试', () {
    test('查询存在条目成功返回 MediaStat', () async {
      const entryId =
          'content://tree/primary%3AMovies/document/primary%3AMovies%2Fvideo.mp4';

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            expect(call.method, 'statDocument');
            expect(call.arguments['uri'], entryId);
            return <String, dynamic>{
              'name': 'video.mp4',
              'isDirectory': false,
              'size': 12345678,
              'modifiedAt': 1700004000000,
            };
          });

      const adapter = AndroidSafSourceAdapter(channel: channel);
      final stat = await adapter.stat(testConfig, entryId);

      expect(stat.size, 12345678);
      expect(
        stat.modifiedAt,
        DateTime.fromMillisecondsSinceEpoch(1700004000000, isUtc: true),
      );
    });

    test('文件不存在时安全抛出 NOT_FOUND 且不泄露路径', () async {
      const entryId =
          'content://tree/primary%3AMovies/document/primary%3AMovies%2Fdeleted.mp4';

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            throw PlatformException(
              code: 'FILE_NOT_FOUND',
              message: 'Document deleted at /internal/leak/path',
            );
          });

      const adapter = AndroidSafSourceAdapter(channel: channel);
      try {
        await adapter.stat(testConfig, entryId);
        fail('Should throw MediaSourceException');
      } on MediaSourceException catch (e) {
        expect(e.code, 'NOT_FOUND');
        expect(e.message, contains('不存在'));
        expect(e.toString(), isNot(contains('/internal/leak/path')));
      }
    });
  });

  group('AndroidSafSourceAdapter resolvePlayback 播放解析测试', () {
    test('合法 content URI 解析为带展示名的 PlaybackResource', () async {
      const entryId =
          'content://tree/primary%3AMovies/document/primary%3AMovies%2Favatar.mkv';

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            if (call.method == 'statDocument') {
              return <String, dynamic>{'name': 'avatar.mkv', 'size': 9999999};
            }
            return null;
          });

      const adapter = AndroidSafSourceAdapter(channel: channel);
      final resource = await adapter.resolvePlayback(testConfig, entryId);

      expect(resource.uri.toString(), entryId);
      expect(resource.displayName, 'avatar.mkv');
      expect(resource.uri.isScheme('content'), isTrue);
    });

    test('非法 scheme 定位符解析抛出 INVALID_URI', () async {
      const adapter = AndroidSafSourceAdapter(channel: channel);
      expect(
        () => adapter.resolvePlayback(testConfig, 'file:///sdcard/video.mp4'),
        throwsA(
          isA<MediaSourceException>().having(
            (e) => e.code,
            'code',
            'INVALID_URI',
          ),
        ),
      );
    });

    test('目标文件无法 stat 访问时抛出安全异常', () async {
      const entryId =
          'content://tree/primary%3AMovies/document/primary%3AMovies%2Flost.mp4';

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            throw PlatformException(
              code: 'FILE_NOT_FOUND',
              message: 'Cannot stat document',
            );
          });

      const adapter = AndroidSafSourceAdapter(channel: channel);
      expect(
        () => adapter.resolvePlayback(testConfig, entryId),
        throwsA(
          isA<MediaSourceException>().having(
            (e) => e.code,
            'code',
            'NOT_FOUND',
          ),
        ),
      );
    });
  });

  group('AndroidSafSourceAdapter checkPermission 测试', () {
    test('权限仍有效返回 true', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            expect(call.method, 'checkPermission');
            return true;
          });

      const adapter = AndroidSafSourceAdapter(channel: channel);
      final accessible = await adapter.checkPermission(testConfig.rootLocator);
      expect(accessible, isTrue);
    });

    test('权限已失效或异常返回 false', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async => false);

      const adapter = AndroidSafSourceAdapter(channel: channel);
      final accessible = await adapter.checkPermission(testConfig.rootLocator);
      expect(accessible, isFalse);
    });
  });
}
