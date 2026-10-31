import 'dart:convert';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:reelva/features/danmaku/infrastructure/danmaku_api.dart';
import 'package:reelva/features/danmaku/infrastructure/local_danmaku_loader.dart';
import 'package:reelva/features/player/domain/playback_resource.dart';
import 'package:reelva/features/sources/domain/media_sidecar_adapter.dart';
import 'package:reelva/features/sources/domain/source_models.dart';
import 'package:reelva/features/sources/infrastructure/android_saf_source_adapter.dart';

const _recordingXml = '''<?xml version="1.0" encoding="utf-8"?>
<i>
  <BililiveRecorder version="2.20.0"/>
  <BililiveRecorderRecordInfo start_time="2026-10-25T02:10:23+08:00"/>
  <d p="83.456,4,25,65280,1792865505943,0,0,0" raw="{&quot;ignored&quot;:true}">底部 &amp; 弹幕</d>
  <gift ts="61.428" giftname="礼物"/>
  <sc ts="70" time="5" price="2">付费留言</sc>
  <guard ts="107.137" level="3"/>
  <d p="72.063,1,25,16777215,1792865494871,0,0,0">普通弹幕</d>
</i>''';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('reelva_danmaku_');
  });
  tearDown(() async {
    await directory.delete(recursive: true);
  });

  test('直接打开中文路径的视频按文件名加载同名 XML，保留时间、颜色和类型', () async {
    final video = File(p.join(directory.path, '录屏 100% #.flv'));
    final xml = File(p.setExtension(video.path, '.xml'));
    await xml.writeAsString(_recordingXml);
    const loader = LocalDanmakuLoader();
    final result = await loader.loadSibling(
      PlaybackResource(uri: video.uri, displayName: '修改后的展示名称'),
    );
    expect(result!.fileName, '录屏 100% #.xml');
    expect(result.comments.map((comment) => comment.timeMs), [72063, 83456]);
    expect(result.comments.first.text, '普通弹幕');
    expect(result.comments.last.text, '底部 & 弹幕');
    expect(result.comments.last.mode, 4);
    expect(result.comments.last.color, 0x00ff00);
    expect(result.comments.every((comment) => comment.bilibili), isTrue);
  });

  test('缺少同名文件或直接输入网络地址时不加载其他 XML', () async {
    await File(p.join(directory.path, 'other.xml'))
        .writeAsString(_recordingXml);
    const loader = LocalDanmakuLoader();
    for (final uri in [
      File(p.join(directory.path, 'movie.mkv')).uri,
      Uri.parse('https://example.test/movie.mkv'),
    ]) {
      expect(
        await loader.loadSibling(
          PlaybackResource(uri: uri, displayName: 'movie'),
        ),
        isNull,
      );
    }
  });

  test('包含大段原始消息的 XML 超过通用 2 MiB 限制仍可加载', () async {
    final xml = File(p.join(directory.path, 'large.xml'));
    await xml.writeAsString(
      '<i><d p="1.125,1,25,16777215" raw="${'x' * (3 * 1024 * 1024)}">大文件</d></i>',
    );
    final result = await const LocalDanmakuLoader().loadSibling(
      PlaybackResource(
        uri: File(p.join(directory.path, 'large.flv')).uri,
        displayName: 'large.flv',
      ),
    );
    expect(result!.comments.single.timeMs, 1125);
  });

  test('损坏和过大的本地 XML 返回明确错误', () async {
    final video = File(p.join(directory.path, 'broken.flv'));
    final xml = File(p.setExtension(video.path, '.xml'));
    final resource = PlaybackResource(
      uri: video.uri,
      displayName: 'broken.flv',
    );
    await xml.writeAsString('<i><d');
    await expectLater(
      const LocalDanmakuLoader().loadSibling(resource),
      throwsA(
        isA<DanmakuException>().having(
          (e) => e.message,
          'message',
          contains('格式无效'),
        ),
      ),
    );
    final handle = await xml.open(mode: FileMode.write);
    await handle.truncate(maxDanmakuFileBytes + 1);
    await handle.close();
    await expectLater(
      const LocalDanmakuLoader().loadSibling(resource),
      throwsA(
        isA<DanmakuException>().having(
          (e) => e.message,
          'message',
          contains('16 MiB'),
        ),
      ),
    );
  });

  test('Windows 手动选择筛选 XML，支持不同名文件和取消', () async {
    final xml = File(p.join(directory.path, '另一份弹幕.XML'));
    await xml.writeAsString(_recordingXml);
    var cancelled = false;
    final loader = LocalDanmakuLoader(
      platformOverride: TargetPlatform.windows,
      openFilePicker:
          ({
            List<XTypeGroup> acceptedTypeGroups = const [],
            String? initialDirectory,
            String? confirmButtonText,
          }) async {
            expect(acceptedTypeGroups.single.extensions, ['xml']);
            return cancelled ? null : XFile(xml.path);
          },
    );
    expect((await loader.pick())!.fileName, '另一份弹幕.XML');
    cancelled = true;
    expect(await loader.pick(), isNull);
  });

  test('媒体源只读取同名 XML，使用独立大小限制', () async {
    final adapter = _RecordingSourceAdapter();
    final result = await const LocalDanmakuLoader().loadFromSource(
      adapter: adapter,
      source: _source,
      videoId: 'opaque-video',
      fileName: '录屏.flv',
    );
    expect(adapter.readIds, ['opaque-xml']);
    expect(result!.fileName, '录屏.XML');
    expect(result.comments, hasLength(2));
  });

  test('Android 授权目录通过不透明文档标识自动发现并读取同名 XML', () async {
    const root = 'content://provider/tree/root';
    const video = '$root/document/video';
    const folder = '$root/document/folder';
    const xml = '$root/document/xml';
    const channel = MethodChannel('reelva/media_documents');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    messenger.setMockMethodCallHandler(channel, (call) async {
      final args = (call.arguments as Map).cast<String, dynamic>();
      switch (call.method) {
        case 'parentDocument':
          expect(args['documentUri'], video);
          return folder;
        case 'listChildren':
          expect(args['parentUri'], folder);
          return {
            'hasMore': false,
            'entries': [
              {
                'externalId': xml,
                'locator': xml,
                'name': '录屏.xml',
                'isDirectory': false,
              },
            ],
          };
        case 'readSidecar':
          expect(args['treeUri'], root);
          expect(args['uri'], xml);
          expect(args['maxBytes'], maxDanmakuFileBytes);
          return Uint8List.fromList(utf8.encode(_recordingXml));
        default:
          fail('Unexpected call: ${call.method}');
      }
    });
    final result = await const LocalDanmakuLoader().loadFromSource(
      adapter: const AndroidSafSourceAdapter(),
      source: const MediaSourceConfig(
        id: 1,
        kind: 'androidSaf',
        name: 'SAF',
        rootLocator: root,
      ),
      videoId: video,
      fileName: '录屏.flv',
    );
    expect(result!.comments, hasLength(2));
  });

  test('Android 单文件选择通过授权 URI 读取，拒绝非 XML 并处理取消和权限错误', () async {
    const channel = MethodChannel('reelva/media_documents');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    var name = '直播.xml';
    var cancelled = false;
    var denied = false;
    var reads = 0;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'pickDanmaku') {
        return cancelled
            ? null
            : {'uri': 'content://provider/document/xml', 'name': name};
      }
      expect(call.method, 'readDocument');
      final args = (call.arguments as Map).cast<String, dynamic>();
      expect(args['uri'], 'content://provider/document/xml');
      expect(args['maxBytes'], maxDanmakuFileBytes);
      reads++;
      if (denied) {
        throw PlatformException(
          code: 'SECURITY_ERROR',
          message: '/private/secret.xml',
        );
      }
      return Uint8List.fromList(utf8.encode(_recordingXml));
    });
    const loader = LocalDanmakuLoader(platformOverride: TargetPlatform.android);
    expect((await loader.pick())!.comments, hasLength(2));
    name = 'video.mp4';
    await expectLater(loader.pick(), throwsA(isA<DanmakuException>()));
    expect(reads, 1);
    cancelled = true;
    expect(await loader.pick(), isNull);
    cancelled = false;
    name = '直播.xml';
    denied = true;
    await expectLater(
      loader.pick(),
      throwsA(
        isA<DanmakuException>().having(
          (e) => e.message,
          'message',
          '无权访问所选媒体资源',
        ),
      ),
    );
  });
}

const _source = MediaSourceConfig(
  id: 1,
  kind: 'webdav',
  name: 'source',
  rootLocator: 'root',
);

class _RecordingSourceAdapter extends Fake implements MediaSidecarAdapter {
  final readIds = <String>[];
  @override
  Future<String?> parentDirectory(
    MediaSourceConfig source,
    String entryId,
  ) async {
    expect(entryId, 'opaque-video');
    return 'opaque-folder';
  }

  @override
  Stream<MediaEntry> listEntries(
    MediaSourceConfig source,
    String directoryId,
  ) async* {
    expect(directoryId, 'opaque-folder');
    for (final (id, name, directory) in [
      ('other', '另一部.xml', false),
      ('directory', '录屏.xml', true),
      ('opaque-xml', '录屏.XML', false),
    ]) {
      yield MediaEntry(
        externalId: id,
        locator: id,
        name: name,
        isDirectory: directory,
      );
    }
  }

  @override
  Future<Uint8List> readBytes(
    MediaSourceConfig source,
    String entryId, {
    int maxBytes = 2 * 1024 * 1024,
  }) async {
    expect(maxBytes, maxDanmakuFileBytes);
    readIds.add(entryId);
    return Uint8List.fromList(utf8.encode(_recordingXml));
  }
}
