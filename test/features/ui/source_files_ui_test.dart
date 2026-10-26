import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:drift/native.dart';
import 'package:drift/drift.dart' show DatabaseConnection;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reelva/app/router.dart';
import 'package:reelva/app/theme/reelva_theme.dart';
import 'package:reelva/core/database/app_database.dart';
import 'package:reelva/features/library/infrastructure/media_library_repository.dart';
import 'package:reelva/features/library/presentation/manual_match_page.dart';
import 'package:reelva/features/metadata/application/metadata_providers.dart';
import 'package:reelva/features/metadata/application/nfo_providers.dart';
import 'package:reelva/features/metadata/application/nfo_service.dart';
import 'package:reelva/features/metadata/domain/tmdb_models.dart';
import 'package:reelva/features/metadata/infrastructure/tmdb_token_store.dart';
import 'package:reelva/features/sources/application/source_providers.dart';
import 'package:reelva/features/sources/source_files_page.dart';
import 'package:reelva/shared/widgets/glass_widgets.dart';

import '../metadata/metadata_service_test.dart'
    show FakeFlutterSecureStorage, FakeTmdbClient;
import '../metadata/nfo_test_helpers.dart';
import '../sources/source_browser_test.dart';

const _captureDir = String.fromEnvironment('REELVA_UI_CAPTURE_DIR');

class _IdleMetadataController extends MetadataController {
  @override
  Future<void> refresh() async {}
}

class _DelayedNfoService extends FakeNfoService {
  final started = Completer<void>();
  final response = Completer<NfoResult>();

  @override
  Future<NfoResult> export({
    int? workId,
    List<int>? fileIds,
    bool replaceIdentity = false,
  }) {
    exports++;
    if (exports == 1) {
      started.complete();
      return response.future;
    }
    return Future.value(NfoResult(saved: fileIds?.length ?? 1));
  }
}

