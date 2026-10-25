import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reelva/app/router.dart';
import 'package:reelva/core/database/app_database.dart';
import 'package:reelva/features/library/infrastructure/media_library_repository.dart';
import 'package:reelva/features/library/library_page.dart';
import 'package:reelva/features/library/presentation/work_details_page.dart';
import 'package:reelva/features/library/presentation/manual_match_dialog.dart';
import 'package:reelva/features/metadata/application/metadata_providers.dart';
import 'package:reelva/features/metadata/domain/tmdb_models.dart';
import 'package:reelva/features/metadata/infrastructure/tmdb_client.dart';
import 'package:reelva/features/metadata/infrastructure/tmdb_token_store.dart';
import 'package:reelva/features/player/application/player_providers.dart';
import 'package:reelva/features/player/domain/playback_resource.dart';
import 'package:reelva/features/player/presentation/player_page.dart';
import 'package:reelva/features/sources/application/source_providers.dart';
import 'package:reelva/features/sources/domain/media_source_adapter.dart';
import 'package:reelva/features/sources/domain/source_models.dart';
import 'package:reelva/features/sources/sources_page.dart';

import '../player/fake_player_engine.dart';

/// 测试用内存 TokenStore，避免在 Widget 测试中调用真实平台安全存储
class FakeTmdbTokenStore extends TmdbTokenStore {
  String? _token;
  FakeTmdbTokenStore([this._token]);

  @override
  Future<String?> read() async => _token;

  @override
  Future<void> save(String rawToken) async {
    _token = TmdbTokenStore.sanitizeToken(rawToken);
  }

  @override
  Future<void> delete() async {
    _token = null;
  }

  @override
  Future<bool> isConfigured() async => _token != null && _token!.isNotEmpty;
}

/// 测试用可控 TMDB 客户端
class FakeTmdbClient extends TmdbClient {
  FakeTmdbClient() : super(tokenStore: FakeTmdbTokenStore('test_token'));

  List<TmdbWork> movieSearchResults = [];
  Map<int, TmdbWork> movieDetailsMap = {};
  List<TmdbWork> tvSearchResults = [];
  Map<int, TmdbWork> tvDetailsMap = {};
  Map<String, List<TmdbEpisode>> tvSeasonEpisodesMap = {};

  @override
  Future<List<TmdbWork>> searchMovie(
    String query, {
    int? year,
    int page = 1,
    String language = 'zh-CN',
  }) async {
    return movieSearchResults;
  }

  @override
  Future<TmdbWork> getMovieDetails(int id, {String language = 'zh-CN'}) async {
    return movieDetailsMap[id] ??
        const TmdbWork(
          id: 157336,
          type: 'movie',
          title: '星际穿越',
          year: 2014,
          posterPath: null,
        );
  }

  @override
  Future<List<TmdbWork>> searchTv(
    String query, {
    int? year,
    int page = 1,
    String language = 'zh-CN',
  }) async {
    return tvSearchResults;
  }

  @override
  Future<TmdbWork> getTvDetails(int id, {String language = 'zh-CN'}) async {
    return tvDetailsMap[id] ??
        const TmdbWork(
          id: 1399,
          type: 'series',
          title: '权力的游戏',
          year: 2011,
          posterPath: null,
        );
  }

  @override
  Future<List<TmdbEpisode>> getTvSeasonEpisodes(
    int tvId,
    int seasonNumber, {
    String language = 'zh-CN',
  }) async {
    final key = '$tvId:$seasonNumber';
    return tvSeasonEpisodesMap[key] ?? const [];
  }
}

/// 可控制选择、流式枚举与播放解析的测试媒体源适配器
class FakeControllableMediaSourceAdapter implements MediaSourceAdapter {
  FakeControllableMediaSourceAdapter({
    this.directoryToPick = const DirectorySelection(
      kind: 'local',
      rootLocator: 'C:/videos',
      name: '本地视频',
    ),
    List<MediaEntry>? entriesToStream,
    this.streamController,
    this.playbackResourceToResolve,
    this.shouldFailResolve = false,
    this.resolveErrorMessage = '文件已离线或无法读取',
  }) : entriesToStream = entriesToStream ?? const [];

  @override
  String get kind => 'local';

  final DirectorySelection? directoryToPick;
  final List<MediaEntry> entriesToStream;
  final StreamController<MediaEntry>? streamController;
  final PlaybackResource? playbackResourceToResolve;
  final bool shouldFailResolve;
  final String resolveErrorMessage;

  int resolveCount = 0;
  String? lastResolvedEntryId;

  @override
  Future<DirectorySelection?> pickDirectory({String? initialLocator}) async {
    return directoryToPick;
  }

  @override
  Stream<MediaEntry> listEntries(MediaSourceConfig source, String directoryId) {
    if (streamController != null) {
      return streamController!.stream;
    }
    return Stream.fromIterable(entriesToStream);
  }

