import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reelva/core/database/app_database.dart';
import 'package:reelva/features/library/infrastructure/media_library_repository.dart';
import 'package:reelva/features/metadata/application/metadata_service.dart';
import 'package:reelva/features/metadata/domain/matching_file.dart';
import 'package:reelva/features/metadata/domain/media_filename_parser.dart';
import 'package:reelva/features/metadata/domain/tmdb_models.dart';
import 'package:reelva/features/metadata/infrastructure/tmdb_token_store.dart';
import 'package:reelva/features/sources/domain/source_models.dart';

import 'metadata_service_test.dart'
    show FakeFlutterSecureStorage, FakeTmdbClient;

void main() {
  late AppDatabase db;
  late MediaLibraryRepository repo;
  late MetadataService service;
  late FakeTmdbClient client;
  setUp(() async {
    db = AppDatabase(executor: NativeDatabase.memory());
    repo = MediaLibraryRepository(db);
    client = FakeTmdbClient();
    final tokens = TmdbTokenStore(storage: FakeFlutterSecureStorage());
    await tokens.save('1234567890abcdef1234567890abcdef');
    service = MetadataService(
      tmdbClient: client,
      mediaLibraryRepository: repo,
      tokenStore: tokens,
    );
  });
  tearDown(() => db.close());

  test('季号优先采用文件名，其次父目录，缺失时不虚构第一季', () {
    final directory = MediaFilenameParser.parse(
      'E03.mkv',
      directoryNames: ['Show.2024', 'S02'],
    );
    expect(
      (
        directory.title,
        directory.year,
        directory.seasonNumber,
        directory.episodeNumber,
      ),
      ('Show', 2024, 2, 3),
    );
    final explicit = MediaFilenameParser.parse(
      'Show.S03E01.mkv',
      directoryNames: ['Show', 'S02'],
    );
    expect(explicit.seasonNumber, 3);
    final alternate = MediaFilenameParser.parse(
      'Show.1x05.mkv',
      directoryNames: ['Show', 'S02'],
    );
    expect(alternate.seasonNumber, 1);
    expect(MediaFilenameParser.parse('Show.E03.mkv').seasonNumber, isNull);
    expect(MediaFilenameParser.parse('Show.S00E01.mkv').seasonNumber, 0);
    expect(
      MediaFilenameParser.parse('Show.E01-E02.mkv').isMultiEpisode,
      isTrue,
    );
    expect(
      MediaFilenameParser.parse('Show.2024.1080p.mkv').episodeNumber,
      isNull,
    );
    expect(MediaFilenameParser.parse('300.mkv').episodeNumber, isNull);
    expect(
      MediaFilenameParser.parse(
        '03.mkv',
        directoryNames: ['Show', 'S02'],
      ).episodeNumber,
      3,
    );
  });

  test('聚合搜索保留相同数字编号的电影与剧集', () async {
    client.searchMovieHandler = (query, year) => const [
      TmdbWork(id: 1, type: 'movie', title: 'Show', year: 2024),
    ];
    client.searchTvHandler = (query, year) => const [
      TmdbWork(id: 1, type: 'series', title: 'Show', year: 2024),
    ];
    final results = await service.search('Show');
    expect(results.map((work) => work.type).toSet(), {'movie', 'series'});
  });

  test('无季号的纯数字剧集默认第一季，并保留明确季号和人工清空', () async {
    final requested = <int>[];
    client.getTvSeasonEpisodesHandler = (id, season) {
      requested.add(season);
      return [
        for (final number in [1, 2])
          TmdbEpisode(seasonNumber: season, episodeNumber: number),
      ];
    };
    const files = [
      MatchingFile(fileId: 1, name: '01.mkv', directoryNames: ['Show']),
      MatchingFile(fileId: 2, name: '02.mp4'),
      MatchingFile(fileId: 3, name: '01.mkv', directoryNames: ['Show', 'S02']),
      MatchingFile(
        fileId: 4,
        name: '02.mkv',
        directoryNames: ['Show'],
        seasonNumber: 3,
      ),
    ];
    final plans = await service.prepareFileMatches(
      files,
      const TmdbWork(id: 1, type: 'series', title: 'Show'),
    );
    expect(plans.map((plan) => (plan.seasonNumber, plan.episodeNumber)), [
      (1, 1),
      (1, 2),
      (2, 1),
      (3, 2),
    ]);
    expect(plans.every((plan) => plan.error == null), isTrue);
    expect(requested, [1, 2, 3]);
    final cleared = await service.prepareFileMatches(
      [files.first],
      const TmdbWork(id: 1, type: 'series', title: 'Show'),
      overrides: {1: (season: null, episode: 1)},
    );
    expect(cleared.single.error, '请选择所属季');
    final numeric = MediaFilenameParser.parse(
      '02.mkv',
      directoryNames: ['Show'],
    );
    expect(
      (numeric.type, numeric.seasonNumber, numeric.episodeNumber),
      ('series', 1, 2),
    );
    expect(MediaFilenameParser.parse('300.mkv').type, isNull);
  });

  test('批量预览从各自目录读取季号，只请求所需季并标明异常文件', () async {
    final requested = <int>[];
    client.getTvSeasonEpisodesHandler = (id, season) {
      requested.add(season);
      return [TmdbEpisode(seasonNumber: season, episodeNumber: 1)];
    };
    final prepared = await service.prepareFileMatches(const [
      MatchingFile(fileId: 1, name: 'E01.mkv', directoryNames: ['Show', 'S01']),
      MatchingFile(fileId: 2, name: 'E01.mkv', directoryNames: ['Show', 'S02']),
      MatchingFile(fileId: 3, name: 'Show.S01E01.2160p.mkv'),
      MatchingFile(fileId: 4, name: 'E03.mkv'),
      MatchingFile(fileId: 5, name: 'Show.S01E99.mkv'),
      MatchingFile(fileId: 6, name: 'Show.S01E01-E02.mkv'),
    ], const TmdbWork(id: 1, type: 'series', title: 'Show'));
    expect(prepared.take(3).map((file) => file.episode?.seasonNumber), [
      1,
      2,
      1,
    ]);
    expect(requested, [1, 2]);
    expect(prepared[3].error, '请选择所属季');
    expect(prepared[4].error, contains('没有第 1 季第 99 集'));
    expect(prepared[5].error, contains('包含多集'));
  });

  test('自动匹配只处理所选文件，未选中的同作品版本保持原关联', () async {
    final source = await repo.upsertSource(
      kind: 'local',
      rootLocator: 'C:/media',
      name: '媒体',
    );
    final ids = await repo.indexSourceFiles(source.id, [
      for (final name in ['Movie.2024.1080p.mkv', 'Movie.2024.2160p.mkv'])
        MediaEntry(
          externalId: name,
          locator: name,
          name: name,
          isDirectory: false,
        ),
    ]);
    await repo.recognizePendingFiles();
    final old = (await repo.watchWorks().first).single;
    const movie = TmdbWork(id: 8, type: 'movie', title: 'Movie', year: 2024);
    client.searchMovieHandler = (query, year) => [movie];
    client.getMovieDetailsHandler = (id) => movie;
    final steps = <(int, int)>[];
    final result = await service.matchFilesAutomatically([
      MatchingFile(
        fileId: ids['Movie.2024.1080p.mkv']!,
        name: 'Movie.2024.1080p.mkv',
      ),
    ], onProgress: (done, total) => steps.add((done, total)));
    expect(result.matched, 1);
    expect(result.errors, isEmpty);
    expect(steps, [(0, 1), (1, 1)]);
    expect(
      (await repo.getWorkDetails(old.id))!.versions.single.fileId,
      ids['Movie.2024.2160p.mkv'],
    );
  });

  test('手动匹配先完成后，迟到的全库自动识别跳过旧作品而不误报失败', () async {
    final source = await repo.upsertSource(
      kind: 'local',
      rootLocator: 'C:/late',
      name: '媒体',
    );
    final ids = await repo.indexSourceFiles(source.id, const [
      MediaEntry(
        externalId: 'movie',
        locator: 'movie',
        name: 'Movie.2024.mkv',
        isDirectory: false,
      ),
    ]);
    const automatic = TmdbWork(
      id: 10,
      type: 'movie',
      title: 'Movie',
      year: 2024,
    );
    final started = Completer<void>();
    final response = Completer<TmdbWork>();
    client.searchMovieHandler = (query, year) => [automatic];
    client.getMovieDetailsHandler = (id) {
      started.complete();
      return response.future;
    };
    final refresh = service.refresh();
    await started.future;
    await repo.applyMetadataToFiles({
      ids.values.single: null,
    }, const TmdbWork(id: 20, type: 'movie', title: '手动确认的电影', year: 2024));
    response.complete(automatic);
    final result = await refresh;
    expect(result.errors, isEmpty);
    expect(result.skipped, 1);
    expect((await repo.watchWorks().first).single.title, '手动确认的电影');
  });
}
