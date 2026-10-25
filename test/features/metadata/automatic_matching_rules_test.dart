import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reelva/core/database/app_database.dart';
import 'package:reelva/features/library/infrastructure/media_library_repository.dart';
import 'package:reelva/features/metadata/application/metadata_service.dart';
import 'package:reelva/features/metadata/domain/match_decision.dart';
import 'package:reelva/features/metadata/domain/matching_file.dart';
import 'package:reelva/features/metadata/domain/tmdb_models.dart';
import 'package:reelva/features/metadata/infrastructure/tmdb_token_store.dart';
import 'package:reelva/features/sources/domain/source_models.dart';
import 'package:reelva/features/progress/infrastructure/playback_progress_repository.dart';

import 'metadata_service_test.dart'
    show FakeFlutterSecureStorage, FakeTmdbClient;

void main() {
  late AppDatabase db;
  late MediaLibraryRepository repo;
  late FakeTmdbClient client;
  late MetadataService service;
  late int sourceId;
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
    sourceId = (await repo.upsertSource(
      kind: 'local',
      rootLocator: 'C:/media',
      name: '媒体',
    )).id;
  });
  tearDown(() => db.close());

  Future<List<MatchingFile>> index(List<String> paths) async {
    final ids = await repo.indexSourceFiles(sourceId, [
      for (final path in paths)
        MediaEntry(
          externalId: path,
          locator: path,
          name: path.split('/').last,
          isDirectory: false,
        ),
    ]);
    return [
      for (final path in paths)
        MatchingFile(
          fileId: ids[path]!,
          name: path.split('/').last,
          directoryNames: path.split('/')..removeLast(),
        ),
    ];
  }

  const hyouka = TmdbWork(
    id: 101,
    type: 'series',
    title: '冰果',
    originalTitle: 'Hyouka',
    year: 2012,
    seasonNumbers: [0, 1],
  );
  List<TmdbEpisode> episodes(int season, int count) => [
    for (var n = 1; n <= count; n++)
      TmdbEpisode(seasonNumber: season, episodeNumber: n),
  ];

  test('无年份中文目录和罗马音联合核验，24 集共享搜索、详情与季请求', () async {
    final files = await index([
      for (var n = 1; n <= 24; n++)
        '动漫/B_冰果/[VCB-Studio] Hyouka [${n.toString().padLeft(2, '0')}][1080p].mkv',
    ]);
    final searches = <String>[];
    var details = 0;
    var seasons = 0;
    client.searchTvHandler = (query, year) {
      expect(year, isNull);
      searches.add(query);
      return [hyouka.copyWith(aliases: const [])];
    };
    client.getTvDetailsHandler = (id) {
      details++;
      return hyouka;
    };
    client.getTvSeasonEpisodesHandler = (id, season) {
      seasons++;
      return episodes(season, 24);
    };
    final result = await service.refresh();
    expect(result.matched, 1);
    expect(result.errors, isEmpty);
    expect(searches, ['冰果', 'Hyouka']);
    expect((details, seasons), (1, 1));
    final work = (await repo.watchWorks().first).single;
    expect(work.metadataSource, 'tmdb');
    expect(
      (await repo.getWorkDetails(work.id))!.versions,
      hasLength(files.length),
    );
    await service.refresh();
    expect(searches, hasLength(2));
  });

  test('年份过滤未命中会回退无年份检索，之后仍校验年份', () async {
    final files = await index(['Interstellar.2014.mkv']);
    final filters = <int?>[];
    client.searchMovieHandler = (query, year) {
      filters.add(year);
      return year != null
          ? []
          : const [
              TmdbWork(id: 1, type: 'movie', title: 'Interstellar', year: 2014),
            ];
    };
    final result = await service.matchFilesAutomatically(files);
    expect(result.matched, 1);
    expect(filters.take(2), [2014, null]);
    expect(filters.length, lessThanOrEqualTo(6));
  });

  test('短标题差一个字只推荐，保留原身份且可读出候选和原因', () async {
    final files = await index(['B_冰果/冰果.S01E01.mkv']);
    client.searchTvHandler = (query, year) => const [
      TmdbWork(id: 2, type: 'series', title: '冰果传', year: 2024),
    ];
    final result = await service.matchFilesAutomatically(files);
    expect((result.matched, result.needsReview), (0, 1));
    expect(result.reviewReasons, {MatchReason.candidateAmbiguous: 1});
    expect(await db.select(db.externalIds).get(), isEmpty);
    final work = (await repo.unmatchedWorks()).single;
    final review = (await repo.matchingFilesForWork(work.id)).single;
    expect(review.reviewReason, MatchReason.candidateAmbiguous);
    expect(review.suggestions.single.title, '冰果传');
  });

  test('旧 needs_review 条目无需重扫即可使用目录证据，迁移后保留观看进度', () async {
    final files = await index(['B_冰果/[VCB-Studio] Hyouka [01][1080p].mkv']);
    final progress = PlaybackProgressRepository(db: db);
    await progress.saveProgress(
      fileId: files.single.fileId,
      position: const Duration(minutes: 5),
      duration: const Duration(minutes: 24),
    );
    await db.customStatement(
      "UPDATE media_files SET parse_state = 'needs_review'",
    );
    client.searchTvHandler = (query, year) => [hyouka];
    client.getTvSeasonEpisodesHandler = (id, season) => episodes(season, 24);
    final result = await service.refresh();
    expect(result.matched, 1);
    expect(
      (await progress.getProgress(files.single.fileId))!.position,
      const Duration(minutes: 5),
    );
    final assignment = (await db.select(db.mediaAssignments).get()).single;
    expect(assignment.workId, isNull);
    expect(assignment.episodeId, isNotNull);
  });

  test('S02 的绝对第 13 集按已核实的前季 12 集映射为 S02E01', () async {
    final files = await index([
      'D_胆大党/Dandadan S02/[VCB-Studio] Dandadan [13].mkv',
    ]);
    const show = TmdbWork(
      id: 3,
      type: 'series',
      title: '胆大党',
      originalTitle: 'Dandadan',
    );
    client.searchTvHandler = (query, year) => [show];
    client.getTvSeasonEpisodesHandler = (id, season) => episodes(season, 12);
    final result = await service.matchFilesAutomatically(files);
    expect(result.matched, 1);
    final details = (await repo.getWorkDetails(
      (await repo.watchWorks().first).single.id,
    ))!;
    expect(
      (
        details.versions.single.seasonNumber,
        details.versions.single.episodeNumber,
      ),
      (2, 1),
    );
  });

  test('绝对编号与季内编号都合法但对应不同单集时不自动认领', () async {
    final files = await index([
      'D_胆大党/Dandadan S02/[VCB-Studio] Dandadan [13].mkv',
    ]);
    client.searchTvHandler = (query, year) => const [
      TmdbWork(id: 3, type: 'series', title: '胆大党', originalTitle: 'Dandadan'),
    ];
    client.getTvSeasonEpisodesHandler = (id, season) =>
        episodes(season, season == 1 ? 12 : 24);
    final result = await service.matchFilesAutomatically(files);
    expect(result.reviewReasons, {MatchReason.episodeMappingUnverified: 1});
    expect(await db.select(db.externalIds).get(), isEmpty);
  });

  test('纯数字默认第 1 季预填，不作为自动确认季号的证据', () async {
    final files = await index(['Z_主角/01.mp4']);
    client.searchTvHandler = (query, year) => const [
      TmdbWork(id: 4, type: 'series', title: '主角', seasonNumbers: [1]),
    ];
    final result = await service.matchFilesAutomatically(files);
    expect(files.single.seriesNumbers, (season: 1, episode: 1));
    expect(result.matched, 0);
  });

  for (final name in [
    '[VCB-Studio] Hyouka [11.5].mkv',
    '[VCB-Studio] Hyouka [OAD(00)].mkv',
  ]) {
    test('$name 使用第 0 季实际存在的唯一特别篇，并用于手动预览', () async {
      final files = await index(['B_冰果/$name']);
      client.searchTvHandler = (query, year) => [hyouka];
      client.getTvSeasonEpisodesHandler = (id, season) {
        expect(season, 0);
        return const [TmdbEpisode(seasonNumber: 0, episodeNumber: 3)];
      };
      final plans = await service.prepareFileMatches(files, hyouka);
      expect((plans.single.seasonNumber, plans.single.episodeNumber), (0, 3));
      expect(plans.single.error, isNull);
      final result = await service.matchFilesAutomatically(files);
      expect(result.matched, 1);
    });
  }

  test('第 0 季多个特别篇无法区分时保留待确认，明确标题才可映射', () async {
    final files = await index(['B_冰果/[VCB-Studio] Hyouka [11.5].mkv']);
    client.searchTvHandler = (query, year) => [hyouka];
    client.getTvSeasonEpisodesHandler = (id, season) => const [
      TmdbEpisode(seasonNumber: 0, episodeNumber: 1, title: '另一个世界 杏篇'),
      TmdbEpisode(seasonNumber: 0, episodeNumber: 2, title: '另一个世界 智代篇'),
    ];
    final result = await service.matchFilesAutomatically(files);
    expect(result.reviewReasons, {MatchReason.specialUnverified: 1});
    final named = await index(['B_冰果/Hyouka [OVA][另一个世界 杏篇].mkv']);
    final namedResult = await service.matchFilesAutomatically(named);
    expect(namedResult.matched, 1);
  });

  test('额外媒体不发请求且不出现在待匹配列表，源索引和普通影视库保留', () async {
    await index([
      'C_超时空辉夜姬/Chou Kaguya-hime! - ray MV.mkv',
      'Other/Bonus/MenuJP1.mkv',
    ]);
    client.searchMovieHandler = (_, _) => throw StateError('附属视频不应检索');
    client.searchTvHandler = (_, _) => throw StateError('附属视频不应检索');
    final result = await service.refresh();
    expect(result.errors, isEmpty);
    expect(await repo.unmatchedWorks(), isEmpty);
    expect(await repo.watchWorks(unmatchedOnly: true).first, isEmpty);
    expect(await repo.watchWorks().first, hasLength(2));
  });

  test('已确认 TMDB 绑定与人工锁都阻止后续自动覆盖', () async {
    final files = await index(['Movie.2024.mkv', 'Other.2024.mkv']);
    await repo.applyMetadataToFiles(
      {files.first.fileId: null},
      const TmdbWork(id: 9, type: 'movie', title: '已确认'),
      manual: false,
    );
    final localWork = (await repo.getVideo(files.last.fileId))!;
    final work = (await repo.unmatchedWorks()).single;
    await repo.editMetadata(work.id, title: '人工标题');
    final result = await service.matchFilesAutomatically(files);
    expect(result.skipped, 2);
    expect((await repo.getVideo(localWork.fileId))!.title, '人工标题');
    expect(
      (await db.select(db.externalIds).get()).single.providerEntityId,
      'movie:9',
    );
  });

  for (final code in ['unauthorized', 'rate_limit', 'network_error']) {
    test('$code 单独报告为错误，不计为未命中且不写外部 ID', () async {
      final files = await index(['Interstellar.2014.mkv']);
      client.searchMovieHandler = (_, _) =>
          throw MetadataException(code, code: code);
      final result = await service.matchFilesAutomatically(files);
      expect(result.errors, [code]);
      expect(result.needsReview, 0);
      expect(await db.select(db.externalIds).get(), isEmpty);
    });
  }

  test('年份、跨类型和多集范围负向样例不发生自动绑定', () async {
    final cases = (jsonDecode(
      File('test/fixtures/tmdb_directory_cases.json').readAsStringSync(),
    ) as List<dynamic>).cast<Map<String, dynamic>>();
    final range = cases.firstWhere(
      (sample) => (sample['name'] as String).contains('88-90'),
    );
    final files = await index([
      'Interstellar.2014.mkv',
      'Show.S01E01.mkv',
      'J_巨人/${range['name']}',
    ]);
    client.searchMovieHandler = (_, _) => const [
      TmdbWork(id: 1, type: 'movie', title: 'Interstellar', year: 1999),
    ];
    client.searchTvHandler = (_, _) => const [
      TmdbWork(id: 2, type: 'movie', title: 'Show'),
    ];
    final result = await service.matchFilesAutomatically(files);
    expect(result.matched, 0);
    expect(result.needsReview, 3);
    expect(await db.select(db.externalIds).get(), isEmpty);
  });

  test('目录简称与文件具体篇章冲突时不凭合集名称自动绑定', () async {
    final files = await index(['F_Fate/Fate Zero.S01E01.mkv']);
    client.searchTvHandler = (_, _) => const [
      TmdbWork(id: 50, type: 'series', title: 'Fate', seasonNumbers: [1]),
    ];
    final result = await service.matchFilesAutomatically(files);
    expect(result.matched, 0);
    expect(result.reviewReasons, {MatchReason.candidateAmbiguous: 1});
  });

  test('真实电影名中的 Movie 不是发布标签，不能删词认领另一部电影', () async {
    final files = await index(['The.Lego.Movie.2014.mkv']);
    client.searchMovieHandler = (_, _) => const [
      TmdbWork(id: 60, type: 'movie', title: 'The Lego', year: 2014),
    ];
    final result = await service.matchFilesAutomatically(files);
    expect(result.matched, 0);
    expect(await db.select(db.externalIds).get(), isEmpty);
  });

  test('本地季号不在 TMDB 实际季列表时提示核对，不误报网络错误', () async {
    final files = await index([
      'D_胆大党/Dandadan S02/[VCB-Studio] Dandadan [13].mkv',
    ]);
    client.searchTvHandler = (_, _) => const [
      TmdbWork(
        id: 3,
        type: 'series',
        title: '胆大党',
        originalTitle: 'Dandadan',
        seasonNumbers: [1],
      ),
    ];
    client.getTvSeasonEpisodesHandler = (_, _) => throw StateError('不应请求不存在的季');
    final result = await service.matchFilesAutomatically(files);
    expect(result.errors, isEmpty);
    expect(result.reviewReasons, {MatchReason.episodeMappingUnverified: 1});
  });
}
