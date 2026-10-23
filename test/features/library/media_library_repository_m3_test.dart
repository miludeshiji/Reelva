import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reelva/core/database/app_database.dart';
import 'package:reelva/features/library/infrastructure/media_library_repository.dart';
import 'package:reelva/features/metadata/domain/tmdb_models.dart';
import 'package:reelva/features/sources/domain/source_models.dart';

void main() {
  group('MediaLibraryRepository M3 behavioral requirements', () {
    late AppDatabase db;
    late MediaLibraryRepository repo;

    setUp(() {
      db = AppDatabase(executor: NativeDatabase.memory());
      repo = MediaLibraryRepository(db);
    });

    tearDown(() async {
      await db.close();
    });

    test('recognizePendingFiles groups two quality versions of same movie into one work', () async {
      final source = await repo.upsertSource(
        kind: 'local',
        rootLocator: 'C:/Movies',
        name: 'Movies',
      );

      final now = DateTime.now();
      final entries = [
        MediaEntry(
          externalId: 'm1',
          locator: 'Inception.2010.1080p.mkv',
          name: 'Inception.2010.1080p.mkv',
          isDirectory: false,
          size: 2000000000,
          modifiedAt: now,
        ),
        MediaEntry(
          externalId: 'm2',
          locator: 'Inception.2010.2160p.4K.mkv',
          name: 'Inception.2010.2160p.4K.mkv',
          isDirectory: false,
          size: 8000000000,
          modifiedAt: now,
        ),
      ];

      final scanId = await repo.beginScan(source.id);
      await repo.applyScanBatch(source.id, scanId, entries);
      await repo.finishScan(source.id, scanId);

      // 验证通过 watchWorks 识别后仅产生一个逻辑作品，且 versionCount 为 2
      final works = await repo.watchWorks().first;
      expect(works, hasLength(1));
      final work = works.first;
      expect(work.title, 'Inception');
      expect(work.year, 2010);
      expect(work.type, 'movie');
      expect(work.versionCount, 2);

      // 验证详情包含两个不同版本的 LibraryVersion
      final details = await repo.getWorkDetails(work.id);
      expect(details, isNotNull);
      expect(details!.versions, hasLength(2));
      final fileNames = details.versions.map((v) => v.fileName).toList();
      expect(fileNames, contains('Inception.2010.1080p.mkv'));
      expect(fileNames, contains('Inception.2010.2160p.4K.mkv'));
    });

    test('recognizePendingFiles creates series, season, and episode hierarchy without trigger violation', () async {
      final source = await repo.upsertSource(
        kind: 'local',
        rootLocator: 'C:/TV',
        name: 'TV',
      );

      final now = DateTime.now();
      final entries = [
        MediaEntry(
          externalId: 'bb1',
          locator: 'Breaking.Bad.S01E01.Pilot.1080p.mkv',
          name: 'Breaking.Bad.S01E01.Pilot.1080p.mkv',
          isDirectory: false,
          size: 1500000000,
          modifiedAt: now,
        ),
        MediaEntry(
          externalId: 'bb2',
          locator: 'Breaking.Bad.S01E02.Cat.in.the.Bag.1080p.mkv',
          name: 'Breaking.Bad.S01E02.Cat.in.the.Bag.1080p.mkv',
          isDirectory: false,
          size: 1500000000,
          modifiedAt: now,
        ),
      ];

      final scanId = await repo.beginScan(source.id);
      await repo.applyScanBatch(source.id, scanId, entries);
      await repo.finishScan(source.id, scanId);

      final works = await repo.watchWorks().first;
      expect(works, hasLength(1));
      final seriesWork = works.first;
      expect(seriesWork.title, 'Breaking Bad');
      expect(seriesWork.type, 'series');
      expect(seriesWork.versionCount, 2);

      // 验证数据库底层的 seasons 和 episodes 表结构
      final seasons = await (db.select(
        db.seasons,
      )..where((s) => s.seriesId.equals(seriesWork.id))).get();
      expect(seasons, hasLength(1));
      expect(seasons.first.seasonNumber, 1);

      final episodes = await (db.select(
        db.episodes,
      )..where((e) => e.seasonId.equals(seasons.first.id))).get();
      expect(episodes, hasLength(2));
      expect(episodes.map((e) => e.episodeNumber).toList()..sort(), [1, 2]);

      // 验证 media_assignments 绑定在 episode_id 上，且 work_id 为 null（符合数据库触发器）
      final assignments = await db.select(db.mediaAssignments).get();
      expect(assignments, hasLength(2));
      expect(
        assignments.every((a) => a.workId == null && a.episodeId != null),
        isTrue,
      );

      // 验证 watchWorkDetails 正确输出季集号
      final details = await repo.getWorkDetails(seriesWork.id);
      expect(details, isNotNull);
      expect(details!.versions, hasLength(2));
      expect(details.versions.every((v) => v.seasonNumber == 1), isTrue);
      expect(details.versions.map((v) => v.episodeNumber).toList()..sort(), [
        1,
        2,
      ]);
    });

    test('multi-episode and unknown candidates remain needs-review without faking episodes', () async {
      final source = await repo.upsertSource(
        kind: 'local',
        rootLocator: 'C:/Media',
        name: 'Media',
      );

      final now = DateTime.now();
      final entries = [
        MediaEntry(
          externalId: 'multi1',
          locator: 'Friends.S03E01-E02.1080p.mkv',
          name: 'Friends.S03E01-E02.1080p.mkv',
          isDirectory: false,
          size: 1000000000,
          modifiedAt: now,
        ),
        MediaEntry(
          externalId: 'special1',
          locator: 'Attack.on.Titan.Special.mkv',
          name: 'Attack.on.Titan.Special.mkv',
          isDirectory: false,
          size: 1000000000,
          modifiedAt: now,
        ),
      ];

      final scanId = await repo.beginScan(source.id);
      await repo.applyScanBatch(source.id, scanId, entries);
      await repo.finishScan(source.id, scanId);

      // 验证 media_files.parse_state 被标记为 needs_review
      final files = await db.select(db.mediaFiles).get();
      expect(files, hasLength(2));
      expect(files.every((f) => f.parseState == 'needs_review'), isTrue);

      // 严禁在 episodes 表中伪造假的单集
      final episodes = await db.select(db.episodes).get();
      expect(episodes, isEmpty);

      // 严禁将 series 作品直接挂载为 movie assignment（候选作品保留 type == null，不违反触发器）
      final assignments = await db.select(db.mediaAssignments).get();
      expect(assignments, hasLength(2));
      for (final a in assignments) {
        expect(a.workId, isNotNull);
        final work = await (db.select(
          db.works,
        )..where((w) => w.id.equals(a.workId!))).getSingle();
        expect(work.type, isNull);
      }
    });

    test('preserves user manual metadata lock and existing playback progress during recognition', () async {
      final source = await repo.upsertSource(
        kind: 'local',
        rootLocator: 'C:/Movies',
        name: 'Movies',
      );

      final now = DateTime.now();
      final entries = [
        MediaEntry(
          externalId: 'entry1',
          locator: 'Custom.Movie.2020.mkv',
          name: 'Custom.Movie.2020.mkv',
          isDirectory: false,
          size: 1000000000,
          modifiedAt: now,
        ),
      ];

      final scanId = await repo.beginScan(source.id);
      await repo.applyScanBatch(source.id, scanId, entries);

      // 在 finishScan 识别前，用户先进行了手动编辑加锁与播放进度记录
      final assignment = (await db.select(db.mediaAssignments).get()).first;
      await repo.editMetadata(
        assignment.workId!,
        title: 'User Locked Title',
        year: 2021,
      );

      // 插入播放进度
      await db
          .into(db.playbackProgresses)
          .insert(
            PlaybackProgressesCompanion.insert(
              targetType: 'work',
              targetId: assignment.workId!,
              workId: Value(assignment.workId),
              positionMs: const Value(120000),
              durationMs: const Value(3600000),
            ),
          );

      await repo.finishScan(source.id, scanId);

      // 验证识别后手动加锁的标题未被文件名解析覆盖
      final works = await repo.watchWorks().first;
      expect(works, hasLength(1));
      expect(works.first.title, 'User Locked Title');
      expect(works.first.year, 2021);
      expect(works.first.metadataLocked, isTrue);

      // 验证播放进度保持完好
      final prog = await (db.select(
        db.playbackProgresses,
      )..where((p) => p.workId.equals(assignment.workId!))).getSingle();
      expect(prog.positionMs, 120000);
    });

    test('applyMetadata merges same TMDB work into canonical work and migrates progress', () async {
      final source = await repo.upsertSource(
        kind: 'local',
        rootLocator: 'C:/Films',
        name: 'Films',
      );

      // 创建两部原本由于文件名差异未归并的电影候选作品
      final now = DateTime.now();
      final entries = [
        MediaEntry(
          externalId: 'cd1',
          locator: 'Matrix.Part1.mkv',
          name: 'Matrix.Part1.mkv',
          isDirectory: false,
          size: 1000,
          modifiedAt: now,
        ),
        MediaEntry(
          externalId: 'cd2',
          locator: 'The.Matrix.1999.mkv',
          name: 'The.Matrix.1999.mkv',
          isDirectory: false,
          size: 2000,
          modifiedAt: now,
        ),
      ];

      final scanId = await repo.beginScan(source.id);
      await repo.applyScanBatch(source.id, scanId, entries);
      await repo.finishScan(source.id, scanId);

      final initialWorks = await db.select(db.works).get();
      expect(initialWorks, hasLength(2));
      final work1Id = initialWorks[0].id;
      final work2Id = initialWorks[1].id;

      // 为 work2 记录播放进度
      await db
          .into(db.playbackProgresses)
          .insert(
            PlaybackProgressesCompanion.insert(
              targetType: 'work',
              targetId: work2Id,
              workId: Value(work2Id),
              positionMs: const Value(45000),
              durationMs: const Value(7200000),
            ),
          );

      const tmdbMetadata = TmdbWork(
        id: 603,
        type: 'movie',
        title: 'The Matrix',
        originalTitle: 'The Matrix',
        year: 1999,
        overview: 'Welcome to the Real World.',
      );

      // 1. work1 匹配到 TMDB 603
      final canonicalId1 = await repo.applyMetadata(
        work1Id,
        tmdbMetadata,
        manual: true,
      );
      expect(canonicalId1, work1Id);

      // 2. work2 也匹配到相同的 TMDB 603 -> 应当归并到 canonicalId1
      final canonicalId2 = await repo.applyMetadata(
        work2Id,
        tmdbMetadata,
        manual: true,
      );
      expect(canonicalId2, canonicalId1);

      // 验证被合并的旧 work2 已被安全清理，两份媒体文件均归属于 canonicalId1
      final worksAfterMerge = await repo.watchWorks().first;
      expect(worksAfterMerge, hasLength(1));
      expect(worksAfterMerge.first.id, canonicalId1);
      expect(worksAfterMerge.first.versionCount, 2);

      // 验证播放进度已迁移到 canonicalId1
      final prog = await (db.select(
        db.playbackProgresses,
      )..where((p) => p.workId.equals(canonicalId1))).getSingle();
      expect(prog.positionMs, 45000);
    });
    test('automatic merge into locked canonical work preserves canonical title and lock state', () async {
      final source = await repo.upsertSource(
        kind: 'local',
        rootLocator: 'C:/Movies',
        name: 'Movies',
      );

      final now = DateTime.now();
      final entries = [
        MediaEntry(
          externalId: 'm_lock1',
          locator: 'Alien.1979.1080p.mkv',
          name: 'Alien.1979.1080p.mkv',
          isDirectory: false,
          size: 2000,
          modifiedAt: now,
        ),
        MediaEntry(
          externalId: 'm_lock2',
          locator: 'Alien.1979.2160p.mkv',
          name: 'Alien.1979.2160p.mkv',
          isDirectory: false,
          size: 8000,
          modifiedAt: now,
        ),
      ];

      final scanId = await repo.beginScan(source.id);
      await repo.applyScanBatch(source.id, scanId, entries);
      await repo.finishScan(source.id, scanId);

      final works = await repo.watchWorks().first;
      final canonicalId = works.first.id;

      // 手动编辑 canonical 作品并加锁
      await repo.editMetadata(
        canonicalId,
        title: 'Alien (User Custom Locked Title)',
      );
      await db.customStatement(
        'INSERT INTO external_ids (work_id, provider, provider_entity_id, created_at) VALUES (?, ?, ?, ?)',
        [
          canonicalId,
          'tmdb',
          'movie:348',
          DateTime.now().millisecondsSinceEpoch ~/ 1000,
        ],
      );

      // 创建一个临时作品代表待自动匹配的新文件
      final orphanWorkId = await db
          .into(db.works)
          .insert(
            WorksCompanion.insert(
              title: 'Alien Incoming',
              metadataSource: const Value('local'),
              metadataLocked: const Value(false),
            ),
          );
      final orphanFileId = (await db.select(db.mediaFiles).get()).last.id;
      await (db.update(db.mediaAssignments)
            ..where((a) => a.fileId.equals(orphanFileId)))
          .write(MediaAssignmentsCompanion(workId: Value(orphanWorkId)));

      // 自动匹配调用（manual == false）
      const autoMetadata = TmdbWork(
        id: 348,
        type: 'movie',
        title: 'Alien Overwrite Attempt',
        overview: 'Overwritten overview',
      );
      final mergedId = await repo.applyMetadata(
        orphanWorkId,
        autoMetadata,
        manual: false,
      );
      expect(mergedId, canonicalId);

      // 验证 canonical 作品的人工标题与锁定状态完好无损，但版本已被并入
      final canonicalDetails = await repo.getWorkDetails(canonicalId);
      expect(canonicalDetails!.work.title, 'Alien (User Custom Locked Title)');
      expect(canonicalDetails.work.metadataLocked, isTrue);
      expect(canonicalDetails.versions, hasLength(2));
    });

    test(
      'manual rebinding to new TMDB ID removes stale old external_ids',
      () async {
        final source = await repo.upsertSource(
          kind: 'local',
          rootLocator: 'C:/Movies',
          name: 'Movies',
        );

        final now = DateTime.now();
        final entries = [
          MediaEntry(
            externalId: 'rebind1',
            locator: 'Rematch.Movie.2020.mkv',
            name: 'Rematch.Movie.2020.mkv',
            isDirectory: false,
            size: 1000,
            modifiedAt: now,
          ),
        ];

        final scanId = await repo.beginScan(source.id);
        await repo.applyScanBatch(source.id, scanId, entries);
        await repo.finishScan(source.id, scanId);

        final work = (await repo.watchWorks().first).first;

        // 1. 初次绑定到 TMDB 550
        await repo.applyMetadata(
          work.id,
          const TmdbWork(id: 550, type: 'movie', title: 'Fight Club'),
          manual: true,
        );
        final ext550 = await db
            .customSelect(
              'SELECT work_id FROM external_ids WHERE provider = ? AND provider_entity_id = ?',
              variables: [
                Variable.withString('tmdb'),
                Variable.withString('movie:550'),
              ],
            )
            .getSingleOrNull();
        expect(ext550?.read<int>('work_id'), work.id);

        // 2. 人工改绑到 TMDB 600
        await repo.applyMetadata(
          work.id,
          const TmdbWork(id: 600, type: 'movie', title: 'Full Metal Jacket'),
          manual: true,
        );
        // 验证旧的 550 记录已被彻底清理，不再指向该作品
        final ext550After = await db
            .customSelect(
              'SELECT work_id FROM external_ids WHERE provider = ? AND provider_entity_id = ?',
              variables: [
                Variable.withString('tmdb'),
                Variable.withString('movie:550'),
              ],
            )
            .getSingleOrNull();
        expect(ext550After, isNull);

        // 新的 600 记录生效
        final ext600 = await db
            .customSelect(
              'SELECT work_id FROM external_ids WHERE provider = ? AND provider_entity_id = ?',
              variables: [
                Variable.withString('tmdb'),
                Variable.withString('movie:600'),
              ],
            )
            .getSingleOrNull();
        expect(ext600?.read<int>('work_id'), work.id);
      },
    );

    test(
      'series with different explicit years create separate series works',
      () async {
        final source = await repo.upsertSource(
          kind: 'local',
          rootLocator: 'C:/TV',
          name: 'TV',
        );

        final now = DateTime.now();
        final entries = [
          MediaEntry(
            externalId: 'fargo1',
            locator: 'Fargo.1996.S01E01.mkv',
            name: 'Fargo.1996.S01E01.mkv',
            isDirectory: false,
            size: 1000,
            modifiedAt: now,
          ),
          MediaEntry(
            externalId: 'fargo2',
            locator: 'Fargo.2014.S01E01.mkv',
            name: 'Fargo.2014.S01E01.mkv',
            isDirectory: false,
            size: 1000,
            modifiedAt: now,
          ),
        ];

        final scanId = await repo.beginScan(source.id);
        await repo.applyScanBatch(source.id, scanId, entries);
        await repo.finishScan(source.id, scanId);

        // 明确不同年份的同名剧集严格建立两个独立剧集作品，不发生错误合并
        final works = await repo.watchWorks().first;
        expect(works, hasLength(2));
        final years = works.map((w) => w.year).toSet();
        expect(years, contains(1996));
        expect(years, contains(2014));
      },
    );

    test('series without year still establishes series season 1 episode 5 hierarchy', () async {
      final source = await repo.upsertSource(
        kind: 'local',
        rootLocator: 'C:/TV',
        name: 'TV',
      );

      final now = DateTime.now();
      final entries = [
        MediaEntry(
          externalId: 'noyear1',
          locator: 'Show.Name.S01E05.1080p.mkv',
          name: 'Show.Name.S01E05.1080p.mkv',
          isDirectory: false,
          size: 1000,
          modifiedAt: now,
        ),
      ];

      final scanId = await repo.beginScan(source.id);
      await repo.applyScanBatch(source.id, scanId, entries);
      await repo.finishScan(source.id, scanId);

      final works = await repo.watchWorks().first;
      expect(works, hasLength(1));
      final work = works.first;
      expect(work.title, 'Show Name');
      expect(work.type, 'series');

      final details = await repo.getWorkDetails(work.id);
      expect(details!.versions, hasLength(1));
      expect(details.versions.first.seasonNumber, 1);
      expect(details.versions.first.episodeNumber, 5);
    });

    test(
      'directory entries are excluded from library works count and display',
      () async {
        final source = await repo.upsertSource(
          kind: 'local',
          rootLocator: 'C:/Media',
          name: 'Media',
        );

        final now = DateTime.now();
        final entries = [
          MediaEntry(
            externalId: 'dir1',
            locator: 'FolderEntry',
            name: 'FolderEntry',
            isDirectory: true,
            size: 0,
            modifiedAt: now,
          ),
        ];

        final scanId = await repo.beginScan(source.id);
        await repo.applyScanBatch(source.id, scanId, entries);
        await repo.finishScan(source.id, scanId);

        final works = await repo.watchWorks().first;
        expect(works, isEmpty);
      },
    );

    test(
      'applyMetadata rejects incompatible movie vs series matching',
      () async {
        final source = await repo.upsertSource(
          kind: 'local',
          rootLocator: 'C:/TV',
          name: 'TV',
        );

        final now = DateTime.now();
        final entries = [
          MediaEntry(
            externalId: 's1',
            locator: 'Show.S01E01.mkv',
            name: 'Show.S01E01.mkv',
            isDirectory: false,
            size: 1000,
            modifiedAt: now,
          ),
        ];

        final scanId = await repo.beginScan(source.id);
        await repo.applyScanBatch(source.id, scanId, entries);
        await repo.finishScan(source.id, scanId);

        final seriesWork = (await repo.watchWorks().first).first;
        expect(seriesWork.type, 'series');

        // 尝试将已有季集的剧集作品匹配为电影 -> 抛出 ArgumentError
        expect(
          () => repo.applyMetadata(
            seriesWork.id,
            const TmdbWork(id: 999, type: 'movie', title: 'Some Movie'),
            manual: true,
          ),
          throwsA(isA<ArgumentError>()),
        );
      },
    );

    test('applyEpisodeMetadata updates local episodes only without creating phantoms', () async {
      final source = await repo.upsertSource(
        kind: 'local',
        rootLocator: 'C:/TV',
        name: 'TV',
      );

      final now = DateTime.now();
      final entries = [
        MediaEntry(
          externalId: 'ep1',
          locator: 'Drama.S01E01.mkv',
          name: 'Drama.S01E01.mkv',
          isDirectory: false,
          size: 1000,
          modifiedAt: now,
        ),
      ];

      final scanId = await repo.beginScan(source.id);
      await repo.applyScanBatch(source.id, scanId, entries);
      await repo.finishScan(source.id, scanId);

      final work = (await repo.watchWorks().first).first;

      final tmdbEpisodes = [
        const TmdbEpisode(
          seasonNumber: 1,
          episodeNumber: 1,
          title: 'Official Pilot Title',
          overview: 'The beginning.',
        ),
        const TmdbEpisode(
          seasonNumber: 1,
          episodeNumber: 2,
          title: 'Phantom Episode 2',
          overview: 'This file does not exist locally.',
        ),
      ];

      await repo.applyEpisodeMetadata(work.id, tmdbEpisodes, manual: true);

      // 本地存在的 E01 获得标题更新
      final eps = await db.select(db.episodes).get();
      expect(eps, hasLength(1));
      expect(eps.first.episodeNumber, 1);
      expect(eps.first.title, 'Official Pilot Title');
      expect(eps.first.overview, 'The beginning.');
    });

    test('editMetadata validates inputs and sets local lock', () async {
      final source = await repo.upsertSource(
        kind: 'local',
        rootLocator: 'C:/Movies',
        name: 'Movies',
      );

      final now = DateTime.now();
      final entries = [
        MediaEntry(
          externalId: 'e1',
          locator: 'Movie.2019.mkv',
          name: 'Movie.2019.mkv',
          isDirectory: false,
          size: 1000,
          modifiedAt: now,
        ),
      ];

      final scanId = await repo.beginScan(source.id);
      await repo.applyScanBatch(source.id, scanId, entries);
      await repo.finishScan(source.id, scanId);

      final work = (await repo.watchWorks().first).first;

      // 空标题校验
      expect(
        () => repo.editMetadata(work.id, title: '   '),
        throwsA(isA<ArgumentError>()),
      );

      // 非法年份校验
      expect(
        () => repo.editMetadata(work.id, title: 'Valid', year: 1700),
        throwsA(isA<ArgumentError>()),
      );

      // 正常编辑成功并锁定
      await repo.editMetadata(
        work.id,
        title: 'New Custom Title',
        year: 2020,
        overview: 'Manual edit overview',
      );

      final updated = await repo.getWorkDetails(work.id);
      expect(updated!.work.title, 'New Custom Title');
      expect(updated.work.year, 2020);
      expect(updated.work.metadataLocked, isTrue);
      expect(updated.work.metadataSource, 'local');
    });

    test('watchLibrary and getVideo series joins function correctly for episode files', () async {
      final source = await repo.upsertSource(
        kind: 'local',
        rootLocator: 'C:/Series',
        name: 'Series',
      );

      final now = DateTime.now();
      final entries = [
        MediaEntry(
          externalId: 's_ep1',
          locator: 'Westworld.S01E01.1080p.mkv',
          name: 'Westworld.S01E01.1080p.mkv',
          isDirectory: false,
          size: 2000,
          modifiedAt: now,
        ),
      ];

      final scanId = await repo.beginScan(source.id);
      await repo.applyScanBatch(source.id, scanId, entries);
      await repo.finishScan(source.id, scanId);

      // watchLibrary 能够通过 series -> season -> episode 正确关联并获取 series work title
      final videos = await repo.watchLibrary().first;
      expect(videos, hasLength(1));
      final video = videos.first;
      expect(video.fileName, 'Westworld.S01E01.1080p.mkv');
      expect(video.title, 'Westworld');
      expect(video.available, isTrue);

      // getVideo 也能够正常获取
      final singleVideo = await repo.getVideo(video.fileId);
      expect(singleVideo, isNotNull);
      expect(singleVideo!.title, 'Westworld');
      expect(singleVideo.available, isTrue);
    });

    test('scanning series file with year into locked null-year series attaches version without overwriting year', () async {
      final source = await repo.upsertSource(
        kind: 'local',
        rootLocator: 'C:/TV',
        name: 'TV',
      );

      // 先创建一个手工锁定且无年份的剧集作品
      final seriesId = await db
          .into(db.works)
          .insert(
            WorksCompanion.insert(
              title: 'SpecialShow',
              type: const Value('series'),
              metadataSource: const Value('local'),
              metadataLocked: const Value(true), // 显式加锁且 year 为 null
            ),
          );

      final now = DateTime.now();
      final entries = [
        MediaEntry(
          externalId: 'sp_ep1',
          locator: 'SpecialShow.2023.S01E01.mkv',
          name: 'SpecialShow.2023.S01E01.mkv',
          isDirectory: false,
          size: 1000,
          modifiedAt: now,
        ),
      ];

      final scanId = await repo.beginScan(source.id);
      await repo.applyScanBatch(source.id, scanId, entries);
      await repo.finishScan(source.id, scanId);

      // 验证作品加锁状态与 year 依然完好为 null，但版本已正确附加上去
      final details = await repo.getWorkDetails(seriesId);
      expect(details, isNotNull);
      expect(details!.work.title, 'SpecialShow');
      expect(details.work.year, isNull);
      expect(details.work.metadataLocked, isTrue);
      expect(details.versions, hasLength(1));
      expect(details.versions.first.seasonNumber, 1);
      expect(details.versions.first.episodeNumber, 1);
    });

    test('multiple movie candidates with same title and year do not merge automatically and do not throw', () async {
      final source = await repo.upsertSource(
        kind: 'local',
        rootLocator: 'C:/Movies',
        name: 'Movies',
      );

      // 先在库中手工制造两个同名同年的独立作品（例如不同 TMDB 身份或不同版本冲突）
      await db
          .into(db.works)
          .insert(
            WorksCompanion.insert(
              title: 'AmbiguousMovie',
              type: const Value('movie'),
              year: const Value(2022),
              metadataSource: const Value('tmdb'),
              metadataLocked: const Value(true),
            ),
          );
      await db
          .into(db.works)
          .insert(
            WorksCompanion.insert(
              title: 'AmbiguousMovie',
              type: const Value('movie'),
              year: const Value(2022),
              metadataSource: const Value('local'),
              metadataLocked: const Value(false),
            ),
          );

      final now = DateTime.now();
      final entries = [
        MediaEntry(
          externalId: 'amb_movie_1',
          locator: 'AmbiguousMovie.2022.1080p.mkv',
          name: 'AmbiguousMovie.2022.1080p.mkv',
          isDirectory: false,
          size: 2000,
          modifiedAt: now,
        ),
      ];

      final scanId = await repo.beginScan(source.id);
      await repo.applyScanBatch(source.id, scanId, entries);
      // 扫描识别不应抛出异常，且保留为独立候选供人工处理
      await repo.finishScan(source.id, scanId);

      final files = await db.select(db.mediaFiles).get();
      expect(files.any((f) => f.parseState == 'needs_review'), isTrue);
    });

    test('manual matching unresolved file to series binds episode and marks file parsed', () async {
      final source = await repo.upsertSource(
        kind: 'local',
        rootLocator: 'C:/TV',
        name: 'TV',
      );

      final now = DateTime.now();
      final entries = [
        MediaEntry(
          externalId: 'entry-show-1',
          locator: 'Show.mkv',
          name: 'Show.mkv',
          isDirectory: false,
          size: 500000000,
          modifiedAt: now,
        ),
      ];

      final scanId = await repo.beginScan(source.id);
      await repo.applyScanBatch(source.id, scanId, entries);
      await repo.finishScan(source.id, scanId);

      final works = await repo.watchWorks().first;
      expect(works, hasLength(1));
      final unassignedWork = works.first;
      expect(unassignedWork.type, isNull);

      final canonicalId = await repo.applyMetadata(
        unassignedWork.id,
        const TmdbWork(id: 115036, type: 'series', title: 'Show'),
        manual: true,
        episode: const TmdbEpisode(
          seasonNumber: 1,
          episodeNumber: 1,
          title: 'Pilot',
        ),
      );

      final details = await repo.getWorkDetails(canonicalId);
      expect(details, isNotNull);
      expect(details!.work.type, 'series');
      expect(details.work.metadataLocked, isTrue);
      expect(details.versions, hasLength(1));
      expect(details.versions.first.fileName, 'Show.mkv');
      expect(details.versions.first.seasonNumber, 1);
      expect(details.versions.first.episodeNumber, 1);
      expect(details.versions.first.episodeTitle, 'Pilot');

      final file = await (db.select(
        db.mediaFiles,
      )..where((f) => f.id.equals(details.versions.first.fileId))).getSingle();
      expect(file.parseState, 'parsed');

      final oldWork = await (db.select(
        db.works,
      )..where((w) => w.id.equals(unassignedWork.id))).getSingleOrNull();
      expect(oldWork, isNull);
    });

    test('manual matching merges into existing canonical series preserving versions, progress, and lock', () async {
      final source = await repo.upsertSource(
        kind: 'local',
        rootLocator: 'C:/TV',
        name: 'TV',
      );

      final now = DateTime.now();
      final entries1 = [
        MediaEntry(
          externalId: 'entry-ep1',
          locator: 'Severance.S01E01.mkv',
          name: 'Severance.S01E01.mkv',
          isDirectory: false,
          size: 1000,
          modifiedAt: now,
        ),
      ];

      final scan1 = await repo.beginScan(source.id);
      await repo.applyScanBatch(source.id, scan1, entries1);
      await repo.finishScan(source.id, scan1);

      final work1 = (await repo.watchWorks().first).first;
      final canonicalSeriesId = await repo.applyMetadata(
        work1.id,
        const TmdbWork(id: 115036, type: 'series', title: 'Severance'),
        manual: true,
      );

      final entries2 = [
        MediaEntry(
          externalId: 'entry-ep2',
          locator: 'Show.mkv',
          name: 'Show.mkv',
          isDirectory: false,
          size: 2000,
          modifiedAt: now,
        ),
      ];

      final scan2 = await repo.beginScan(source.id);
      await repo.applyScanBatch(source.id, scan2, entries2);
      await repo.finishScan(source.id, scan2);

      final allWorks = await repo.watchWorks().first;
      final unassignedWork = allWorks.firstWhere(
        (w) => w.id != canonicalSeriesId,
      );

      await db
          .into(db.playbackProgresses)
          .insert(
            PlaybackProgressesCompanion.insert(
              targetType: 'work',
              targetId: unassignedWork.id,
              workId: Value(unassignedWork.id),
              positionMs: const Value(50000),
              durationMs: const Value(100000),
              updatedAt: Value(now),
            ),
          );

      final mergedId = await repo.applyMetadata(
        unassignedWork.id,
        const TmdbWork(id: 115036, type: 'series', title: 'Severance'),
        manual: true,
        episode: const TmdbEpisode(
          seasonNumber: 1,
          episodeNumber: 2,
          title: 'Half Loop',
        ),
      );

      expect(mergedId, equals(canonicalSeriesId));

      final details = await repo.getWorkDetails(canonicalSeriesId);
      expect(details, isNotNull);
      expect(details!.work.metadataLocked, isTrue);
      expect(details.versions, hasLength(2));
      final fileNames = details.versions.map((v) => v.fileName).toList();
      expect(fileNames, contains('Severance.S01E01.mkv'));
      expect(fileNames, contains('Show.mkv'));

      final ep2 =
          await (db.select(db.episodes).join([
                innerJoin(
                  db.seasons,
                  db.seasons.id.equalsExp(db.episodes.seasonId),
                ),
              ])..where(
                db.seasons.seriesId.equals(canonicalSeriesId) &
                    db.episodes.episodeNumber.equals(2),
              ))
              .getSingle();
      final ep2Id = ep2.readTable(db.episodes).id;

      final progress =
          await (db.select(db.playbackProgresses)..where(
                (p) =>
                    p.targetType.equals('episode') & p.targetId.equals(ep2Id),
              ))
              .getSingleOrNull();
      expect(progress, isNotNull);
      expect(progress!.positionMs, 50000);

      final oldWork = await (db.select(
        db.works,
      )..where((w) => w.id.equals(unassignedWork.id))).getSingleOrNull();
      expect(oldWork, isNull);
    });

    test('applyMetadata without episode on non-series work throws ArgumentError and preserves database unchanged', () async {
      final source = await repo.upsertSource(
        kind: 'local',
        rootLocator: 'C:/TV',
        name: 'TV',
      );

      final now = DateTime.now();
      final entries = [
        MediaEntry(
          externalId: 'entry-show-1',
          locator: 'Show.mkv',
          name: 'Show.mkv',
          isDirectory: false,
          size: 500000000,
          modifiedAt: now,
        ),
      ];

      final scanId = await repo.beginScan(source.id);
      await repo.applyScanBatch(source.id, scanId, entries);
      await repo.finishScan(source.id, scanId);

      final works = await repo.watchWorks().first;
      expect(works, hasLength(1));
      final unassignedWork = works.first;
      expect(unassignedWork.type, isNull);

      final initialAssignments = await db.select(db.mediaAssignments).get();
      final initialWorks = await db.select(db.works).get();

      expect(
        () => repo.applyMetadata(
          unassignedWork.id,
          const TmdbWork(id: 115036, type: 'series', title: 'Show'),
          manual: true,
          episode: null,
        ),
        throwsA(isA<ArgumentError>()),
      );

      final finalWorks = await db.select(db.works).get();
      final finalAssignments = await db.select(db.mediaAssignments).get();
      expect(finalWorks.length, equals(initialWorks.length));
      expect(finalWorks.first.type, isNull);
      expect(finalWorks.first.metadataLocked, isFalse);
      expect(finalAssignments.length, equals(initialAssignments.length));
      expect(finalAssignments.first.workId, equals(unassignedWork.id));
      expect(finalAssignments.first.episodeId, isNull);
    });

    test('applyMetadata on multi-episode file throws multi_episode_unsupported and preserves database', () async {
      final source = await repo.upsertSource(
        kind: 'local',
        rootLocator: 'C:/TV',
        name: 'TV',
      );

      final now = DateTime.now();
      final entries = [
        MediaEntry(
          externalId: 'entry-multi-1',
          locator: 'Show.S01E01-E02.mkv',
          name: 'Show.S01E01-E02.mkv',
          isDirectory: false,
          size: 500000000,
          modifiedAt: now,
        ),
      ];

      final scanId = await repo.beginScan(source.id);
      await repo.applyScanBatch(source.id, scanId, entries);
      await repo.finishScan(source.id, scanId);

      final works = await repo.watchWorks().first;
      expect(works, hasLength(1));
      final multiWork = works.first;

      final initialFiles = await db.select(db.mediaFiles).get();
      expect(initialFiles.first.candidateDetails, startsWith('multi_episode'));

      expect(
        () => repo.applyMetadata(
          multiWork.id,
          const TmdbWork(id: 115036, type: 'series', title: 'Show'),
          manual: true,
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

      final finalFiles = await db.select(db.mediaFiles).get();
      expect(finalFiles.first.parseState, 'needs_review');
    });
  });
}
