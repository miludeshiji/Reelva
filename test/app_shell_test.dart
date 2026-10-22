import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reelva/app/app.dart';
import 'package:reelva/app/router.dart';
import 'package:reelva/features/home/home_page.dart';
import 'package:reelva/features/library/library_page.dart';
import 'package:reelva/features/settings/settings_page.dart';
import 'package:reelva/features/sources/sources_page.dart';

void main() {
  group('Reelva Shell Navigation Tests', () {
    testWidgets(
      'Desktop wide layout uses NavigationRail and navigates all 4 destinations',
      (tester) async {
        tester.view.physicalSize = const Size(1200, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(const ProviderScope(child: ReelvaApp()));
        await tester.pumpAndSettle();

        expect(find.byType(NavigationRail), findsOneWidget);
        expect(find.byType(NavigationBar), findsNothing);
        expect(find.byType(HomePage), findsOneWidget);

        // Navigate to 影视库
        final libraryDest = find.descendant(
          of: find.byType(NavigationRail),
          matching: find.text('影视库'),
        );
        await tester.tap(libraryDest);
        await tester.pumpAndSettle();
        expect(find.byType(LibraryPage), findsOneWidget);

        // Navigate to 媒体源
        final sourcesDest = find.descendant(
          of: find.byType(NavigationRail),
          matching: find.text('媒体源'),
        );
        await tester.tap(sourcesDest);
        await tester.pumpAndSettle();
        expect(find.byType(SourcesPage), findsOneWidget);

        // Navigate to 设置
        final settingsDest = find.descendant(
          of: find.byType(NavigationRail),
          matching: find.text('设置'),
        );
        await tester.tap(settingsDest);
        await tester.pumpAndSettle();
        expect(find.byType(SettingsPage), findsOneWidget);

        // Navigate back to 首页
        final homeDest = find.descendant(
          of: find.byType(NavigationRail),
          matching: find.text('首页'),
        );
        await tester.tap(homeDest);
        await tester.pumpAndSettle();
        expect(find.byType(HomePage), findsOneWidget);
      },
    );

    testWidgets(
      'Mobile narrow layout uses NavigationBar and navigates all 4 destinations',
      (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(const ProviderScope(child: ReelvaApp()));
        await tester.pumpAndSettle();

        expect(find.byType(NavigationBar), findsOneWidget);
        expect(find.byType(NavigationRail), findsNothing);
        expect(find.byType(HomePage), findsOneWidget);

        // Navigate to 影视库
        final libraryDest = find.descendant(
          of: find.byType(NavigationBar),
          matching: find.text('影视库'),
        );
        await tester.tap(libraryDest);
        await tester.pumpAndSettle();
        expect(find.byType(LibraryPage), findsOneWidget);

        // Navigate to 媒体源
        final sourcesDest = find.descendant(
          of: find.byType(NavigationBar),
          matching: find.text('媒体源'),
        );
        await tester.tap(sourcesDest);
        await tester.pumpAndSettle();
        expect(find.byType(SourcesPage), findsOneWidget);

        // Navigate to 设置
        final settingsDest = find.descendant(
          of: find.byType(NavigationBar),
          matching: find.text('设置'),
        );
        await tester.tap(settingsDest);
        await tester.pumpAndSettle();
        expect(find.byType(SettingsPage), findsOneWidget);

        // Navigate back to 首页
        final homeDest = find.descendant(
          of: find.byType(NavigationBar),
          matching: find.text('首页'),
        );
        await tester.tap(homeDest);
        await tester.pumpAndSettle();
        expect(find.byType(HomePage), findsOneWidget);
      },
    );

    testWidgets('Home empty state action links to sources page', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(const ProviderScope(child: ReelvaApp()));
      await tester.pumpAndSettle();

      expect(find.byType(HomePage), findsOneWidget);

      final actionFinder = find.widgetWithText(FilledButton, '前往媒体源');
      expect(actionFinder, findsOneWidget);

      await tester.tap(actionFinder);
      await tester.pumpAndSettle();

      expect(find.byType(SourcesPage), findsOneWidget);
    });

    testWidgets('Direct routes navigate to specified destinations', (
      tester,
    ) async {
      final router = createRouter(initialLocation: '/library');
      addTearDown(router.dispose);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [routerProvider.overrideWithValue(router)],
          child: const ReelvaApp(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(LibraryPage), findsOneWidget);
    });

    testWidgets(
      'Unknown routes display safe error without raw URL and recover to home',
      (tester) async {
        const unknownPath = '/non-existent-secret-path';
        final router = createRouter(initialLocation: unknownPath);
        addTearDown(router.dispose);

        await tester.pumpWidget(
          ProviderScope(
            overrides: [routerProvider.overrideWithValue(router)],
            child: const ReelvaApp(),
          ),
        );
        await tester.pumpAndSettle();

        // Raw URL must NOT be displayed in UI
        expect(find.textContaining(unknownPath), findsNothing);

        // Safe recovery action works without depending on incidental text
        final recoverButton = find.widgetWithText(FilledButton, '返回首页');
        expect(recoverButton, findsOneWidget);

        await tester.tap(recoverButton);
        await tester.pumpAndSettle();

        expect(find.byType(HomePage), findsOneWidget);
      },
    );

    testWidgets(
      'Small viewport with high text scaling renders and navigates all destinations without overflow',
      (tester) async {
        tester.view.physicalSize = const Size(320, 568);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(
          const MediaQuery(
            data: MediaQueryData(
              size: Size(320, 568),
              textScaler: TextScaler.linear(1.5),
            ),
            child: ProviderScope(child: ReelvaApp()),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byType(HomePage), findsOneWidget);
        expect(find.byType(NavigationBar), findsOneWidget);
        expect(tester.takeException(), isNull);

        // Verify destination navigation under small viewport
        final libraryDest = find.descendant(
          of: find.byType(NavigationBar),
          matching: find.text('影视库'),
        );
        await tester.tap(libraryDest);
        await tester.pumpAndSettle();
        expect(find.byType(LibraryPage), findsOneWidget);
        expect(tester.takeException(), isNull);

        final sourcesDest = find.descendant(
          of: find.byType(NavigationBar),
          matching: find.text('媒体源'),
        );
        await tester.tap(sourcesDest);
        await tester.pumpAndSettle();
        expect(find.byType(SourcesPage), findsOneWidget);
        expect(tester.takeException(), isNull);

        final settingsDest = find.descendant(
          of: find.byType(NavigationBar),
          matching: find.text('设置'),
        );
        await tester.tap(settingsDest);
        await tester.pumpAndSettle();
        expect(find.byType(SettingsPage), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  });
}
