import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reelva/app/router.dart';
import 'package:reelva/app/theme/reelva_theme.dart';
import 'package:reelva/core/database/app_database.dart';
import 'package:reelva/features/library/infrastructure/media_library_repository.dart';
import 'package:reelva/features/player/domain/playback_resource.dart';
import 'package:reelva/features/sources/application/source_providers.dart';
import 'package:reelva/features/sources/add_source_page.dart';
import 'package:reelva/features/sources/domain/media_source_adapter.dart';
import 'package:reelva/features/sources/domain/source_models.dart';
import 'package:reelva/features/sources/infrastructure/remote_credentials_store.dart';
import 'package:reelva/features/sources/remote_source_dialog.dart';
import 'package:reelva/features/sources/source_setup_page.dart';
import 'package:reelva/features/sources/sources_page.dart';

import '../sources/infrastructure/remote_credentials_store_test.dart';

class _FakeStubAdapter implements MediaSourceAdapter {
  const _FakeStubAdapter(this.kind, {this.cancelDirectorySelection = false});

  final bool cancelDirectorySelection;

  @override
  final String kind;

  @override
  Future<DirectorySelection?> pickDirectory({String? initialLocator}) async {
    return !cancelDirectorySelection &&
            (kind == 'local' || kind == 'androidSaf')
        ? const DirectorySelection(
            kind: 'local',
            rootLocator: 'C:/TestVideos',
            name: '本地视频目录',
          )
        : null;
  }

  @override
  Stream<MediaEntry> listEntries(
    MediaSourceConfig source,
    String directoryId,
  ) => const Stream.empty();

  @override
  Future<MediaStat> stat(MediaSourceConfig source, String entryId) async =>
      const MediaStat();

  @override
  Future<PlaybackResource> resolvePlayback(
    MediaSourceConfig source,
    String entryId,
  ) async => throw UnimplementedError();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late MediaLibraryRepository repo;
  late FakeFlutterSecureStorage fakeStorage;
  late RemoteCredentialsStore credStore;

  setUp(() {
    db = AppDatabase(executor: NativeDatabase.memory());
    repo = MediaLibraryRepository(db);
    fakeStorage = FakeFlutterSecureStorage();
    credStore = RemoteCredentialsStore(storage: fakeStorage);
  });

  tearDown(() async {
    await db.close();
  });

  Widget buildTestApp({bool cancelDirectorySelection = false}) {
    final router = createRouter(initialLocation: '/sources');
    addTearDown(router.dispose);
    return ProviderScope(
      overrides: [
        platformOverrideProvider.overrideWithValue(TargetPlatform.windows),
        appDatabaseProvider.overrideWithValue(db),
        mediaLibraryRepositoryProvider.overrideWithValue(repo),
        remoteCredentialsStoreProvider.overrideWithValue(credStore),
        sourceAdaptersProvider.overrideWithValue({
          'local': _FakeStubAdapter(
            'local',
            cancelDirectorySelection: cancelDirectorySelection,
          ),
          'androidSaf': const _FakeStubAdapter('androidSaf'),
          'webdav': const _FakeStubAdapter('webdav'),
          'openlist': const _FakeStubAdapter('openlist'),
          'smb': const _FakeStubAdapter('smb'),
        }),
      ],
      child: MaterialApp.router(theme: ReelvaTheme.light, routerConfig: router),
    );
  }

