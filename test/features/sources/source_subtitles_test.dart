import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reelva/features/player/domain/playback_resource.dart';
import 'package:reelva/features/sources/application/source_subtitles.dart';
import 'package:reelva/features/sources/domain/media_source_adapter.dart';
import 'package:reelva/features/sources/domain/source_models.dart';
import 'package:reelva/features/sources/infrastructure/android_saf_source_adapter.dart';

class SubtitleSourceAdapter extends Fake implements MediaSourceAdapter {
  SubtitleSourceAdapter({this.kind = 'webdav'});
  @override
  final String kind;
  final entries = <String, List<MediaEntry>>{};
  final requestedDirectories = <String>[];
  final resolvedIds = <String>[];
  final failIds = <String>{};
  int prepareCount = 0;
  @override
  Stream<MediaEntry> listEntries(
    MediaSourceConfig source,
    String directoryId,
  ) async* {
    requestedDirectories.add(directoryId);
    yield* Stream.fromIterable(entries[directoryId] ?? []);
  }

  @override
  Future<PlaybackResource> resolvePlayback(
    MediaSourceConfig source,
    String entryId,
  ) async {
    resolvedIds.add(entryId);
    if (failIds.contains(entryId)) throw const MediaSourceException('offline');
    return PlaybackResource(
      uri: Uri(scheme: 'reelva-source', path: entryId),
      displayName: 'adapter name',
      prepare: () async {
        prepareCount++;
        return PlaybackResource(
          uri: Uri.parse('http://127.0.0.1:1234/subtitle'),
          displayName: entryId,
        );
      },
    );
  }
}

MediaEntry subtitleEntry(String id, {String? name, bool directory = false}) =>
    MediaEntry(
      externalId: id,
      locator: id,
      name: name ?? id.split('/').last,
      isDirectory: directory,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('reelva/media_documents');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  for (final (kind, root, video, parent) in [
    ('local', r'C:\Videos', 'movie.mkv', r'C:\Videos'),
    ('local', r'C:\Videos', 'Season 1/movie.mkv', 'Season 1'),
    (
      'webdav',
      'https://dav.test/videos/',
      'movie.mkv',
      'https://dav.test/videos/',
    ),
    ('webdav', 'https://dav.test/videos/', '中文 目录/movie.mkv', '中文 目录'),
    ('smb', 'smb://host/share/媒体', '/媒体/movie.mkv', '/媒体'),
  ]) {
    test('$kind 从实际父目录发现字幕，保留延迟连接和真实文件名 ($video)', () async {
      final adapter = SubtitleSourceAdapter(kind: kind);
      adapter.entries[parent] = [
        subtitleEntry('movie.zh.ASS'),
        subtitleEntry('movie.en.srt'),
        subtitleEntry('movie.mkv'),
        subtitleEntry('movie.idx'),
        subtitleEntry('folder.ass', directory: true),
      ];
      final subtitles = await discoverSourceSubtitles(
        source: MediaSourceConfig(
          id: 7,
          kind: kind,
          name: 'source',
          rootLocator: root,
        ),
        adapter: adapter,
        videoId: video,
      );
      expect(adapter.requestedDirectories, [parent]);
      expect(adapter.resolvedIds, ['movie.zh.ASS', 'movie.en.srt']);
      expect(adapter.prepareCount, 0);
      expect(subtitles.map((resource) => resource.displayName), [
        'movie.zh.ASS',
        'movie.en.srt',
      ]);
      expect(subtitles.map((resource) => resource.fileName), [
        'movie.zh.ASS',
        'movie.en.srt',
      ]);
      expect(subtitles.every((resource) => resource.sourceId == 7), isTrue);
      await subtitles.first.prepare!();
      expect(adapter.prepareCount, 1);
    });
  }

  test('一份字幕失效不影响同目录中的其他字幕', () async {
    final adapter = SubtitleSourceAdapter();
    adapter.entries['root'] = [
      subtitleEntry('missing.ass'),
      subtitleEntry('movie.srt'),
    ];
    adapter.failIds.add('missing.ass');
    final subtitles = await discoverSourceSubtitles(
      source: const MediaSourceConfig(
        id: 1,
        kind: 'webdav',
        name: 'source',
        rootLocator: 'root',
      ),
      adapter: adapter,
      videoId: 'movie.mkv',
    );
    expect(subtitles.map((resource) => resource.displayName), ['movie.srt']);
  });

  for (final fastPath in [true, false]) {
    test('SAF 使用不透明文档 ID 定位父目录，支持 provider 路径查询=$fastPath', () async {
      const root = 'content://provider/tree/root';
      const folder = '$root/document/opaque-folder';
      const video = '$root/document/opaque-video';
      const subtitle = '$root/document/opaque-subtitle';
      final queries = <String>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        final arguments = (call.arguments as Map).cast<String, dynamic>();
        switch (call.method) {
          case 'parentDocument':
            expect(arguments['treeUri'], root);
            expect(arguments['documentUri'], video);
            return fastPath ? folder : null;
          case 'listChildren':
            final parent = arguments['parentUri'] as String? ?? root;
            queries.add(parent);
            final entries = parent == root
                ? [subtitleEntry(folder, name: '目录', directory: true)]
                : [
                    subtitleEntry(video, name: 'movie.mkv'),
                    subtitleEntry(subtitle, name: 'movie.zh.ass'),
                  ];
            return {
              'hasMore': false,
              'entries': entries
                  .map(
                    (entry) => {
                      'externalId': entry.externalId,
                      'locator': entry.locator,
                      'name': entry.name,
                      'isDirectory': entry.isDirectory,
                    },
                  )
                  .toList(),
            };
          case 'statDocument':
            return {'name': 'movie.zh.ass'};
        }
        return null;
      });
      final subtitles = await discoverSourceSubtitles(
        source: const MediaSourceConfig(
          id: 4,
          kind: 'androidSaf',
          name: 'SAF',
          rootLocator: root,
        ),
        adapter: const AndroidSafSourceAdapter(),
        videoId: video,
      );
      expect(subtitles.single.uri.toString(), subtitle);
      expect(queries, fastPath ? [folder] : [root, folder, folder]);
    });
  }
}
