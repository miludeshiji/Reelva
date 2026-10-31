import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:reelva/features/danmaku/application/danmaku_controller.dart';
import 'package:reelva/features/danmaku/domain/danmaku.dart';
import 'package:reelva/features/danmaku/infrastructure/danmaku_api.dart';
import 'package:reelva/features/player/domain/playback_resource.dart';

import 'danmaku_fakes.dart';

void main() {
  late MemoryDanmakuStore store;
  late FakeDanmakuApi api;
  late DanmakuController controller;
  late Future<LocalDanmakuFile?> Function(PlaybackResource) loadLocal;
  late Future<LocalDanmakuFile?> Function() pickLocal;
  var queryCount = 0;
  const local = LocalDanmakuFile(
    fileName: '录播.xml',
    comments: [DanmakuComment(timeMs: 72063, text: '本地弹幕', bilibili: true)],
  );
  final resource = PlaybackResource(
    uri: Uri.parse('https://example.test/video'),
    displayName: 'Example.S01E01.mkv',
  );
  setUp(() {
    store = MemoryDanmakuStore();
    api = FakeDanmakuApi(store);
    queryCount = 0;
    loadLocal = (_) async => null;
    pickLocal = () async => local;
    controller = DanmakuController(
      api: api,
      store: store,
      queryLoader: (_) async {
        queryCount++;
        return testDanmakuQuery;
      },
      localLoader: (resource) => loadLocal(resource),
      localPicker: () => pickLocal(),
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
    var localLoads = 0;
    loadLocal = (_) async {
      localLoads++;
      return null;
    };
    await controller.open(resource);
    expect(api.searchCount, 0);
    expect(controller.query, isNull);
    expect(localLoads, 0);
    await controller.updateSettings(
      controller.settings.copyWith(enabled: true),
    );
    expect(controller.selected, testDanmakuEpisode);
    expect(localLoads, 1);
  });
  test('同目录弹幕优先于已保存在线关联，不依赖影视识别并复用文件偏移', () async {
    loadLocal = (_) async => local;
    store.bindings[testDanmakuQuery.contentKey] = testBilibiliEpisode;
    store.offsets[DanmakuQuery.fromResource(resource).versionKey] = -2.5;
    await controller.open(resource);
    expect(queryCount, 0);
    expect(api.searchCount, 0);
    expect(api.loaded, isEmpty);
    expect(controller.localFileName, '录播.xml');
    expect(controller.selected, isNull);
    expect(controller.comments.single.timeMs, 72063);
    expect(controller.offsetSeconds, -2.5);
  });
  test('损坏的同目录弹幕明确报错，不自动改挂无关在线弹幕', () async {
    loadLocal = (_) async => throw const DanmakuException('弹幕 XML 格式无效');
    await controller.open(resource);
    expect(controller.message, '弹幕 XML 格式无效');
    expect(controller.loading, isFalse);
    expect(api.searchCount, 0);
    expect(controller.comments, isEmpty);
  });
  test('手动选择本地弹幕胜过迟到的自动请求，取消选择保留当前弹幕', () async {
    final automatic = Completer<LocalDanmakuFile?>();
    final entered = Completer<void>();
    loadLocal = (_) {
      entered.complete();
      return automatic.future;
    };
    final opening = controller.open(resource);
    await entered.future;
    await controller.pickLocal();
    automatic.complete(
      const LocalDanmakuFile(fileName: 'old.xml', comments: []),
    );
    await opening;
    expect(controller.localFileName, '录播.xml');
    expect(controller.comments.single.text, '本地弹幕');
    expect(api.searchCount, 0);
    pickLocal = () async => null;
    await controller.pickLocal();
    expect(controller.localFileName, '录播.xml');
    expect(controller.message, '已加载 1 条本地弹幕');
  });
  test('关闭时手动选文件会开启弹幕，同一视频再次开关保留所选文件', () async {
    store.settings = const DanmakuSettings();
    final versionKey = DanmakuQuery.fromResource(resource).versionKey;
    store.offsets[versionKey] = 1.5;
    await controller.open(resource);
    await controller.pickLocal();
    expect(controller.settings.enabled, isTrue);
    expect(store.settings.enabled, isTrue);
    expect(controller.offsetSeconds, 1.5);
    await controller.updateOffset(2);
    expect(store.offsets[versionKey], 2);
    await controller.updateSettings(
      controller.settings.copyWith(enabled: false),
    );
    await controller.updateSettings(
      controller.settings.copyWith(enabled: true),
    );
    expect(controller.localFileName, '录播.xml');
    expect(controller.comments.single.text, '本地弹幕');
    expect(api.searchCount, 0);
  });
  test('视频切换后迟到的本地读取或选择不影响新视频', () async {
    for (final manual in [false, true]) {
      final pending = Completer<LocalDanmakuFile?>();
      final entered = Completer<void>();
      loadLocal = (_) {
        if (!entered.isCompleted) entered.complete();
        return pending.future;
      };
      pickLocal = () {
        entered.complete();
        return pending.future;
      };
      Future<void> operation;
      if (manual) {
        loadLocal = (_) async => null;
        await controller.open(resource);
        operation = controller.pickLocal();
      } else {
        operation = controller.open(resource);
      }
      await entered.future;
      await controller.open(null);
      pending.complete(local);
      await operation;
      expect(controller.comments, isEmpty);
      expect(controller.localFileName, isNull);
      expect(controller.pickingLocal, isFalse);
    }
  });
  test('本地加载后可手动切换在线来源，按影视身份保存关联', () async {
    loadLocal = (_) async => local;
    await controller.open(resource);
    await controller.select(testBilibiliEpisode);
    expect(controller.localFileName, isNull);
    expect(controller.selected, testBilibiliEpisode);
    expect(store.bindings[testDanmakuQuery.contentKey], testBilibiliEpisode);
    expect(queryCount, 1);
  });
}
