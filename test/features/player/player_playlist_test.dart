import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reelva/features/player/application/player_providers.dart';
import 'package:reelva/features/player/domain/playback_playlist_entry.dart';
import 'package:reelva/features/player/domain/playback_resource.dart';
import 'package:reelva/features/player/domain/playback_snapshot.dart';
import 'package:reelva/features/player/presentation/player_controls.dart';
import 'package:reelva/features/player/presentation/player_page.dart';
import 'package:reelva/features/sources/application/source_providers.dart';

import 'fake_player_engine.dart';

class _PlaylistSources extends SourceController {
  bool fail = false;

  @override
  Future<PlaybackResource> resolvePlayback(int fileId) async {
    if (fail) throw StateError('offline');
    final entry = _entries.firstWhere((entry) => entry.fileId == fileId);
    return PlaybackResource(
      uri: Uri.parse('file:///episode-$fileId.mkv'),
      displayName: entry.displayTitle,
      libraryFileId: fileId,
    );
  }
}

const _entries = [
  PlaybackPlaylistEntry(
    fileId: 11,
    title: '初次相遇',
    available: true,
    seasonNumber: 1,
    episodeNumber: 1,
  ),
  PlaybackPlaylistEntry(
    fileId: 12,
    title: '雨后的约定',
    available: true,
    seasonNumber: 1,
    episodeNumber: 2,
  ),
  PlaybackPlaylistEntry(
    fileId: 13,
    title: '新的旅程',
    available: true,
    seasonNumber: 2,
    episodeNumber: 1,
  ),
  PlaybackPlaylistEntry(
    fileId: 14,
    title: '离线剧集',
    available: false,
    seasonNumber: 2,
    episodeNumber: 2,
  ),
];

void main() {
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (_) async => null);
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  testWidgets('上下集和播放列表复用会话，保留集名、当前集和不可用状态', (tester) async {
    final engine = FakePlayerEngine();
    final source = _PlaylistSources();
    final resource = PlaybackResource(
      uri: Uri.parse('file:///episode-11.mkv'),
      displayName: _entries.first.displayTitle,
      libraryFileId: 11,
      playlist: _entries,
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          playerSessionProvider.overrideWithValue(
            createFakeSession(engine: engine),
          ),
          sourceControllerProvider.overrideWith(() => source),
        ],
        child: MaterialApp(home: PlayerPage(initialResource: resource)),
      ),
    );
    await tester.pumpAndSettle();
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await engine.dispose();
    });
    final controls = tester.state(find.byType(PlayerControls));
    final previous = find.byKey(const Key('player_previous_episode_button'));
    final next = find.byKey(const Key('player_next_episode_button'));
    final playlist = find.byKey(const Key('player_playlist_button'));
    expect(tester.widget<IconButton>(previous).onPressed, isNull);
    expect(find.text(_entries.first.displayTitle), findsOneWidget);
    expect(find.byKey(const Key('player_episode_label')), findsNothing);
    final options = find.byKey(const Key('player_options_menu_button'));
    await tester.tap(options);
    await tester.pumpAndSettle();
    expect(find.text('视频信息'), findsOneWidget);
    expect(find.byKey(const Key('player_statistics_overlay')), findsNothing);
    expect(find.text('选择本地视频'), findsNothing);
    expect(find.text('输入网络链接'), findsNothing);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('player_statistics_overlay')), findsNothing);
    await tester.tap(options);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('player_video_info_button')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('player_statistics_overlay')), findsOneWidget);
    expect(find.byKey(const Key('appbar_pick_file_button')), findsNothing);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('player_statistics_overlay')), findsNothing);

    await tester.tap(next);
    await tester.pumpAndSettle();
    expect(engine.lastOpenedResource!.libraryFileId, 12);
    expect(engine.openCount, 2);
    expect(tester.state(find.byType(PlayerControls)), same(controls));
    expect(find.text(_entries[1].displayTitle), findsOneWidget);

    source.fail = true;
    await tester.tap(next);
    await tester.pumpAndSettle();
    expect(engine.lastOpenedResource!.libraryFileId, 12);
    expect(engine.openCount, 2);
    expect(find.text('无法播放该集，请检查媒体源后重试'), findsOneWidget);
    source.fail = false;
    ScaffoldMessenger.of(tester.element(playlist)).hideCurrentSnackBar();
    await tester.pumpAndSettle();

    await tester.tap(playlist);
    await tester.pumpAndSettle();
    final panel = find.byKey(const Key('player_playlist_panel'));
    expect(Theme.of(tester.element(panel)).brightness, Brightness.dark);
    var anchorRect = tester.getRect(playlist);
    var panelRect = tester.getRect(panel);
    expect(panelRect.width, 280);
    expect(panelRect.right, closeTo(anchorRect.right, 0.01));
    expect(panelRect.bottom, closeTo(anchorRect.top - 8, 0.01));
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpAndSettle();
    anchorRect = tester.getRect(playlist);
    panelRect = tester.getRect(panel);
    expect(panelRect.width, 280);
    expect(panelRect.right, closeTo(anchorRect.right, 0.01));
    expect(panelRect.bottom, closeTo(anchorRect.top - 8, 0.01));
    expect(
      tester
          .widget<ListTile>(
            find.byKey(const ValueKey('player_playlist_entry_12')),
          )
          .trailing,
      isNull,
    );
    expect(
      tester
          .widget<ListTile>(
            find.byKey(const ValueKey('player_playlist_entry_12')),
          )
          .selected,
      isTrue,
    );
    expect(
      tester
          .widget<ListTile>(
            find.byKey(const ValueKey('player_playlist_entry_14')),
          )
          .enabled,
      isFalse,
    );
    await tester.tap(find.text('新的旅程'));
    await tester.pumpAndSettle();
    expect(engine.lastOpenedResource!.libraryFileId, 13);
    expect(tester.widget<IconButton>(next).onPressed, isNull);
    expect(find.text(_entries[2].displayTitle), findsOneWidget);
    await tester.tap(previous);
    await tester.pumpAndSettle();
    expect(engine.lastOpenedResource!.libraryFileId, 12);

    engine.emit(
      engine.snapshot.copyWith(
        subtitleTracks: const [PlaybackTrack(id: 'zh', label: '简体中文')],
        audioTracks: const [PlaybackTrack(id: 'zh', label: '国语')],
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('player_more_button')));
    await tester.pumpAndSettle();
    for (final type in ['subtitle', 'audio']) {
      await tester.tap(find.byKey(Key('player_${type}_track_button')));
      await tester.pumpAndSettle();
      final trackPanel = tester.getRect(
        find.byKey(Key('player_${type}_panel')),
      );
      expect(
        Theme.of(tester.element(find.byKey(Key('player_${type}_panel'))))
            .brightness,
        Brightness.dark,
      );
      final playlistAnchor = tester.getRect(playlist);
      expect(trackPanel.right, closeTo(playlistAnchor.right, 0.01));
      expect(trackPanel.bottom, closeTo(playlistAnchor.top - 8, 0.01));
      await tester.tap(find.byTooltip(type == 'subtitle' ? '关闭字幕' : '关闭音频'));
      await tester.pumpAndSettle();
    }
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
