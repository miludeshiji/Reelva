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
import 'package:reelva/features/metadata/domain/tmdb_models.dart';
import 'package:reelva/features/metadata/infrastructure/tmdb_token_store.dart';
import 'package:reelva/features/sources/application/source_providers.dart';
import 'package:reelva/features/sources/source_files_page.dart';
import 'package:reelva/shared/widgets/glass_widgets.dart';

import '../metadata/metadata_service_test.dart'
    show FakeFlutterSecureStorage, FakeTmdbClient;
import '../sources/source_browser_test.dart';

const _captureDir = String.fromEnvironment('REELVA_UI_CAPTURE_DIR');

class _IdleMetadataController extends MetadataController {
  @override
  Future<void> refresh() async {}
}

void main() {
  setUpAll(() async {
    if (_captureDir.isEmpty) return;
    final font = ByteData.sublistView(
      await File('C:/Windows/Fonts/msyh.ttc').readAsBytes(),
    );
    final loader = FontLoader('Microsoft YaHei')..addFont(Future.value(font));
    await loader.load();
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
      final boundary = GlobalKey();
      addTearDown(() async {
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
      expect(find.byKey(const Key('source_files_selection_bar')), findsNothing);
      expect(find.byType(GlassCard), findsWidgets);

      await tester.tap(find.byKey(const Key('source_file_checkbox_season1')));
      await tester.pumpAndSettle();
      expect(find.text('已选 2 个视频'), findsOneWidget);
      await tester.ensureVisible(find.text('S01'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('S01'));
      await tester.pumpAndSettle();
      final secondFile = find.byKey(const Key('source_file_checkbox_file2'));
      await tester.ensureVisible(secondFile);
      await tester.pumpAndSettle();
      await tester.tap(secondFile);
      await tester.pumpAndSettle();
      expect(find.text('已选 1 个视频'), findsOneWidget);
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
      await tester.ensureVisible(season2);
      await tester.pumpAndSettle();
      await tester.tap(season2);
      await tester.pumpAndSettle();
      expect(find.text('已选 2 个视频'), findsOneWidget);
      final missingSeason = find.byKey(const Key('source_file_checkbox_file4'));
      await tester.ensureVisible(missingSeason);
      await tester.pumpAndSettle();
      await tester.tap(missingSeason);
      await tester.pumpAndSettle();
      expect(find.text('已选 3 个视频'), findsOneWidget);
      await _capture(tester, boundary, 'source-files-${viewport.name}.png');

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
      await tester.pumpAndSettle();
      expect(find.byType(ManualMatchPage), findsNothing);
      expect(find.text('手动匹配完成，影视库已更新'), findsOneWidget);
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
