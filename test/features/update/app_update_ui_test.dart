import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:reelva/app/theme/reelva_theme.dart';
import 'package:reelva/features/settings/about_page.dart';
import 'package:reelva/features/update/application/app_update_providers.dart';
import 'package:reelva/features/update/domain/app_release.dart';
import 'package:reelva/features/update/infrastructure/apk_downloader.dart';
import 'package:reelva/features/update/infrastructure/github_release_client.dart';
import 'package:reelva/features/update/infrastructure/update_preferences_store.dart';
import 'package:reelva/features/update/presentation/app_update_dialog.dart';
import 'package:reelva/features/update/presentation/update_prompt_host.dart';
import 'package:reelva/features/update/presentation/update_settings_card.dart';

import 'update_test_helpers.dart';

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
  });

  testWidgets('手动检查显示新版本说明，Windows 按钮打开对应附件和版本页', (tester) async {
    final adapter = UpdateHttpAdapter(
      (_) => jsonResponse(releaseJson('0.2.0')),
    );
    final client = GithubReleaseClient(dio: Dio()..httpClientAdapter = adapter);
    addTearDown(client.close);
    final opened = <Uri>[];
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => const Scaffold(body: UpdateSettingsCard()),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          githubReleaseClientProvider.overrideWithValue(client),
          openUpdateUrlProvider.overrideWithValue((uri) async {
            opened.add(uri);
          }),
        ],
        child: MaterialApp.router(
          theme: ReelvaTheme.light,
          routerConfig: router,
          builder: (context, child) =>
              UpdatePromptHost(router: router, child: child!),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(adapter.requests, isEmpty);
    await tester.tap(find.byKey(const Key('check_update_button')));
    await tester.pumpAndSettle();
    expect(find.byType(AppUpdateDialog), findsOneWidget);
    expect(find.text('0.1.0 → 0.2.0'), findsOneWidget);
    expect(
      find.textContaining('支持应用内检查更新', findRichText: true),
      findsOneWidget,
    );
    for (final key in [
      'update_windows_installer',
      'update_windows_portable',
      'update_release_github',
    ]) {
      await tester.tap(find.byKey(Key(key)));
      await tester.pumpAndSettle();
    }
    expect(opened[0].path, endsWith('/Reelva-0.2.0-windows-x64-installer.exe'));
    expect(opened[1].path, endsWith('/Reelva-0.2.0-windows-x64.zip'));
    expect(opened[2].path, endsWith('/tag/v0.2.0'));
    await tester.tap(find.byKey(const Key('update_dialog_close')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('github_repository_button')));
    await tester.pumpAndSettle();
    expect(opened.last, GithubReleaseClient.repositoryUrl);
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

  testWidgets('没有更新显示统一提示，网络错误允许再次检查', (tester) async {
    var attempt = 0;
    final client = GithubReleaseClient(
      dio: Dio()
        ..httpClientAdapter = UpdateHttpAdapter((_) {
          attempt++;
          return attempt == 1
              ? jsonResponse({}, status: 503)
              : jsonResponse({}, status: 404);
        }),
    );
    addTearDown(client.close);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [githubReleaseClientProvider.overrideWithValue(client)],
        child: MaterialApp(
          theme: ReelvaTheme.light,
          home: const Scaffold(body: UpdateSettingsCard()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('check_update_button')));
    await tester.pumpAndSettle();
    expect(find.text('检查更新失败，请稍后重试'), findsOneWidget);
    final errorNotice = tester.widget<SnackBar>(find.byType(SnackBar));
    final noticeTheme = Theme.of(tester.element(find.byType(SnackBar)))
        .snackBarTheme;
    expect(
      errorNotice.behavior ?? noticeTheme.behavior,
      SnackBarBehavior.floating,
    );
    final noticeSurface = find
        .descendant(of: find.byType(SnackBar), matching: find.byType(Material))
        .first;
    final noticeBounds = tester.getRect(noticeSurface);
    final scaffoldBounds = tester.getRect(find.byType(Scaffold));
    expect(noticeBounds.left, greaterThan(scaffoldBounds.left));
    expect(noticeBounds.right, lessThan(scaffoldBounds.right));
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('check_update_button')));
    await tester.pumpAndSettle();
    expect(find.text('暂无新版本'), findsOneWidget);
    expect(
      tester.widget<SnackBar>(find.byType(SnackBar)).behavior ??
          noticeTheme.behavior,
      SnackBarBehavior.floating,
    );
    expect(attempt, 2);
  });

  testWidgets(
    '限流后仍能提示新版本，并打开对应发布页下载',
    (tester) async {
      final client = GithubReleaseClient(
        dio: Dio()
          ..httpClientAdapter = UpdateHttpAdapter((options) {
            return options.uri.host == 'api.github.com'
                ? jsonResponse({}, status: 403)
                : atomResponse(['0.2.0']);
          }),
      );
      addTearDown(client.close);
      final opened = <Uri>[];
      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (_, _) => const Scaffold(body: UpdateSettingsCard()),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            githubReleaseClientProvider.overrideWithValue(client),
            openUpdateUrlProvider.overrideWithValue(
              (uri) async => opened.add(uri),
            ),
            updateAbisProvider.overrideWith(
              (ref) => throw StateError('无需识别架构'),
            ),
          ],
          child: MaterialApp.router(
            theme: ReelvaTheme.light,
            routerConfig: router,
            builder: (context, child) =>
                UpdatePromptHost(router: router, child: child!),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('check_update_button')));
      await tester.pumpAndSettle();
      expect(find.text('0.1.0 → 0.2.0'), findsOneWidget);
      expect(find.text('在 GitHub 查看并下载'), findsOneWidget);
      expect(find.byKey(const Key('update_android_apk')), findsNothing);
      expect(find.byKey(const Key('update_windows_installer')), findsNothing);
      expect(find.byKey(const Key('update_windows_portable')), findsNothing);
      await tester.tap(find.byKey(const Key('update_release_github')));
      await tester.pumpAndSettle();
      expect(
        opened.single.toString(),
        'https://github.com/miludeshiji/Reelva/releases/tag/v0.2.0',
      );
      expect(tester.takeException(), isNull);
    },
    variant: const TargetPlatformVariant({
      TargetPlatform.android,
      TargetPlatform.windows,
    }),
  );

  testWidgets('启动自动检查，播放期间延后至返回时提示且只弹一次', (tester) async {
    FlutterSecureStorage.setMockInitialValues({});
    final response = Completer<ResponseBody>();
    final adapter = UpdateHttpAdapter((_) => response.future);
    final client = GithubReleaseClient(dio: Dio()..httpClientAdapter = adapter);
    addTearDown(client.close);
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => const Scaffold(body: Text('首页')),
        ),
        GoRoute(
          path: '/player',
          builder: (_, _) => const Scaffold(body: Text('播放')),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [githubReleaseClientProvider.overrideWithValue(client)],
        child: MaterialApp.router(
          routerConfig: router,
          builder: (context, child) =>
              UpdatePromptHost(router: router, child: child!),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(adapter.requests, hasLength(1));
    unawaited(router.push<void>('/player'));
    await tester.pumpAndSettle();
    response.complete(jsonResponse(releaseJson('0.2.0')));
    await tester.pumpAndSettle();
    expect(find.byType(AppUpdateDialog), findsNothing);
    router.pop();
    await tester.pumpAndSettle();
    expect(find.byType(AppUpdateDialog), findsOneWidget);
    await tester.tap(find.byKey(const Key('update_dialog_close')));
    await tester.pumpAndSettle();
    unawaited(router.push<void>('/player'));
    await tester.pumpAndSettle();
    router.pop();
    await tester.pumpAndSettle();
    expect(find.byType(AppUpdateDialog), findsNothing);
    expect(adapter.requests, hasLength(1));
  });

  testWidgets('关于页读取实际版本，自动检查开关可持久保存', (tester) async {
    PackageInfo.setMockInitialValues(
      appName: 'Reelva',
      packageName: 'com.github.miludeshiji.reelva',
      version: '1.2.3-beta10',
      buildNumber: '42',
      buildSignature: '',
    );
    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: AboutPage())),
    );
    await tester.pumpAndSettle();
    expect(find.text('版本 1.2.3-beta10 (Build 42)'), findsOneWidget);
    final toggle = find.byKey(const Key('automatic_update_switch'));
    final github = tester.getRect(
      find.byKey(const Key('github_repository_button')),
    );
    final check = tester.getRect(find.byKey(const Key('check_update_button')));
    expect(tester.getRect(toggle).bottom, lessThan(github.top));
    expect(github.center.dy, check.center.dy);
    expect(check.left - github.right, ReelvaDesign.space12);
    await tester.ensureVisible(toggle);
    await tester.tap(
      find.descendant(of: toggle, matching: find.byType(Switch)),
    );
    await tester.pumpAndSettle();
    expect((await const UpdatePreferencesStore().read()).automatic, isTrue);
  });

  testWidgets('320px 大字弹窗完整可滚动，Android 仅提供适用 APK 和 GitHub', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 568);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final release = AppRelease.fromJson(
      releaseJson('0.2.0'),
      AppVersion.tryParse('0.2.0')!,
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          updateAbisProvider.overrideWith(
            (ref) async => ['arm64-v8a', 'armeabi-v7a'],
          ),
        ],
        child: MaterialApp(
          theme: ReelvaTheme.light,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(1.5)),
            child: child!,
          ),
          home: Scaffold(
            body: AppUpdateDialog(release: release, currentVersion: '0.1.0'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('下载并安装（arm64-v8a）'), findsOneWidget);
    expect(find.byKey(const Key('update_windows_installer')), findsNothing);
    await tester.ensureVisible(find.byKey(const Key('update_release_github')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));

  testWidgets('Android 下载校验完成才交付安装器，拒绝授权后重试复用文件', (tester) async {
    final directory = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('reelva-update-ui-'),
    ))!;
    addTearDown(() => directory.delete(recursive: true));
    final adapter = UpdateHttpAdapter(
      (_) => ResponseBody.fromString(
        'abc',
        200,
        headers: {
          Headers.contentLengthHeader: ['3'],
        },
      ),
    );
    final downloader = ApkDownloader(
      dio: Dio()..httpClientAdapter = adapter,
      temporaryDirectory: () async => directory,
    );
    addTearDown(downloader.close);
    final installPaths = <String>[];
    var grant = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('reelva/app_update'), (
          call,
        ) async {
          if (call.method == 'supportedAbis') {
            return ['arm64-v8a', 'armeabi-v7a'];
          }
          installPaths.add((call.arguments as Map)['path'] as String);
          return grant;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('reelva/app_update'),
            null,
          ),
    );
    final release = AppRelease.fromJson(
      releaseJson('0.2.0'),
      AppVersion.tryParse('0.2.0')!,
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [apkDownloaderProvider.overrideWithValue(downloader)],
        child: MaterialApp(
          home: Scaffold(
            body: AppUpdateDialog(release: release, currentVersion: '0.1.0'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const Key('update_android_apk')));
      for (var i = 0; i < 50 && installPaths.isEmpty; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    });
    await tester.pumpAndSettle();
    expect(installPaths, hasLength(1));
    expect(
      await tester.runAsync(() => File(installPaths.single).readAsString()),
      'abc',
    );
    expect(find.text('继续安装'), findsOneWidget);
    grant = true;
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const Key('update_android_apk')));
      for (var i = 0; i < 50 && installPaths.length < 2; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    });
    await tester.pumpAndSettle();
    expect(installPaths, [installPaths.first, installPaths.first]);
    expect(adapter.requests, hasLength(1));
    expect(find.text('已打开系统安装界面'), findsOneWidget);
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));
}
