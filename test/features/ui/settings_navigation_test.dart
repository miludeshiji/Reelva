import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reelva/app/router.dart';
import 'package:reelva/app/theme/reelva_theme.dart';
import 'package:reelva/features/metadata/application/metadata_providers.dart';
import 'package:reelva/features/metadata/infrastructure/tmdb_token_store.dart';
import 'package:reelva/features/settings/settings_page.dart';
import 'package:reelva/features/settings/player_settings_page.dart';
import 'package:reelva/features/settings/player_shortcuts_page.dart';
import 'package:reelva/features/settings/settings_subpages.dart';
import 'package:reelva/features/sync/application/sync_providers.dart';
import 'package:reelva/features/sync/application/sync_service.dart';
import 'package:reelva/features/sync/domain/sync_models.dart';
import 'package:reelva/features/sync/infrastructure/sync_configuration_store.dart';
import 'package:reelva/features/sync/infrastructure/sync_repository.dart';
import 'package:reelva/shared/widgets/glass_navigation.dart';

class _TokenStore extends TmdbTokenStore {
  String? token;

  @override
  Future<String?> read() async => token;

  @override
  Future<void> save(String rawToken) async => token = rawToken;

  @override
  Future<void> delete() async => token = null;
}

class _MetadataController extends MetadataController {
  int refreshCount = 0;

  @override
  MetadataTaskState build() => const MetadataTaskState();

  @override
  Future<void> refresh() async => refreshCount++;
}

class _SyncStore implements SyncConfigurationStore {
  SyncConfiguration? configuration;

  @override
  Future<SyncConfiguration?> read() async => configuration;

  @override
  Future<void> save(SyncConfiguration value) async => configuration = value;

  @override
  Future<void> delete() async => configuration = null;
}

class _SyncRepository implements SyncRepository {
  @override
  Future<void> resetTransport() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _SyncService implements SyncService {
  int synchronizeCount = 0;

  @override
  Future<SyncReport> synchronize() async {
    synchronizeCount++;
    return const SyncReport(
      uploaded: 0,
      downloaded: 0,
      applied: 0,
      pending: 0,
      localOnly: 0,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late _TokenStore tokenStore;
  late _MetadataController metadataController;
  late _SyncStore syncStore;
  late _SyncService syncService;

  setUp(() {
    tokenStore = _TokenStore();
    metadataController = _MetadataController();
    syncStore = _SyncStore();
    syncService = _SyncService();
  });

  Widget buildTestApp() {
    final router = createRouter(initialLocation: '/settings');
    addTearDown(router.dispose);
    return ProviderScope(
      overrides: [
        tmdbTokenStoreProvider.overrideWithValue(tokenStore),
        metadataControllerProvider.overrideWith(() => metadataController),
        syncConfigurationStoreProvider.overrideWithValue(syncStore),
        syncRepositoryProvider.overrideWithValue(_SyncRepository()),
        syncServiceProvider.overrideWith((ref, configuration) => syncService),
        pendingSourceBindingsProvider.overrideWith((ref) async => []),
      ],
      child: MaterialApp.router(theme: ReelvaTheme.light, routerConfig: router),
    );
  }

  testWidgets('五个设置入口打开独立子页并在返回后保留主页滚动位置', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 568);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    try {
      await tester.pumpWidget(buildTestApp());
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsNothing);
      for (final entry in [
        (key: 'settings_player_tile', type: PlayerSettingsPage),
        (key: 'settings_shortcuts_tile', type: PlayerShortcutsPage),
        (key: 'settings_tmdb_tile', type: TmdbSettingsPage),
        (key: 'settings_sync_tile', type: SyncSettingsPage),
        (key: 'settings_cache_tile', type: PosterCacheSettingsPage),
      ]) {
        final tile = find.byKey(Key(entry.key));
        await tester.ensureVisible(tile);
        await tester.pumpAndSettle();
        final scrollable = tester.state<ScrollableState>(
          find
              .descendant(
                of: find.byType(SettingsPage),
                matching: find.byType(Scrollable),
              )
              .first,
        );
        final offset = scrollable.position.pixels;
        await tester.tap(tile);
        await tester.pumpAndSettle();
        expect(find.byType(entry.type), findsOneWidget);
        expect(find.byType(SettingsPage), findsNothing);
        expect(find.byType(GlassBottomNavigationBar), findsNothing);
        await tester.tap(find.byKey(const Key('settings_subpage_back_button')));
        await tester.pumpAndSettle();
        expect(find.byType(SettingsPage), findsOneWidget);
        expect(scrollable.mounted, isTrue);
        expect(scrollable.position.pixels, offset);
        expect(find.byType(GlassBottomNavigationBar), findsOneWidget);
      }
      expect(syncService.synchronizeCount, 0);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    }
  });

