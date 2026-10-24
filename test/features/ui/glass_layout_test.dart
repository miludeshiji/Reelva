import 'dart:io';
import 'dart:ui' as ui;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reelva/app/router.dart';
import 'package:reelva/app/shell_page.dart';
import 'package:reelva/app/theme/reelva_theme.dart';
import 'package:reelva/core/database/app_database.dart';
import 'package:reelva/features/home/application/home_providers.dart';
import 'package:reelva/features/home/home_page.dart';
import 'package:reelva/features/library/domain/library_work.dart';
import 'package:reelva/features/library/library_page.dart';
import 'package:reelva/features/library/presentation/work_details_page.dart';
import 'package:reelva/features/metadata/application/metadata_providers.dart';
import 'package:reelva/features/player/application/player_providers.dart';
import 'package:reelva/features/player/domain/playback_resource.dart';
import 'package:reelva/features/player/domain/playback_snapshot.dart';
import 'package:reelva/features/player/presentation/player_page.dart';
import 'package:reelva/features/progress/application/progress_providers.dart';
import 'package:reelva/features/settings/about_page.dart';
import 'package:reelva/features/settings/settings_page.dart';
import 'package:reelva/features/sources/application/source_providers.dart';
import 'package:reelva/features/sources/domain/source_models.dart';
import 'package:reelva/features/sources/sources_page.dart';
import 'package:reelva/features/sync/application/sync_providers.dart';
import 'package:reelva/shared/widgets/glass_navigation.dart';

import '../player/fake_player_engine.dart';

// fvm flutter test --no-pub --dart-define=REELVA_UI_CAPTURE_DIR=<绝对目录> test/features/ui/glass_layout_test.dart
// Screenshots use real Widget rendering with test data and a test video frame,
// not native video output or device screenshots.
const _captureDir = String.fromEnvironment('REELVA_UI_CAPTURE_DIR');
const _longTitle = '穿越漫长岁月与群星之间的旅人：在世界尽头重逢的故事';
const _sourceError = '媒体源暂时无法连接，请检查家庭服务器与共享目录的访问权限后重新扫描';
const _edition = '导演加长珍藏修复版 · 2160p HDR · 国语与原声双音轨';
final _overview = List.filled(
  6,
  '一群来自不同城市的旅人在漫长的星际航行中寻找失落的家园。'
  '他们穿过山川、海洋与遥远的群星，逐渐发现记忆背后的秘密，'
  '并在一次次重逢与离别中学会理解彼此，最终决定共同守护这片故土。',
).join('\n\n');

final _works = List<LibraryWork>.generate(
  24,
  (index) => LibraryWork(
    id: index + 1,
    type: index.isEven ? 'movie' : 'series',
    title: '$_longTitle（第 ${index + 1} 部）',
    originalTitle: 'Travellers Among the Stars — Chapter ${index + 1}',
    year: 2024,
    overview: _overview,
    versionCount: index.isEven ? 3 : 8,
  ),
);

final _continueWatching = List<ContinueWatchingEntry>.generate(
  5,
  (index) => ContinueWatchingEntry(
    workId: index + 1,
    fileId: 101 + index,
    title: _works[index].title,
    position: Duration(minutes: 18 + index * 7, seconds: 24),
    duration: const Duration(hours: 2, minutes: 16),
    seasonNumber: index.isOdd ? 2 : null,
    episodeNumber: index.isOdd ? 12 : null,
  ),
);