  testWidgets('列表卡片选择本地目录后在独立配置页添加并返回媒体源', (tester) async {
    try {
      await tester.pumpWidget(buildTestApp());
      expect(find.byType(FloatingActionButton), findsNothing);
      await tester.pumpAndSettle();
      expect(find.byType(FloatingActionButton), findsNothing);

      final addButton = find.byKey(const Key('sources_add_appbar_button'));
      expect(addButton, findsOneWidget);
      await tester.tap(addButton);
      await tester.pumpAndSettle();

      expect(find.byType(AddSourcePage), findsOneWidget);
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('本地目录'), findsOneWidget);
      for (final kind in SourceSetupKind.values) {
        expect(find.byKey(Key('add_source_type_${kind.name}')), findsOneWidget);
      }
      expect(find.byType(TextFormField), findsNothing);
      await tester.tap(find.byKey(const Key('add_source_type_local')));
      await tester.pumpAndSettle();
      expect(find.byType(SourceSetupPage), findsOneWidget);

      expect(find.byKey(const Key('add_source_name_field')), findsOneWidget);
      expect(find.byKey(const Key('remote_source_url_field')), findsNothing);
      expect(
        find.byKey(const Key('add_source_extensions_field')).hitTestable(),
        findsNothing,
      );
      await tester.tap(find.byKey(const Key('add_source_advanced_options')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('add_source_extensions_field')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('add_source_excluded_field')),
        findsOneWidget,
      );

      final confirmBtn = find.byKey(const Key('add_source_confirm_button'));
      expect(confirmBtn, findsOneWidget);
      expect(find.text('选择目录并添加'), findsOneWidget);

      await tester.ensureVisible(confirmBtn);
      await tester.tap(confirmBtn);
      await tester.pumpAndSettle();

      expect(find.text('本地视频目录'), findsOneWidget);
      expect(find.byType(SourcesPage), findsOneWidget);
      expect(find.byType(SourceSetupPage), findsNothing);
      expect(find.byType(AddSourcePage), findsNothing);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(Duration.zero);
    }
  });

  testWidgets('WebDAV 配置校验保留输入并通过原有安全存储完成添加', (tester) async {
    try {
      await tester.pumpWidget(buildTestApp());
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('sources_add_appbar_button')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('add_source_type_webdav')));
      await tester.pumpAndSettle();

      // 确认 URL 字段出现
      expect(find.byKey(const Key('remote_source_url_field')), findsOneWidget);
      expect(
        find.byKey(const Key('remote_source_username_field')),
        findsOneWidget,
      );

      final passFinder = find.byKey(const Key('remote_source_password_field'));
      expect(passFinder, findsOneWidget);
      final passWidget = tester.widget<TextField>(
        find.descendant(of: passFinder, matching: find.byType(TextField)),
      );
      expect(passWidget.obscureText, isTrue); // 密码密文遮蔽

      await tester.enterText(
        find.byKey(const Key('add_source_name_field')),
        '远程 WebDAV',
      );
      await tester.enterText(passFinder, 'my_secret_pwd');
      final confirmBtn = find.byKey(const Key('add_source_confirm_button'));
      await tester.ensureVisible(confirmBtn);
      await tester.tap(confirmBtn);
      await tester.pumpAndSettle();
      expect(find.text('请输入根目录地址'), findsOneWidget);
      expect(
        tester.widget<TextFormField>(passFinder).controller!.text,
        'my_secret_pwd',
      );
      await tester.enterText(
        find.byKey(const Key('remote_source_url_field')),
        'invalid-address',
      );
      await tester.ensureVisible(confirmBtn);
      await tester.tap(confirmBtn);
      await tester.pumpAndSettle();
      expect(
        find.text('WebDAV 地址必须是以 http:// 或 https:// 开头的有效网址'),
        findsOneWidget,
      );

      await tester.enterText(
        find.byKey(const Key('remote_source_url_field')),
        'https://dav.test.local/movies/',
      );
      await tester.ensureVisible(confirmBtn);
      await tester.tap(confirmBtn);
      await tester.pumpAndSettle();

      expect(find.text('远程 WebDAV'), findsOneWidget);
      final sources = await tester.runAsync(() => repo.watchSources().first);
      final credentials = await tester.runAsync(
        () => credStore.read(sources!.single.credentialRef!),
      );
      expect(credentials!.password, 'my_secret_pwd');
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(Duration.zero);
    }
  });

  testWidgets('配置页和来源选择页逐级返回媒体源', (tester) async {
    try {
      await tester.pumpWidget(buildTestApp());
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('sources_add_card')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('add_source_type_webdav')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('source_setup_back_button')));
      await tester.pumpAndSettle();
      expect(find.byType(AddSourcePage), findsOneWidget);
      await tester.tap(find.byKey(const Key('add_source_back_button')));
      await tester.pumpAndSettle();
      expect(find.byType(SourcesPage), findsOneWidget);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(Duration.zero);
    }
  });

  testWidgets('取消系统目录选择会保留配置页且不创建媒体源', (tester) async {
    try {
      await tester.pumpWidget(buildTestApp(cancelDirectorySelection: true));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('sources_add_appbar_button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('add_source_type_local')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('add_source_name_field')),
        '保留的目录名称',
      );
      final confirm = find.byKey(const Key('add_source_confirm_button'));
      await tester.ensureVisible(confirm);
      await tester.tap(confirm);
      await tester.pumpAndSettle();
      expect(find.byType(SourceSetupPage), findsOneWidget);
      expect(
        tester
            .widget<TextFormField>(
              find.byKey(const Key('add_source_name_field')),
            )
            .controller!
            .text,
        '保留的目录名称',
      );
      expect(tester.widget<FilledButton>(confirm).onPressed, isNotNull);
      final sources = await tester.runAsync(() => repo.watchSources().first);
      expect(sources, isEmpty);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(Duration.zero);
    }
  });

  testWidgets('移动端键盘展开后配置页仍可滚动到提交操作', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetViewInsets);
    try {
      await tester.pumpWidget(buildTestApp());
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('sources_add_appbar_button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('add_source_type_webdav')));
      await tester.pumpAndSettle();
      final password = find.byKey(const Key('remote_source_password_field'));
      await tester.ensureVisible(password);
      await tester.tap(password);
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      await tester.pumpAndSettle();
      final confirm = find.byKey(const Key('add_source_confirm_button'));
      await tester.ensureVisible(confirm);
      await tester.pumpAndSettle();
      expect(confirm.hitTestable(), findsOneWidget);
      expect(tester.getRect(confirm).bottom, lessThanOrEqualTo(544));
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(Duration.zero);
    }
  });

  testWidgets('Windows 宽窄窗口切换保留表单输入和高级选项展开状态', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1440, 900);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    try {
      await tester.pumpWidget(buildTestApp());
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('sources_add_appbar_button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('add_source_type_webdav')));
      await tester.pumpAndSettle();
      final pageState = tester.state(find.byType(SourceSetupPage));
      final address = find.byKey(const Key('remote_source_url_field'));
      await tester.enterText(address, 'https://dav.example.com/movies/');
      await tester.tap(find.byKey(const Key('add_source_advanced_options')));
      await tester.pumpAndSettle();
      final extensions = find.byKey(const Key('add_source_extensions_field'));
      await tester.enterText(extensions, 'mkv, mp4, webm');
      final connection = find.byKey(const Key('source_setup_connection_card'));
      final advanced = find.byKey(const Key('source_setup_advanced_card'));
      expect(tester.getTopLeft(connection).dy, tester.getTopLeft(advanced).dy);

      tester.view.physicalSize = const Size(390, 844);
      await tester.pumpAndSettle();
      expect(tester.state(find.byType(SourceSetupPage)), same(pageState));
      expect(
        tester.widget<TextFormField>(address).controller!.text,
        'https://dav.example.com/movies/',
      );
      expect(
        tester.widget<TextFormField>(extensions).controller!.text,
        'mkv, mp4, webm',
      );
      expect(
        tester.getTopLeft(advanced).dy,
        greaterThan(tester.getBottomRight(connection).dy),
      );
      final confirm = find.byKey(const Key('add_source_confirm_button'));
      await tester.ensureVisible(confirm);
      await tester.pumpAndSettle();
      expect(confirm.hitTestable(), findsOneWidget);

      tester.view.physicalSize = const Size(1440, 900);
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(connection).dy, tester.getTopLeft(advanced).dy);
      expect(
        tester.widget<TextFormField>(extensions).controller!.text,
        'mkv, mp4, webm',
      );
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(Duration.zero);
    }
  });

  for (final kind in [SourceSetupKind.openlist, SourceSetupKind.smb]) {
    testWidgets('${kind.label} 独立配置保留凭据、路径和高级扫描选项', (tester) async {
      try {
        await tester.pumpWidget(buildTestApp());
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('sources_add_appbar_button')));
        await tester.pumpAndSettle();
        final choice = find.byKey(Key('add_source_type_${kind.name}'));
        await tester.ensureVisible(choice);
        await tester.tap(choice);
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const Key('remote_source_url_field')),
          kind == SourceSetupKind.openlist
              ? 'https://files.example/base'
              : 'smb://nas.example/Movies',
        );
        if (kind == SourceSetupKind.openlist) {
          final token = find.byKey(const Key('remote_source_token_field'));
          expect(
            tester
                .widget<TextField>(
                  find.descendant(of: token, matching: find.byType(TextField)),
                )
                .obscureText,
            isTrue,
          );
          await tester.enterText(token, 'test-token');
          await tester.enterText(
            find.byKey(const Key('remote_source_openlist_path_field')),
            '/Movies',
          );
        } else {
          expect(
            find.byKey(const Key('remote_source_token_field')),
            findsNothing,
          );
          await tester.enterText(
            find.byKey(const Key('remote_source_username_field')),
            'viewer',
          );
          await tester.enterText(
            find.byKey(const Key('remote_source_password_field')),
            'test-password',
          );
        }
        final advanced = find.byKey(const Key('add_source_advanced_options'));
        await tester.ensureVisible(advanced);
        await tester.tap(advanced);
        await tester.pumpAndSettle();
        final credentialField = find.byKey(
          Key(
            kind == SourceSetupKind.openlist
                ? 'remote_source_user_agent_field'
                : 'remote_source_domain_field',
          ),
        );
        await tester.ensureVisible(credentialField);
        await tester.enterText(
          credentialField,
          kind == SourceSetupKind.openlist ? 'Reelva Test' : 'WORKGROUP',
        );
        final extensions = find.byKey(const Key('add_source_extensions_field'));
        await tester.ensureVisible(extensions);
        await tester.enterText(extensions, 'mp4, mkv');
        final excluded = find.byKey(const Key('add_source_excluded_field'));
        await tester.ensureVisible(excluded);
        await tester.enterText(excluded, 'Trailers');
        final confirm = find.byKey(const Key('add_source_confirm_button'));
        await tester.ensureVisible(confirm);
        await tester.tap(confirm);
        await tester.pumpAndSettle();
        expect(find.byType(SourcesPage), findsOneWidget);
        final sources = await tester.runAsync(() => repo.watchSources().first);
        final source = sources!.single;
        expect(source.kind, kind.name);
        expect(source.extensions, ['mp4', 'mkv']);
        expect(source.excludedDirectories, ['Trailers']);
        final credentials = await tester.runAsync(
          () => credStore.read(source.credentialRef!),
        );
        if (kind == SourceSetupKind.openlist) {
          expect(source.rootLocator, 'https://files.example/base#/Movies');
          expect(credentials!.token, 'test-token');
          expect(credentials.playbackHeaders['User-Agent'], 'Reelva Test');
        } else {
          expect(credentials!.domain, 'WORKGROUP');
        }
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(Duration.zero);
      }
    });
  }

  testWidgets('远程源卡片操作呈现“修改凭据”，根目录稳定不可编辑且机密字段不预填', (tester) async {
    try {
      // 预置一个带有凭据的 WebDAV 源
      await credStore.write(
        'cred_test_1',
        const RemoteCredentials(username: 'admin', password: 'old_secret_pwd'),
      );
      await repo.upsertSource(
        kind: 'webdav',
        rootLocator: 'https://nas.lan/dav/',
        name: '家庭 NAS',
        credentialRef: 'cred_test_1',
      );

      await tester.pumpWidget(buildTestApp());
      await tester.pumpAndSettle();

      expect(find.text('家庭 NAS'), findsOneWidget);

      // 弹出菜单中包含“修改凭据”而非“重新授权”
      final menuBtn = find.byKey(const Key('source_menu_button_1'));
      expect(menuBtn, findsOneWidget);
      await tester.tap(menuBtn);
      await tester.pumpAndSettle();

      expect(find.text('修改凭据'), findsOneWidget);
      expect(find.text('重新授权'), findsNothing);

      await tester.tap(find.text('修改凭据'));
      await tester.pumpAndSettle();

      // 弹窗中呈现稳定的根目录只读文本
      expect(find.byType(EditCredentialsDialog), findsOneWidget);
      expect(find.text('https://nas.lan/dav/'), findsOneWidget);

      // 密码输入框初始为空且密文遮蔽（绝不预填旧密码）
      final editPassFinder = find.byKey(
        const Key('edit_credentials_password_field'),
      );
      expect(editPassFinder, findsOneWidget);
      final editPassWidget = tester.widget<TextField>(editPassFinder);
      expect(editPassWidget.obscureText, isTrue);
      expect(editPassWidget.controller?.text ?? '', isEmpty);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(Duration.zero);
    }
  });
}
