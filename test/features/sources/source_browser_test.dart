import 'package:flutter_test/flutter_test.dart';
import 'package:reelva/features/player/domain/playback_resource.dart';
import 'package:reelva/features/sources/application/source_browser.dart';
import 'package:reelva/features/sources/domain/media_source_adapter.dart';
import 'package:reelva/features/sources/domain/source_models.dart';

class TreeSourceAdapter implements MediaSourceAdapter {
  TreeSourceAdapter(this.entries);
  final Map<String, List<MediaEntry>> entries;
  final calls = <String>[];
  bool failNextRead = false;
  @override
  String get kind => 'local';
  @override
  Stream<MediaEntry> listEntries(
    MediaSourceConfig source,
    String directoryId,
  ) async* {
    calls.add(directoryId);
    if (failNextRead) {
      failNextRead = false;
      throw const MediaSourceException('目录读取失败');
    }
    yield* Stream.fromIterable(entries[directoryId] ?? []);
  }

  @override
  Future<DirectorySelection?> pickDirectory({String? initialLocator}) async =>
      null;
  @override
  Future<MediaStat> stat(MediaSourceConfig source, String entryId) async =>
      const MediaStat();
  @override
  Future<PlaybackResource> resolvePlayback(
    MediaSourceConfig source,
    String entryId,
  ) async => throw UnimplementedError();
}

MediaEntry treeEntry(String id, String name, {bool directory = false}) =>
    MediaEntry(externalId: id, locator: id, name: name, isDirectory: directory);

void main() {
  test('按不透明目录标识递归，过滤非视频并避免回到祖先目录', () async {
    final adapter = TreeSourceAdapter({
      'season-token': [
        treeEntry('episode-token', 'E01.mkv'),
        treeEntry('readme', 'README.txt'),
        treeEntry('hidden', '.cache', directory: true),
        treeEntry('root-token', '循环链接', directory: true),
      ],
      'root-token': [treeEntry('other', '不属于所选文件夹.mkv')],
    });
    final browser = SourceBrowser(
      source: const MediaSourceConfig(
        id: 1,
        kind: 'androidSaf',
        name: 'Show',
        rootLocator: 'root-token',
      ),
      adapter: adapter,
    );
    expect(
      browser.cachedFileIdsUnder('season-token', ancestors: ['root-token']),
      isNull,
    );
    await browser.listDirectory('season-token');
    expect(
      browser.cachedFileIdsUnder('season-token', ancestors: ['root-token']),
      {'episode-token'},
    );
    final files = await browser.collectFiles(
      directoryIds: ['root-token', 'season-token'],
      directoryNames: ['Show', 'S02'],
    );
    expect(files.single.entry.externalId, 'episode-token');
    expect(files.single.directoryNames, ['Show', 'S02']);
    expect(adapter.calls, ['season-token']);
    await browser.listDirectory('season-token');
    expect(adapter.calls.length, 1);
  });

  test('目录枚举失败后可重试，不把错误当作空文件夹', () async {
    final adapter = TreeSourceAdapter({
      'root': [treeEntry('file', 'E01.mkv')],
    })..failNextRead = true;
    final browser = SourceBrowser(
      source: const MediaSourceConfig(
        id: 1,
        kind: 'local',
        name: 'Show',
        rootLocator: 'root',
      ),
      adapter: adapter,
    );
    await expectLater(
      browser.listDirectory('root'),
      throwsA(isA<MediaSourceException>()),
    );
    expect((await browser.listDirectory('root')).single.externalId, 'file');
  });
}