final _sources = [
  MediaSourceConfig(
    id: 1,
    kind: 'local',
    name: '本地收藏 · 超长中文目录名称与家庭珍藏影视完整修复版本',
    rootLocator: 'F:/家庭影视收藏/电影与纪录片/高清修复收藏/完整多音轨珍藏版本',
    lastScanAt: DateTime(2026, 10, 20, 18, 30),
  ),
  MediaSourceConfig(
    id: 2,
    kind: 'smb',
    name: '家庭 NAS · 客厅与书房共享的超高清影视资料存储中心',
    rootLocator: 'smb://nas.example.invalid/家庭共享/超高清影视/多季剧集与电影收藏',
    lastScanAt: DateTime(2026, 10, 20, 19, 45),
    errorMessage: _sourceError,
  ),
  MediaSourceConfig(
    id: 3,
    kind: 'webdav',
    name: '远程 WebDAV · 异地备份与长名称媒体资源收藏目录',
    rootLocator: 'https://media.example.invalid/dav/archive/家庭影视备份/多版本与字幕资料/',
    lastScanAt: DateTime(2026, 10, 19, 9, 15),
  ),
];

final _details = WorkDetails(
  work: _works[1],
  versions: List<LibraryVersion>.generate(
    8,
    (index) => LibraryVersion(
      fileId: 101 + index,
      fileName: '星际旅人.第二季.第${index + 1}集.2160p.HDR.多音轨珍藏修复版.mkv',
      sourceName: _sources[index % _sources.length].name,
      available: index != 1,
      editionLabel: _edition,
      sourceError: index == 1 ? _sourceError : null,
      seasonNumber: 2,
      episodeNumber: index ~/ 2 + 1,
      episodeTitle: '重返群星之下：穿越漫长旅途后再次遇见熟悉的故乡与朋友',
    ),
  ),
);

class _IdleMetadataController extends MetadataController {
  @override
  MetadataTaskState build() => const MetadataTaskState();

  @override
  Future<void> refresh() async {}
}

class _FixtureSourceController extends SourceController {
  @override
  Map<int, ScanProgress> build() => const {
    1: ScanProgress(visited: 428, videos: 96),
    2: ScanProgress(visited: 38, videos: 12, error: _sourceError),
    3: ScanProgress(visited: 152, videos: 47),
  };
}

enum _Page {
  home('HomePage', '/', HomePage),
  library('LibraryPage', '/library', LibraryPage),
  sources('SourcesPage', '/sources', SourcesPage),
  details('WorkDetailsPage', '/library/work/2', WorkDetailsPage),
  player('PlayerPage', '/player', PlayerPage),
  settings('SettingsPage', '/settings', SettingsPage),
  about('AboutPage', '/settings/about', AboutPage);

  const _Page(this.label, this.location, this.widgetType);
  final String label;
  final String location;
  final Type widgetType;
}

