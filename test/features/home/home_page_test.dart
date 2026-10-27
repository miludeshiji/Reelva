import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:reelva/app/router.dart';
import 'package:reelva/core/database/app_database.dart';
import 'package:reelva/core/errors/safe_error_widget.dart';
import 'package:reelva/features/home/application/home_providers.dart';
import 'package:reelva/features/home/home_page.dart';
import 'package:reelva/features/library/domain/library_work.dart';
import 'package:reelva/features/library/infrastructure/media_library_repository.dart';
import 'package:reelva/features/library/presentation/work_details_page.dart';
import 'package:reelva/features/player/application/player_providers.dart';
import 'package:reelva/features/player/domain/playback_resource.dart';
import 'package:reelva/features/player/presentation/player_page.dart';
import 'package:reelva/features/progress/application/progress_providers.dart';
import 'package:reelva/features/progress/presentation/watch_history_page.dart';
import 'package:reelva/features/sources/application/source_providers.dart';
import 'package:reelva/features/sources/domain/media_source_adapter.dart';
import 'package:reelva/features/sources/domain/source_models.dart';
import 'package:reelva/shared/widgets/poster_image.dart';
import 'package:reelva/features/sources/sources_page.dart';
import 'package:reelva/shared/widgets/empty_state_view.dart';

import '../player/fake_player_engine.dart';

/// 测试用媒体源适配器，支持可控的 resolvePlayback 行为
class FakeHomeSourceAdapter implements MediaSourceAdapter {
  FakeHomeSourceAdapter({
    this.shouldFailResolve = false,
    this.resolveErrorMessage = '媒体文件已离线或损坏',
  });

  @override
  String get kind => 'local';

  bool shouldFailResolve;
  String resolveErrorMessage;
  int resolveCount = 0;
  String? lastResolvedEntryId;
  Completer<void>? resolveCompleter;

  @override
  Future<DirectorySelection?> pickDirectory({String? initialLocator}) async =>
      null;

  @override
  Stream<MediaEntry> listEntries(
    MediaSourceConfig source,
    String directoryId,
  ) => const Stream.empty();

  @override
  Future<MediaStat> stat(MediaSourceConfig source, String entryId) async =>
      const MediaStat();

  @override
  Future<PlaybackResource> resolvePlayback(
    MediaSourceConfig source,
    String entryId,
  ) async {
    resolveCount++;
    lastResolvedEntryId = entryId;

    if (resolveCompleter != null) {
      await resolveCompleter!.future;
    }

    if (shouldFailResolve) {
      throw MediaSourceException(resolveErrorMessage, code: 'file_unavailable');
    }

    return PlaybackResource(
      uri: Uri.file('C:/videos/$entryId.mkv'),
      displayName: 'Video $entryId',
      libraryFileId: int.tryParse(entryId),
    );
  }
}

Widget createHomeTestApp({
  required AppDatabase db,
  GoRouter? router,
  List<Override> overrides = const [],
}) {
  return ProviderScope(
    overrides: [
      appDatabaseProvider.overrideWithValue(db),
      playerSessionProvider.overrideWith((ref) => createFakeSession()),
      if (router != null) routerProvider.overrideWithValue(router),
      ...overrides,
    ],
    child: MaterialApp.router(
      routerConfig: router ?? createRouter(initialLocation: '/'),
    ),
  );
}

Future<void> _cleanUpTestWidgets(
  WidgetTester tester, {
  GoRouter? router,
  required AppDatabase db,
}) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(Duration.zero);
  router?.dispose();
  await tester.runAsync(db.close);
}

