import 'package:drift/drift.dart' show DatabaseConnection;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:reelva/app/app.dart';
import 'package:reelva/app/desktop_preferences.dart';
import 'package:reelva/app/router.dart';
import 'package:reelva/core/database/app_database.dart';
import 'package:reelva/features/home/home_page.dart';
import 'package:reelva/features/library/library_page.dart';
import 'package:reelva/features/player/application/player_providers.dart';
import 'package:reelva/features/player/presentation/player_page.dart';
import 'package:reelva/features/settings/settings_page.dart';
import 'package:reelva/features/sources/application/source_providers.dart';
import 'package:reelva/features/sources/sources_page.dart';
import 'package:reelva/features/update/infrastructure/update_preferences_store.dart';
import 'package:reelva/shared/widgets/glass_navigation.dart';

import 'features/player/fake_player_engine.dart';

Widget createTestApp({
  required AppDatabase db,
  GoRouter? router,
  bool sidebarCollapsed = false,
}) {
  return ProviderScope(
    overrides: [
      appDatabaseProvider.overrideWithValue(db),
      playerSessionProvider.overrideWith((ref) => createFakeSession()),
      sidebarCollapsedProvider.overrideWith(
        () => SidebarCollapsedController(initialValue: sidebarCollapsed),
      ),
      if (router != null) routerProvider.overrideWithValue(router),
    ],
    child: const ReelvaApp(),
  );
}

