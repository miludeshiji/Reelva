import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:reelva/app/theme/reelva_theme.dart';
import 'package:reelva/features/player/domain/playback_resource.dart';
import 'package:reelva/features/progress/application/progress_providers.dart';
import 'package:reelva/features/progress/presentation/watch_history_page.dart';
import 'package:reelva/features/sources/application/source_providers.dart';
import 'package:reelva/features/sources/domain/source_models.dart';

final _history = [
  WatchHistoryEntry(
    id: 1,
    entry: const ContinueWatchingEntry(
      workId: 7,
      fileId: 71,
      title: '观看历史中有很长中文名称的电视剧作品',
      position: Duration(minutes: 12),
      duration: Duration(minutes: 48),
      seasonNumber: 2,
      episodeNumber: 3,
    ),
    completed: false,
    updatedAt: DateTime(2026, 10, 26, 12, 30),
  ),
  WatchHistoryEntry(
    id: 2,
    entry: const ContinueWatchingEntry(
      workId: 7,
      fileId: 70,
      title: '已看完的上一集',
      position: Duration(minutes: 48),
      duration: Duration(minutes: 48),
      seasonNumber: 2,
      episodeNumber: 2,
      available: false,
    ),
    completed: true,
    updatedAt: DateTime(2026, 10, 25, 21),
  ),
];

class _HistorySourceController extends SourceController {
  final resolvedFiles = <int>[];
  Completer<void>? pending;
  bool fail = false;

  @override
  Future<PlaybackResource> resolvePlayback(int fileId) async {
    resolvedFiles.add(fileId);
    if (pending != null) await pending!.future;
    if (fail) throw const MediaSourceException('播放地址解析失败');
    return PlaybackResource(
      uri: Uri.file('C:/media/$fileId.mkv'),
      displayName: '$fileId.mkv',
      libraryFileId: fileId,
    );
  }
}

GoRouter _createRouter() => GoRouter(
  initialLocation: '/history',
  routes: [
    GoRoute(
      path: '/history',
      builder: (context, state) => const WatchHistoryPage(),
    ),
    GoRoute(
      path: '/player',
      builder: (context, state) => Scaffold(
        appBar: AppBar(),
        body: Text('播放文件 ${(state.extra! as PlaybackResource).libraryFileId}'),
      ),
    ),
    GoRoute(
      path: '/library/work/:id',
      builder: (context, state) => Scaffold(
        appBar: AppBar(),
        body: Text('作品详情 ${state.pathParameters['id']}'),
      ),
    ),
  ],
);

void main() {
  for (final (size, scale) in [
    (const Size(1200, 800), 1.0),
    (const Size(320, 568), 1.5),
  ]) {
    testWidgets('观看历史展示季集、完播、离线和时间，适配 $size / $scale', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            watchHistoryProvider.overrideWith((ref) => Stream.value(_history)),
          ],
          child: MaterialApp(
            theme: ReelvaTheme.light,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(scale)),
              child: child!,
            ),
            home: const WatchHistoryPage(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('观看历史'), findsOneWidget);
      expect(find.text('第 2 季 · 第 3 集'), findsOneWidget);
      expect(find.text('未看完'), findsOneWidget);
      expect(find.text('12:00 / 48:00'), findsOneWidget);
      expect(find.text('最近观看 2026/10/26 12:30'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.byKey(const Key('watch_history_entry_2')),
        200,
        scrollable: find.byType(Scrollable),
      );
      expect(find.text('已看完'), findsOneWidget);
      expect(find.text('文件离线'), findsOneWidget);
      expect(find.text('第 2 季 · 第 2 集'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('观看历史播放防重复点击，返回后保留列表，离线记录进入详情', (tester) async {
    final router = _createRouter();
    final controller = _HistorySourceController()..pending = Completer<void>();
    var loads = 0;
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      router.dispose();
    });
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          watchHistoryProvider.overrideWith((ref) {
            loads++;
            return Stream.value(_history);
          }),
          sourceControllerProvider.overrideWith(() => controller),
        ],
        child: MaterialApp.router(
          theme: ReelvaTheme.light,
          routerConfig: router,
        ),
      ),
    );
    await tester.pumpAndSettle();
    final pageState = tester.state(find.byType(WatchHistoryPage));
    final firstCard = find.byKey(const Key('watch_history_entry_1'));
    await tester.tap(firstCard);
    await tester.tap(firstCard);
    await tester.pump();
    expect(controller.resolvedFiles, [71]);
    controller.pending!.complete();
    await tester.pumpAndSettle();
    expect(find.text('播放文件 71'), findsOneWidget);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(router.routeInformationProvider.value.uri.path, '/history');
    expect(tester.state(find.byType(WatchHistoryPage)), same(pageState));
    expect(loads, 1);

    await tester.tap(find.byKey(const Key('watch_history_play_2')));
    await tester.pumpAndSettle();
    expect(find.text('作品详情 7'), findsOneWidget);
    expect(controller.resolvedFiles, [71]);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(router.routeInformationProvider.value.uri.path, '/history');
    expect(loads, 1);
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();

    controller.fail = true;
    await tester.tap(find.byKey(const Key('watch_history_play_1')));
    await tester.pumpAndSettle();
    expect(find.text('播放地址解析失败'), findsOneWidget);
    controller.fail = false;
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    expect(find.text('播放文件 71'), findsOneWidget);
    expect(controller.resolvedFiles, [71, 71, 71]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('观看历史加载、失败重试和空记录状态', (tester) async {
    final pending = StreamController<List<WatchHistoryEntry>>();
    var loads = 0;
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await pending.close();
    });
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          watchHistoryProvider.overrideWith(
            (ref) => loads++ == 0 ? pending.stream : Stream.value(const []),
          ),
        ],
        child: MaterialApp(
          theme: ReelvaTheme.light,
          home: const WatchHistoryPage(),
        ),
      ),
    );
    await tester.pump();
    expect(find.byKey(const Key('watch_history_loading')), findsOneWidget);
    pending.addError(StateError('不应显示的内部异常'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('watch_history_error')), findsOneWidget);
    expect(find.text('不应显示的内部异常'), findsNothing);
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('watch_history_empty')), findsOneWidget);
    expect(loads, 2);
    expect(tester.takeException(), isNull);
  });
}