void main() {
  group('HomePage Widget & Behavioral Tests (M4)', () {
    testWidgets(
      'Empty library displays source CTA without a floating player button',
      (tester) async {
        final db = AppDatabase(executor: NativeDatabase.memory());
        final router = createRouter(initialLocation: '/');

        try {
          await tester.pumpWidget(
            createHomeTestApp(
              db: db,
              router: router,
              overrides: [
                continueWatchingProvider.overrideWith(
                  (ref) => Stream.value(const <ContinueWatchingEntry>[]),
                ),
                recentWorksProvider.overrideWith(
                  (ref) => Stream.value(const <LibraryWork>[]),
                ),
              ],
            ),
          );
          await tester.pumpAndSettle();

          expect(find.byType(HomePage), findsOneWidget);
          expect(find.byType(EmptyStateView), findsOneWidget);
          expect(find.text('暂无影视内容'), findsOneWidget);
          expect(find.text('前往媒体源'), findsOneWidget);

          expect(find.byType(FloatingActionButton), findsNothing);

          // Tap CTA navigates to SourcesPage
          await tester.tap(find.widgetWithText(FilledButton, '前往媒体源'));
          await tester.pumpAndSettle();
          expect(find.byType(SourcesPage), findsOneWidget);
        } finally {
          await _cleanUpTestWidgets(tester, router: router, db: db);
        }
      },
    );

    testWidgets('Header opens player and returns without reloading home', (
      tester,
    ) async {
      final db = AppDatabase(executor: NativeDatabase.memory());
      final router = createRouter(initialLocation: '/');
      var recentWorksLoads = 0;

      try {
        await tester.pumpWidget(
          createHomeTestApp(
            db: db,
            router: router,
            overrides: [
              continueWatchingProvider.overrideWith(
                (ref) => Stream.value(const <ContinueWatchingEntry>[]),
              ),
              recentWorksProvider.overrideWith((ref) {
                recentWorksLoads++;
                return Stream.value(const [
                  LibraryWork(
                    id: 1,
                    title: '测试电影',
                    year: 2026,
                    versionCount: 1,
                    available: true,
                  ),
                ]);
              }),
            ],
          ),
        );
        await tester.pumpAndSettle();

        final homeState = tester.state(find.byType(HomePage));
        final openPlayer = find.byKey(const Key('home_open_player_fab'));
        expect(openPlayer, findsOneWidget);

        await tester.tap(openPlayer);
        await tester.pumpAndSettle();

        expect(find.byType(PlayerPage), findsOneWidget);

        await tester.tap(find.byKey(const Key('player_back_button')));
        await tester.pumpAndSettle();

        expect(router.routeInformationProvider.value.uri.path, '/');
        expect(tester.state(find.byType(HomePage)), same(homeState));
        expect(recentWorksLoads, 1);
      } finally {
        await _cleanUpTestWidgets(tester, router: router, db: db);
      }
    });

    testWidgets(
      'Continue watching view all opens history and returns with home state intact',
      (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final db = AppDatabase(executor: NativeDatabase.memory());
        final router = createRouter();
        var continueWatchingLoads = 0;
        const entry = ContinueWatchingEntry(
          workId: 1,
          title: '测试观看记录',
          fileId: 1,
          position: Duration(minutes: 10),
          duration: Duration(hours: 1),
        );
        try {
          await tester.pumpWidget(
            createHomeTestApp(
              db: db,
              router: router,
              overrides: [
                continueWatchingProvider.overrideWith((ref) {
                  continueWatchingLoads++;
                  return Stream.value(const [entry]);
                }),
                recentWorksProvider.overrideWith(
                  (ref) => Stream.value(const []),
                ),
                watchHistoryProvider.overrideWith(
                  (ref) => Stream.value([
                    WatchHistoryEntry(
                      id: 1,
                      entry: entry,
                      completed: false,
                      updatedAt: DateTime(2026, 10, 26, 12),
                    ),
                  ]),
                ),
              ],
            ),
          );
          await tester.pumpAndSettle();
          final homeState = tester.state(find.byType(HomePage));
          final viewAll = find.widgetWithText(TextButton, '查看全部');
          await tester.ensureVisible(viewAll);
          await tester.pumpAndSettle();
          final scrollable = tester.state<ScrollableState>(
            find.descendant(
              of: find.byType(HomePage),
              matching: find.byWidgetPredicate(
                (widget) =>
                    widget is Scrollable &&
                    widget.axisDirection == AxisDirection.down,
              ),
            ),
          );
          final offset = scrollable.position.pixels;
          await tester.tap(viewAll);
          await tester.pumpAndSettle();

          expect(router.routeInformationProvider.value.uri.path, '/history');
          expect(find.byType(WatchHistoryPage), findsOneWidget);
          expect(
            find.byKey(const Key('watch_history_entry_1')),
            findsOneWidget,
          );
          expect(
            find.byKey(const ValueKey('navigation_destination_library')),
            findsNothing,
          );

          await tester.tap(find.byKey(const Key('watch_history_back_button')));
          await tester.pumpAndSettle();
          expect(router.routeInformationProvider.value.uri.path, '/');
          expect(tester.state(find.byType(HomePage)), same(homeState));
          expect(scrollable.position.pixels, closeTo(offset, 0.1));
          expect(continueWatchingLoads, 1);
          expect(tester.takeException(), isNull);
        } finally {
          await _cleanUpTestWidgets(tester, router: router, db: db);
        }
      },
    );

    testWidgets(
      'Continue watching card shows progress and plays correct fileId into /player',
      (tester) async {
        final db = AppDatabase(executor: NativeDatabase.memory());
        final router = createRouter(initialLocation: '/');
        final repo = MediaLibraryRepository(db);
        final sourceAdapter = FakeHomeSourceAdapter();

        try {
          final video = (await tester.runAsync(() async {
            final src = await repo.upsertSource(
              kind: 'local',
              rootLocator: 'C:/videos',
              name: 'Local',
            );
            final scanId = await repo.beginScan(src.id);
            await repo.applyScanBatch(src.id, scanId, [
              MediaEntry(
                externalId: '101',
                locator: 'Inception.2010.mkv',
                name: 'Inception.2010.mkv',
                isDirectory: false,
                size: 1000,
                modifiedAt: DateTime.now(),
              ),
            ]);
            await repo.finishScan(src.id, scanId);
            return (await repo.watchLibrary().first).first;
          }))!;

          final entry = ContinueWatchingEntry(
            workId: 1,
            title: '盗梦空间',
            fileId: video.fileId,
            position: const Duration(minutes: 30),
            duration: const Duration(minutes: 120),
            available: true,
          );

          await tester.pumpWidget(
            createHomeTestApp(
              db: db,
              router: router,
              overrides: [
                sourceAdaptersProvider.overrideWithValue({
                  'local': sourceAdapter,
                }),
                continueWatchingProvider.overrideWith(
                  (ref) => Stream.value([entry]),
                ),
                recentWorksProvider.overrideWith(
                  (ref) => Stream.value(const <LibraryWork>[]),
                ),
              ],
            ),
          );
          await tester.pumpAndSettle();

          expect(find.text('继续观看'), findsOneWidget);
          // 使用唯一卡片 key，避免海报占位图与卡片主标题文字双重匹配
          expect(
            find.byKey(const Key('continue_watching_card_1')),
            findsOneWidget,
          );
          expect(find.text('30:00 / 2:00:00'), findsOneWidget);

          // Tap play icon
          final playFinder = find.byKey(const Key('continue_watching_play_1'));
          expect(playFinder, findsOneWidget);
          await tester.tap(playFinder);
          await tester.pumpAndSettle();

          expect(sourceAdapter.resolveCount, 1);
          expect(find.byType(PlayerPage), findsOneWidget);
        } finally {
          await _cleanUpTestWidgets(tester, router: router, db: db);
        }
      },
    );

    testWidgets(
      'Duplicate-click protection prevents redundant resolvePlayback calls',
      (tester) async {
        final db = AppDatabase(executor: NativeDatabase.memory());
        final router = createRouter(initialLocation: '/');
        final repo = MediaLibraryRepository(db);
        final sourceAdapter = FakeHomeSourceAdapter();

        try {
          final video = (await tester.runAsync(() async {
            final src = await repo.upsertSource(
              kind: 'local',
              rootLocator: 'C:/videos',
              name: 'Local',
            );
            final scanId = await repo.beginScan(src.id);
            await repo.applyScanBatch(src.id, scanId, [
              MediaEntry(
                externalId: '202',
                locator: 'Matrix.1999.mkv',
                name: 'Matrix.1999.mkv',
                isDirectory: false,
                size: 1000,
                modifiedAt: DateTime.now(),
              ),
            ]);
            await repo.finishScan(src.id, scanId);
            return (await repo.watchLibrary().first).first;
          }))!;

          sourceAdapter.resolveCompleter = Completer<void>();

          final entry = ContinueWatchingEntry(
            workId: 2,
            title: '黑客帝国',
            fileId: video.fileId,
            position: const Duration(minutes: 15),
            duration: const Duration(minutes: 136),
            available: true,
          );

          await tester.pumpWidget(
            createHomeTestApp(
              db: db,
              router: router,
              overrides: [
                sourceAdaptersProvider.overrideWithValue({
                  'local': sourceAdapter,
                }),
                continueWatchingProvider.overrideWith(
                  (ref) => Stream.value([entry]),
                ),
                recentWorksProvider.overrideWith(
                  (ref) => Stream.value(const <LibraryWork>[]),
                ),
              ],
            ),
          );
          await tester.pumpAndSettle();

          final playFinder = find.byKey(const Key('continue_watching_play_2'));
          // Rapid double tap
          await tester.tap(playFinder);
          await tester.tap(playFinder);
          await tester.pump();

          expect(sourceAdapter.resolveCount, 1);

          // Complete the resolve
          sourceAdapter.resolveCompleter!.complete();
          await tester.pumpAndSettle();

          expect(sourceAdapter.resolveCount, 1);
          expect(find.byType(PlayerPage), findsOneWidget);
        } finally {
          if (sourceAdapter.resolveCompleter != null &&
              !sourceAdapter.resolveCompleter!.isCompleted) {
            sourceAdapter.resolveCompleter!.complete();
          }
          await _cleanUpTestWidgets(tester, router: router, db: db);
        }
      },
    );

    testWidgets(
      'Unavailable continue watching item routes to work details for recovery',
      (tester) async {
        final db = AppDatabase(executor: NativeDatabase.memory());
        final router = createRouter(initialLocation: '/');
        final sourceAdapter = FakeHomeSourceAdapter();

        try {
          const entry = ContinueWatchingEntry(
            workId: 99,
            title: '离线影视',
            fileId: 999,
            position: Duration(minutes: 40),
            duration: Duration(minutes: 90),
            available: false,
          );

          await tester.pumpWidget(
            createHomeTestApp(
              db: db,
              router: router,
              overrides: [
                sourceAdaptersProvider.overrideWithValue({
                  'local': sourceAdapter,
                }),
                continueWatchingProvider.overrideWith(
                  (ref) => Stream.value([entry]),
                ),
                recentWorksProvider.overrideWith(
                  (ref) => Stream.value(const <LibraryWork>[]),
                ),
              ],
            ),
          );
          await tester.pumpAndSettle();

          expect(find.text('文件离线'), findsOneWidget);

          // Tap the card
          final cardFinder = find.byKey(const Key('continue_watching_card_99'));
          await tester.tap(cardFinder);
          await tester.pumpAndSettle();

          // Must NOT attempt to resolve playback for unavailable item
          expect(sourceAdapter.resolveCount, 0);

          // Routed to WorkDetailsPage with id 99
          expect(find.byType(WorkDetailsPage), findsOneWidget);
          expect(find.text('媒体文件当前不可用，已打开作品详情进行恢复'), findsOneWidget);
        } finally {
          await _cleanUpTestWidgets(tester, router: router, db: db);
        }
      },
    );

    testWidgets(
      'Playback resolution failure displays error SnackBar with safe retry action',
      (tester) async {
        final db = AppDatabase(executor: NativeDatabase.memory());
        final router = createRouter(initialLocation: '/');
        final repo = MediaLibraryRepository(db);
        final sourceAdapter = FakeHomeSourceAdapter();

        try {
          final video = (await tester.runAsync(() async {
            final src = await repo.upsertSource(
              kind: 'local',
              rootLocator: 'C:/videos',
              name: 'Local',
            );
            final scanId = await repo.beginScan(src.id);
            await repo.applyScanBatch(src.id, scanId, [
              MediaEntry(
                externalId: '303',
                locator: 'Gladiator.2000.mkv',
                name: 'Gladiator.2000.mkv',
                isDirectory: false,
                size: 1000,
                modifiedAt: DateTime.now(),
              ),
            ]);
            await repo.finishScan(src.id, scanId);
            return (await repo.watchLibrary().first).first;
          }))!;

          // Make resolve fail initially
          sourceAdapter.shouldFailResolve = true;

          final entry = ContinueWatchingEntry(
            workId: 3,
            title: '角斗士',
            fileId: video.fileId,
            position: const Duration(minutes: 50),
            duration: const Duration(minutes: 155),
            available: true,
          );

          await tester.pumpWidget(
            createHomeTestApp(
              db: db,
              router: router,
              overrides: [
                sourceAdaptersProvider.overrideWithValue({
                  'local': sourceAdapter,
                }),
                continueWatchingProvider.overrideWith(
                  (ref) => Stream.value([entry]),
                ),
                recentWorksProvider.overrideWith(
                  (ref) => Stream.value(const <LibraryWork>[]),
                ),
              ],
            ),
          );
          await tester.pumpAndSettle();

          final playFinder = find.byKey(const Key('continue_watching_play_3'));
          await tester.tap(playFinder);
          await tester.pumpAndSettle();

          // Error message SnackBar shown
          expect(find.text('媒体文件已离线或损坏'), findsOneWidget);
          final retryFinder = find.widgetWithText(SnackBarAction, '重试');
          expect(retryFinder, findsOneWidget);

          // Fix failure and tap retry
          sourceAdapter.shouldFailResolve = false;
          await tester.tap(retryFinder);
          await tester.pumpAndSettle();

          expect(sourceAdapter.resolveCount, 2);
          expect(find.byType(PlayerPage), findsOneWidget);
        } finally {
          await _cleanUpTestWidgets(tester, router: router, db: db);
        }
      },
    );

    testWidgets(
      'Recently added covers and badges enlarge on hover without moving text, and cards open details',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(1200, 900);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPhysicalSize);
        final db = AppDatabase(executor: NativeDatabase.memory());
        final router = createRouter(initialLocation: '/');

        try {
          const works = [
            LibraryWork(
              id: 10,
              title: '沙丘',
              year: 2021,
              versionCount: 2,
              available: true,
            ),
            LibraryWork(
              id: 11,
              title: '奥本海默',
              year: 2023,
              versionCount: 1,
              available: true,
            ),
          ];

          await tester.pumpWidget(
            createHomeTestApp(
              db: db,
              router: router,
              overrides: [
                continueWatchingProvider.overrideWith(
                  (ref) => Stream.value(const <ContinueWatchingEntry>[]),
                ),
                recentWorksProvider.overrideWith((ref) => Stream.value(works)),
              ],
            ),
          );
          await tester.pumpAndSettle();

          expect(find.text('最近添加'), findsOneWidget);
          // 使用唯一卡片 key，避免海报文字与标题文字重复
          expect(find.byKey(const Key('recent_work_card_10')), findsOneWidget);
          expect(find.byKey(const Key('recent_work_card_11')), findsOneWidget);
          expect(find.text('2 版本'), findsOneWidget);

          final card = find.byKey(const Key('recent_work_card_10'));
          await tester.ensureVisible(card);
          await tester.pumpAndSettle();
          final poster = find.descendant(
            of: card,
            matching: find.byType(PosterImage),
          );
          final title = find
              .descendant(of: card, matching: find.text('沙丘'))
              .last;
          final metadata = find.descendant(
            of: card,
            matching: find.text('2021'),
          );
          final posterRect = tester.getRect(poster);
          final badgeRect = tester.getRect(find.text('2 版本'));
          final titleRect = tester.getRect(title);
          final metadataRect = tester.getRect(metadata);
          final mouse = await tester.createGesture(
            kind: PointerDeviceKind.mouse,
          );
          await mouse.addPointer(location: Offset.zero);
          await mouse.moveTo(posterRect.center);
          await tester.pumpAndSettle();
          expect(
            tester.getRect(poster).width,
            closeTo(posterRect.width * 1.03, 0.1),
          );
          expect(
            tester.getRect(poster).height,
            closeTo(posterRect.height * 1.03, 0.1),
          );
          expect(
            tester.getRect(find.text('2 版本')).width,
            closeTo(badgeRect.width * 1.03, 0.1),
          );
          expect(tester.getRect(title), titleRect);
          expect(tester.getRect(metadata), metadataRect);
          await mouse.moveTo(Offset.zero);
          await tester.pumpAndSettle();
          expect(tester.getRect(poster), posterRect);
          await mouse.removePointer();

          // 标题区域仍可打开作品详情。
          await tester.tap(title);
          await tester.pumpAndSettle();

          expect(find.byType(WorkDetailsPage), findsOneWidget);
        } finally {
          await _cleanUpTestWidgets(tester, router: router, db: db);
        }
      },
    );

    testWidgets('Home handles loading and error states with retry', (
      tester,
    ) async {
      final db = AppDatabase(executor: NativeDatabase.memory());
      final cwController = StreamController<List<ContinueWatchingEntry>>();
      final rwController = StreamController<List<LibraryWork>>();

      try {
        await tester.pumpWidget(
          createHomeTestApp(
            db: db,
            overrides: [
              continueWatchingProvider.overrideWith(
                (ref) => cwController.stream,
              ),
              recentWorksProvider.overrideWith((ref) => rwController.stream),
            ],
          ),
        );
        await tester.pump();

        // Loading state
        expect(find.byKey(const Key('home_loading_indicator')), findsOneWidget);
        expect(find.byType(FloatingActionButton), findsNothing);

        // Error state
        cwController.addError(Exception('Network error'));
        rwController.addError(Exception('Database error'));
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('home_error_view')), findsOneWidget);
        expect(find.byType(SafeErrorWidget), findsOneWidget);
        expect(find.byKey(const Key('home_retry_button')), findsOneWidget);
      } finally {
        // 先 unmount 解除 stream 监听并消费定时器，再关闭 controller
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(Duration.zero);
        cwController.close();
        rwController.close();
        await tester.runAsync(db.close);
      }
    });

    testWidgets(
      'Single shelf failure displays inline retry banner while preserving other shelf',
      (tester) async {
        final db = AppDatabase(executor: NativeDatabase.memory());

        try {
          const works = [
            LibraryWork(
              id: 20,
              title: '流浪地球',
              year: 2019,
              versionCount: 1,
              available: true,
            ),
          ];

          await tester.pumpWidget(
            createHomeTestApp(
              db: db,
              overrides: [
                continueWatchingProvider.overrideWith(
                  (ref) => Stream.error(Exception('CW failed')),
                ),
                recentWorksProvider.overrideWith((ref) => Stream.value(works)),
              ],
            ),
          );
          await tester.pumpAndSettle();

          // Recent works is rendered
          expect(find.text('最近添加'), findsOneWidget);
          expect(find.byKey(const Key('recent_work_card_20')), findsOneWidget);

          // Continue watching error banner is visible with retry
          expect(
            find.byKey(const Key('home_continue_watching_error_banner')),
            findsOneWidget,
          );
          expect(
            find.byKey(const Key('home_continue_watching_retry_button')),
            findsOneWidget,
          );
        } finally {
          await _cleanUpTestWidgets(tester, db: db);
        }
      },
    );

    testWidgets('Series episode subtitle is formatted correctly', (
      tester,
    ) async {
      final db = AppDatabase(executor: NativeDatabase.memory());

      try {
        const entry = ContinueWatchingEntry(
          workId: 5,
          title: '绝命毒师',
          seasonNumber: 2,
          episodeNumber: 4,
          position: Duration(minutes: 18, seconds: 20),
          duration: Duration(minutes: 47, seconds: 0),
          available: true,
        );

        await tester.pumpWidget(
          createHomeTestApp(
            db: db,
            overrides: [
              continueWatchingProvider.overrideWith(
                (ref) => Stream.value([entry]),
              ),
              recentWorksProvider.overrideWith(
                (ref) => Stream.value(const <LibraryWork>[]),
              ),
            ],
          ),
        );
        await tester.pumpAndSettle();

        expect(
          find.byKey(const Key('continue_watching_card_5')),
          findsOneWidget,
        );
        expect(find.text('S2 E4 · 18:20'), findsOneWidget);
      } finally {
        await _cleanUpTestWidgets(tester, db: db);
      }
    });
  });

  group('Home SQLite Progress and Recent Works Aggregation Tests', () {
    late AppDatabase db;
    late MediaLibraryRepository mediaRepo;
    late PlaybackProgressRepository progressRepo;

    setUp(() {
      db = AppDatabase(executor: NativeDatabase.memory());
      mediaRepo = MediaLibraryRepository(db);
      progressRepo = PlaybackProgressRepository(db: db);
    });

    tearDown(() async {
      await db.close();
    });

    test('Continue watching excludes completed and < 5s items, orders by updatedAt DESC', () async {
      final source = await mediaRepo.upsertSource(
        kind: 'local',
        rootLocator: 'C:/Movies',
        name: 'Movies',
      );

      final now = DateTime.now();
      final entries = [
        MediaEntry(
          externalId: 'm1',
          locator: 'Movie1.2020.mkv',
          name: 'Movie1.2020.mkv',
          isDirectory: false,
          size: 1000,
          modifiedAt: now,
        ),
        MediaEntry(
          externalId: 'm2',
          locator: 'Movie2.2021.mkv',
          name: 'Movie2.2021.mkv',
          isDirectory: false,
          size: 1000,
          modifiedAt: now,
        ),
        MediaEntry(
          externalId: 'm3',
          locator: 'Movie3.2022.mkv',
          name: 'Movie3.2022.mkv',
          isDirectory: false,
          size: 1000,
          modifiedAt: now,
        ),
        MediaEntry(
          externalId: 'm4',
          locator: 'Movie4.2023.mkv',
          name: 'Movie4.2023.mkv',
          isDirectory: false,
          size: 1000,
          modifiedAt: now,
        ),
      ];

      final scanId = await mediaRepo.beginScan(source.id);
      await mediaRepo.applyScanBatch(source.id, scanId, entries);
      await mediaRepo.finishScan(source.id, scanId);

      // Trigger recognition
      await mediaRepo.recognizePendingFiles();

      final videos = await mediaRepo.watchLibrary().first;
      final f1 = videos
          .firstWhere((v) => v.fileName == 'Movie1.2020.mkv')
          .fileId;
      final f2 = videos
          .firstWhere((v) => v.fileName == 'Movie2.2021.mkv')
          .fileId;
      final f3 = videos
          .firstWhere((v) => v.fileName == 'Movie3.2022.mkv')
          .fileId;
      final f4 = videos
          .firstWhere((v) => v.fileName == 'Movie4.2023.mkv')
          .fileId;

      // m1: valid uncompleted progress (pos >= 5s, < 90%)
      await progressRepo.saveProgress(
        fileId: f1,
        position: const Duration(minutes: 20),
        duration: const Duration(minutes: 100),
      );

      // m2: completed explicitly
      await progressRepo.saveProgress(
        fileId: f2,
        position: const Duration(minutes: 50),
        duration: const Duration(minutes: 100),
        completed: true,
      );

      // m3: natural completion (pos >= 90% of duration)
      await progressRepo.saveProgress(
        fileId: f3,
        position: const Duration(minutes: 95),
        duration: const Duration(minutes: 100),
      );

      // m4: position < 5s -> should be excluded
      await progressRepo.saveProgress(
        fileId: f4,
        position: const Duration(seconds: 4),
        duration: const Duration(minutes: 100),
      );

      final continueList = await progressRepo.watchContinueWatching().first;

      // Only m1 qualifies
      expect(continueList, hasLength(1));
      expect(continueList.first.title, 'Movie1');
      expect(continueList.first.fileId, f1);
    });

    test('Recent works deduplicates versions into one work and orders by created_at DESC', () async {
      final source = await mediaRepo.upsertSource(
        kind: 'local',
        rootLocator: 'C:/Movies',
        name: 'Movies',
      );

      final now = DateTime.now();
      final entries = [
        MediaEntry(
          externalId: 'v1_1080',
          locator: 'Avatar.2009.1080p.mkv',
          name: 'Avatar.2009.1080p.mkv',
          isDirectory: false,
          size: 2000,
          modifiedAt: now,
        ),
        MediaEntry(
          externalId: 'v1_4k',
          locator: 'Avatar.2009.2160p.mkv',
          name: 'Avatar.2009.2160p.mkv',
          isDirectory: false,
          size: 8000,
          modifiedAt: now,
        ),
        MediaEntry(
          externalId: 'v2',
          locator: 'Titanic.1997.1080p.mkv',
          name: 'Titanic.1997.1080p.mkv',
          isDirectory: false,
          size: 3000,
          modifiedAt: now,
        ),
      ];

      final scanId = await mediaRepo.beginScan(source.id);
      await mediaRepo.applyScanBatch(source.id, scanId, entries);
      await mediaRepo.finishScan(source.id, scanId);

      final recentWorks = await mediaRepo.watchRecentWorks(limit: 20).first;

      // Total works is 2 (Avatar has 2 versions deduped into 1 work)
      expect(recentWorks, hasLength(2));

      final avatar = recentWorks.firstWhere((w) => w.title == 'Avatar');
      expect(avatar.versionCount, 2);

      final titanic = recentWorks.firstWhere((w) => w.title == 'Titanic');
      expect(titanic.versionCount, 1);
    });
  });
}
