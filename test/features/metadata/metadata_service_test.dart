import 'dart:async';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reelva/features/library/domain/library_work.dart';
import 'package:reelva/features/library/infrastructure/media_library_repository.dart';
import 'package:reelva/features/metadata/application/metadata_service.dart';
import 'package:reelva/features/metadata/domain/tmdb_models.dart';
import 'package:reelva/features/metadata/infrastructure/tmdb_client.dart';
import 'package:reelva/features/metadata/infrastructure/tmdb_token_store.dart';

class FakeFlutterSecureStorage extends FlutterSecureStorage {
  final Map<String, String> _data = {};

  @override
  Future<String?> read({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async => _data[key];

  @override
  Future<void> write({
    required String key,
    required String? value,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (value == null) {
      _data.remove(key);
    } else {
      _data[key] = value;
    }
  }

  @override
  Future<void> delete({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async => _data.remove(key);
}

class FakeTmdbClient implements TmdbClient {
  List<TmdbWork> Function(String query, int? year)? searchMovieHandler;
  List<TmdbWork> Function(String query, int? year)? searchTvHandler;
  FutureOr<TmdbWork> Function(int id)? getMovieDetailsHandler;
  FutureOr<TmdbWork> Function(int id)? getTvDetailsHandler;
  List<TmdbEpisode> Function(int tvId, int seasonNumber)?
  getTvSeasonEpisodesHandler;

  @override
  Future<List<TmdbWork>> searchMovie(
    String query, {
    int? year,
    int page = 1,
    String language = 'zh-CN',
  }) async {
    return searchMovieHandler?.call(query, year) ?? const [];
  }

  @override
  Future<List<TmdbWork>> searchTv(
    String query, {
    int? year,
    int page = 1,
    String language = 'zh-CN',
  }) async {
    return searchTvHandler?.call(query, year) ?? const [];
  }

  @override
  Future<TmdbWork> getMovieDetails(int id, {String language = 'zh-CN'}) async {
    if (getMovieDetailsHandler != null) {
      return await getMovieDetailsHandler!(id);
    }
    return TmdbWork(id: id, type: 'movie', title: 'Movie $id');
  }

  @override
  Future<TmdbWork> getTvDetails(int id, {String language = 'zh-CN'}) async {
    if (getTvDetailsHandler != null) {
      return await getTvDetailsHandler!(id);
    }
    return TmdbWork(id: id, type: 'series', title: 'Series $id');
  }

  @override
  Future<List<TmdbEpisode>> getTvSeasonEpisodes(
    int tvId,
    int seasonNumber, {
    String language = 'zh-CN',
  }) async {
    if (getTvSeasonEpisodesHandler != null) {
      return getTvSeasonEpisodesHandler!(tvId, seasonNumber);
    }
    return const [];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeMediaLibraryRepository implements MediaLibraryRepository {
  int recognizePendingCalls = 0;
  List<LibraryWork> unmatched = [];
  Map<int, WorkDetails> detailsMap = {};
  List<Map<String, dynamic>> appliedMetadata = [];
  List<Map<String, dynamic>> appliedEpisodes = [];
  List<Map<String, dynamic>> edited = [];

  @override
  Future<void> recognizePendingFiles() async {
    recognizePendingCalls++;
  }

  @override
  Future<List<LibraryWork>> unmatchedWorks() async => unmatched;

  @override
  Future<WorkDetails?> getWorkDetails(int workId) async => detailsMap[workId];

  @override
  Future<int> applyMetadata(
    int workId,
    TmdbWork metadata, {
    bool manual = false,
    TmdbEpisode? episode,
  }) async {
    appliedMetadata.add({
      'workId': workId,
      'metadata': metadata,
      'manual': manual,
      'episode': episode,
    });
    return workId;
  }

  bool multiEpisode = false;

  @override
  Future<bool> hasMultiEpisodeFiles(int workId) async => multiEpisode;

  @override
  Future<void> applyEpisodeMetadata(
    int workId,
    List<TmdbEpisode> episodes, {
    bool manual = false,
  }) async {
    appliedEpisodes.add({
      'workId': workId,
      'episodes': episodes,
      'manual': manual,
    });
  }

  @override
  Future<void> editMetadata(
    int workId, {
    required String title,
    int? year,
    String? overview,
    String? posterPath,
  }) async {
    edited.add({
      'workId': workId,
      'title': title,
      'year': year,
      'overview': overview,
      'posterPath': posterPath,
    });
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('MetadataService', () {
    late FakeFlutterSecureStorage fakeStorage;
    late TmdbTokenStore tokenStore;
    late FakeTmdbClient fakeClient;
    late FakeMediaLibraryRepository fakeRepo;
    late MetadataService service;

    setUp(() async {
      fakeStorage = FakeFlutterSecureStorage();
      tokenStore = TmdbTokenStore(storage: fakeStorage);
      await tokenStore.save('1234567890abcdef1234567890abcdef');

      fakeClient = FakeTmdbClient();
      fakeRepo = FakeMediaLibraryRepository();

      service = MetadataService(
        tmdbClient: fakeClient,
        mediaLibraryRepository: fakeRepo,
        tokenStore: tokenStore,
      );
    });

    test('computeMatchScore gives high confidence to exact title and year', () {
      const candidate = TmdbWork(
        id: 1,
        type: 'movie',
        title: 'Interstellar',
        originalTitle: 'Interstellar',
        year: 2014,
      );

      final score = MetadataService.computeMatchScore(
        query: 'Interstellar',
        targetYear: 2014,
        candidate: candidate,
      );

      expect(score, greaterThanOrEqualTo(0.95));
    });

    test('computeMatchScore gives credit to aliases and penalizes year discrepancy', () {
      const candidateWithAlias = TmdbWork(
        id: 2,
        type: 'movie',
        title: '星际穿越',
        originalTitle: 'Interstellar',
        aliases: ['星际启示录', '星际效应'],
        year: 2014,
      );

      final aliasScore = MetadataService.computeMatchScore(
        query: '星际启示录',
        targetYear: 2014,
        candidate: candidateWithAlias,
      );
      expect(aliasScore, greaterThanOrEqualTo(0.90));

      final badYearScore = MetadataService.computeMatchScore(
        query: '星际穿越',
        targetYear: 1999, // 15 years off!
        candidate: candidateWithAlias,
      );
      expect(badYearScore, lessThan(0.40));
    });

    test('search sorts candidates descending by confidence score', () async {
      fakeClient.searchMovieHandler = (q, y) => [
        const TmdbWork(
          id: 1,
          type: 'movie',
          title: 'Avatar: The Way of Water',
          year: 2022,
        ),
        const TmdbWork(id: 2, type: 'movie', title: 'Avatar', year: 2009),
      ];

      final results = await service.search('Avatar', type: 'movie', year: 2009);
      expect(results.length, equals(2));
      // Avatar (2009) should rank first because of exact year and title match!
      expect(results.first.id, equals(2));
      expect(results.first.title, equals('Avatar'));
    });

    test(
      'refresh uses singleflight and deduplicates concurrent calls',
      () async {
        final future1 = service.refresh();
        final future2 = service.refresh();
        expect(identical(future1, future2), isTrue);
        await future1;
      },
    );

    test(
      'refresh auto-matches high confidence candidate and skips low confidence',
      () async {
        fakeRepo.unmatched = [
          const LibraryWork(
            id: 10,
            title: 'The Dark Knight',
            type: 'movie',
            year: 2008,
          ),
          const LibraryWork(
            id: 20,
            title: 'Ambiguous Movie',
            type: 'movie',
            year: 2020,
          ),
          const LibraryWork(
            id: 30,
            title: 'Locked Movie',
            type: 'movie',
            year: 2015,
            metadataLocked: true, // Should be skipped!
          ),
        ];

        fakeClient.searchMovieHandler = (query, year) {
          if (query == 'The Dark Knight') {
            return [
              const TmdbWork(
                id: 155,
                type: 'movie',
                title: 'The Dark Knight',
                year: 2008,
              ),
            ];
          }
          if (query == 'Ambiguous Movie') {
            return [
              // Two nearly identical scores with no clear winner!
              const TmdbWork(
                id: 201,
                type: 'movie',
                title: 'Ambiguous Movie 1',
                year: 2020,
              ),
              const TmdbWork(
                id: 202,
                type: 'movie',
                title: 'Ambiguous Movie 2',
                year: 2020,
              ),
            ];
          }
          return [];
        };

        final result = await service.refresh();

        expect(result.matched, equals(1)); // Only The Dark Knight
        expect(result.needsReview, equals(1)); // Ambiguous Movie
        expect(result.skipped, equals(1)); // Locked Movie
        expect(fakeRepo.appliedMetadata.length, equals(1));
        expect(fakeRepo.appliedMetadata.first['workId'], equals(10));
        expect(fakeRepo.appliedMetadata.first['manual'], isFalse);
      },
    );

    test(
      'matchManually fetches details, applies episodes for series, and locks',
      () async {
        fakeRepo.detailsMap[50] = const WorkDetails(
          work: LibraryWork(id: 50, title: 'Severance', type: 'series'),
          versions: [
            LibraryVersion(
              fileId: 1,
              fileName: 'Severance.S01E01.mkv',
              sourceName: 'Local',
              available: true,
              seasonNumber: 1,
              episodeNumber: 1,
            ),
          ],
        );

        fakeClient.getTvDetailsHandler = (id) => const TmdbWork(
          id: 115036,
          type: 'series',
          title: 'Severance',
          year: 2022,
        );

        fakeClient.getTvSeasonEpisodesHandler = (id, season) => [
          const TmdbEpisode(
            seasonNumber: 1,
            episodeNumber: 1,
            title: 'Good News About Hell',
          ),
        ];

        const candidate = TmdbWork(
          id: 115036,
          type: 'series',
          title: 'Severance',
        );
        final canonicalId = await service.matchManually(50, candidate);

        expect(canonicalId, equals(50));
        expect(fakeRepo.appliedMetadata.length, equals(1));
        expect(fakeRepo.appliedMetadata.first['manual'], isTrue);
        expect(fakeRepo.appliedEpisodes.length, equals(1));
        expect(fakeRepo.appliedEpisodes.first['manual'], isTrue);
        expect(fakeRepo.appliedEpisodes.first['episodes'].length, equals(1));
      },
    );

    test('matchManually throws on concurrent call for same workId', () async {
      fakeRepo.detailsMap[1] = const WorkDetails(
        work: LibraryWork(id: 1, title: 'Test', type: 'movie'),
        versions: [],
      );
      final completer = Completer<TmdbWork>();
      fakeClient.getMovieDetailsHandler = (id) => completer.future;

      const candidate = TmdbWork(id: 100, type: 'movie', title: 'Test');

      // First call is waiting on completer
      final future1 = service.matchManually(1, candidate);

      // Second call for the same workId should be rejected by concurrent lock
      expect(
        () => service.matchManually(1, candidate),
        throwsA(
          isA<MetadataException>().having(
            (e) => e.code,
            'code',
            'concurrent_lock',
          ),
        ),
      );

      completer.complete(const TmdbWork(id: 100, type: 'movie', title: 'Done'));
      await future1;
    });

    test(
      'matchManually throws and does not lock when season episodes fetch fails',
      () async {
        fakeRepo.detailsMap[50] = const WorkDetails(
          work: LibraryWork(id: 50, title: 'Failing Show', type: 'series'),
          versions: [
            LibraryVersion(
              fileId: 1,
              fileName: 'Failing.S01E01.mkv',
              sourceName: 'Local',
              available: true,
              seasonNumber: 1,
              episodeNumber: 1,
            ),
          ],
        );

        fakeClient.getTvDetailsHandler = (id) => const TmdbWork(
          id: 999,
          type: 'series',
          title: 'Failing Show',
          year: 2022,
        );

        fakeClient.getTvSeasonEpisodesHandler = (id, season) =>
            throw const MetadataException(
              'Season 1 not found',
              code: 'not_found',
            );

        expect(
          () => service.matchManually(
            50,
            const TmdbWork(id: 999, type: 'series', title: 'Failing Show'),
          ),
          throwsA(
            isA<MetadataException>().having((e) => e.code, 'code', 'not_found'),
          ),
        );

        expect(fakeRepo.appliedMetadata, isEmpty);
        expect(fakeRepo.appliedEpisodes, isEmpty);
      },
    );

    test('matchManually throws episode_not_found and does not write when episode does not exist', () async {
      fakeRepo.detailsMap[60] = const WorkDetails(
        work: LibraryWork(id: 60, title: 'Show'),
        versions: [
          LibraryVersion(
            fileId: 1,
            fileName: 'Show.mkv',
            sourceName: 'Local',
            available: true,
          ),
        ],
      );

      fakeClient.getTvDetailsHandler = (id) =>
          const TmdbWork(id: 100, type: 'series', title: 'Show');

      fakeClient.getTvSeasonEpisodesHandler = (id, season) => [
        const TmdbEpisode(seasonNumber: 1, episodeNumber: 1, title: 'Ep 1'),
      ];

      expect(
        () => service.matchManually(
          60,
          const TmdbWork(id: 100, type: 'series', title: 'Show'),
          episode: const TmdbEpisode(seasonNumber: 1, episodeNumber: 99),
        ),
        throwsA(
          isA<MetadataException>().having(
            (e) => e.code,
            'code',
            'episode_not_found',
          ),
        ),
      );

      expect(fakeRepo.appliedMetadata, isEmpty);
      expect(fakeRepo.appliedEpisodes, isEmpty);
    });

    test(
      'matchManually requires episode when matching unassigned work to series',
      () async {
        fakeRepo.detailsMap[61] = const WorkDetails(
          work: LibraryWork(id: 61, title: 'Show'),
          versions: [],
        );

        expect(
          () => service.matchManually(
            61,
            const TmdbWork(id: 100, type: 'series', title: 'Show'),
          ),
          throwsA(
            isA<MetadataException>().having(
              (e) => e.code,
              'code',
              'episode_required',
            ),
          ),
        );

        expect(fakeRepo.appliedMetadata, isEmpty);
      },
    );

    test(
      'matchManually rejects series to movie match with incompatible_type',
      () async {
        fakeRepo.detailsMap[62] = const WorkDetails(
          work: LibraryWork(id: 62, title: 'Series Show', type: 'series'),
          versions: [],
        );

        expect(
          () => service.matchManually(
            62,
            const TmdbWork(id: 200, type: 'movie', title: 'Movie Title'),
          ),
          throwsA(
            isA<MetadataException>().having(
              (e) => e.code,
              'code',
              'incompatible_type',
            ),
          ),
        );

        expect(fakeRepo.appliedMetadata, isEmpty);
      },
    );

    test(
      'matchManually rejects non-existent work with work_not_found',
      () async {
        expect(
          () => service.matchManually(
            9999,
            const TmdbWork(id: 100, type: 'series', title: 'Show'),
          ),
          throwsA(
            isA<MetadataException>().having(
              (e) => e.code,
              'code',
              'work_not_found',
            ),
          ),
        );
      },
    );

    test(
      'matchManually rejects multi-episode file with multi_episode_unsupported',
      () async {
        fakeRepo.detailsMap[63] = const WorkDetails(
          work: LibraryWork(id: 63, title: 'Multi Show'),
          versions: [],
        );
        fakeRepo.multiEpisode = true;

        expect(
          () => service.matchManually(
            63,
            const TmdbWork(id: 100, type: 'series', title: 'Multi Show'),
            episode: const TmdbEpisode(seasonNumber: 1, episodeNumber: 1),
          ),
          throwsA(
            isA<MetadataException>().having(
              (e) => e.code,
              'code',
              'multi_episode_unsupported',
            ),
          ),
        );

        expect(fakeRepo.appliedMetadata, isEmpty);
      },
    );

    test('editLocal validates inputs and calls repository', () async {
      expect(
        () => service.editLocal(1, title: '  '),
        throwsA(
          isA<MetadataException>().having(
            (e) => e.code,
            'code',
            'invalid_title',
          ),
        ),
      );

      expect(
        () => service.editLocal(1, title: 'Valid', year: 1800),
        throwsA(
          isA<MetadataException>().having(
            (e) => e.code,
            'code',
            'invalid_year',
          ),
        ),
      );

      await service.editLocal(
        1,
        title: 'Custom Title',
        year: 2021,
        overview: 'Custom description',
        posterPath: '/custom.jpg',
      );

      expect(fakeRepo.edited.length, equals(1));
      expect(fakeRepo.edited.first['title'], equals('Custom Title'));
      expect(fakeRepo.edited.first['year'], equals(2021));

      // Null / 空字符串允许清除海报
      await service.editLocal(
        1,
        title: 'Cleared Poster Title',
        posterPath: '   ',
      );
      expect(fakeRepo.edited.last['posterPath'], isNull);

      // 规范化补全前导斜杠
      await service.editLocal(
        1,
        title: 'Normalized Title',
        posterPath: 'poster.webp',
      );
      expect(fakeRepo.edited.last['posterPath'], equals('/poster.webp'));

      // 禁止完整 URL
      expect(
        () => service.editLocal(
          1,
          title: 'Bad URL',
          posterPath: 'https://image.tmdb.org/t/p/w500/poster.jpg',
        ),
        throwsA(
          isA<MetadataException>().having(
            (e) => e.code,
            'code',
            'invalid_poster_path',
          ),
        ),
      );

      // 禁止查询参数
      expect(
        () => service.editLocal(
          1,
          title: 'Bad Query',
          posterPath: '/poster.jpg?api_key=secret',
        ),
        throwsA(
          isA<MetadataException>().having(
            (e) => e.code,
            'code',
            'invalid_poster_path',
          ),
        ),
      );

      // 禁止非法扩展名或路径穿越
      expect(
        () => service.editLocal(
          1,
          title: 'Bad Ext',
          posterPath: '/malicious.exe',
        ),
        throwsA(
          isA<MetadataException>().having(
            (e) => e.code,
            'code',
            'invalid_poster_path',
          ),
        ),
      );

      expect(
        () => service.editLocal(
          1,
          title: 'Traversal',
          posterPath: '../escape.jpg',
        ),
        throwsA(
          isA<MetadataException>().having(
            (e) => e.code,
            'code',
            'invalid_poster_path',
          ),
        ),
      );
    });
  });
}