  @override
  Future<MediaStat> stat(MediaSourceConfig source, String entryId) async {
    return const MediaStat();
  }

  @override
  Future<PlaybackResource> resolvePlayback(
    MediaSourceConfig source,
    String entryId,
  ) async {
    resolveCount++;
    lastResolvedEntryId = entryId;

    if (shouldFailResolve) {
      throw MediaSourceException(resolveErrorMessage);
    }

    return playbackResourceToResolve ??
        PlaybackResource(
          uri: Uri.file('C:/videos/$entryId'),
          displayName: entryId,
        );
  }
}

void main() {
  group('Sources and Library UI Slice Tests (M3)', () {
    late AppDatabase memoryDb;
    late MediaLibraryRepository repository;
    late FakePlayerEngine fakePlayerEngine;
    late FakeTmdbTokenStore fakeTokenStore;

    setUp(() {
      memoryDb = AppDatabase(executor: NativeDatabase.memory());
      repository = MediaLibraryRepository(memoryDb);
      fakePlayerEngine = FakePlayerEngine();
      fakeTokenStore = FakeTmdbTokenStore();
    });

    tearDown(() async {
      await memoryDb.close();
    });

    testWidgets(
      'Prove end-to-end import -> library work card -> details -> select version -> player',
      (tester) async {
        const file1080p = 'Avatar.2009.1080p.BluRay.mkv';
        const file2160p = 'Avatar.2009.2160p.4K.UHD.mkv';

        final fakeAdapter = FakeControllableMediaSourceAdapter(
          directoryToPick: const DirectorySelection(
            kind: 'local',
            rootLocator: 'C:/videos',
            name: '本地电影',
          ),
          entriesToStream: [
            MediaEntry(
              externalId: file1080p,
              locator: file1080p,
              name: file1080p,
              isDirectory: false,
              size: 10485760,
              modifiedAt: DateTime(2026, 1, 1),
            ),
            MediaEntry(
              externalId: file2160p,
              locator: file2160p,
              name: file2160p,
              isDirectory: false,
              size: 41943040,
              modifiedAt: DateTime(2026, 1, 1),
            ),
          ],
        );

        final fakeSession = createFakeSession(engine: fakePlayerEngine);
        final testRouter = createRouter(initialLocation: '/sources');
        addTearDown(testRouter.dispose);

        try {
          await tester.pumpWidget(
            ProviderScope(
              overrides: [
                appDatabaseProvider.overrideWithValue(memoryDb),
                mediaLibraryRepositoryProvider.overrideWithValue(repository),
                tmdbTokenStoreProvider.overrideWithValue(fakeTokenStore),
                platformOverrideProvider.overrideWithValue(
                  TargetPlatform.windows,
                ),
                sourceAdaptersProvider.overrideWithValue({
                  'local': fakeAdapter,
                }),
                playerSessionProvider.overrideWithValue(fakeSession),
                routerProvider.overrideWithValue(testRouter),
              ],
              child: MaterialApp.router(routerConfig: testRouter),
            ),
          );
          await tester.pumpAndSettle();

          // 1. 在 SourcesPage 进入来源选择页，再打开本地目录配置
          expect(find.byType(SourcesPage), findsOneWidget);
          final addButton = find.byKey(const Key('sources_add_appbar_button'));
          expect(addButton, findsOneWidget);
          await tester.tap(addButton);
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(const Key('add_source_type_local')));
          await tester.pumpAndSettle();

          // 2. 确认添加并触发 SourceController.addDirectory 真实流程
          final confirmButton = find.byKey(
            const Key('add_source_confirm_button'),
          );
          expect(confirmButton, findsOneWidget);
          await tester.ensureVisible(confirmButton);
          await tester.tap(confirmButton);
          await tester.pumpAndSettle();

          // 媒体源列表中呈现了新导入的媒体源
          expect(find.text('本地电影'), findsOneWidget);

          // 3. 切换至 LibraryPage（呈现逻辑作品海报墙：两个画质聚合成一张卡片）
          testRouter.go('/library');
          await tester.pumpAndSettle();

          expect(find.byType(LibraryPage), findsOneWidget);
          final workCardFinder = find.byKey(const Key('library_work_card_1'));
          expect(workCardFinder, findsOneWidget);

          // 确认仅聚合成一张作品卡片且包含两个版本
          final works = await tester.runAsync(
            () => repository.watchWorks().first,
          );
          expect(works, isNotNull);
          expect(works!.length, 1);
          expect(works.first.versionCount, 2);

          // 4. 点击作品海报卡片导航至作品详情页
          await tester.tap(workCardFinder);
          await tester.pumpAndSettle();

          // 5. 验证进入了 WorkDetailsPage，并呈现两个不同画质的文件版本
          expect(find.byType(WorkDetailsPage), findsOneWidget);
          final titleWidget = tester.widget<Text>(
            find.byKey(const Key('work_details_title')),
          );
          expect(titleWidget.data, 'Avatar');

          // 验证详情页呈现两个版本条目
          expect(find.byKey(const Key('work_version_item_1')), findsOneWidget);
          expect(find.byKey(const Key('work_version_item_2')), findsOneWidget);
          final detailsState = tester.state(find.byType(WorkDetailsPage));

          // 6. 选择第二个 2160p (4K) 版本进行播放
          final play2160pFinder = find.byKey(
            const Key('work_play_version_button_2'),
          );
          expect(play2160pFinder, findsOneWidget);
          await tester.ensureVisible(play2160pFinder);
          await tester.pumpAndSettle();
          await tester.tap(play2160pFinder);
          await tester.pumpAndSettle();

          // 7. 验证导航已无缝跳转至 PlayerPage，且底层引擎与适配器真实收到 2160p 版本
          expect(find.byType(PlayerPage), findsOneWidget);
          expect(fakePlayerEngine.openCount, 1);
          expect(fakeAdapter.resolveCount, 1);
          expect(fakeAdapter.lastResolvedEntryId, file2160p);
          expect(fakePlayerEngine.lastOpenedResource?.displayName, file2160p);
          expect(find.text(file2160p), findsOneWidget);

          // 8. 播放器返回时保留作品详情及滚动位置
          await tester.tap(find.byKey(const Key('player_back_button')));
          await tester.pumpAndSettle();
          expect(
            testRouter.routeInformationProvider.value.uri.path,
            '/library/work/1',
          );
          expect(
            tester.state(find.byType(WorkDetailsPage)),
            same(detailsState),
          );
          expect(play2160pFinder.hitTestable(), findsOneWidget);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump(Duration.zero);
        }
      },
    );

    testWidgets(
      'Resolution failure in details retains visible details and presents safe feedback',
      (tester) async {
        final source = await repository.upsertSource(
          kind: 'local',
          rootLocator: 'C:/media',
          name: '本地电影',
        );
        final scanId = await repository.beginScan(source.id);
        await repository.applyScanBatch(source.id, scanId, const [
          MediaEntry(
            externalId: 'broken.mp4',
            locator: 'broken.mp4',
            name: 'broken.mp4',
            isDirectory: false,
            size: 1024,
          ),
        ]);
        await repository.finishScan(source.id, scanId);

        final failingAdapter = FakeControllableMediaSourceAdapter(
          shouldFailResolve: true,
          resolveErrorMessage: '目标文件已被移动或离线',
        );

        final testRouter = createRouter(initialLocation: '/library/work/1');
        addTearDown(testRouter.dispose);

        try {
          await tester.pumpWidget(
            ProviderScope(
              overrides: [
                appDatabaseProvider.overrideWithValue(memoryDb),
                mediaLibraryRepositoryProvider.overrideWithValue(repository),
                tmdbTokenStoreProvider.overrideWithValue(fakeTokenStore),
                platformOverrideProvider.overrideWithValue(
                  TargetPlatform.windows,
                ),
                sourceAdaptersProvider.overrideWithValue({
                  'local': failingAdapter,
                }),
                playerSessionProvider.overrideWithValue(
                  createFakeSession(engine: fakePlayerEngine),
                ),
                routerProvider.overrideWithValue(testRouter),
              ],
              child: MaterialApp.router(routerConfig: testRouter),
            ),
          );
          await tester.pumpAndSettle();

          expect(find.byType(WorkDetailsPage), findsOneWidget);
          final playButtonFinder = find.byKey(
            const Key('work_play_version_button_1'),
          );
          expect(playButtonFinder, findsOneWidget);
          await tester.ensureVisible(playButtonFinder);
          await tester.pumpAndSettle();
          await tester.tap(playButtonFinder);
          await tester.pumpAndSettle();

          // 解析失败保留当前详情页视图，未跳转播放器，无崩溃
          expect(find.byType(WorkDetailsPage), findsOneWidget);
          expect(find.byType(PlayerPage), findsNothing);
          expect(fakePlayerEngine.openCount, 0);

          // 呈现安全提示与重试按钮
          expect(find.text('目标文件已被移动或离线'), findsOneWidget);
          expect(find.text('重试'), findsOneWidget);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump(Duration.zero);
        }
      },
    );

    testWidgets(
      'Offline manual local edit updates metadata and visibly locks work',
      (tester) async {
        final source = await repository.upsertSource(
          kind: 'local',
          rootLocator: 'C:/movies',
          name: '经典库',
        );
        final scanId = await repository.beginScan(source.id);
        await repository.applyScanBatch(source.id, scanId, const [
          MediaEntry(
            externalId: 'matrix.mkv',
            locator: 'matrix.mkv',
            name: 'matrix.mkv',
            isDirectory: false,
            size: 5000000,
          ),
        ]);
        await repository.finishScan(source.id, scanId);

        final testRouter = createRouter(initialLocation: '/library/work/1');
        addTearDown(testRouter.dispose);

        try {
          await tester.pumpWidget(
            ProviderScope(
              overrides: [
                appDatabaseProvider.overrideWithValue(memoryDb),
                mediaLibraryRepositoryProvider.overrideWithValue(repository),
                tmdbTokenStoreProvider.overrideWithValue(fakeTokenStore),
                platformOverrideProvider.overrideWithValue(
                  TargetPlatform.windows,
                ),
                routerProvider.overrideWithValue(testRouter),
              ],
              child: MaterialApp.router(routerConfig: testRouter),
            ),
          );
          await tester.pumpAndSettle();

          // 1. 验证初始作品详情展示
          expect(find.byType(WorkDetailsPage), findsOneWidget);
          expect(find.text('matrix'), findsWidgets);
          expect(find.byKey(const Key('work_locked_badge')), findsNothing);

          // 2. 点击本地编辑按钮唤出对话框
          final editButtonFinder = find.byKey(
            const Key('work_local_edit_button'),
          );
          expect(editButtonFinder, findsOneWidget);
          await tester.ensureVisible(editButtonFinder);
          await tester.pumpAndSettle();
          await tester.tap(editButtonFinder);
          await tester.pumpAndSettle();

          // 3. 修改标题为 '黑客帝国'，年份为 1999，简介为 '经典科幻电影'
          final titleInput = find.byKey(const Key('local_edit_title_input'));
          expect(titleInput, findsOneWidget);
          await tester.enterText(titleInput, '黑客帝国');

          final yearInput = find.byKey(const Key('local_edit_year_input'));
          expect(yearInput, findsOneWidget);
          await tester.enterText(yearInput, '1999');

          final overviewInput = find.byKey(
            const Key('local_edit_overview_input'),
          );
          expect(overviewInput, findsOneWidget);
          await tester.enterText(overviewInput, '经典科幻电影');

          // 4. 点击保存并锁定
          final saveButton = find.byKey(const Key('local_edit_save_button'));
          expect(saveButton, findsOneWidget);
          await tester.tap(saveButton);
          await tester.pumpAndSettle();

          // 5. 验证对话框关闭，详情页数据已更新且呈现锁定标记
          final updatedTitleWidget = tester.widget<Text>(
            find.byKey(const Key('work_details_title')),
          );
          expect(updatedTitleWidget.data, '黑客帝国');
          expect(find.text('1999'), findsOneWidget);
          expect(find.text('经典科幻电影'), findsOneWidget);
          expect(find.byKey(const Key('work_locked_badge')), findsOneWidget);

          final updatedWorkDetails = await tester.runAsync(
            () => repository.getWorkDetails(1),
          );
          expect(updatedWorkDetails, isNotNull);
          expect(updatedWorkDetails!.work.title, '黑客帝国');
          expect(updatedWorkDetails.work.year, 1999);
          expect(updatedWorkDetails.work.overview, '经典科幻电影');
          expect(updatedWorkDetails.work.metadataLocked, isTrue);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump(Duration.zero);
        }
      },
    );

    testWidgets(
      'Manual match merges candidate into canonical work, preserves all versions and locks metadata',
      (tester) async {
        // 1. 在内存库中建立两个不同的本地候选条目
        final source = await repository.upsertSource(
          kind: 'local',
          rootLocator: 'C:/movies',
          name: '科幻源',
        );
        final scanId = await repository.beginScan(source.id);
        await repository.applyScanBatch(source.id, scanId, const [
          MediaEntry(
            externalId: 'Interstellar.2014.1080p.mkv',
            locator: 'Interstellar.2014.1080p.mkv',
            name: 'Interstellar.2014.1080p.mkv',
            isDirectory: false,
            size: 10485760,
          ),
          MediaEntry(
            externalId: 'XingJiChuanYue.2014.2160p.mkv',
            locator: 'XingJiChuanYue.2014.2160p.mkv',
            name: 'XingJiChuanYue.2014.2160p.mkv',
            isDirectory: false,
            size: 41943040,
          ),
        ]);
        await repository.finishScan(source.id, scanId);

        final initialWorks =
            await tester.runAsync(() => repository.watchWorks().first) ?? [];
        expect(initialWorks.length, 2);
        final canonicalTarget = initialWorks[0];
        final candidateWork = initialWorks[1];

        const tmdbInterstellar = TmdbWork(
          id: 157336,
          type: 'movie',
          title: '星际穿越',
          year: 2014,
          overview: '近未来的地球黄沙遍野，人类面临绝境...',
          posterPath: null,
        );

        // 先将目标条目绑定至 TMDB 规范影视（确立 canonicalWorkId）
        final canonicalId =
            await tester.runAsync(
              () => repository.applyMetadata(
                canonicalTarget.id,
                tmdbInterstellar,
                manual: true,
              ),
            ) ??
            canonicalTarget.id;
        expect(canonicalId, canonicalTarget.id);

        // 2. 注入受控的 FakeTmdbClient
        final fakeTmdbClient = FakeTmdbClient()
          ..movieSearchResults = [tmdbInterstellar]
          ..movieDetailsMap[157336] = tmdbInterstellar;

        // 3. 从待匹配的候选作品（candidateWork.id）详情页进入
        final testRouter = createRouter(
          initialLocation: '/library/work/${candidateWork.id}',
        );
        addTearDown(testRouter.dispose);

        try {
          await tester.pumpWidget(
            ProviderScope(
              overrides: [
                appDatabaseProvider.overrideWithValue(memoryDb),
                mediaLibraryRepositoryProvider.overrideWithValue(repository),
                tmdbTokenStoreProvider.overrideWithValue(fakeTokenStore),
                tmdbClientProvider.overrideWithValue(fakeTmdbClient),
                platformOverrideProvider.overrideWithValue(
                  TargetPlatform.windows,
                ),
                routerProvider.overrideWithValue(testRouter),
              ],
              child: MaterialApp.router(routerConfig: testRouter),
            ),
          );
          await tester.pumpAndSettle();

          // 4. 确认在候选作品详情页，点击“手动匹配”
          expect(find.byType(WorkDetailsPage), findsOneWidget);
          final matchButton = find.byKey(const Key('work_manual_match_button'));
          expect(matchButton, findsOneWidget);
          await tester.ensureVisible(matchButton);
          await tester.pumpAndSettle();
          await tester.tap(matchButton);
          await tester.pumpAndSettle();

          expect(find.byType(ManualMatchDialog), findsOneWidget);

          // 5. 验证错误年份输入校验（格式错误未发出有效搜索，列表未渲染）
          final yearInput = find.byKey(const Key('manual_match_year_input'));
          await tester.enterText(yearInput, 'not-a-year');
          final searchButton = find.byKey(
            const Key('manual_match_search_button'),
          );
          await tester.tap(searchButton);
          await tester.pumpAndSettle();

          expect(
            find.byKey(const Key('manual_match_results_list')),
            findsNothing,
          );

          // 清除错误年份，输入正确标题与年份进行搜索
          await tester.enterText(yearInput, '2014');
          final queryInput = find.byKey(const Key('manual_match_query_input'));
          await tester.enterText(queryInput, '星际穿越');
          await tester.tap(searchButton);
          await tester.pumpAndSettle();

          // 搜索结果卡片呈现
          expect(
            find.byKey(const Key('manual_match_results_list')),
            findsOneWidget,
          );
          final selectButton = find.byKey(
            const Key('manual_match_select_button_157336'),
          );
          expect(selectButton, findsOneWidget);

          // 6. 选定匹配目标 TMDB 条目
          await tester.tap(selectButton);
          await tester.pumpAndSettle();

          // 7. 观测端到端行为：
          // (a) 弹窗关闭，路由自动切换并导航至规范作品详情页（/library/work/$canonicalId）
          expect(find.byType(ManualMatchDialog), findsNothing);
          expect(find.byType(WorkDetailsPage), findsOneWidget);

          // (b) 两个版本文件完整保留于 canonical 作品下
          final canonicalDetails = await tester.runAsync(
            () => repository.getWorkDetails(canonicalId),
          );
          expect(canonicalDetails, isNotNull);
          expect(canonicalDetails!.versions.length, 2);
          expect(
            canonicalDetails.versions.any((v) => v.fileName.contains('1080p')),
            isTrue,
          );
          expect(
            canonicalDetails.versions.any((v) => v.fileName.contains('2160p')),
            isTrue,
          );

          // (c) 元数据标记为已锁定，UI 呈现锁定徽章
          expect(canonicalDetails.work.metadataLocked, isTrue);
          expect(find.byKey(const Key('work_locked_badge')), findsOneWidget);

          // (d) 后续自动触发的 applyMetadata 不得覆写手动匹配与锁定结果
          await tester.runAsync(
            () => repository.applyMetadata(
              canonicalId,
              const TmdbWork(id: 999999, type: 'movie', title: '被篡改的标题'),
              manual: false,
            ),
          );
          final afterAutoWork = await tester.runAsync(
            () => repository.getWorkDetails(canonicalId),
          );
          expect(afterAutoWork!.work.title, '星际穿越');
          expect(afterAutoWork.work.metadataLocked, isTrue);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump(Duration.zero);
        }
      },
    );

    testWidgets(
      'Manual match unresolved file to TV prompts episode confirmation and locks canonical work',
      (tester) async {
        // 1. 初始化无季集影视文件 Show.mkv
        final source = await repository.upsertSource(
          kind: 'local',
          rootLocator: 'C:/shows',
          name: '剧集源',
        );
        final scanId = await repository.beginScan(source.id);
        await repository.applyScanBatch(source.id, scanId, const [
          MediaEntry(
            externalId: 'Show.mkv',
            locator: 'Show.mkv',
            name: 'Show.mkv',
            isDirectory: false,
            size: 20480000,
          ),
        ]);
        await repository.finishScan(source.id, scanId);

        final initialWorks =
            await tester.runAsync(() => repository.watchWorks().first) ?? [];
        expect(initialWorks.length, 1);
        final initialWork = initialWorks.first;
        expect(initialWork.type, isNull);
        expect(initialWork.metadataLocked, isFalse);

        // 2. 注入受控的 FakeTmdbClient，提供 TV 搜索、详情与分集数据
        const tmdbSeries = TmdbWork(
          id: 115036,
          type: 'series',
          title: 'Show',
          year: 2022,
          overview: '关于 Show 的剧集介绍...',
          posterPath: null,
        );

        const season2Episode3 = TmdbEpisode(
          seasonNumber: 2,
          episodeNumber: 3,
          title: '第三集测试',
          overview: '第三集剧情介绍',
        );

        final fakeTmdbClient = FakeTmdbClient()
          ..tvSearchResults = [tmdbSeries]
          ..tvDetailsMap[115036] = tmdbSeries
          ..tvSeasonEpisodesMap['115036:2'] = [
            const TmdbEpisode(seasonNumber: 2, episodeNumber: 1, title: '第一集'),
            const TmdbEpisode(seasonNumber: 2, episodeNumber: 2, title: '第二集'),
            season2Episode3,
          ];

        // 3. 进入未解决候选条目的详情页
        final testRouter = createRouter(
          initialLocation: '/library/work/${initialWork.id}',
        );
        addTearDown(testRouter.dispose);

        try {
          await tester.pumpWidget(
            ProviderScope(
              overrides: [
                appDatabaseProvider.overrideWithValue(memoryDb),
                mediaLibraryRepositoryProvider.overrideWithValue(repository),
                tmdbTokenStoreProvider.overrideWithValue(fakeTokenStore),
                tmdbClientProvider.overrideWithValue(fakeTmdbClient),
                platformOverrideProvider.overrideWithValue(
                  TargetPlatform.windows,
                ),
                routerProvider.overrideWithValue(testRouter),
              ],
              child: MaterialApp.router(routerConfig: testRouter),
            ),
          );
          await tester.pumpAndSettle();

          expect(find.byType(WorkDetailsPage), findsOneWidget);
          final matchButton = find.byKey(const Key('work_manual_match_button'));
          expect(matchButton, findsOneWidget);
          await tester.ensureVisible(matchButton);
          await tester.pumpAndSettle();
          await tester.tap(matchButton);
          await tester.pumpAndSettle();

          expect(find.byType(ManualMatchDialog), findsOneWidget);

          // 4. 切换为剧集类型并搜索 Show
          await tester.tap(find.text('剧集'));
          await tester.pumpAndSettle();

          final queryInput = find.byKey(const Key('manual_match_query_input'));
          await tester.enterText(queryInput, 'Show');
          final searchButton = find.byKey(
            const Key('manual_match_search_button'),
          );
          await tester.tap(searchButton);
          await tester.pumpAndSettle();

          expect(
            find.byKey(const Key('manual_match_results_list')),
            findsOneWidget,
          );
          final selectButton = find.byKey(
            const Key('manual_match_select_button_115036'),
          );
          expect(selectButton, findsOneWidget);

          // 5. 点击选定匹配，由于未确立剧集身份，触发私有分集确认框
          await tester.tap(selectButton);
          await tester.pumpAndSettle();

          expect(
            find.byKey(const Key('manual_match_season_input')),
            findsOneWidget,
          );
          expect(
            find.byKey(const Key('manual_match_episode_input')),
            findsOneWidget,
          );

          // 先取消并证明数据库无锁定或身份修改
          final cancelButton = find.byKey(
            const Key('manual_match_episode_cancel_button'),
          );
          await tester.tap(cancelButton);
          await tester.pumpAndSettle();

          expect(
            find.byKey(const Key('manual_match_season_input')),
            findsNothing,
          );
          expect(find.byType(ManualMatchDialog), findsOneWidget);

          final workAfterCancel = await tester.runAsync(
            () => repository.getWorkDetails(initialWork.id),
          );
          expect(workAfterCancel, isNotNull);
          expect(workAfterCancel!.work.type, isNull);
          expect(workAfterCancel.work.metadataLocked, isFalse);

          // 6. 再次选择、填写真实 API fixture 中的季/集 (2/3)
          await tester.tap(selectButton);
          await tester.pumpAndSettle();

          expect(
            find.byKey(const Key('manual_match_season_input')),
            findsOneWidget,
          );
          await tester.enterText(
            find.byKey(const Key('manual_match_season_input')),
            '2',
          );
          await tester.enterText(
            find.byKey(const Key('manual_match_episode_input')),
            '3',
          );

          final confirmButton = find.byKey(
            const Key('manual_match_episode_confirm_button'),
          );
          await tester.tap(confirmButton);
          await tester.pumpAndSettle();

          // 7. 观测对话框关闭并展示 canonical 详情、分集、锁定与版本
          expect(find.byType(ManualMatchDialog), findsNothing);
          expect(find.byType(WorkDetailsPage), findsOneWidget);
          expect(find.byKey(const Key('work_locked_badge')), findsOneWidget);

          final canonicalWorks =
              await tester.runAsync(() => repository.watchWorks().first) ?? [];
          expect(canonicalWorks.length, 1);
          final canonicalId = canonicalWorks.first.id;

          final canonicalDetails = await tester.runAsync(
            () => repository.getWorkDetails(canonicalId),
          );
          expect(canonicalDetails, isNotNull);
          expect(canonicalDetails!.work.type, 'series');
          expect(canonicalDetails.work.metadataLocked, isTrue);
          expect(canonicalDetails.versions.length, 1);

          final version = canonicalDetails.versions.first;
          expect(version.fileName, 'Show.mkv');
          expect(version.seasonNumber, 2);
          expect(version.episodeNumber, 3);
          expect(version.episodeTitle, '第三集测试');

          final versionItemFinder = find.byKey(
            Key('work_version_item_${version.fileId}'),
          );
          expect(versionItemFinder, findsOneWidget);
          expect(
            find.descendant(
              of: versionItemFinder,
              matching: find.textContaining('S02E03'),
            ),
            findsOneWidget,
          );
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump(Duration.zero);
        }
      },
    );

    testWidgets(
      'Controlled scan cancellation converges UI to idle and preserves existing library',
      (tester) async {
        // 1. 初始化已有成功扫描的视频
        final source = await repository.upsertSource(
          kind: 'local',
          rootLocator: 'C:/videos',
          name: '长期存档源',
        );
        final initScanId = await repository.beginScan(source.id);
        await repository.applyScanBatch(source.id, initScanId, const [
          MediaEntry(
            externalId: 'saved_video.mp4',
            locator: 'saved_video.mp4',
            name: 'saved_video.mp4',
            isDirectory: false,
            size: 10240,
          ),
        ]);
        await repository.finishScan(source.id, initScanId);

        // 2. 注入受控异步流，挂起扫描任务
        final activeScanStreamController = StreamController<MediaEntry>();

        final controllableAdapter = FakeControllableMediaSourceAdapter(
          streamController: activeScanStreamController,
        );

        final testRouter = createRouter(initialLocation: '/sources');
        addTearDown(testRouter.dispose);

        try {
          await tester.pumpWidget(
            ProviderScope(
              overrides: [
                appDatabaseProvider.overrideWithValue(memoryDb),
                mediaLibraryRepositoryProvider.overrideWithValue(repository),
                tmdbTokenStoreProvider.overrideWithValue(fakeTokenStore),
                platformOverrideProvider.overrideWithValue(
                  TargetPlatform.windows,
                ),
                sourceAdaptersProvider.overrideWithValue({
                  'local': controllableAdapter,
                }),
                routerProvider.overrideWithValue(testRouter),
              ],
              child: MaterialApp.router(routerConfig: testRouter),
            ),
          );
          await tester.pumpAndSettle();

          // 点击刷新触发实际扫描执行
          final refreshButton = find.byKey(
            Key('source_refresh_button_${source.id}'),
          );
          expect(refreshButton, findsOneWidget);
          await tester.tap(refreshButton);
          await tester.pump();

          // 验证正在扫描状态：进度指示条与取消按钮呈现，刷新按钮收起
          expect(
            find.byKey(Key('source_progress_bar_${source.id}')),
            findsOneWidget,
          );
          final cancelButtonFinder = find.byKey(
            Key('source_cancel_button_${source.id}'),
          );
          expect(cancelButtonFinder, findsOneWidget);
          expect(
            find.byKey(Key('source_refresh_button_${source.id}')),
            findsNothing,
          );

          // 3. 点击取消扫描并关闭挂起的流
          await tester.tap(cancelButtonFinder);
          await activeScanStreamController.close();
          await tester.pumpAndSettle();
          // 4. 验证 UI 成功收束：取消按钮消失，刷新按钮恢复呈现
          expect(
            find.byKey(Key('source_progress_bar_${source.id}')),
            findsNothing,
          );
          expect(
            find.byKey(Key('source_refresh_button_${source.id}')),
            findsOneWidget,
          );

          // 5. 验证已有库内容完整保留，未被取消操作误删或标记离线
          final currentWorks = await tester.runAsync(
            () => repository.watchWorks().first,
          );
          expect(currentWorks, isNotNull);
          expect(currentWorks!.isNotEmpty, isTrue);
          expect(currentWorks.first.available, isTrue);

          final savedVideo = await tester.runAsync(
            () => repository.getVideo(1),
          );
          expect(savedVideo, isNotNull);
          expect(savedVideo!.available, isTrue);
          expect(savedVideo.fileName, 'saved_video.mp4');

          testRouter.go('/library');
          await tester.pumpAndSettle();
          expect(find.byType(LibraryPage), findsOneWidget);
          expect(
            find.byKey(Key('library_work_card_${currentWorks.first.id}')),
            findsOneWidget,
          );
        } finally {
          if (!activeScanStreamController.isClosed) {
            await activeScanStreamController.close();
          }
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump(Duration.zero);
        }
      },
    );

    testWidgets(
      'LibraryPage supports pagination limit initially 100 and load more (+100)',
      (tester) async {
        final (worksTotal, lastWorkId) =
            await tester.runAsync(() async {
              final source = await repository.upsertSource(
                kind: 'local',
                rootLocator: 'C:/huge_collection',
                name: '大合辑',
              );
              final scanId = await repository.beginScan(source.id);

              final entries = List.generate(
                105,
                (i) => MediaEntry(
                  externalId: 'video_${i.toString().padLeft(3, '0')}.mp4',
                  locator: 'video_${i.toString().padLeft(3, '0')}.mp4',
                  name: 'video_${i.toString().padLeft(3, '0')}.mp4',
                  isDirectory: false,
                ),
              );
              await repository.applyScanBatch(source.id, scanId, entries);
              await repository.finishScan(source.id, scanId);

              final allWorks = await repository.watchWorks(limit: 200).first;
              return (allWorks.length, allWorks.last.id);
            }) ??
            (0, 0);

        expect(worksTotal, 105);

        final testRouter = createRouter(initialLocation: '/library');

        try {
          await tester.pumpWidget(
            ProviderScope(
              overrides: [
                appDatabaseProvider.overrideWithValue(memoryDb),
                mediaLibraryRepositoryProvider.overrideWithValue(repository),
                tmdbTokenStoreProvider.overrideWithValue(fakeTokenStore),
                platformOverrideProvider.overrideWithValue(
                  TargetPlatform.windows,
                ),
                routerProvider.overrideWithValue(testRouter),
              ],
              child: MaterialApp.router(routerConfig: testRouter),
            ),
          );
          await tester.pumpAndSettle();

          // 初始 100 条限制下，第 105 部作品尚未出现在网格中
          expect(
            find.byKey(Key('library_work_card_$lastWorkId')),
            findsNothing,
          );

          final loadMoreFinder = find.byKey(
            const Key('library_load_more_button'),
          );
          final scrollableFinder = find.descendant(
            of: find.byKey(const Key('library_works_scroll_view')),
            matching: find.byWidgetPredicate(
              (widget) =>
                  widget is Scrollable &&
                  axisDirectionToAxis(widget.axisDirection) == Axis.vertical,
            ),
          );

          // 滚动至视图底部展示“加载更多”按钮并交互
          await tester.scrollUntilVisible(
            loadMoreFinder,
            300,
            scrollable: scrollableFinder,
          );
          await tester.pumpAndSettle();

          expect(loadMoreFinder, findsOneWidget);
          await tester.tap(loadMoreFinder);
          await tester.pumpAndSettle();

          // 加载更多后按钮收起，继续滚动至第 2 页的第 105 部作品卡片
          expect(loadMoreFinder, findsNothing);

          final lastWorkCardFinder = find.byKey(
            Key('library_work_card_$lastWorkId'),
          );
          await tester.scrollUntilVisible(
            lastWorkCardFinder,
            300,
            scrollable: scrollableFinder,
          );
          await tester.pumpAndSettle();

          expect(lastWorkCardFinder, findsOneWidget);

          // 点击进入该作品详情页，验证第 105 个具体文件版本可见
          await tester.tap(lastWorkCardFinder);
          await tester.pumpAndSettle();

          expect(find.byType(WorkDetailsPage), findsOneWidget);
          expect(find.text('video_104.mp4'), findsOneWidget);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump(Duration.zero);
          testRouter.dispose();
        }
      },
    );

    testWidgets(
      'PlayerPage initialResource direct mount auto-opens and displays title',
      (tester) async {
        final resource = PlaybackResource(
          uri: Uri.file('C:/movies/interstellar.mkv'),
          displayName: '星际穿越.mkv',
        );

        final fakeSession = createFakeSession(engine: fakePlayerEngine);

        try {
          await tester.pumpWidget(
            ProviderScope(
              overrides: [playerSessionProvider.overrideWithValue(fakeSession)],
              child: MaterialApp(home: PlayerPage(initialResource: resource)),
            ),
          );
          await tester.pumpAndSettle();

          expect(find.text('星际穿越.mkv'), findsOneWidget);
          expect(fakePlayerEngine.openCount, 1);
          expect(fakePlayerEngine.lastOpenedResource, resource);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump(Duration.zero);
        }
      },
    );
  });
}
