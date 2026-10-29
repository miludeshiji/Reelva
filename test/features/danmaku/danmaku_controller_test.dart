import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:reelva/features/danmaku/application/danmaku_controller.dart';
import 'package:reelva/features/danmaku/domain/danmaku.dart';
import 'package:reelva/features/player/domain/playback_resource.dart';

import 'danmaku_fakes.dart';

void main() {
  late MemoryDanmakuStore store;
  late FakeDanmakuApi api;
  late DanmakuController controller;
  final resource = PlaybackResource(
    uri: Uri.parse('https://example.test/video'),
    displayName: 'Example.S01E01.mkv',
  );
  setUp(() {
    store = MemoryDanmakuStore();
    api = FakeDanmakuApi(store);
    controller = DanmakuController(
      api: api,
      store: store,
      queryLoader: (_) async => testDanmakuQuery,
    );
  });
  tearDown(() {
    controller.dispose();
    api.dispose();
  });
  test('已保存的单集关联与文件偏移直接复用', () async {
    store.bindings[testDanmakuQuery.contentKey] = testBilibiliEpisode;
    store.offsets[testDanmakuQuery.versionKey] = -1.5;
    await controller.open(resource);
    expect(api.searchCount, 0);
    expect(controller.selected, testBilibiliEpisode);
    expect(controller.offsetSeconds, -1.5);
  });
  test('弹弹play无弹幕时自动尝试B站', () async {
    api.onComments = (episode) async =>
        episode.source == DanmakuSource.dandanplay
        ? []
        : [const DanmakuComment(timeMs: 0, text: 'bili')];
    await controller.open(resource);
    expect(controller.selected, testBilibiliEpisode);
    expect(controller.comments.single.text, 'bili');
  });
  test('换集使迟到的旧请求失效', () async {
    final old = Completer<List<DanmakuComment>>();
    api.onComments = (_) => old.future;
    final opening = controller.open(resource);
    while (api.loaded.isEmpty) {
      await Future<void>.delayed(Duration.zero);
    }
    await controller.open(null);
    old.complete([const DanmakuComment(timeMs: 0, text: 'old')]);
    await opening;
    expect(controller.comments, isEmpty);
    expect(controller.selected, isNull);
  });
  test('手动选择胜过尚未结束的自动加载并保存绑定', () async {
    final automatic = Completer<List<DanmakuComment>>();
    api.onComments = (episode) => episode.source == DanmakuSource.dandanplay
        ? automatic.future
        : Future.value([const DanmakuComment(timeMs: 0, text: 'manual')]);
    final opening = controller.open(resource);
    while (api.loaded.isEmpty) {
      await Future<void>.delayed(Duration.zero);
    }
    await controller.select(testBilibiliEpisode);
    automatic.complete([const DanmakuComment(timeMs: 0, text: 'old')]);
    await opening;
    expect(controller.selected, testBilibiliEpisode);
    expect(controller.comments.single.text, 'manual');
    expect(store.bindings[testDanmakuQuery.contentKey], testBilibiliEpisode);
  });
  test('关闭弹幕取消在途请求，保存失败回退设置和偏移', () async {
    await controller.open(resource);
    store.failWrites = true;
    await controller.updateSettings(
      controller.settings.copyWith(enabled: false),
    );
    expect(controller.settings.enabled, isTrue);
    await controller.updateOffset(2);
    expect(controller.offsetSeconds, 0);
    expect(store.offsets, isEmpty);
  });
  test('默认关闭时不访问媒体库或网络，手动开启后自动搜索', () async {
    store.settings = const DanmakuSettings();
    await controller.open(resource);
    expect(api.searchCount, 0);
    expect(controller.query, isNull);
    await controller.updateSettings(
      controller.settings.copyWith(enabled: true),
    );
    expect(controller.selected, testDanmakuEpisode);
  });
}
