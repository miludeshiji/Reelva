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

    group('watchWorks filters', () {
      late int sourceId;
      var entryNumber = 0;

      setUp(() async {
        entryNumber = 0;
        sourceId = await db
            .into(db.mediaSources)
            .insert(
              MediaSourcesCompanion.insert(
                kind: 'local',
                name: 'Filters',
                rootLocator: 'C:/Filters',
              ),
            );
      });

      Future<void> addVersion(int workId, {String? type, int? source}) async {
        final name = 'fixture-${entryNumber++}.mkv';
        final entryId = await db
            .into(db.mediaEntries)
            .insert(
              MediaEntriesCompanion.insert(
                sourceId: source ?? sourceId,
                externalEntryId: name,
                relativeLocator: name,
                name: name,
                isDirectory: false,
              ),
            );
        final fileId = await db
            .into(db.mediaFiles)
            .insert(
              MediaFilesCompanion.insert(
                entryId: entryId,
                parseState: const Value('parsed'),
              ),
            );
        int? episodeId;
        if (type == 'series') {
          final seasonId = await db
              .into(db.seasons)
              .insert(
                SeasonsCompanion.insert(seriesId: workId, seasonNumber: 1),
              );
          episodeId = await db
              .into(db.episodes)
              .insert(
                EpisodesCompanion.insert(seasonId: seasonId, episodeNumber: 1),
              );
        }
        await db
            .into(db.mediaAssignments)
            .insert(
              MediaAssignmentsCompanion.insert(
                fileId: fileId,
                workId: Value(episodeId == null ? workId : null),
                episodeId: Value(episodeId),
              ),
            );
      }

      Future<int> addWork(
        String title, {
        String? originalTitle,
        String? type = 'movie',
        DateTime? createdAt,
        int? source,
      }) async {
        final id = await db
            .into(db.works)
            .insert(
              WorksCompanion.insert(
                title: title,
                originalTitle: Value(originalTitle),
                type: Value(type),
                createdAt: Value(createdAt ?? DateTime.utc(2026)),
              ),
            );
        await addVersion(id, type: type, source: source);
        return id;
      }

      test('searches title and original title beyond the default page before limiting', () async {
        await db.transaction(() async {
          for (var i = 0; i < 105; i++) {
            await addWork('A filler $i');
          }
        });
        final titleMatch = await addWork('Z Midnight Train');
        final originalMatch = await addWork(
          'Z Translated',
          originalTitle: 'The Midnight Train Returns',
        );

        final firstPage = await repo.watchWorks().first;
        expect(firstPage, hasLength(100));
        expect(firstPage.map((w) => w.id), isNot(contains(titleMatch)));
        expect(firstPage.map((w) => w.id), isNot(contains(originalMatch)));
        final matches = await repo.watchWorks(search: 'mIDNIGHT tRAIN').first;
        expect(matches.map((w) => w.id), [titleMatch, originalMatch]);
        final bounded = await repo
            .watchWorks(search: 'Midnight Train', limit: 1)
            .first;
        expect(bounded.map((w) => w.id), [titleMatch]);
      });

      test('待匹配筛选在分页前排除 TMDB 条目、人工确认和停用来源', () async {
        final locked = await addWork('A Locked');
        await repo.editMetadata(locked, title: 'A Locked');
        final matched = await addWork('B Matched');
        await repo.applyMetadata(
          matched,
          const TmdbWork(id: 900, type: 'movie', title: 'B Matched'),
        );
        final disabled = await repo.upsertSource(
          kind: 'local',
          rootLocator: 'C:/Disabled',
          name: 'Disabled',
        );
        await addWork('C Disabled', source: disabled.id);
        await repo.disableSource(disabled.id);
        final pending = await addWork('Z Pending');
        final result = await repo
            .watchWorks(unmatchedOnly: true, limit: 1)
            .first;
        expect(result.map((work) => work.id), [pending]);
        expect((await repo.unmatchedWorks()).map((work) => work.id), [pending]);
        expect(
          await repo.watchWorks(unmatchedOnly: true, search: 'Pending').first,
          hasLength(1),
        );
      });

      test(
        'preserves contiguous phrases and leading and trailing spaces',
        () async {
          final plain = await addWork('Alpha Beta');
          final padded = await addWork(' Alpha Beta ');
          final split = await addWork('Alpha other Beta');
          final doubled = await addWork('Alpha  Beta');

          final phrase = await repo.watchWorks(search: 'aLPHA bETA').first;
          expect(phrase.map((w) => w.id), [padded, plain]);
          final spaces = await repo.watchWorks(search: ' Alpha Beta ').first;
          expect(spaces.map((w) => w.id), [padded]);
          final doubleSpaces = await repo
              .watchWorks(search: 'Alpha  Beta')
              .first;
          expect(doubleSpaces.map((w) => w.id), [doubled]);
          final reordered = await repo.watchWorks(search: 'Beta Alpha').first;
          expect(reordered, isEmpty);
          final onlySpace = await repo.watchWorks(search: ' ').first;
          expect(
            onlySpace.map((w) => w.id),
            containsAll([plain, padded, split, doubled]),
          );
        },
      );

      test(
        'treats percent, underscore and backslash as literals in both titles',
        () async {
          final percent = await addWork('Literal 100%');
          final underscore = await addWork('Literal A_B');
          final backslash = await addWork(r'Literal A\B');
          final combined = await addWork('Original', originalTitle: r'100%_\');
          await addWork('Literal 1000 A-B AB');

          for (final (search, expected) in <(String, List<int>)>[
            ('%', [percent, combined]),
            ('_', [underscore, combined]),
            (r'\', [backslash, combined]),
            (r'%_\', [combined]),
          ]) {
            final matches = await repo.watchWorks(search: search).first;
            expect(matches.map((w) => w.id), expected, reason: search);
          }
          final injection = await repo.watchWorks(search: "' OR 1=1 --").first;
          expect(injection, isEmpty);
        },
      );

      test('filters exact types before the limit and follows series episode assignments', () async {
        final unknown = await addWork('A Unknown', type: null);
        final movie = await addWork('B Shared', type: 'movie');
        final series = await addWork('C Shared', type: 'series');
        await addVersion(movie);

        final all = await repo.watchWorks(type: null).first;
        expect(all.map((w) => w.id), [unknown, movie, series]);
        expect(all.singleWhere((w) => w.id == movie).versionCount, 2);
        final movies = await repo.watchWorks(type: 'movie', limit: 1).first;
        expect(movies.map((w) => w.id), [movie]);
        final shows = await repo
            .watchWorks(type: 'series', limit: 1, search: 'shared')
            .first;
        expect(shows.map((w) => w.id), [series]);
        expect(shows.single.versionCount, 1);
        final uppercase = await repo.watchWorks(type: 'Movie').first;
        expect(uppercase, isEmpty);
        final injection = await repo.watchWorks(type: "movie' OR 1=1 --").first;
        expect(injection, isEmpty);
      });

      test('orders by case insensitive title and id or by creation time and descending id', () async {
        final old = DateTime.utc(2025);
        final recent = DateTime.utc(2026);
        final first = await addWork('beta', createdAt: recent);
        final second = await addWork('Beta', createdAt: recent);
        final third = await addWork('Alpha', createdAt: old);

        final alphabetical = await repo.watchWorks().first;
        expect(alphabetical.map((w) => w.id), [third, first, second]);
        final newest = await repo.watchWorks(recentlyAdded: true).first;
        expect(newest.map((w) => w.id), [second, first, third]);
        final bounded = await repo
            .watchWorks(
              recentlyAdded: true,
              search: 'beta',
              type: 'movie',
              limit: 1,
            )
            .first;
        expect(bounded.map((w) => w.id), [second]);
      });

      test(
        'excludes disabled sources while retaining enabled offline versions',
        () async {
          final disabledSource = await db
              .into(db.mediaSources)
              .insert(
                MediaSourcesCompanion.insert(
                  kind: 'local',
                  name: 'Disabled',
                  rootLocator: 'C:/Disabled',
                  enabled: const Value(false),
                ),
              );
          await addWork('A Match Hidden', source: disabledSource);
          await addWork(
            'B Match Hidden Series',
            type: 'series',
            source: disabledSource,
          );
          final movie = await addWork('C Match Movie');
          final series = await addWork('D Match Series', type: 'series');
          await addVersion(movie, source: disabledSource);
          await db
              .update(db.mediaEntries)
              .write(const MediaEntriesCompanion(available: Value(false)));

          final matches = await repo.watchWorks(search: 'match').first;
          expect(matches.map((w) => w.id), [movie, series]);
          expect(
            matches.every((w) => !w.available && w.versionCount == 1),
            isTrue,
          );
          final bounded = await repo
              .watchWorks(search: 'match', limit: 1)
              .first;
          expect(bounded.single.id, movie);
        },
      );
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

    test('同名新文件不会仅凭标题挂入已锁定作品，原有人工信息保持不变', () async {
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

      // 保留人工信息；缺少已确认身份的新文件独立进入本地候选。
      final details = await repo.getWorkDetails(seriesId);
      expect(details, isNotNull);
      expect(details!.work.title, 'SpecialShow');
      expect(details.work.year, isNull);
      expect(details.work.metadataLocked, isTrue);
      expect(details.versions, isEmpty);
      final candidates = await repo.unmatchedWorks();
      expect(candidates, hasLength(1));
      expect(candidates.single.id, isNot(seriesId));
      final candidate = (await repo.getWorkDetails(candidates.single.id))!;
      expect(candidate.work.year, 2023);
      expect(candidate.versions.single.seasonNumber, 1);
      expect(candidate.versions.single.episodeNumber, 1);
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

    test('watchRecentWorks orders works by created_at DESC, id DESC and groups versions', () async {
      final source = await repo.upsertSource(
        kind: 'local',
        rootLocator: 'C:/Movies',
        name: 'Movies',
      );

      final now = DateTime.now();
      final entries = [
        MediaEntry(
          externalId: 'm1_1080',
          locator: 'Inception.2010.1080p.mkv',
          name: 'Inception.2010.1080p.mkv',
          isDirectory: false,
          size: 2000000000,
          modifiedAt: now,
        ),
        MediaEntry(
          externalId: 'm1_4k',
          locator: 'Inception.2010.2160p.4K.mkv',
          name: 'Inception.2010.2160p.4K.mkv',
          isDirectory: false,
          size: 8000000000,
          modifiedAt: now,
        ),
        MediaEntry(
          externalId: 'm2',
          locator: 'Interstellar.2014.1080p.mkv',
          name: 'Interstellar.2014.1080p.mkv',
          isDirectory: false,
          size: 3000000000,
          modifiedAt: now,
        ),
      ];

      final scanId = await repo.beginScan(source.id);
      await repo.applyScanBatch(source.id, scanId, entries);
      await repo.finishScan(source.id, scanId);

      // watchRecentWorks automatically triggers recognizePendingFiles
      final recents = await repo.watchRecentWorks(limit: 20).first;
      expect(recents, hasLength(2));

      // Inception has 2 versions deduped into 1 work
      final inception = recents.firstWhere((w) => w.title == 'Inception');
      expect(inception.versionCount, 2);

      final interstellar = recents.firstWhere((w) => w.title == 'Interstellar');
      expect(interstellar.versionCount, 1);

      // Update created_at to verify order
      await (db.update(
        db.works,
      )..where((w) => w.id.equals(inception.id))).write(
        WorksCompanion(createdAt: Value(now.subtract(const Duration(days: 1)))),
      );
      await (db.update(db.works)..where((w) => w.id.equals(interstellar.id)))
          .write(WorksCompanion(createdAt: Value(now)));

      final orderedRecents = await repo.watchRecentWorks(limit: 20).first;
      expect(orderedRecents.first.id, interstellar.id);
      expect(orderedRecents.last.id, inception.id);
    });

    test(
      'watchRecentWorks respects limit and excludes disabled sources',
      () async {
        final source = await repo.upsertSource(
          kind: 'local',
          rootLocator: 'C:/Movies',
          name: 'Movies',
        );

        final now = DateTime.now();
        final entries = List.generate(
          5,
          (i) => MediaEntry(
            externalId: 'm$i',
            locator: 'Movie.$i.2020.mkv',
            name: 'Movie.$i.2020.mkv',
            isDirectory: false,
            size: 1000000000,
            modifiedAt: now,
          ),
        );

        final scanId = await repo.beginScan(source.id);
        await repo.applyScanBatch(source.id, scanId, entries);
        await repo.finishScan(source.id, scanId);

        final bounded = await repo.watchRecentWorks(limit: 3).first;
        expect(bounded, hasLength(3));

        await repo.disableSource(source.id);
        final afterDisabled = await repo.watchRecentWorks().first;
        expect(afterDisabled, isEmpty);
      },
    );
  });
}
