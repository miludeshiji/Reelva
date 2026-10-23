import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reelva/core/database/app_database.dart';
import 'package:reelva/features/library/infrastructure/media_library_repository.dart';
import 'package:reelva/features/player/domain/playback_resource.dart';
import 'package:reelva/features/sources/application/source_providers.dart';
import 'package:reelva/features/sources/domain/media_source_adapter.dart';
import 'package:reelva/features/sources/domain/source_models.dart';
import 'package:reelva/features/sources/infrastructure/remote_credentials_store.dart';
import 'package:reelva/features/sources/remote_source_dialog.dart';
import 'package:reelva/features/sources/sources_page.dart';

import '../sources/infrastructure/remote_credentials_store_test.dart';

class _FakeStubAdapter implements MediaSourceAdapter {
  const _FakeStubAdapter(this.kind);

  @override
  final String kind;

  @override
  Future<DirectorySelection?> pickDirectory({String? initialLocator}) async {
    return kind == 'local' || kind == 'androidSaf'
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

  Widget buildTestApp() {
    return ProviderScope(
      overrides: [
        platformOverrideProvider.overrideWithValue(TargetPlatform.windows),
        appDatabaseProvider.overrideWithValue(db),
        mediaLibraryRepositoryProvider.overrideWithValue(repo),
        remoteCredentialsStoreProvider.overrideWithValue(credStore),
        sourceAdaptersProvider.overrideWithValue({
          'local': const _FakeStubAdapter('local'),
          'androidSaf': const _FakeStubAdapter('androidSaf'),
          'webdav': const _FakeStubAdapter('webdav'),
        }),
      ],
      child: const MaterialApp(home: SourcesPage()),
    );
  }

  testWidgets('添加弹窗默认展示本地配置并保留原有交互', (tester) async {
    try {
      await tester.pumpWidget(buildTestApp());
      await tester.pumpAndSettle();

      final fab = find.byKey(const Key('sources_add_fab'));
      expect(fab, findsOneWidget);
      await tester.tap(fab);
      await tester.pumpAndSettle();

      // 默认类型下拉值为本地目录
      expect(find.text('本地目录'), findsOneWidget);

      // 原有的本地字段与确认按钮均存在
      expect(find.byKey(const Key('add_source_name_field')), findsOneWidget);
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
      expect(find.text('选择目录'), findsOneWidget);

      // 点击选择目录完成添加
      await tester.tap(confirmBtn);
      await tester.pumpAndSettle();

      expect(find.text('本地视频目录'), findsOneWidget);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(Duration.zero);
    }
  });

  testWidgets('切换至远程类型呈现安全脱敏表单并支持添加', (tester) async {
    try {
      await tester.pumpWidget(buildTestApp());
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('sources_add_fab')));
      await tester.pumpAndSettle();

      // 切换至 WebDAV
      final typeDropdown = find.byKey(const Key('add_source_type_dropdown'));
      await tester.tap(typeDropdown);
      await tester.pumpAndSettle();

      await tester.tap(find.text('WebDAV').last);
      await tester.pumpAndSettle();

      // 确认 URL 字段出现
      expect(find.byKey(const Key('remote_source_url_field')), findsOneWidget);
      expect(
        find.byKey(const Key('remote_source_username_field')),
        findsOneWidget,
      );

      final passFinder = find.byKey(const Key('remote_source_password_field'));
      expect(passFinder, findsOneWidget);
      final passWidget = tester.widget<TextField>(passFinder);
      expect(passWidget.obscureText, isTrue); // 密码密文遮蔽

      // 输入 WebDAV 地址并确认添加
      await tester.enterText(
        find.byKey(const Key('remote_source_url_field')),
        'https://dav.test.local/movies/',
      );
      await tester.enterText(
        find.byKey(const Key('add_source_name_field')),
        '远程 WebDAV',
      );
      await tester.enterText(passFinder, 'my_secret_pwd');

      final confirmBtn = find.byKey(const Key('add_source_confirm_button'));
      expect(find.text('添加'), findsOneWidget);
      await tester.tap(confirmBtn);
      await tester.pumpAndSettle();

      expect(find.text('远程 WebDAV'), findsOneWidget);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(Duration.zero);
    }
  });

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
