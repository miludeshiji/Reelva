import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:reelva/features/metadata/domain/directory_context_resolver.dart';
import 'package:reelva/features/metadata/domain/media_filename_parser.dart';

void main() {
  final cases = (jsonDecode(
    File('test/fixtures/tmdb_directory_cases.json').readAsStringSync(),
  ) as List<dynamic>).cast<Map<String, dynamic>>();
  for (final sample in cases) {
    test('${sample['source']}:${sample['line']} ${sample['name']}', () {
      final parsed = MediaFilenameParser.parse(
        sample['name'] as String,
        directoryNames: (sample['directories'] as List<dynamic>).cast<String>(),
      );
      final actual = {
        'title': parsed.title,
        'type': parsed.type,
        'season': parsed.seasonNumber,
        'episode': parsed.episodeNumber,
        'special': parsed.isSpecialOrOva,
        'extra': parsed.isExtra,
        'multi': parsed.isMultiEpisode,
        'absolute': parsed.absoluteEpisodeNumber,
        'revision': parsed.editionRevision,
        'raw': parsed.rawEpisodeToken,
        'inferred': parsed.isSeasonInferred,
      };
      final expected = sample['expected'] as Map<String, dynamic>;
      for (final entry in expected.entries.where(
        (entry) => entry.key != 'queries',
      )) {
        expect(actual[entry.key], entry.value, reason: entry.key);
      }
      for (final query in expected['queries'] as List<dynamic>? ?? const []) {
        expect(parsed.titleCandidates, contains(query));
      }
    });
  }

  test('多协议目录只取根内层级，不使用 URL 查询、凭据或不透明 SAF 标识', () {
    List<String> resolve(String kind, String root, String locator) =>
        DirectoryContextResolver.resolve(
          kind: kind,
          rootLocator: root,
          locator: locator,
        );
    expect(resolve('local', r'C:\media', r'B_冰果\S01\01.mkv'), [
      'media',
      'B_冰果',
      'S01',
    ]);
    expect(resolve('local', r'C:\media', r'C:\other\01.mkv'), isEmpty);
    expect(
      resolve('webdav', 'https://example.test/dav/动漫/', 'B_冰果/S01/01.mkv'),
      ['动漫', 'B_冰果', 'S01'],
    );
    expect(
      resolve(
        'webdav',
        'https://example.test/dav/',
        'https://example.test/01.mkv?title=foo',
      ),
      isEmpty,
    );
    expect(
      resolve('webdav', 'https://example.test/dav/', '../other/01.mkv'),
      isEmpty,
    );
    expect(
      resolve('openlist', 'https://example.test/#/media', '/media/B_冰果/01.mkv'),
      ['media', 'B_冰果'],
    );
    expect(
      resolve(
        'openlist',
        'https://example.test/#%2Fmedia%2F%E5%8A%A8%E6%BC%AB',
        '/media/动漫/B_冰果/01.mkv',
      ),
      ['动漫', 'B_冰果'],
    );
    expect(
      resolve('openlist', 'https://example.test/#/media', '/outside/01.mkv'),
      isEmpty,
    );
    expect(resolve('smb', 'smb://server/share/media', '/media/B_冰果/01.mkv'), [
      'media',
      'B_冰果',
    ]);
    expect(
      resolve(
        'androidSaf',
        'content://com.android.externalstorage.documents/tree/primary%3Amedia',
        'content://com.android.externalstorage.documents/tree/primary%3Amedia/document/primary%3Amedia%2FB_%E5%86%B0%E6%9E%9C%2F01.mkv',
      ),
      ['media', 'B_冰果'],
    );
    expect(
      resolve(
        'androidSaf',
        'content://provider/tree/123',
        'content://provider/document/456',
      ),
      isEmpty,
    );
  });

  test('真实英文冠词、片名数字和续集标记不作为目录索引删除', () {
    expect(
      MediaFilenameParser.cleanDirectoryTitle('A Beautiful Mind'),
      'A Beautiful Mind',
    );
    expect(
      MediaFilenameParser.cleanDirectoryTitle('V for Vendetta'),
      'V for Vendetta',
    );
    expect(MediaFilenameParser.parse('1917.2019.mkv').title, '1917');
    expect(MediaFilenameParser.parse('1984.mp4').year, isNull);
    expect(
      MediaFilenameParser.parse('2001.A.Space.Odyssey.1968.mkv').title,
      '2001 A Space Odyssey',
    );
  });
}
