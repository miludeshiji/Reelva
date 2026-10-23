import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reelva/app/router.dart';
import 'package:reelva/core/database/app_database.dart';
import 'package:reelva/features/library/infrastructure/media_library_repository.dart';
import 'package:reelva/features/library/library_page.dart';
import 'package:reelva/features/player/application/player_providers.dart';
import 'package:reelva/features/player/domain/playback_resource.dart';
import 'package:reelva/features/player/presentation/player_page.dart';
import 'package:reelva/features/sources/application/source_providers.dart';
import 'package:reelva/features/sources/domain/media_source_adapter.dart';
import 'package:reelva/features/sources/domain/source_models.dart';
import 'package:reelva/features/sources/sources_page.dart';

import '../player/fake_player_engine.dart';

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
  group('Sources and Library UI Slice Tests', () {
    late AppDatabase memoryDb;
    late MediaLibraryRepository repository;
    late FakePlayerEngine fakePlayerEngine;

    setUp(() {
      memoryDb = AppDatabase(executor: NativeDatabase.memory());
      repository = MediaLibraryRepository(memoryDb);
      fakePlayerEngine = FakePlayerEngine();
    });

    tearDown(() async {
      await memoryDb.close();
    });

    testWidgets(
      'Prove end-to-end import -> library -> actual resolved resource handed to fake playback engine',
      (tester) async {
        final expectedResource = PlaybackResource(
          uri: Uri.file('C:/videos/avatar.mkv'),
          displayName: 'avatar.mkv',
        );

        final fakeAdapter = FakeControllableMediaSourceAdapter(
          directoryToPick: const DirectorySelection(
            kind: 'local',
            rootLocator: 'C:/videos',
            name: '本地电影',
          ),
          entriesToStream: [
            MediaEntry(
              externalId: 'avatar.mkv',
              locator: 'avatar.mkv',
              name: 'avatar.mkv',
              isDirectory: false,
              size: 2048000,
              modifiedAt: DateTime(2026, 1, 1),
            ),
          ],
          playbackResourceToResolve: expectedResource,
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

          // 1. 在 SourcesPage 触发添加媒体源弹窗
          expect(find.byType(SourcesPage), findsOneWidget);
          final addFabFinder = find.byKey(const Key('sources_add_fab'));
          expect(addFabFinder, findsOneWidget);
          await tester.tap(addFabFinder);
          await tester.pumpAndSettle();

          // 2. 确认添加并触发 SourceController.addDirectory 真实流程
          final confirmButton = find.byKey(
            const Key('add_source_confirm_button'),
          );
          expect(confirmButton, findsOneWidget);
          await tester.tap(confirmButton);
          await tester.pumpAndSettle();

          // 媒体源列表中呈现了新导入的媒体源
          expect(find.text('本地电影'), findsOneWidget);

          // 3. 切换至 LibraryPage
          testRouter.go('/library');
          await tester.pumpAndSettle();

          // 影视库呈现了通过适配器扫描导入的条目
          expect(find.byType(LibraryPage), findsOneWidget);
          expect(find.text('avatar'), findsOneWidget);
          expect(find.text('本地电影'), findsOneWidget);

          // 4. 点击视频条目触发解析并跳转播放器
          final videoItemFinder = find.byKey(const Key('library_video_item_1'));
          expect(videoItemFinder, findsOneWidget);
          await tester.tap(videoItemFinder);
          await tester.pumpAndSettle();

          // 5. 验证导航已无缝跳转至 PlayerPage 且底层播放器引擎真实收到资源调度
          expect(find.byType(PlayerPage), findsOneWidget);
          expect(fakePlayerEngine.openCount, 1);
          expect(fakePlayerEngine.lastOpenedResource, expectedResource);
          expect(fakeAdapter.resolveCount, 1);
          expect(fakeAdapter.lastResolvedEntryId, 'avatar.mkv');
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump(Duration.zero);
        }
      },
    );

    testWidgets(
      'Resolution failure retains visible library and presents safe feedback',
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

        final testRouter = createRouter(initialLocation: '/library');
        addTearDown(testRouter.dispose);

        try {
          await tester.pumpWidget(
            ProviderScope(
              overrides: [
                appDatabaseProvider.overrideWithValue(memoryDb),
                mediaLibraryRepositoryProvider.overrideWithValue(repository),
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

          expect(find.byType(LibraryPage), findsOneWidget);
          await tester.tap(find.byKey(const Key('library_video_item_1')));
          await tester.pumpAndSettle();

          // 解析失败保留当前库视图，未跳转播放器，无崩溃
          expect(find.byType(LibraryPage), findsOneWidget);
          expect(find.byType(PlayerPage), findsNothing);
          expect(fakePlayerEngine.openCount, 0);

          // 呈现安全提示
          expect(find.text('目标文件已被移动或离线'), findsOneWidget);
          expect(find.text('重试'), findsOneWidget);
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
        addTearDown(activeScanStreamController.close);

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
          testRouter.go('/library');
          await tester.pumpAndSettle();

          expect(find.byType(LibraryPage), findsOneWidget);
          expect(find.text('saved_video'), findsOneWidget);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump(Duration.zero);
        }
      },
    );

    testWidgets(
      'LibraryPage supports pagination limit initially 100 and load more (+100)',
      (tester) async {
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

        final testRouter = createRouter(initialLocation: '/library');
        addTearDown(testRouter.dispose);

        try {
          await tester.pumpWidget(
            ProviderScope(
              overrides: [
                appDatabaseProvider.overrideWithValue(memoryDb),
                mediaLibraryRepositoryProvider.overrideWithValue(repository),
                platformOverrideProvider.overrideWithValue(
                  TargetPlatform.windows,
                ),
                routerProvider.overrideWithValue(testRouter),
              ],
              child: MaterialApp.router(routerConfig: testRouter),
            ),
          );
          await tester.pumpAndSettle();

          final loadMoreFinder = find.byKey(
            const Key('library_load_more_button'),
          );
          expect(loadMoreFinder, findsOneWidget);

          await tester.tap(loadMoreFinder);
          await tester.pumpAndSettle();

          expect(loadMoreFinder, findsNothing);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump(Duration.zero);
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
