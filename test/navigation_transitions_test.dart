import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:reelva/app/app.dart';
import 'package:reelva/app/router.dart';
import 'package:reelva/features/home/application/home_providers.dart';
import 'package:reelva/features/home/home_page.dart';
import 'package:reelva/features/library/domain/library_work.dart';
import 'package:reelva/features/library/library_page.dart';
import 'package:reelva/features/library/presentation/work_details_page.dart';
import 'package:reelva/features/metadata/application/metadata_providers.dart';
import 'package:reelva/features/player/application/player_providers.dart';
import 'package:reelva/features/player/presentation/player_page.dart';
import 'package:reelva/features/progress/application/progress_providers.dart';
import 'package:reelva/features/settings/about_page.dart';
import 'package:reelva/features/settings/settings_page.dart';
import 'package:reelva/features/sources/application/source_providers.dart';
import 'package:reelva/features/sources/sources_page.dart';
import 'package:reelva/features/update/infrastructure/update_preferences_store.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'features/player/fake_player_engine.dart';

const _work = LibraryWork(id: 1, type: 'movie', title: '测试电影');

class _IdleMetadataController extends MetadataController {
  @override
  Future<void> refresh() async {}
}

Widget _testApp(GoRouter router) {
  return ProviderScope(
    overrides: [
      routerProvider.overrideWithValue(router),
      playerSessionProvider.overrideWith((ref) => createFakeSession()),
      metadataControllerProvider.overrideWith(_IdleMetadataController.new),
      continueWatchingProvider.overrideWith((ref) => Stream.value(const [])),
      recentWorksProvider.overrideWith((ref) => Stream.value(const [_work])),
      libraryWorksProvider.overrideWith(
        (ref, limit) => Stream.value(const [_work]),
      ),
      filteredLibraryWorksProvider.overrideWith(
        (ref, filter) => Stream.value(const [_work]),
      ),
      workDetailsProvider.overrideWith(
        (ref, id) => Stream.value(const WorkDetails(work: _work, versions: [])),
      ),
      mediaSourcesProvider.overrideWith((ref) => Stream.value(const [])),
    ],
    child: const ReelvaApp(),
  );
}

void main() {
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({
      UpdatePreferencesStore.automaticKey: 'false',
    });
    PackageInfo.setMockInitialValues(
      appName: 'Reelva',
      packageName: 'com.github.miludeshiji.reelva',
      version: '0.1.0',
      buildNumber: '1',
      buildSignature: '',
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('window_manager'),
          (call) async => true,
        );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('reelva/player_input'),
          (call) async => null,
        );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('window_manager'), null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('reelva/player_input'),
          null,
        );
  });

  testWidgets(
    'Branch changes animate while preserving page state',
    (tester) async {
      final router = createRouter(initialLocation: '/library');
      tester.view.physicalSize = defaultTargetPlatform == TargetPlatform.windows
          ? const Size(1200, 800)
          : const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      try {
        await tester.pumpWidget(_testApp(router));
        await tester.pumpAndSettle();
        final libraryElement = tester.element(find.byType(LibraryPage));
        await tester.enterText(
          find.byKey(const Key('library_search_field')),
          '保留搜索条件',
        );
        await tester.pumpAndSettle();

        for (final (destination, pageType) in [
          ('settings', SettingsPage),
          ('home', HomePage),
          ('sources', SourcesPage),
          ('library', LibraryPage),
        ]) {
          await tester.tap(
            find.byKey(ValueKey('navigation_destination_$destination')),
          );
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 100));
          final fadingPage = find.ancestor(
            of: find.byType(pageType),
            matching: find.byType(Opacity),
          );
          expect(fadingPage, findsWidgets);
          expect(
            fadingPage.evaluate().map(
              (element) => (element.widget as Opacity).opacity,
            ),
            contains(inExclusiveRange(0.0, 1.0)),
          );
          await tester.pumpAndSettle();
        }

        expect(tester.element(find.byType(LibraryPage)), same(libraryElement));
        final searchField = tester.widget<TextField>(
          find.descendant(
            of: find.byKey(const Key('library_search_field')),
            matching: find.byType(TextField),
          ),
        );
        expect(searchField.controller!.text, '保留搜索条件');
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        router.dispose();
      }
    },
    variant: const TargetPlatformVariant({
      TargetPlatform.android,
      TargetPlatform.windows,
    }),
  );

  testWidgets(
    'Page entry and back use the license page Material transitions',
    (tester) async {
      final router = createRouter(initialLocation: '/settings');

      try {
        await tester.pumpWidget(_testApp(router));
        await tester.pumpAndSettle();

        for (final (parent, destination, pageType) in [
          ('/settings', '/settings/about', AboutPage),
          ('/library', '/library/work/1', WorkDetailsPage),
          ('/library', '/player', PlayerPage),
        ]) {
          router.go(parent);
          await tester.pumpAndSettle();
          if (pageType == PlayerPage) {
            router.push<void>(destination);
          } else {
            router.go(destination);
          }
          await tester.pump();

          final route =
              ModalRoute.of(
                    tester.element(find.byType(pageType, skipOffstage: false)),
                  )!
                  as PageRoute<void>;
          expect(route.settings, isA<MaterialPage<void>>());
          expect(route.animation!.status, AnimationStatus.forward);
          await tester.pump(const Duration(milliseconds: 100));
          expect(route.animation!.value, inExclusiveRange(0.0, 1.0));
          await tester.pumpAndSettle();

          if (pageType == AboutPage) {
            final licenseButton = find.text('查看第三方开源许可证');
            await tester.ensureVisible(licenseButton);
            await tester.pumpAndSettle();
            await tester.tap(licenseButton);
            await tester.pumpAndSettle();
            final licenseRoute =
                ModalRoute.of(tester.element(find.byType(LicensePage)))!
                    as PageRoute<void>;
            expect(route.transitionDuration, licenseRoute.transitionDuration);
            expect(
              route.reverseTransitionDuration,
              licenseRoute.reverseTransitionDuration,
            );
            await tester.tap(find.byType(BackButton));
            await tester.pumpAndSettle();
            await tester.tap(
              find.byKey(const Key('settings_subpage_back_button')),
            );
          } else if (pageType == PlayerPage) {
            await tester.tap(find.byKey(const Key('player_back_button')));
            // 播放器先在下一帧放行路由返回，再由后续帧启动退出动画。
            await tester.pump();
          } else {
            await tester.tap(find.byKey(const Key('work_details_back_button')));
          }
          await tester.pump();
          expect(route.animation!.status, AnimationStatus.reverse);
          await tester.pump(const Duration(milliseconds: 100));
          expect(route.animation!.value, inExclusiveRange(0.0, 1.0));
          await tester.pumpAndSettle();
          expect(find.byType(pageType), findsNothing);
          expect(router.routeInformationProvider.value.uri.path, parent);
        }
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        router.dispose();
      }
    },
    variant: const TargetPlatformVariant({
      TargetPlatform.android,
      TargetPlatform.windows,
    }),
  );
}