  testWidgets('TMDB 子页保存清除凭据并更新主页摘要且不回显秘密', (tester) async {
    try {
      await tester.pumpWidget(buildTestApp());
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('settings_tmdb_tile')));
      await tester.pumpAndSettle();
      final input = find.byKey(const Key('tmdb_token_input'));
      expect(tester.widget<TextField>(input).obscureText, isTrue);
      await tester.enterText(input, '0123456789abcdef0123456789abcdef');
      final save = find.byKey(const Key('tmdb_save_button'));
      await tester.ensureVisible(save);
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(tokenStore.token, '0123456789abcdef0123456789abcdef');
      expect(metadataController.refreshCount, 0);
      expect(tester.widget<TextField>(input).controller!.text, isEmpty);
      await tester.tap(find.byKey(const Key('settings_subpage_back_button')));
      await tester.pumpAndSettle();
      expect(find.text('已配置 · 管理 API 凭据'), findsOneWidget);
      await tester.tap(find.byKey(const Key('settings_tmdb_tile')));
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(input).controller!.text, isEmpty);
      final delete = find.byKey(const Key('tmdb_delete_button'));
      await tester.ensureVisible(delete);
      await tester.tap(delete);
      await tester.pumpAndSettle();
      await tester.tap(find.text('确认移除'));
      await tester.pumpAndSettle();
      expect(tokenStore.token, isNull);
      await tester.tap(find.byKey(const Key('settings_subpage_back_button')));
      await tester.pumpAndSettle();
      expect(find.text('未配置 · 设置 API 凭据'), findsOneWidget);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    }
  });

  testWidgets('同步子页复用配置保存与手动同步且进入页面不发起同步', (tester) async {
    syncStore.configuration = SyncConfiguration(
      endpoint: Uri.parse('https://dav.example.com/sync/'),
      username: 'viewer',
      password: 'saved-password',
    );
    try {
      await tester.pumpWidget(buildTestApp());
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('settings_sync_tile')));
      await tester.pumpAndSettle();
      expect(syncService.synchronizeCount, 0);
      final password = find.byKey(const Key('sync_password'));
      expect(tester.widget<TextField>(password).controller!.text, isEmpty);
      expect(tester.widget<TextField>(password).obscureText, isTrue);
      await tester.enterText(
        find.byKey(const Key('sync_endpoint')),
        'https://dav.example.com/new-sync/',
      );
      await tester.enterText(password, 'new-password');
      final save = find.byKey(const Key('sync_save'));
      await tester.ensureVisible(save);
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(syncStore.configuration!.endpoint.path, '/new-sync/');
      expect(syncStore.configuration!.password, 'new-password');
      expect(syncService.synchronizeCount, 0);
      final synchronize = find.byKey(const Key('sync_now'));
      await tester.ensureVisible(synchronize);
      await tester.tap(synchronize);
      await tester.pumpAndSettle();
      expect(syncService.synchronizeCount, 1);
      await tester.tap(find.byKey(const Key('settings_subpage_back_button')));
      await tester.pumpAndSettle();
      expect(find.text('已配置 · WebDAV 手动同步'), findsOneWidget);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    }
  });
}
