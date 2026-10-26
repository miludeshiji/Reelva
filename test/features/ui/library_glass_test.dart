import 'package:reelva/features/metadata/application/nfo_providers.dart';

import '../metadata/nfo_test_helpers.dart';

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:drift/drift.dart' show DatabaseConnection;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:reelva/app/theme/reelva_theme.dart';
import 'package:reelva/app/router.dart';
import 'package:reelva/core/database/app_database.dart';
import 'package:reelva/features/library/infrastructure/media_library_repository.dart';
import 'package:reelva/features/library/domain/library_work.dart';
import 'package:reelva/features/library/library_page.dart';
import 'package:reelva/features/library/presentation/work_details_page.dart';
import 'package:reelva/features/library/presentation/manual_match_page.dart';
import 'package:reelva/features/metadata/application/metadata_providers.dart';
import 'package:reelva/features/metadata/presentation/metadata_status_card.dart';
import 'package:reelva/features/metadata/domain/tmdb_models.dart';
import 'package:reelva/features/sources/domain/source_models.dart';
import 'package:reelva/features/player/domain/playback_resource.dart';
import 'package:reelva/features/sources/application/source_providers.dart';

import '../metadata/metadata_service_test.dart' show FakeTmdbClient;

const _movie = LibraryWork(id: 1, type: 'movie', title: '黑客帝国', year: 1999);
const _series = LibraryWork(id: 2, type: 'series', title: '剧集收藏', year: 2024);
const _laterMovie = LibraryWork(
  id: 105,
  type: 'movie',
  title: '沙丘',
  originalTitle: 'Dune',
  year: 2024,
);
const _details = WorkDetails(
  work: LibraryWork(
    id: 7,
    type: 'series',
    title: '真实剧集',
    originalTitle: 'Original Series',
    metadataSource: 'tmdb',
    versionCount: 3,
  ),
  versions: [
    LibraryVersion(
      fileId: 70,
      fileName: 'Show.S01E01.offline.mkv',
      sourceName: '离线媒体源',
      available: false,
      sourceError: '媒体源暂不可用',
      seasonNumber: 1,
      episodeNumber: 1,
      episodeTitle: '启程',
    ),
    LibraryVersion(
      fileId: 71,
      fileName: 'Show.S01E01.mkv',
      sourceName: '本地媒体源',
      available: true,
      editionLabel: '1080p',
      seasonNumber: 1,
      episodeNumber: 1,
      episodeTitle: '启程',
    ),
    LibraryVersion(
      fileId: 72,
      fileName: 'Show.S02E02.mkv',
      sourceName: '家庭 NAS',
      available: true,
      editionLabel: '2160p',
      seasonNumber: 2,
      episodeNumber: 2,
      episodeTitle: '重逢',
    ),
  ],
);

class _IdleMetadataController extends MetadataController {
  @override
  Future<void> refresh() async {}
}

class _ProgressMetadataController extends _IdleMetadataController {
  @override
  MetadataTaskState build() => const MetadataTaskState(running: true);

  void report(MetadataTaskState progress) => state = progress;
}

class _ReviewMetadataController extends _IdleMetadataController {
  int refreshCount = 0;

  @override
  MetadataTaskState build() =>
      const MetadataTaskState(result: MetadataRefreshResult(needsReview: 1065));

  @override
  Future<void> refresh() async {
    refreshCount++;
  }
}

class _RecordingSourceController extends SourceController {
  final resolvedFiles = <int>[];

  @override
  Future<PlaybackResource> resolvePlayback(int fileId) async {
    resolvedFiles.add(fileId);
    return PlaybackResource(
      uri: Uri.file('C:/media/$fileId.mkv'),
      displayName: '$fileId.mkv',
      libraryFileId: fileId,
    );
  }
}

