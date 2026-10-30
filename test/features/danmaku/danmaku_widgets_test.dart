import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reelva/features/danmaku/application/danmaku_controller.dart';
import 'package:reelva/features/danmaku/application/danmaku_providers.dart';
import 'package:reelva/features/danmaku/domain/danmaku.dart';
import 'package:reelva/features/danmaku/presentation/danmaku_layer.dart';
import 'package:reelva/features/danmaku/presentation/danmaku_panel.dart';
import 'package:reelva/features/player/domain/playback_resource.dart';
import 'package:reelva/features/player/domain/playback_snapshot.dart';
import 'package:reelva/features/player/presentation/player_controls.dart';

import '../player/fake_player_engine.dart';

import 'danmaku_fakes.dart';

void main() {
  for (final width in [720.0, 800.0]) {
    testWidgets('弹幕入口在宽度 $width 的播放控件中可用', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = Size(width, 480);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final engine = FakePlayerEngine();
      addTearDown(engine.dispose);
      var opened = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.bottomCenter,
              child: PlayerControls(
                snapshot: const PlaybackSnapshot(
                  status: PlaybackStatus.playing,
                ),
                engine: engine,
                isFullscreen: false,
                onToggleFullscreen: () {},
                onShowDanmaku: () => opened++,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      if (find.byKey(const Key('player_more_button')).evaluate().isNotEmpty) {
        await tester.tap(find.byKey(const Key('player_more_button')));
        await tester.pumpAndSettle();
      }
      await tester.tap(find.byKey(const Key('player_danmaku_button')));
      expect(opened, 1);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('弹幕跟随暂停、缓冲、定位和三倍速，退出清理动画', (tester) async {
    final store = MemoryDanmakuStore();
    final api = FakeDanmakuApi(store);
    api.onComments = (_) async => [
      for (var i = 0; i < 40; i++) DanmakuComment(timeMs: i * 100, text: '$i'),
    ];
    final controller = DanmakuController(
      api: api,
      store: store,
      queryLoader: (_) async => testDanmakuQuery,
    );
    addTearDown(() {
      controller.dispose();
      api.dispose();
    });
    final snapshot = ValueNotifier(
      const PlaybackSnapshot(status: PlaybackStatus.playing),
    );
    addTearDown(snapshot.dispose);
    final resource = PlaybackResource(
      uri: Uri.parse('https://example.test/video'),
      displayName: 'Example',
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [danmakuControllerProvider.overrideWithValue(controller)],
        child: MaterialApp(
          home: ValueListenableBuilder(
            valueListenable: snapshot,
            builder: (context, value, _) =>
                DanmakuLayer(resource: resource, snapshot: value),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    snapshot.value = snapshot.value.copyWith(status: PlaybackStatus.buffering);
    await tester.pumpAndSettle();
    expect(tester.binding.transientCallbackCount, 0);
    snapshot.value = snapshot.value.copyWith(
      status: PlaybackStatus.paused,
      position: const Duration(seconds: 2),
    );
    await tester.pumpAndSettle();
    expect(tester.binding.transientCallbackCount, 0);
    snapshot.value = snapshot.value.copyWith(
      status: PlaybackStatus.playing,
      rate: 3,
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(tester.binding.transientCallbackCount, greaterThan(0));
    expect(tester.takeException(), isNull);
    snapshot.value = snapshot.value.copyWith(status: PlaybackStatus.idle);
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<Visibility>(
            find.descendant(
              of: find.byType(DanmakuLayer),
              matching: find.byType(Visibility),
            ),
          )
          .visible,
      isFalse,
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets('窄屏大字号弹幕面板可开关和搜索，显示设置不溢出', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 568);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = MemoryDanmakuStore()..settings = const DanmakuSettings();
    final api = FakeDanmakuApi(store);
    final controller = DanmakuController(
      api: api,
      store: store,
      queryLoader: (_) async => testDanmakuQuery,
    );
    addTearDown(() {
      controller.dispose();
      api.dispose();
    });
    await controller.open(null);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(1.5)),
          child: child!,
        ),
        home: Scaffold(
          body: DanmakuPanel(controller: controller, initialKeyword: 'Example'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('显示弹幕'));
    await tester.pumpAndSettle();
    expect(controller.settings.enabled, isTrue);
    await tester.tap(find.text('显示与时间设置'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.scrollUntilVisible(
      find.byKey(const Key('danmaku_search')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.enterText(find.byKey(const Key('danmaku_search')), 'Example');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    expect(api.searchCount, 1);
    expect(tester.takeException(), isNull);
  });
}