void main() {
  group('Reelva Shell Navigation Tests', () {
    setUp(() {
      FlutterSecureStorage.setMockInitialValues({
        UpdatePreferencesStore.automaticKey: 'false',
      });
    });

    testWidgets(
      'Desktop sidebar collapses to icon navigation and preserves state across destinations',
      (tester) async {
        final db = AppDatabase(executor: NativeDatabase.memory());
        addTearDown(db.close);
        tester.view.physicalSize = const Size(1200, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        try {
          await tester.pumpWidget(createTestApp(db: db));
          await tester.pumpAndSettle();

          final sidebar = find.byType(GlassSidebar);
          final toggle = find.byKey(const ValueKey('sidebar_toggle'));
          expect(sidebar, findsOneWidget);
          expect(tester.getSize(sidebar).width, 248);
          expect(find.byType(GlassBottomNavigationBar), findsNothing);
          expect(find.byType(HomePage), findsOneWidget);
          expect(
            find.byKey(const ValueKey('sidebar_open_player')),
            findsNothing,
          );

          await tester.tap(toggle);
          await tester.pumpAndSettle();
          expect(tester.getSize(sidebar).width, 112);
          expect(
            find.descendant(of: sidebar, matching: find.text('Reelva')),
            findsNothing,
          );

          // Navigate to 影视库
          final libraryDest = find.byKey(
            const ValueKey('navigation_destination_library'),
          );
          expect(
            find.descendant(of: libraryDest, matching: find.text('影视库')),
            findsNothing,
          );
          expect(
            find.descendant(of: libraryDest, matching: find.byType(Icon)),
            findsOneWidget,
          );
          await tester.tap(libraryDest);
          await tester.pumpAndSettle();
          expect(find.byType(LibraryPage), findsOneWidget);
          expect(
            tester.widget<Semantics>(libraryDest).properties.selected,
            isTrue,
          );

          // Navigate to 媒体源
          final sourcesDest = find.byKey(
            const ValueKey('navigation_destination_sources'),
          );
          await tester.tap(sourcesDest);
          await tester.pumpAndSettle();
          expect(find.byType(SourcesPage), findsOneWidget);

          // Navigate to 设置
          final settingsDest = find.byKey(
            const ValueKey('navigation_destination_settings'),
          );
          await tester.tap(settingsDest);
          await tester.pumpAndSettle();
          expect(find.byType(SettingsPage), findsOneWidget);

          // Navigate back to 首页
          final homeDest = find.byKey(
            const ValueKey('navigation_destination_home'),
          );
          await tester.tap(homeDest);
          await tester.pumpAndSettle();
          expect(find.byType(HomePage), findsOneWidget);
          expect(tester.getSize(sidebar).width, 112);

          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pumpAndSettle();
          final collapsed = await const DesktopPreferencesStore()
              .readSidebarCollapsed();
          expect(collapsed, isTrue);
          await tester.pumpWidget(
            createTestApp(db: db, sidebarCollapsed: collapsed),
          );
          await tester.pumpAndSettle();
          expect(tester.getSize(sidebar).width, 112);

          await tester.tap(toggle);
          await tester.pumpAndSettle();
          expect(tester.getSize(sidebar).width, 248);
          expect(
            find.descendant(of: sidebar, matching: find.text('Reelva')),
            findsOneWidget,
          );
          expect(
            find.descendant(of: libraryDest, matching: find.byType(Icon)),
            findsOneWidget,
          );
          expect(
            find.descendant(of: libraryDest, matching: find.text('影视库')),
            findsOneWidget,
          );
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump(Duration.zero);
          await db.close();
        }
      },
      variant: TargetPlatformVariant.only(TargetPlatform.windows),
    );

    testWidgets(
      'Mobile narrow layout uses GlassBottomNavigationBar and navigates all 4 destinations',
      (tester) async {
        final db = AppDatabase(executor: NativeDatabase.memory());
        addTearDown(db.close);
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        try {
          await tester.pumpWidget(createTestApp(db: db));
          await tester.pumpAndSettle();

          expect(find.byType(GlassBottomNavigationBar), findsOneWidget);
          expect(find.byType(GlassSidebar), findsNothing);
          expect(find.byType(HomePage), findsOneWidget);

          // Navigate to 影视库
          final libraryDest = find.byKey(
            const ValueKey('navigation_destination_library'),
          );
          await tester.tap(libraryDest);
          await tester.pumpAndSettle();
          expect(find.byType(LibraryPage), findsOneWidget);

          // Navigate to 媒体源
          final sourcesDest = find.byKey(
            const ValueKey('navigation_destination_sources'),
          );
          await tester.tap(sourcesDest);
          await tester.pumpAndSettle();
          expect(find.byType(SourcesPage), findsOneWidget);

          // Navigate to 设置
          final settingsDest = find.byKey(
            const ValueKey('navigation_destination_settings'),
          );
          await tester.tap(settingsDest);
          await tester.pumpAndSettle();
          expect(find.byType(SettingsPage), findsOneWidget);

          // Navigate back to 首页
          final homeDest = find.byKey(
            const ValueKey('navigation_destination_home'),
          );
          await tester.tap(homeDest);
          await tester.pumpAndSettle();
          expect(find.byType(HomePage), findsOneWidget);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump(Duration.zero);
          await db.close();
        }
      },
    );

    testWidgets('Home empty state action links to sources page', (
      tester,
    ) async {
      final db = AppDatabase(executor: NativeDatabase.memory());
      addTearDown(db.close);
      tester.view.physicalSize = const Size(800, 600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      try {
        await tester.pumpWidget(createTestApp(db: db));
        await tester.pumpAndSettle();

        expect(find.byType(HomePage), findsOneWidget);

        final actionFinder = find.widgetWithText(FilledButton, '前往媒体源');
        expect(actionFinder, findsOneWidget);

        await tester.tap(actionFinder);
        await tester.pumpAndSettle();

        expect(find.byType(SourcesPage), findsOneWidget);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(Duration.zero);
        await db.close();
      }
    });

    for (final (path, pageType) in [
      ('/', HomePage),
      ('/library', LibraryPage),
      ('/sources', SourcesPage),
      ('/settings', SettingsPage),
    ]) {
      testWidgets('Player exit preserves the page and state at $path', (
        tester,
      ) async {
        final db = AppDatabase(
          executor: DatabaseConnection(
            NativeDatabase.memory(),
            closeStreamsSynchronously: true,
          ),
        );
        final router = createRouter(initialLocation: path);
        tester.view.physicalSize = const Size(1200, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        try {
          await tester.pumpWidget(createTestApp(db: db, router: router));
          await tester.pumpAndSettle();

          final pageElement = tester.element(find.byType(pageType));
          if (pageType == LibraryPage) {
            await tester.enterText(
              find.byKey(const Key('library_search_field')),
              '保留搜索条件',
            );
            await tester.pumpAndSettle();
          }

          router.push<void>('/player');
          await tester.pumpAndSettle();
          expect(find.byType(PlayerPage), findsOneWidget);

          await tester.tap(find.byKey(const Key('player_back_button')));
          await tester.pumpAndSettle();

          expect(router.routeInformationProvider.value.uri.path, path);
          expect(tester.element(find.byType(pageType)), same(pageElement));
          if (pageType == LibraryPage) {
            final searchField = tester.widget<TextField>(
              find.descendant(
                of: find.byKey(const Key('library_search_field')),
                matching: find.byType(TextField),
              ),
            );
            expect(searchField.controller!.text, '保留搜索条件');
          }
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
          router.dispose();
          await db.close();
        }
      });
    }

    testWidgets('Direct routes navigate to specified destinations', (
      tester,
    ) async {
      final db = AppDatabase(executor: NativeDatabase.memory());
      addTearDown(db.close);
      final router = createRouter(initialLocation: '/library');
      addTearDown(router.dispose);

      try {
        await tester.pumpWidget(createTestApp(db: db, router: router));
        await tester.pumpAndSettle();

        expect(find.byType(LibraryPage), findsOneWidget);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(Duration.zero);
        await db.close();
      }
    });
    testWidgets(
      'Unknown routes display safe error without raw URL and recover to home',
      (tester) async {
        final db = AppDatabase(executor: NativeDatabase.memory());
        addTearDown(db.close);
        const unknownPath = '/non-existent-secret-path';
        final router = createRouter(initialLocation: unknownPath);
        addTearDown(router.dispose);

        try {
          await tester.pumpWidget(createTestApp(db: db, router: router));
          await tester.pumpAndSettle();

          // Raw URL must NOT be displayed in UI
          expect(find.textContaining(unknownPath), findsNothing);

          // Safe recovery action works without depending on incidental text
          final recoverButton = find.widgetWithText(FilledButton, '返回首页');
          expect(recoverButton, findsOneWidget);

          await tester.tap(recoverButton);
          await tester.pumpAndSettle();

          expect(find.byType(HomePage), findsOneWidget);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump(Duration.zero);
          await db.close();
        }
      },
    );
    testWidgets(
      'Small viewport with high text scaling renders and navigates all destinations without overflow',
      (tester) async {
        final db = AppDatabase(executor: NativeDatabase.memory());
        addTearDown(db.close);
        tester.view.physicalSize = const Size(320, 568);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        try {
          tester.platformDispatcher.textScaleFactorTestValue = 1.5;
          addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
          await tester.pumpWidget(createTestApp(db: db));
          await tester.pumpAndSettle();

          expect(find.byType(HomePage), findsOneWidget);
          expect(find.byType(GlassBottomNavigationBar), findsOneWidget);
          expect(tester.takeException(), isNull);

          // Verify destination navigation under small viewport
          final libraryDest = find.byKey(
            const ValueKey('navigation_destination_library'),
          );
          await tester.tap(libraryDest);
          await tester.pumpAndSettle();
          expect(find.byType(LibraryPage), findsOneWidget);
          expect(tester.takeException(), isNull);

          final sourcesDest = find.byKey(
            const ValueKey('navigation_destination_sources'),
          );
          await tester.tap(sourcesDest);
          await tester.pumpAndSettle();
          expect(find.byType(SourcesPage), findsOneWidget);
          expect(tester.takeException(), isNull);

          final settingsDest = find.byKey(
            const ValueKey('navigation_destination_settings'),
          );
          await tester.tap(settingsDest);
          await tester.pumpAndSettle();
          expect(find.byType(SettingsPage), findsOneWidget);
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump(Duration.zero);
          await db.close();
        }
      },
    );
  });
}