Future<void> _pumpLibrary(
  WidgetTester tester, {
  required List<LibraryWorksFilter> requests,
  required List<LibraryWork> Function(LibraryWorksFilter) filteredWorks,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        metadataControllerProvider.overrideWith(_IdleMetadataController.new),
        libraryWorksProvider.overrideWith(
          (ref, limit) => Stream.value(const [_movie, _series]),
        ),
        filteredLibraryWorksProvider.overrideWith((ref, filter) {
          requests.add(filter);
          return Stream.value(filteredWorks(filter));
        }),
      ],
      child: MaterialApp(theme: ReelvaTheme.light, home: const LibraryPage()),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> _pumpDetails(
  WidgetTester tester,
  _RecordingSourceController controller,
) async {
  final router = GoRouter(
    initialLocation: '/library/work/7',
    routes: [
      GoRoute(
        path: '/library/work/:id',
        builder: (context, state) => const WorkDetailsPage(workId: 7),
      ),
      GoRoute(
        path: '/player',
        builder: (context, state) {
          final resource = state.extra! as PlaybackResource;
          return Scaffold(body: Text('播放文件 ${resource.libraryFileId}'));
        },
      ),
    ],
  );
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    router.dispose();
  });
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        workDetailsProvider.overrideWith((ref, id) => Stream.value(_details)),
        sourceControllerProvider.overrideWith(() => controller),
      ],
      child: MaterialApp.router(theme: ReelvaTheme.light, routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('影视库可导出已有元数据，失败提示支持重试', (tester) async {
    final files = FakeNfoService()..fail = true;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          metadataControllerProvider.overrideWith(_IdleMetadataController.new),
          libraryWorksProvider.overrideWith(
            (ref, limit) => Stream.value(const [_movie]),
          ),
          nfoServiceProvider.overrideWithValue(files),
        ],
        child: MaterialApp(theme: ReelvaTheme.light, home: const LibraryPage()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('library_export_nfo_button')));
    await tester.pumpAndSettle();
    expect(files.exports, 1);
    expect(find.byKey(const Key('nfo_status_card')), findsOneWidget);
    expect(find.text('目录不可写'), findsOneWidget);
    files.fail = false;
    await tester.tap(find.text('重试导出 NFO 与图片'));
    await tester.pumpAndSettle();
    expect(files.exports, 2);
    expect(find.byKey(const Key('nfo_status_card')), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final unmatchedOnly in [false, true]) {
    testWidgets('加载更多保留列表和滚动位置，失败可重试（待匹配：$unmatchedOnly）', (tester) async {
      final works = List.generate(
        205,
        (index) => LibraryWork(id: index + 1, title: '作品 ${index + 1}'),
      );
      final requests = <LibraryWorksFilter>[];
      final pages = <StreamController<List<LibraryWork>>>[];
      Stream<List<LibraryWork>> watchPage(LibraryWorksFilter filter) {
        requests.add(filter);
        if (filter.limit == 100) return Stream.value(works.take(100).toList());
        final page = StreamController<List<LibraryWork>>();
        pages.add(page);
        return page.stream;
      }

      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        for (final page in pages) {
          await page.close();
        }
      });
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            metadataControllerProvider.overrideWith(
              _IdleMetadataController.new,
            ),
            libraryWorksProvider.overrideWith(
              (ref, limit) => watchPage((
                limit: limit,
                search: '',
                type: null,
                recentlyAdded: false,
                unmatchedOnly: false,
              )),
            ),
            filteredLibraryWorksProvider.overrideWith(
              (ref, filter) => watchPage(filter),
            ),
          ],
          child: MaterialApp(
            theme: ReelvaTheme.light,
            home: LibraryPage(unmatchedOnly: unmatchedOnly),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final gridFinder = find.byKey(const Key('library_works_grid'));
      final loadMoreFinder = find.byKey(const Key('library_load_more_button'));
      final controller = tester
          .widget<CustomScrollView>(
            find.byKey(const Key('library_works_scroll_view')),
          )
          .controller!;
      controller.jumpTo(controller.position.maxScrollExtent);
      await tester.pumpAndSettle();
      final gridElement = tester.element(gridFinder);
      final offset = controller.offset;
      expect(offset, greaterThan(0));
      expect(find.byKey(const Key('library_work_card_100')), findsOneWidget);

      await tester.tap(loadMoreFinder);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(gridFinder, findsOneWidget);
      expect(tester.element(gridFinder), same(gridElement));
      expect(controller.offset, closeTo(offset, 0.1));
      expect(find.byKey(const Key('library_work_card_100')), findsOneWidget);
      expect(find.byKey(const Key('library_loading_indicator')), findsNothing);
      expect(
        find.byKey(const Key('library_load_more_indicator')),
        findsOneWidget,
      );
      expect(
        tester
            .widget<OutlinedButton>(
              find.descendant(
                of: loadMoreFinder,
                matching: find.byType(OutlinedButton),
              ),
            )
            .onPressed,
        isNull,
      );
      await tester.tap(loadMoreFinder);
      await tester.pump();
      expect(requests.map((request) => request.limit), [100, 200]);
      expect(
        requests.every((request) => request.unmatchedOnly == unmatchedOnly),
        isTrue,
      );

      pages.last.addError(StateError('分页查询失败'));
      await tester.pumpAndSettle();
      expect(tester.element(gridFinder), same(gridElement));
      expect(controller.offset, closeTo(offset, 0.1));
      expect(find.byKey(const Key('library_error_widget')), findsNothing);
      expect(find.text('加载失败，点击重试'), findsOneWidget);

      await tester.tap(loadMoreFinder);
      await tester.pump();
      expect(requests.map((request) => request.limit), [100, 200, 200]);
      expect(tester.element(gridFinder), same(gridElement));
      expect(controller.offset, closeTo(offset, 0.1));
      pages.last.add(works.take(200).toList());
      await tester.pumpAndSettle();
      expect(tester.element(gridFinder), same(gridElement));
      expect(controller.offset, closeTo(offset, 0.1));
      expect(
        tester.widget<SliverGrid>(gridFinder).delegate.estimatedChildCount,
        200,
      );

      controller.jumpTo(controller.position.maxScrollExtent);
      await tester.pumpAndSettle();
      final secondOffset = controller.offset;
      await tester.tap(loadMoreFinder);
      await tester.pump();
      expect(tester.element(gridFinder), same(gridElement));
      expect(controller.offset, closeTo(secondOffset, 0.1));
      expect(requests.map((request) => request.limit), [100, 200, 200, 300]);
      pages.last.add(works);
      await tester.pumpAndSettle();
      expect(tester.element(gridFinder), same(gridElement));
      expect(controller.offset, closeTo(secondOffset, 0.1));
      expect(
        tester.widget<SliverGrid>(gridFinder).delegate.estimatedChildCount,
        205,
      );
      expect(loadMoreFinder, findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('分页等待期间切换筛选重置列表，旧分页结果不会覆盖新筛选', (tester) async {
    final works = List.generate(
      100,
      (index) => LibraryWork(id: index + 1, title: '作品 ${index + 1}'),
    );
    final page = StreamController<List<LibraryWork>>();
    final filteredPage = StreamController<List<LibraryWork>>();
    final requests = <LibraryWorksFilter>[];
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await page.close();
      await filteredPage.close();
    });
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          metadataControllerProvider.overrideWith(_IdleMetadataController.new),
          libraryWorksProvider.overrideWith(
            (ref, limit) => limit == 100 ? Stream.value(works) : page.stream,
          ),
          filteredLibraryWorksProvider.overrideWith((ref, filter) {
            requests.add(filter);
            return filteredPage.stream;
          }),
        ],
        child: MaterialApp(theme: ReelvaTheme.light, home: const LibraryPage()),
      ),
    );
    await tester.pumpAndSettle();
    final controller = tester
        .widget<CustomScrollView>(
          find.byKey(const Key('library_works_scroll_view')),
        )
        .controller!;
    controller.jumpTo(controller.position.maxScrollExtent);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('library_load_more_button')));
    await tester.pump();
    controller.jumpTo(0);
    await tester.pump();
    await tester.tap(find.byKey(const Key('library_filter_movie')));
    await tester.pump();
    expect(requests.single.type, 'movie');
    expect(requests.single.limit, 100);
    expect(controller.offset, 0);
    expect(find.byKey(const Key('library_works_grid')), findsNothing);
    expect(find.byKey(const Key('library_loading_indicator')), findsOneWidget);

    page.add([...works, _laterMovie]);
    await tester.pump();
    expect(find.byKey(const Key('library_works_grid')), findsNothing);
    filteredPage.add(const [_laterMovie]);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('library_work_card_1')), findsNothing);
    expect(find.byKey(const Key('library_work_card_105')), findsOneWidget);
    expect(find.byKey(const Key('library_load_more_button')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('整理结果可进入待匹配列表和手动匹配，处理后实时移出列表', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 900);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final db = AppDatabase(
      executor: DatabaseConnection(
        NativeDatabase.memory(),
        closeStreamsSynchronously: true,
      ),
    );
    final repo = MediaLibraryRepository(db);
    final source = await repo.upsertSource(
      kind: 'local',
      rootLocator: 'C:/Review',
      name: '剧集文件',
    );
    final files = await repo.indexSourceFiles(source.id, [
      for (final name in ['01.mkv', '02.mkv', 'Matched.2024.mkv'])
        MediaEntry(
          externalId: name,
          locator: name,
          name: name,
          isDirectory: false,
        ),
    ]);
    final matchedId = await repo.applyMetadataToFiles({
      files['Matched.2024.mkv']!: null,
    }, const TmdbWork(id: 1, type: 'movie', title: '已匹配作品'));
    final pending = (await tester.runAsync(
      () => repo.watchWorks(unmatchedOnly: true).first,
    ))!;
    expect(pending, hasLength(1));
    final metadata = _ReviewMetadataController();
    final client = FakeTmdbClient();
    client.searchTvHandler = (query, year) => const [
      TmdbWork(id: 2, type: 'series', title: '待确认剧集'),
    ];
    client.getTvSeasonEpisodesHandler = (id, season) => [
      for (final number in [1, 2])
        TmdbEpisode(seasonNumber: season, episodeNumber: number),
    ];
    final router = createRouter(initialLocation: '/sources');
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      router.dispose();
      await db.close();
    });
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          mediaLibraryRepositoryProvider.overrideWithValue(repo),
          nfoServiceProvider.overrideWithValue(FakeNfoService()),
          metadataControllerProvider.overrideWith(() => metadata),
          tmdbClientProvider.overrideWithValue(client),
        ],
        child: MaterialApp.router(
          theme: ReelvaTheme.light,
          routerConfig: router,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('本次整理：已匹配 0 个条目 · 1065 个未自动匹配'), findsOneWidget);
    await _tapVisible(tester, find.byKey(const Key('metadata_review_button')));
    expect(
      tester.widget<LibraryPage>(find.byType(LibraryPage)).unmatchedOnly,
      isTrue,
    );
    expect(
      tester
          .widget<FilterChip>(find.byKey(const Key('library_filter_unmatched')))
          .selected,
      isTrue,
    );
    expect(find.byKey(Key('library_work_card_$matchedId')), findsNothing);
    expect(metadata.refreshCount, 0);
    await _tapVisible(
      tester,
      find.byKey(Key('library_work_card_${pending.first.id}')),
    );
    expect(find.byType(ManualMatchPage), findsOneWidget);
    await _tapVisible(
      tester,
      find.byKey(const Key('manual_match_search_button')),
    );
    await _tapVisible(
      tester,
      find.byKey(const Key('manual_match_select_button_series_2')),
    );
    final fileId = files['01.mkv']!;
    expect(
      tester
          .widget<TextFormField>(
            find.byKey(ValueKey('manual_match_episode_${files['02.mkv']}')),
          )
          .initialValue,
      '2',
    );
    expect(
      tester
          .widget<TextFormField>(
            find.byKey(ValueKey('manual_match_season_${fileId}_0')),
          )
          .initialValue,
      '1',
    );
    expect(
      tester
          .widget<TextFormField>(
            find.byKey(ValueKey('manual_match_episode_$fileId')),
          )
          .initialValue,
      '1',
    );
    await _tapVisible(
      tester,
      find.byKey(const Key('manual_match_apply_button')),
    );
    expect(find.byType(ManualMatchPage), findsNothing);
    expect(
      tester.widget<LibraryPage>(find.byType(LibraryPage)).unmatchedOnly,
      isTrue,
    );
    expect(
      find.byKey(Key('library_work_card_${pending.first.id}')),
      findsNothing,
    );
    expect(
      find.byKey(const Key('library_unmatched_empty_view')),
      findsOneWidget,
    );
  });

  testWidgets('后台识别显示阶段与实际进度，已有作品持续可见', (tester) async {
    final controller = _ProgressMetadataController();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          metadataControllerProvider.overrideWith(() => controller),
          libraryWorksProvider.overrideWith(
            (ref, limit) => Stream.value(const [_movie, _series]),
          ),
        ],
        child: MaterialApp(theme: ReelvaTheme.light, home: const LibraryPage()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('正在整理影片与剧集'), findsOneWidget);
    expect(find.byKey(const Key('library_work_card_1')), findsOneWidget);

    controller.report(
      const MetadataTaskState(
        running: true,
        phase: MetadataPhase.matching,
        processed: 2,
        total: 5,
      ),
    );
    await tester.pump();
    expect(find.text('正在补充海报与简介'), findsOneWidget);
    expect(find.text('已处理 2 / 5 个条目'), findsOneWidget);
    expect(find.byKey(const Key('library_work_card_1')), findsOneWidget);

    controller.report(
      const MetadataTaskState(
        result: MetadataRefreshResult(matched: 4, needsReview: 1),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('媒体库整理完成'), findsOneWidget);
    expect(find.text('本次整理：已匹配 4 个条目 · 1 个未自动匹配'), findsOneWidget);
    expect(find.byKey(const Key('library_work_card_1')), findsOneWidget);
  });

  testWidgets('识别进度卡片在窄屏大字号下正常换行', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 568);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(
      MaterialApp(
        theme: ReelvaTheme.light,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(1.5)),
          child: child!,
        ),
        home: Scaffold(
          body: Center(
            child: MetadataStatusCard(
              state: const MetadataTaskState(
                running: true,
                phase: MetadataPhase.matching,
                processed: 2,
                total: 5,
                activeCount: 4,
              ),
              onRetry: () {},
              margin: const EdgeInsets.all(24),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('已处理 2 / 5 个条目'), findsOneWidget);
    expect(find.text('正在同时处理 4 项'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('搜索请求全库查询，清空搜索恢复原作品列表', (tester) async {
    final requests = <LibraryWorksFilter>[];
    await _pumpLibrary(
      tester,
      requests: requests,
      filteredWorks: (_) => const [_laterMovie],
    );
    expect(requests, isEmpty);
    expect(find.byKey(const Key('library_work_card_1')), findsOneWidget);
    expect(find.byKey(const Key('library_work_card_105')), findsNothing);

    await tester.enterText(find.byType(TextField), '  Dune  ');
    await tester.pumpAndSettle();
    expect(requests.single, (
      limit: 100,
      search: 'Dune',
      type: null,
      recentlyAdded: false,
      unmatchedOnly: false,
    ));
    expect(find.byKey(const Key('library_work_card_105')), findsOneWidget);
    expect(find.byKey(const Key('library_work_card_1')), findsNothing);

    await _tapVisible(tester, find.byTooltip('清空搜索'));
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      '',
    );
    expect(find.byKey(const Key('library_work_card_1')), findsOneWidget);
    expect(find.byKey(const Key('library_work_card_2')), findsOneWidget);
    expect(find.byKey(const Key('library_work_card_105')), findsNothing);
    expect(requests, hasLength(1));
  });

  testWidgets('类别、最近添加与搜索可组合，空结果可恢复全部作品', (tester) async {
    final requests = <LibraryWorksFilter>[];
    await _pumpLibrary(
      tester,
      requests: requests,
      filteredWorks: (filter) {
        if (filter.search == '不存在') return const [];
        return switch (filter.type) {
          'movie' => const [_movie],
          'series' => const [_series],
          _ => const [_movie, _series],
        };
      },
    );

    await _tapVisible(tester, find.byKey(const Key('library_filter_movie')));
    expect(requests.last.type, 'movie');
    expect(find.byKey(const Key('library_work_card_2')), findsNothing);

    await _tapVisible(tester, find.byKey(const Key('library_filter_series')));
    expect(requests.last.type, 'series');
    expect(find.byKey(const Key('library_work_card_1')), findsNothing);

    await _tapVisible(tester, find.byKey(const Key('library_sort_recent')));
    expect(requests.last.type, 'series');
    expect(requests.last.recentlyAdded, isTrue);

    await _tapVisible(tester, find.byKey(const Key('library_filter_all')));
    expect(requests.last.type, isNull);
    expect(requests.last.recentlyAdded, isTrue);
    await _tapVisible(tester, find.byKey(const Key('library_filter_series')));

    await tester.enterText(find.byType(TextField), '不存在');
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('library_search_empty_view')), findsOneWidget);
    await _tapVisible(tester, find.byTooltip('清空搜索'));
    expect(requests.last.search, '');
    expect(requests.last.type, 'series');
    expect(requests.last.recentlyAdded, isTrue);
    expect(find.byKey(const Key('library_work_card_2')), findsOneWidget);

    await tester.enterText(find.byType(TextField), '不存在');
    await tester.pumpAndSettle();
    await _tapVisible(tester, find.text('清空搜索和筛选'));
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      '',
    );
    expect(
      tester
          .widget<ChoiceChip>(find.byKey(const Key('library_filter_all')))
          .selected,
      isTrue,
    );
    expect(
      tester
          .widget<FilterChip>(find.byKey(const Key('library_sort_recent')))
          .selected,
      isFalse,
    );
    expect(find.byKey(const Key('library_work_card_1')), findsOneWidget);
    expect(find.byKey(const Key('library_work_card_2')), findsOneWidget);
  });

  testWidgets('真实季集可选择和展开，离线版本禁用，可手选可用版本播放', (tester) async {
    final controller = _RecordingSourceController();
    await _pumpDetails(tester, controller);
    expect(find.byKey(const Key('work_version_item_70')), findsOneWidget);
    expect(find.byKey(const Key('work_version_item_71')), findsOneWidget);
    expect(find.byKey(const Key('work_version_item_72')), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(
            find.descendant(
              of: find.byKey(const Key('work_play_version_button_70')),
              matching: find.byType(FilledButton),
            ),
          )
          .onPressed,
      isNull,
    );

    await _tapVisible(tester, find.byKey(const Key('work_season_selector')));
    await tester.tap(find.text('第 2 季').last);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('work_version_item_70')), findsNothing);
    expect(find.byKey(const Key('work_version_item_71')), findsNothing);
    expect(find.byKey(const Key('work_version_item_72')), findsOneWidget);
    expect(find.text('第 2 集 (S02E02) · 重逢'), findsOneWidget);

    final seasonTitle = find.descendant(
      of: find.byKey(const PageStorageKey('work_season_7_2')),
      matching: find.text('第 2 季'),
    );
    await _tapVisible(tester, seasonTitle);
    expect(find.byKey(const Key('work_play_version_button_72')), findsNothing);
    await _tapVisible(tester, seasonTitle);
    await _tapVisible(
      tester,
      find.byKey(const Key('work_play_version_button_72')),
    );
    expect(controller.resolvedFiles, [72]);
    expect(find.text('播放文件 72'), findsOneWidget);
  });

  testWidgets('开始播放跳过离线文件，解析首个可用版本', (tester) async {
    final controller = _RecordingSourceController();
    await _pumpDetails(tester, controller);
    await _tapVisible(tester, find.byKey(const Key('work_start_play_button')));
    expect(controller.resolvedFiles, [71]);
    expect(find.text('播放文件 71'), findsOneWidget);
  });
}
