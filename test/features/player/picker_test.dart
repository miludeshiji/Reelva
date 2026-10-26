import 'package:file_selector/file_selector.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reelva/features/player/domain/playback_resource.dart';
import 'package:reelva/features/player/infrastructure/android_media_documents.dart';
import 'package:reelva/features/player/infrastructure/media_file_picker.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const mediaChannel = MethodChannel('reelva/media_documents');

  group('AndroidMediaDocuments 边界与安全映射测试', () {
    test('字幕选择使用独立通道方法，接受字幕文档并支持取消和格式校验', () async {
      var name = '影片.zh.ASS';
      var cancelled = false;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(mediaChannel, (call) async {
            expect(call.method, 'pickSubtitle');
            return cancelled
                ? null
                : {'uri': 'content://provider/document/subtitle', 'name': name};
          });
      const picker = MediaFilePicker(platformOverride: TargetPlatform.android);
      final subtitle = await picker.pickSubtitle();
      expect(subtitle!.uri.scheme, 'content');
      expect(subtitle.displayName, name);
      name = 'movie.mkv';
      await expectLater(
        picker.pickSubtitle(),
        throwsA(isA<MediaPickerException>()),
      );
      cancelled = true;
      expect(await picker.pickSubtitle(), isNull);
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(mediaChannel, null);
    });

    test('pick 用户取消时安全返回 null', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(mediaChannel, (call) async => null);

      const documents = AndroidMediaDocuments();
      final resource = await documents.pick();

      expect(resource, isNull);
    });

    test('pick 权限拒绝安全映射且不泄漏原始敏感信息', () async {
      const secretToken = 'secret_bearer_token_xyz_8971';
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            mediaChannel,
            (call) async => throw PlatformException(
              code: 'SECURITY_ERROR',
              message: 'Permission denied for /private/$secretToken/doc.mp4',
            ),
          );

      const documents = AndroidMediaDocuments();
      try {
        await documents.pick();
        fail('Should throw MediaDocumentException');
      } on MediaDocumentException catch (e) {
        expect(e.code, 'SECURITY_ERROR');
        expect(e.message, contains('无权访问'));
        expect(e.toString(), isNot(contains(secretToken)));
      }
    });

    test('openRead 权限拒绝与文件缺失安全映射且不泄漏原异常路径', () async {
      const hiddenPath = '/data/user/0/secret_vault/hidden_video.mp4';
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(mediaChannel, (call) async {
            if (call.arguments is Map &&
                (call.arguments as Map)['uri'] == 'content://denied') {
              throw PlatformException(
                code: 'SECURITY_ERROR',
                message: 'Access denied: $hiddenPath',
              );
            }
            throw PlatformException(
              code: 'FILE_NOT_FOUND',
              message: 'Not found: $hiddenPath',
            );
          });

      const documents = AndroidMediaDocuments();

      try {
        await documents.openRead(Uri.parse('content://denied'));
        fail('Should throw for security error');
      } on MediaDocumentException catch (e) {
        expect(e.code, 'SECURITY_ERROR');
        expect(e.message, contains('无权访问'));
        expect(e.toString(), isNot(contains(hiddenPath)));
      }

      try {
        await documents.openRead(Uri.parse('content://missing'));
        fail('Should throw for file not found');
      } on MediaDocumentException catch (e) {
        expect(e.code, 'FILE_NOT_FOUND');
        expect(e.message, contains('不存在'));
        expect(e.toString(), isNot(contains(hiddenPath)));
      }
    });
  });

  group('MediaFilePicker 路径转换与安全边界测试', () {
    test('Windows 字幕选择器筛选字幕格式，保留含中文和百分号的路径', () async {
      for (final name in [null, r'C:\字幕\影片 100%.zh.srt']) {
        List<XTypeGroup>? types;
        final picker = MediaFilePicker(
          platformOverride: TargetPlatform.windows,
          openFilePicker:
              ({
                List<XTypeGroup> acceptedTypeGroups = const [],
                String? initialDirectory,
                String? confirmButtonText,
              }) async {
                types = acceptedTypeGroups;
                return XFile(r'C:\字幕\影片 100%.zh.srt', name: name);
              },
        );
        final subtitle = await picker.pickSubtitle();
        expect(
          types!.single.extensions,
          containsAll(['srt', 'ass', 'ssa', 'vtt']),
        );
        expect(types!.single.extensions, isNot(contains('mkv')));
        expect(
          subtitle!.uri.toFilePath(windows: true),
          r'C:\字幕\影片 100%.zh.srt',
        );
        expect(subtitle.displayName, '影片 100%.zh.srt');
      }
    });

    test('Windows 用户取消时返回 null', () async {
      final picker = MediaFilePicker(
        platformOverride: TargetPlatform.windows,
        openFilePicker: ({
          List<XTypeGroup> acceptedTypeGroups = const [],
          String? initialDirectory,
          String? confirmButtonText,
        }) async => null,
      );

      final resource = await picker.pick();
      expect(resource, isNull);
    });

    test('Windows 含空格与中文字符路径正确转换为 file:// URI 并提取 basename', () async {
      final picker = MediaFilePicker(
        platformOverride: TargetPlatform.windows,
        openFilePicker: ({
          List<XTypeGroup> acceptedTypeGroups = const [],
          String? initialDirectory,
          String? confirmButtonText,
        }) async => XFile(r'C:\媒体 视频\测试 影片 2026.mp4', name: ''),
      );

      final resource = await picker.pick();
      expect(resource, isNotNull);
      expect(resource!.uri.scheme, 'file');
      expect(resource.displayName, '测试 影片 2026.mp4');
    });
    test('Windows 含百分号字面量与 %20 路径正确保留且不二次解码', () async {
      const fileName = '100% video %20 %movie.mp4';
      final picker = MediaFilePicker(
        platformOverride: TargetPlatform.windows,
        openFilePicker: ({
          List<XTypeGroup> acceptedTypeGroups = const [],
          String? initialDirectory,
          String? confirmButtonText,
        }) async => XFile('C:\\Media\\$fileName', name: ''),
      );

      final resource = await picker.pick();
      expect(resource, isNotNull);
      expect(resource!.uri.scheme, 'file');
      expect(resource.displayName, fileName);
    });

    test('Windows UNC 网络共享路径正确转换为 file:// URI 并提取 basename', () async {
      final picker = MediaFilePicker(
        platformOverride: TargetPlatform.windows,
        openFilePicker: ({
          List<XTypeGroup> acceptedTypeGroups = const [],
          String? initialDirectory,
          String? confirmButtonText,
        }) async => XFile(r'\\media-server\shares\sample movie.mkv', name: ''),
      );

      final resource = await picker.pick();
      expect(resource, isNotNull);
      expect(resource!.uri.scheme, 'file');
      expect(resource.uri.host, 'media-server');
      expect(resource.displayName, 'sample movie.mkv');
    });

    test('Windows 原生权限异常安全映射且不泄漏敏感信息', () async {
      const internalSecret = 'win32_audit_sec_99421';
      final picker = MediaFilePicker(
        platformOverride: TargetPlatform.windows,
        openFilePicker:
            ({
              List<XTypeGroup> acceptedTypeGroups = const [],
              String? initialDirectory,
              String? confirmButtonText,
            }) async => throw PlatformException(
              code: 'SECURITY_ERROR',
              message: 'Access is denied: $internalSecret',
            ),
      );

      try {
        await picker.pick();
        fail('Should throw MediaPickerException');
      } on MediaPickerException catch (e) {
        expect(e.code, 'SECURITY_ERROR');
        expect(e.message, contains('无权访问'));
        expect(e.toString(), isNot(contains(internalSecret)));
      }
    });

    test('Android 平台异常安全映射至 MediaPickerException', () async {
      const secret = 'android_credential_leak_112';
      final fakeDocs = _FakeAndroidMediaDocuments(
        throwException: const MediaDocumentException(
          '无权访问所选媒体资源',
          code: 'SECURITY_ERROR',
        ),
      );

      final picker = MediaFilePicker(
        platformOverride: TargetPlatform.android,
        androidDocuments: fakeDocs,
      );

      try {
        await picker.pick();
        fail('Should throw MediaPickerException');
      } on MediaPickerException catch (e) {
        expect(e.code, 'SECURITY_ERROR');
        expect(e.message, contains('无权访问'));
        expect(e.toString(), isNot(contains(secret)));
      }
    });

    test('不支持的平台显式抛出 UnsupportedError', () async {
      const pickerLinux = MediaFilePicker(
        platformOverride: TargetPlatform.linux,
      );
      const pickerMac = MediaFilePicker(platformOverride: TargetPlatform.macOS);

      expect(() => pickerLinux.pick(), throwsA(isA<UnsupportedError>()));
      expect(() => pickerMac.pick(), throwsA(isA<UnsupportedError>()));
    });
  });
}

class _FakeAndroidMediaDocuments extends AndroidMediaDocuments {
  _FakeAndroidMediaDocuments({this.throwException});

  final Exception? throwException;

  @override
  Future<PlaybackResource?> pick() async {
    if (throwException != null) {
      throw throwException!;
    }
    return null;
  }
}