void main() {
  setUpAll(() async {
    if (_captureDir.isEmpty) return;
    final font = ByteData.sublistView(
      await File('C:/Windows/Fonts/msyh.ttc').readAsBytes(),
    );
    for (final family in const ['Microsoft YaHei', 'Roboto']) {
      final loader = FontLoader(family)..addFont(Future.value(font));
      await loader.load();
    }
    final icons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await icons.load();
  });

  for (final viewport in [
    (name: 'mobile', size: const Size(390, 844), scale: 1.0),
    (name: 'small-text150', size: const Size(320, 568), scale: 1.5),
    (name: 'landscape', size: const Size(568, 320), scale: 1.0),
    (name: 'desktop', size: const Size(1440, 900), scale: 1.0),
  ]) {
    testWidgets('目录勾选、跨季手动匹配及统一玻璃界面 ${viewport.name}', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = viewport.size;
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetViewInsets);
      final db = AppDatabase(
        executor: DatabaseConnection(
          NativeDatabase.memory(),
          closeStreamsSynchronously: true,
        ),
      );
      final repo = MediaLibraryRepository(db);
      final source = await repo.upsertSource(
        kind: 'local',
        rootLocator: 'root',
        name: 'Show.2024',
      );
      final adapter = TreeSourceAdapter({
        'root': [
          treeEntry('season1', 'S01', directory: true),
          treeEntry('season2', 'S02', directory: true),
          treeEntry('file4', 'E03.mkv'),
        ],
        'season1': [
          treeEntry('file1', 'E01.mkv'),
          treeEntry('file2', 'E02.mkv'),
        ],
        'season2': [treeEntry('file3', 'E01.mkv')],
      });
      const series = TmdbWork(id: 1, type: 'series', title: 'Show', year: 2024);
      final client = FakeTmdbClient();
      client.searchMovieHandler = (query, year) => const [
        TmdbWork(id: 1, type: 'movie', title: 'Show', year: 2024),
      ];
      client.searchTvHandler = (query, year) => [series];
      client.getTvDetailsHandler = (id) => series;
      client.getTvSeasonEpisodesHandler = (id, season) => [
        TmdbEpisode(seasonNumber: season, episodeNumber: 1),
        if (season == 2) const TmdbEpisode(seasonNumber: 2, episodeNumber: 3),
      ];
      final tokens = TmdbTokenStore(storage: FakeFlutterSecureStorage());
      await tokens.save('1234567890abcdef1234567890abcdef');
      final router = createRouter(initialLocation: '/sources');
      final nfo = _DelayedNfoService();
      final boundary = GlobalKey();
      addTearDown(() async {
        if (!nfo.response.isCompleted) nfo.response.complete(const NfoResult());
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        router.dispose();
        await db.close();
      });
      final theme = ReelvaTheme.light;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appDatabaseProvider.overrideWithValue(db),
            mediaLibraryRepositoryProvider.overrideWithValue(repo),
            sourceAdaptersProvider.overrideWithValue({'local': adapter}),
            tmdbClientProvider.overrideWithValue(client),
            tmdbTokenStoreProvider.overrideWithValue(tokens),
            nfoServiceProvider.overrideWithValue(nfo),
            metadataControllerProvider.overrideWith(
              _IdleMetadataController.new,
            ),
          ],
          child: RepaintBoundary(
            key: boundary,
            child: MaterialApp.router(
              debugShowCheckedModeBanner: false,
              theme: _captureDir.isEmpty
                  ? theme
                  : theme.copyWith(
                      textTheme: theme.textTheme.apply(
                        fontFamily: 'Microsoft YaHei',
                      ),
                    ),
              routerConfig: router,
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: TextScaler.linear(viewport.scale)),
                child: child!,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final sourceCard = find.byKey(Key('source_card_${source.id}'));
      await tester.ensureVisible(sourceCard);
      await tester.pumpAndSettle();
      await tester.tap(sourceCard);
      await tester.pumpAndSettle();
      expect(find.byType(SourceFilesPage), findsOneWidget);
      expect(
        find.byKey(const Key('source_files_selection_bar')),
        findsOneWidget,
      );
      expect(find.text('已选 0 个视频'), findsOneWidget);
      expect(
        tester
            .widget<GlassButton>(
              find.byKey(const Key('source_files_manual_match_button')),
            )
            .onPressed,
        isNull,
      );
      expect(find.byType(GlassCard), findsWidgets);

      await tester.tap(find.byKey(const Key('source_file_checkbox_season1')));
      await tester.pumpAndSettle();
      expect(find.text('已选 2 个视频'), findsOneWidget);
      await _revealSourceEntry(tester, find.text('S01'));
      await tester.tap(find.text('S01'));
      await tester.pumpAndSettle();
      final secondFile = find.byKey(const Key('source_file_checkbox_file2'));
      await _revealSourceEntry(tester, secondFile, delta: 100);
      await tester.tap(secondFile);
      await tester.pumpAndSettle();
      expect(find.text('已选 1 个视频'), findsOneWidget);
      final toggleAll = find.byKey(const Key('source_files_toggle_all_button'));
      await tester.ensureVisible(toggleAll);
      await tester.tap(toggleAll);
      await tester.pumpAndSettle();
      expect(find.text('已选 2 个视频'), findsOneWidget);
      await tester.tap(toggleAll);
      await tester.pumpAndSettle();
      expect(find.text('已选 0 个视频'), findsOneWidget);
      final firstFile = find.byKey(const Key('source_file_checkbox_file1'));
      await _revealSourceEntry(tester, firstFile);
      await tester.tap(firstFile);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('source_files_back_button')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<Checkbox>(
              find.byKey(const Key('source_file_checkbox_season1')),
            )
            .value,
        isNull,
      );
      final season2 = find.byKey(const Key('source_file_checkbox_season2'));
      await _revealSourceEntry(tester, season2, delta: 100);
      await tester.tap(season2);
      await tester.pumpAndSettle();
      expect(find.text('已选 2 个视频'), findsOneWidget);
      await _revealSourceEntry(tester, find.text('S01'));
      await tester.tap(find.text('S01'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(toggleAll);
      await tester.tap(toggleAll);
      await tester.pumpAndSettle();
      expect(find.text('已选 3 个视频'), findsOneWidget);
      await tester.tap(toggleAll);
      await tester.pumpAndSettle();
      expect(find.text('已选 1 个视频'), findsOneWidget);
      await _revealSourceEntry(tester, firstFile);
      await tester.tap(firstFile);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('source_files_back_button')));
      await tester.pumpAndSettle();
      final missingSeason = find.byKey(const Key('source_file_checkbox_file4'));
      await _revealSourceEntry(tester, missingSeason, delta: 100);
      await tester.tap(missingSeason);
      await tester.pumpAndSettle();
      expect(find.text('已选 3 个视频'), findsOneWidget);
      await _capture(tester, boundary, 'source-files-${viewport.name}.png');

      if (viewport.name == 'landscape') {
        client.searchTvHandler = (query, year) {
          throw const MetadataException('暂时无法连接 TMDB，请检查网络后重试');
        };
        await tester.tap(
          find.byKey(const Key('source_files_auto_match_button')),
        );
        await tester.pumpAndSettle();
        expect(find.text('已选 3 个视频'), findsOneWidget);
        expect(tester.takeException(), isNull);
        client.searchTvHandler = (query, year) => [series];
      }

      await tester.tap(
        find.byKey(const Key('source_files_manual_match_button')),
      );
      await tester.pumpAndSettle();
      expect(find.byType(ManualMatchPage), findsOneWidget);
      expect(find.byType(SegmentedButton<String>), findsNothing);
      final search = find.byKey(const Key('manual_match_search_button'));
      await tester.ensureVisible(search);
      await tester.pumpAndSettle();
      await tester.tap(search);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('manual_match_select_button_movie_1')),
        findsOneWidget,
      );
      final select = find.byKey(
        const Key('manual_match_select_button_series_1'),
      );
      await tester.scrollUntilVisible(
        select,
        100,
        scrollable: find
            .descendant(
              of: find.byType(CustomScrollView),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.pumpAndSettle();
      await tester.tap(select);
      await tester.pumpAndSettle();
      final batchSeason = find.byKey(
        const Key('manual_match_batch_season_input'),
      );
      await tester.ensureVisible(batchSeason);
      await tester.pumpAndSettle();
      await tester.enterText(batchSeason, '2');
      if (viewport.name != 'desktop') {
        tester.view.viewInsets = FakeViewPadding(
          bottom: viewport.size.height < 400 ? 120 : 240,
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        tester.view.resetViewInsets();
        await tester.pumpAndSettle();
      }
      final fillSeason = find.text('补全缺失季号');
      await tester.ensureVisible(fillSeason);
      await tester.pumpAndSettle();
      await tester.tap(fillSeason);
      await tester.pumpAndSettle();
      expect(find.text('请选择所属季'), findsNothing);
      await _capture(tester, boundary, 'manual-match-${viewport.name}.png');
      expect(tester.takeException(), isNull);
      await tester.tap(find.byKey(const Key('manual_match_apply_button')));
      await tester.runAsync(() => nfo.started.future);
      for (
        var frame = 0;
        frame < 10 && find.byType(ManualMatchPage).evaluate().isNotEmpty;
        frame++
      ) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.byType(ManualMatchPage), findsNothing);
      expect(find.text('手动匹配完成，影视库已更新'), findsOneWidget);
      await _revealSourceEntry(
        tester,
        find.byKey(const Key('source_file_checkbox_file4')),
        delta: 100,
        settle: false,
      );
      expect(find.text('已匹配 · Show（2024） · S02E03'), findsOneWidget);
      expect(find.text('正在后台保存 NFO 与图片'), findsOneWidget);
      expect(nfo.response.isCompleted, isFalse);
      nfo.response.complete(const NfoResult(errors: ['目录不可写']));
      await tester.pumpAndSettle();
      expect(find.text('部分目录元数据未完成保存'), findsOneWidget);
      expect(find.text('目录不可写'), findsOneWidget);
      final retry = find.text('重试导出 NFO 与图片');
      await tester.ensureVisible(retry);
      await tester.pumpAndSettle();
      await tester.tap(retry);
      await tester.pumpAndSettle();
      expect(nfo.exports, 2);
      expect(find.byKey(const Key('nfo_status_card')), findsNothing);
      expect(tester.takeException(), isNull);
      final works = await tester.runAsync(() => repo.watchWorks().first);
      expect(works!.length, 1);
      final details = await tester.runAsync(
        () => repo.getWorkDetails(works.single.id),
      );
      expect(
        details!.versions
            .map((file) => (file.seasonNumber, file.episodeNumber))
            .toSet(),
        {(1, 1), (2, 1), (2, 3)},
      );
    });
  }
}

Future<void> _revealSourceEntry(
  WidgetTester tester,
  Finder finder, {
  double delta = -100,
  bool settle = true,
}) async {
  await tester.scrollUntilVisible(
    finder,
    delta,
    scrollable: find.descendant(
      of: find.byKey(const Key('source_files_list')),
      matching: find.byType(Scrollable),
    ),
  );
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
  }
}

Future<void> _capture(WidgetTester tester, GlobalKey key, String name) async {
  if (_captureDir.isEmpty) return;
  final boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1);
    try {
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      await Directory(_captureDir).create(recursive: true);
      await File('$_captureDir/$name')
          .writeAsBytes(bytes!.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });
}