const _viewports = [
  (name: 'mobile', size: Size(390, 844), scale: 1.0),
  (name: 'small-text150', size: Size(320, 568), scale: 1.5),
  (name: 'landscape', size: Size(568, 320), scale: 1.0),
  (name: 'desktop', size: Size(1440, 900), scale: 1.0),
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final suiteDebugDisableShadows = debugDisableShadows;

  tearDownAll(() {
    debugDisableShadows = suiteDebugDisableShadows;
  });

  setUpAll(() async {
    if (_captureDir.isEmpty) return;
    if (!Platform.isWindows) {
      throw StateError(
        'UI capture requires Windows and the Microsoft YaHei system font.',
      );
    }
    final font = File('C:/Windows/Fonts/msyh.ttc');
    if (!await font.exists()) {
      throw StateError('UI capture requires system font: ${font.path}');
    }
    final fontData = font.readAsBytes().then(ByteData.sublistView);
    // Roboto covers the player's internal Theme.
    for (final family in const ['Microsoft YaHei', 'Roboto']) {
      final loader = FontLoader(family);
      loader.addFont(fontData);
      await loader.load();
    }
    final icons = FontLoader('MaterialIcons');
    icons.addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await icons.load();
  });

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('window_manager'),
      (call) async => true,
    );
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      return null;
    });
  });

  tearDown(() {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('window_manager'),
      null,
    );
    messenger.setMockMethodCallHandler(SystemChannels.platform, null);
  });

  for (final page in _Page.values) {
    for (final viewport in _viewports) {
      testWidgets('${page.label} ${viewport.name} '
          '${viewport.size.width.toInt()}x${viewport.size.height.toInt()} '
          'textScale ${viewport.scale}: real content and responsive layout', (
        tester,
      ) async {
        final previousDebugDisableShadows = debugDisableShadows;
        try {
          if (_captureDir.isNotEmpty) debugDisableShadows = false;
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = viewport.size;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);

          final db = AppDatabase(executor: NativeDatabase.memory());
          final router = createRouter();
          final boundaryKey = GlobalKey();
          final engine = FakePlayerEngine();
          final session = createFakeSession(
            engine: engine,
            videoBuilder: (_) => const SizedBox.expand(
              child: ColoredBox(
                key: Key('layout_fixture_video_frame'),
                color: Color(0xFF213C50),
              ),
            ),
          );
          final resource = PlaybackResource(
            uri: Uri.parse('file:///layout-fixture/episode.mkv'),
            displayName: '$_longTitle.S02E12.2160p.mkv',
          );

          addTearDown(() async {
            await tester.pumpWidget(const SizedBox.shrink());
            await tester.pump();
            router.dispose();
            await tester.runAsync(() async {
              if (!engine.isDisposed) await engine.dispose();
              await db.close();
            });
            expect(tester.takeException(), isNull);
          });

          final capture =
              _captureDir.isNotEmpty &&
              (viewport.name == 'mobile' || viewport.name == 'desktop');
          final lightTheme = ReelvaTheme.light;
          final darkTheme = ReelvaTheme.player;
          await tester.pumpWidget(
            ProviderScope(
              overrides: [
                appDatabaseProvider.overrideWithValue(db),
                recentWorksProvider.overrideWith((ref) => Stream.value(_works)),
                continueWatchingProvider.overrideWith(
                  (ref) => Stream.value(_continueWatching),
                ),
                libraryWorksProvider.overrideWith(
                  (ref, limit) => Stream.value(_works),
                ),
                filteredLibraryWorksProvider.overrideWith(
                  (ref, filter) => Stream.value(_works),
                ),
                workDetailsProvider.overrideWith(
                  (ref, id) => Stream.value(_details),
                ),
                mediaSourcesProvider.overrideWith(
                  (ref) => Stream.value(_sources),
                ),
                sourceControllerProvider.overrideWith(
                  _FixtureSourceController.new,
                ),
                metadataControllerProvider.overrideWith(
                  _IdleMetadataController.new,
                ),
                tmdbCredentialConfiguredProvider.overrideWith(
                  (ref) async => true,
                ),
                syncConfigurationProvider.overrideWith((ref) async => null),
                playerSessionProvider.overrideWithValue(session),
              ],
              child: RepaintBoundary(
                key: boundaryKey,
                // Match ReelvaApp while injecting scaling *inside* MaterialApp.
                child: MaterialApp.router(
                  debugShowCheckedModeBanner: false,
                  theme: capture
                      ? lightTheme.copyWith(
                          textTheme: lightTheme.textTheme.apply(
                            fontFamily: 'Microsoft YaHei',
                          ),
                          primaryTextTheme: lightTheme.primaryTextTheme.apply(
                            fontFamily: 'Microsoft YaHei',
                          ),
                        )
                      : lightTheme,
                  darkTheme: capture
                      ? darkTheme.copyWith(
                          textTheme: darkTheme.textTheme.apply(
                            fontFamily: 'Microsoft YaHei',
                          ),
                          primaryTextTheme: darkTheme.primaryTextTheme.apply(
                            fontFamily: 'Microsoft YaHei',
                          ),
                        )
                      : darkTheme,
                  themeMode: ThemeMode.light,
                  routerConfig: router,
                  builder: (context, child) => MediaQuery(
                    data: MediaQuery.of(
                      context,
                    ).copyWith(textScaler: TextScaler.linear(viewport.scale)),
                    child: child!,
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          router.go(
            page.location,
            extra: page == _Page.player ? resource : null,
          );
          await tester.pumpAndSettle();
          if (page == _Page.player) {
            engine.emit(
              const PlaybackSnapshot(
                status: PlaybackStatus.paused,
                position: Duration(minutes: 18, seconds: 24),
                duration: Duration(hours: 2, minutes: 16),
                buffered: Duration(minutes: 28),
                audioTracks: [PlaybackTrack(id: 'zh', label: '国语 · 多声道原声')],
                subtitleTracks: [
                  PlaybackTrack(id: 'zh-Hans', label: '简体中文 · 完整字幕'),
                ],
                audioTrackId: 'zh',
                subtitleTrackId: 'zh-Hans',
              ),
            );
            await tester.pumpAndSettle();
          }

          final pageFinder = find.byType(page.widgetType);
          expect(pageFinder, findsOneWidget);
          final context = tester.element(pageFinder);
          expect(MediaQuery.sizeOf(context), viewport.size);
          expect(
            MediaQuery.textScalerOf(context).scale(20),
            20 * viewport.scale,
          );
          _expectNavigation(tester, page, viewport.name == 'desktop');
          expect(tester.takeException(), isNull);

          // Capture the actual router/shell before revealing lower content.
          if (capture) {
            await _capture(
              tester,
              boundaryKey,
              '${page.name}-${viewport.name}.png',
              viewport.size,
            );
          }

          await _exerciseContent(tester, page);
          expect(tester.takeException(), isNull);
        } finally {
          debugDisableShadows = previousDebugDisableShadows;
        }
      });
    }
  }
}

void _expectNavigation(WidgetTester tester, _Page page, bool desktop) {
  if (page == _Page.player) {
    expect(find.byType(AppShell), findsNothing);
    expect(find.byType(GlassSidebar), findsNothing);
    expect(find.byType(GlassBottomNavigationBar), findsNothing);
    return;
  }
  expect(find.byType(AppShell), findsOneWidget);
  expect(find.byType(GlassSidebar), desktop ? findsOneWidget : findsNothing);
  expect(
    find.byType(GlassBottomNavigationBar),
    desktop ? findsNothing : findsOneWidget,
  );
  if (page == _Page.home && desktop) {
    final sidebar = tester.getRect(find.byType(GlassSidebar));
    final home = tester.getRect(find.byType(HomePage));
    expect(sidebar.left, 0);
    expect(sidebar.height, tester.view.physicalSize.height);
    expect(home.left, greaterThanOrEqualTo(sidebar.right));
  }
}

Finder _verticalScrollable(_Page page) => find
    .descendant(
      of: find.byType(page.widgetType),
      matching: find.byWidgetPredicate(
        (widget) =>
            widget is Scrollable &&
            axisDirectionToAxis(widget.axisDirection) == Axis.vertical,
      ),
    )
    .first;

Future<void> _reveal(WidgetTester tester, _Page page, Finder target) async {
  await tester.scrollUntilVisible(
    target,
    200,
    scrollable: _verticalScrollable(page),
    maxScrolls: 60,
  );
  await tester.pumpAndSettle();
  expect(target, findsOneWidget);
  expect(
    tester.getRect(target).overlaps(Offset.zero & tester.view.physicalSize),
    isTrue,
  );
  expect(tester.takeException(), isNull);
}

Future<void> _exerciseContent(WidgetTester tester, _Page page) async {
  switch (page) {
    case _Page.home:
      expect(find.byType(FloatingActionButton), findsNothing);
      expect(
        find.byKey(const Key('home_open_player_fab')).hitTestable(),
        findsOneWidget,
      );
      await _reveal(tester, page, find.text('继续观看'));
      expect(find.text('继续观看'), findsOneWidget);
      expect(find.text(_continueWatching.first.title), findsWidgets);
      await _reveal(tester, page, find.byKey(const Key('recent_work_card_16')));
      expect(find.text(_works[15].title), findsWidgets);
    case _Page.library:
      await _reveal(tester, page, find.byKey(const Key('library_work_card_1')));
      expect(find.text(_works.first.title), findsWidgets);
      await _reveal(
        tester,
        page,
        find.byKey(const Key('library_work_card_16')),
      );
      expect(find.text(_works[15].title), findsWidgets);
    case _Page.sources:
      await _reveal(tester, page, find.text(_sources.first.name));
      expect(find.textContaining(_sources.first.rootLocator), findsOneWidget);
      await _reveal(tester, page, find.byKey(const Key('source_error_text_2')));
      expect(find.text(_sourceError), findsWidgets);
      await _reveal(tester, page, find.text(_sources.last.name));
      expect(find.textContaining(_sources.last.rootLocator), findsOneWidget);
    case _Page.details:
      expect(find.byKey(const Key('work_details_title')), findsOneWidget);
      expect(find.text(_details.work.title), findsWidgets);
      await _reveal(tester, page, find.text(_overview));
      await _reveal(
        tester,
        page,
        find.byKey(const Key('work_version_item_102')),
      );
      expect(find.text(_sourceError), findsOneWidget);
      expect(find.text(_edition), findsWidgets);
      await _reveal(
        tester,
        page,
        find.byKey(const Key('work_version_item_108')),
      );
    case _Page.player:
      final title = tester.widget<Text>(
        find.byKey(const Key('player_title_text')),
      );
      expect(title.data, '$_longTitle.S02E12.2160p.mkv');
      expect(
        find.byKey(const Key('layout_fixture_video_frame')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('player_play_button')), findsOneWidget);
      final slider = tester.widget<Slider>(
        find.byKey(const Key('player_seek_slider')),
      );
      expect(
        slider.value,
        const Duration(minutes: 18, seconds: 24).inMilliseconds.toDouble(),
      );
      expect(
        slider.max,
        const Duration(hours: 2, minutes: 16).inMilliseconds.toDouble(),
      );
      await _reveal(
        tester,
        page,
        find.byKey(const Key('player_audio_track_button')),
      );
    case _Page.settings:
      expect(find.text('TMDB 识别'), findsOneWidget);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(SettingsPage)),
      );
      expect(
        container.read(tmdbCredentialConfiguredProvider).asData?.value,
        isTrue,
      );
      expect(container.read(syncConfigurationProvider).asData, isNotNull);
      expect(container.read(syncConfigurationProvider).asData?.value, isNull);
      await _reveal(tester, page, find.byKey(const Key('settings_tmdb_tile')));
      await tester.tap(find.byKey(const Key('settings_tmdb_tile')));
      await tester.pumpAndSettle();
      await _reveal(
        tester,
        page,
        find.byKey(const Key('tmdb_configured_chip')),
      );
      expect(find.text('已配置'), findsOneWidget);
      await _reveal(tester, page, find.byKey(const Key('settings_sync_tile')));
      await tester.tap(find.byKey(const Key('settings_sync_tile')));
      await tester.pumpAndSettle();
      await _reveal(tester, page, find.byKey(const Key('sync_endpoint')));
      expect(find.byKey(const Key('sync_status_chip')), findsOneWidget);
    case _Page.about:
      expect(find.text('现代跨平台媒体库与播放器'), findsOneWidget);
      await _reveal(tester, page, find.text(AboutPage.tmdbRequiredNotice));
      await _reveal(tester, page, find.text('查看第三方开源许可证'));
  }
}

Future<void> _capture(
  WidgetTester tester,
  GlobalKey key,
  String name,
  Size size,
) async {
  final boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  expect(boundary.size, size);
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1);
    try {
      expect(image.width, size.width.toInt());
      expect(image.height, size.height.toInt());
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      expect(bytes, isNotNull);
      await Directory(_captureDir).create(recursive: true);
      await File('$_captureDir/$name')
          .writeAsBytes(bytes!.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });
}
