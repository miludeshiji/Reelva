import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reelva/features/player/domain/playback_resource.dart';
import 'package:reelva/features/player/presentation/source_subtitle_dialog.dart';
import 'package:reelva/features/sources/application/source_providers.dart';
import 'package:reelva/features/sources/domain/source_models.dart';

import '../sources/source_subtitles_test.dart'
    show SubtitleSourceAdapter, subtitleEntry;

void main() {
  for (final size in [
    const Size(1440, 900),
    const Size(390, 844),
    const Size(568, 320),
  ]) {
    testWidgets('浏览源目录选择字幕并保留真实文件名 $size', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final adapter = SubtitleSourceAdapter();
      adapter.entries['root'] = [
        subtitleEntry('opaque-dir', name: '字幕目录', directory: true),
      ];
      adapter.entries['opaque-dir'] = [
        subtitleEntry('opaque-sub', name: '影片.zh.ass'),
        subtitleEntry('opaque-video', name: '影片.mkv'),
        subtitleEntry('opaque-idx', name: '影片.idx'),
      ];
      PlaybackResource? selected;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            mediaSourcesProvider.overrideWith(
              (ref) => Stream.value(const [
                MediaSourceConfig(
                  id: 3,
                  kind: 'webdav',
                  name: '远程影视',
                  rootLocator: 'root',
                ),
                MediaSourceConfig(
                  id: 4,
                  kind: 'webdav',
                  name: '已停用',
                  rootLocator: 'disabled',
                  enabled: false,
                ),
              ]),
            ),
            sourceAdaptersProvider.overrideWithValue({'webdav': adapter}),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () async {
                    selected = await showDialog<PlaybackResource>(
                      context: context,
                      builder: (_) =>
                          const SourceSubtitleDialog(currentSourceId: 3),
                    );
                  },
                  child: const Text('打开字幕选择'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('打开字幕选择'));
      await tester.pumpAndSettle();
      expect(find.text('已停用'), findsNothing);
      expect(find.text('当前播放源'), findsOneWidget);
      await tester.tap(find.text('远程影视'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('字幕目录'));
      await tester.tap(find.text('字幕目录'));
      await tester.pumpAndSettle();
      expect(find.text('影片.mkv'), findsNothing);
      expect(find.text('影片.idx'), findsNothing);
      await tester.ensureVisible(find.text('影片.zh.ass'));
      await tester.tap(find.text('影片.zh.ass'));
      await tester.pumpAndSettle();
      expect(selected!.displayName, '影片.zh.ass');
      expect(selected!.sourceId, 3);
      expect(adapter.resolvedIds, ['opaque-sub']);
      expect(adapter.prepareCount, 0);
      expect(tester.takeException(), isNull);
    });
  }
}
