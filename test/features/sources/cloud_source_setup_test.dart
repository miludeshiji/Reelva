import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:reelva/app/theme/reelva_theme.dart';
import 'package:reelva/features/sources/application/source_providers.dart';
import 'package:reelva/features/sources/cloud_source_setup_page.dart';
import 'package:reelva/features/sources/domain/openlist_models.dart';
import 'package:reelva/features/sources/domain/source_models.dart';
import 'package:reelva/features/sources/infrastructure/openlist_rpc.dart';
import 'package:reelva/features/sources/infrastructure/openlist_service.dart';
import 'package:reelva/features/sources/infrastructure/remote_credentials_store.dart';
import 'package:reelva/features/sources/source_setup_page.dart';

const _accountId = '0123456789abcdef0123456789abcdef';

class _UnusedRpc implements OpenListRpcClient {
  @override
  Future<Map<String, dynamic>> invoke(
    String method,
    Map<String, dynamic> arguments,
  ) async => throw UnimplementedError();
}

class _FakeService extends OpenListService {
  _FakeService()
    : super(rpc: _UnusedRpc(), credentials: RemoteCredentialsStore());

  final saved = <Map<String, dynamic>>[];
  final deleted = <String>[];
  final listed = <String>[];
  bool failList = false;
  bool invalidGrant = false;

  @override
  Future<String> saveAccount({
    String? accountId,
    required String driver,
    required String name,
    required Map<String, dynamic> addition,
  }) async {
    if (invalidGrant) {
      throw const MediaSourceException(
        'private grant message',
        code: 'invalid_grant',
      );
    }
    saved.add({
      'accountId': accountId,
      'driver': driver,
      'name': name,
      'addition': addition,
    });
    return accountId ?? _accountId;
  }

  @override
  Future<List<OpenListEntry>> list(
    String accountId,
    String path, {
    bool refresh = false,
    String? taskId,
  }) async {
    listed.add(path);
    if (failList) throw const MediaSourceException('不应向界面回显的原始错误');
    return path == '/'
        ? const [
            OpenListEntry(name: 'Movies', path: '/Movies', isDirectory: true),
            OpenListEntry(
              name: 'video.mkv',
              path: '/video.mkv',
              isDirectory: false,
            ),
          ]
        : const [];
  }

  @override
  Future<RemoteCredentials> readAccount(String accountId) async =>
      const RemoteCredentials(
        openListDriver: 'Quark',
        openListAuthorization: {'cookie': 'old-cookie-secret'},
      );

  @override
  Future<void> deleteAccount(String accountId) async => deleted.add(accountId);
}

class _FakeController extends SourceController {
  String? accountId;
  String? directory;
  int? reauthorizedId;
  Map<String, dynamic>? authorization;

  @override
  Map<int, ScanProgress> build() => {};

  @override
  Future<MediaSourceConfig> addOpenListSource({
    required String accountId,
    required String directory,
    String? name,
    List<String> extensions = defaultVideoExtensions,
    List<String> excludedDirectories = defaultExcludedDirectories,
  }) async {
    this.accountId = accountId;
    this.directory = directory;
    return MediaSourceConfig(
      id: 1,
      kind: 'openlist',
      name: name ?? '网盘',
      rootLocator: buildOpenListRoot(accountId, directory),
    );
  }

  @override
  Future<void> reauthorizeOpenListSource(
    int id,
    Map<String, dynamic> addition,
  ) async {
    reauthorizedId = id;
    authorization = addition;
  }
}

