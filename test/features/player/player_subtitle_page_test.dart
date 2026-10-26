import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reelva/features/player/application/player_providers.dart';
import 'package:reelva/features/player/domain/playback_resource.dart';
import 'package:reelva/features/player/infrastructure/media_file_picker.dart';
import 'package:reelva/features/player/presentation/player_page.dart';
import 'package:reelva/features/sources/application/source_providers.dart';
import 'package:reelva/features/sources/domain/source_models.dart';

import '../sources/source_subtitles_test.dart'
    show SubtitleSourceAdapter, subtitleEntry;
import 'fake_player_engine.dart';

class _SubtitlePicker extends MediaFilePicker {
  _SubtitlePicker(this.result);
  final Future<PlaybackResource?> result;
  @override
  Future<PlaybackResource?> pickSubtitle() => result;
}

Future<void> _openSubtitles(WidgetTester tester) async {
  final more = find.byKey(const Key('player_more_button'));
  if (more.evaluate().isNotEmpty) {
    await tester.tap(more);
    await tester.pumpAndSettle();
  }
  await tester.tap(find.byKey(const Key('player_subtitle_track_button')));
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('window_manager'),
          (_) async => true,
        );
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('window_manager'), null);
  });
  final video = PlaybackResource(
    uri: Uri.file('C:/movie.mkv'),
    displayName: 'movie.mkv',
    sourceId: 3,
  );

  for (final fromSource in [false, true]) {
    testWidgets('播放页${fromSource ? '手机源字幕' : '桌面本地字幕'}入口加载到当前播放会话', (
      tester,
    ) async {
      tester.view.physicalSize = fromSource
          ? const Size(390, 844)
          : const Size(1440, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final engine = FakePlayerEngine();
      final adapter = SubtitleSourceAdapter();
      adapter.entries['root'] = [subtitleEntry('movie.zh.ass')];
      final subtitle = PlaybackResource(
        uri: Uri.file('C:/movie.zh.ass'),
        displayName: 'movie.zh.ass',
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            playerSessionProvider.overrideWithValue(
              createFakeSession(engine: engine),
            ),
            mediaFilePickerProvider.overrideWithValue(
              _SubtitlePicker(Future.value(subtitle)),
            ),
            mediaSourcesProvider.overrideWith(
              (ref) => Stream.value(const [
                MediaSourceConfig(
                  id: 3,
                  kind: 'webdav',
                  name: '影视源',
                  rootLocator: 'root',
                ),
              ]),
            ),
            sourceAdaptersProvider.overrideWithValue({'webdav': adapter}),
          ],
          child: MaterialApp(home: PlayerPage(initialResource: video)),
        ),
      );
      await tester.pumpAndSettle();
      await _openSubtitles(tester);
      await tester.tap(find.text(fromSource ? '选择媒体源字幕' : '选择本地字幕'));
      await tester.pumpAndSettle();
      if (fromSource) {
        await tester.tap(find.text('影视源'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('movie.zh.ass'));
        await tester.pumpAndSettle();
      }
      expect(engine.lastSubtitleResource!.displayName, 'movie.zh.ass');
      expect(engine.lastOpenedResource, video);
      expect(engine.openCount, 1);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });
  }

  testWidgets('文件选择返回前切换视频，不把字幕加载到下一部视频', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final engine = FakePlayerEngine();
    final session = createFakeSession(engine: engine);
    final selected = Completer<PlaybackResource?>();
    final picker = _SubtitlePicker(selected.future);
    Widget page(PlaybackResource resource) => ProviderScope(
      overrides: [
        playerSessionProvider.overrideWithValue(session),
        mediaFilePickerProvider.overrideWithValue(picker),
      ],
      child: MaterialApp(home: PlayerPage(initialResource: resource)),
    );
    await tester.pumpWidget(page(video));
    await tester.pumpAndSettle();
    await _openSubtitles(tester);
    await tester.tap(find.text('选择本地字幕'));
    await tester.pumpAndSettle();
    final next = PlaybackResource(
      uri: Uri.file('C:/next.mkv'),
      displayName: 'next.mkv',
    );
    await tester.pumpWidget(page(next));
    await tester.pumpAndSettle();
    selected.complete(
      PlaybackResource(uri: Uri.file('C:/movie.ass'), displayName: 'movie.ass'),
    );
    await tester.pumpAndSettle();
    expect(engine.lastOpenedResource, next);
    expect(engine.lastSubtitleResource, isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });
}