void main() {
  Widget app(Widget page, _FakeService service, _FakeController controller) {
    final router = GoRouter(
      initialLocation: '/sources/setup',
      routes: [
        GoRoute(
          path: '/sources',
          builder: (_, _) => const Scaffold(body: Text('媒体源列表')),
          routes: [GoRoute(path: 'setup', builder: (_, _) => page)],
        ),
      ],
    );
    addTearDown(router.dispose);
    return ProviderScope(
      overrides: [
        openListServiceProvider.overrideWithValue(service),
        sourceControllerProvider.overrideWith(() => controller),
      ],
      child: MaterialApp.router(theme: ReelvaTheme.light, routerConfig: router),
    );
  }

  Future<void> connectQuark(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('cloud_manual_options')));
    await tester.pumpAndSettle();
    final field = find.byKey(const Key('cloud_cookie_field'));
    await tester.ensureVisible(field);
    await tester.enterText(field, '__pus=one; __puus=two');
    final connect = find.byKey(const Key('cloud_manual_connect_button'));
    await tester.ensureVisible(connect);
    await tester.tap(connect);
    await tester.pumpAndSettle();
  }

  testWidgets('四种网盘入口分流到各自登录配置页', (tester) async {
    for (final kind in [
      SourceSetupKind.baidu,
      SourceSetupKind.quark,
      SourceSetupKind.pan115,
      SourceSetupKind.pan123,
    ]) {
      await tester.pumpWidget(
        app(SourceSetupPage(kind: kind), _FakeService(), _FakeController()),
      );
      await tester.pumpAndSettle();
      expect(find.byType(CloudSourceSetupPage), findsOneWidget);
      expect(find.text('添加 ${kind.label}'), findsOneWidget);
      expect(find.text('网页登录 ${kind.label}'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    }
  });

  testWidgets('手动登录后选择目录并保存，已绑定账号不会被清理', (tester) async {
    final service = _FakeService();
    final controller = _FakeController();
    await tester.pumpWidget(
      app(const CloudSourceSetupPage(driver: 'Quark'), service, controller),
    );
    await tester.pumpAndSettle();
    await connectQuark(tester);
    expect(service.saved.single['driver'], 'Quark');
    expect(service.saved.single['addition'], {
      'cookie': '__pus=one; __puus=two',
    });
    expect(find.text('video.mkv'), findsNothing);
    final folder = find.byKey(const ValueKey('cloud_directory_/Movies'));
    await tester.ensureVisible(folder);
    await tester.tap(folder);
    await tester.pumpAndSettle();
    expect(find.text('/Movies'), findsOneWidget);
    final save = find.byKey(const Key('cloud_source_confirm_button'));
    await tester.ensureVisible(save);
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(controller.accountId, _accountId);
    expect(controller.directory, '/Movies');
    expect(service.deleted, isEmpty);
    expect(find.text('媒体源列表'), findsOneWidget);
  });

  testWidgets('取消添加清理未绑定的临时账号', (tester) async {
    final service = _FakeService();
    await tester.pumpWidget(
      app(
        const CloudSourceSetupPage(driver: 'Quark'),
        service,
        _FakeController(),
      ),
    );
    await tester.pumpAndSettle();
    await connectQuark(tester);
    await tester.tap(find.byKey(const Key('cloud_source_back_button')));
    await tester.pumpAndSettle();
    expect(service.deleted, [_accountId]);
  });

  testWidgets('读取目录失败保留已授权账号供重试，离开时再清理', (tester) async {
    final service = _FakeService()..failList = true;
    await tester.pumpWidget(
      app(
        const CloudSourceSetupPage(driver: 'Quark'),
        service,
        _FakeController(),
      ),
    );
    await tester.pumpAndSettle();
    await connectQuark(tester);
    expect(find.text('不应向界面回显的原始错误'), findsNothing);
    expect(service.deleted, isEmpty);
    final error = find.byKey(const Key('cloud_source_error'));
    expect(error, findsOneWidget);
    service.failList = false;
    final retry = find.byTooltip('刷新目录');
    await tester.ensureVisible(retry);
    await tester.tap(retry);
    await tester.pumpAndSettle();
    expect(find.text('Movies'), findsOneWidget);
    await tester.tap(find.byKey(const Key('cloud_source_back_button')));
    await tester.pumpAndSettle();
    expect(service.deleted, [_accountId]);
  });

  testWidgets('123 授权失效显示重新授权提示并隐藏原始错误', (tester) async {
    final service = _FakeService()..invalidGrant = true;
    await tester.pumpWidget(
      app(
        const CloudSourceSetupPage(driver: '123 Open'),
        service,
        _FakeController(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('cloud_manual_options')));
    await tester.pumpAndSettle();
    final field = find.byKey(const Key('cloud_refresh_token_field'));
    await tester.ensureVisible(field);
    await tester.enterText(field, 'refresh-token');
    final connect = find.byKey(const Key('cloud_manual_connect_button'));
    await tester.ensureVisible(connect);
    await tester.tap(connect);
    await tester.pumpAndSettle();
    expect(find.text('网盘登录已失效，请重新授权'), findsOneWidget);
    expect(find.text('private grant message'), findsNothing);
  });

  testWidgets('重新授权不回显旧凭据，通过控制器保留账号及根目录', (tester) async {
    final service = _FakeService();
    final controller = _FakeController();
    final source = MediaSourceConfig(
      id: 7,
      kind: 'openlist',
      name: '我的网盘',
      rootLocator: buildOpenListRoot(_accountId, '/Movies'),
    );
    await tester.pumpWidget(
      app(
        CloudSourceSetupPage(driver: 'Quark', source: source),
        service,
        controller,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('当前目录：/Movies'), findsOneWidget);
    expect(find.text('old-cookie-secret'), findsNothing);
    await connectQuark(tester);
    expect(controller.reauthorizedId, 7);
    expect(controller.authorization, {'cookie': '__pus=one; __puus=two'});
    expect(service.saved, isEmpty);
    expect(service.deleted, isEmpty);
    expect(find.text('媒体源列表'), findsOneWidget);
  });
}
