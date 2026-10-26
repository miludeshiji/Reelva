import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reelva/features/sync/application/sync_providers.dart';
import 'package:reelva/features/sync/application/sync_service.dart';
import 'package:reelva/features/sync/domain/sync_models.dart';
import 'package:reelva/features/sync/infrastructure/sync_configuration_store.dart';
import 'package:reelva/features/sync/infrastructure/sync_repository.dart';
import 'package:reelva/features/sync/presentation/sync_settings_card.dart';

class _FakeStore implements SyncConfigurationStore {
  SyncConfiguration? currentConfig;
  int deleteCount = 0;
  bool throwOnRead = false;

  @override
  Future<SyncConfiguration?> read() async {
    if (throwOnRead) {
      throw const SyncException('安全存储损坏');
    }
    return currentConfig;
  }

  @override
  Future<void> save(SyncConfiguration config) async {
    currentConfig = config;
  }

  @override
  Future<void> delete() async {
    deleteCount++;
    currentConfig = null;
  }
}

class _FakeRepo implements SyncRepository {
  int resetTransportCount = 0;

  @override
  Future<void> resetTransport() async {
    resetTransportCount++;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeService implements SyncService {
  int synchronizeCount = 0;
  SyncReport? reportToReturn;
  Object? errorToThrow;

  @override
  Future<SyncReport> synchronize() async {
    synchronizeCount++;
    if (errorToThrow != null) {
      throw errorToThrow!;
    }
    return reportToReturn ??
        const SyncReport(
          uploaded: 1,
          downloaded: 2,
          applied: 2,
          pending: 0,
          localOnly: 0,
        );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakeStore fakeStore;
  late _FakeRepo fakeRepo;
  late _FakeService fakeService;

  final testEndpoint = Uri.parse('https://dav.example.com/sync/');

  setUp(() {
    fakeStore = _FakeStore();
    fakeRepo = _FakeRepo();
    fakeService = _FakeService();
  });

  Widget buildTestWidget({
    Size screenSize = const Size(800, 600),
    double textScale = 1.0,
    List<Override> overrides = const [],
  }) {
    return ProviderScope(
      overrides: [
        syncConfigurationStoreProvider.overrideWithValue(fakeStore),
        syncRepositoryProvider.overrideWithValue(fakeRepo),
        syncServiceProvider.overrideWith((ref, config) => fakeService),
        pendingSourceBindingsProvider.overrideWith((ref) async => []),
        ...overrides,
      ],
      child: MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(
            size: screenSize,
            textScaler: TextScaler.linear(textScale),
          ),
          child: const Scaffold(
            body: SingleChildScrollView(child: SyncSettingsCard()),
          ),
        ),
      ),
    );
  }

  group('SyncSettingsCard UI and Behavior Tests', () {
    testWidgets('加密密码不回显、留空保留，变更端点后不沿用', (tester) async {
      fakeStore.currentConfig = SyncConfiguration(
        endpoint: testEndpoint,
        encryptionPassword: 'test-application-password',
      );
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();
      final field = find.byKey(const Key('sync_encryption_password'));
      expect(tester.widget<TextField>(field).controller!.text, isEmpty);
      expect(tester.widget<TextField>(field).obscureText, isTrue);
      await tester.ensureVisible(find.byKey(const Key('sync_save')));
      await tester.tap(find.byKey(const Key('sync_save')));
      await tester.pumpAndSettle();
      expect(
        fakeStore.currentConfig!.encryptionPassword,
        'test-application-password',
      );
      await tester.enterText(field, 'short');
      await tester.ensureVisible(find.byKey(const Key('sync_save')));
      await tester.tap(find.byKey(const Key('sync_save')));
      await tester.pumpAndSettle();
      expect(find.text('同步加密密码至少需要 12 个字符'), findsOneWidget);
      expect(
        fakeStore.currentConfig!.encryptionPassword,
        'test-application-password',
      );
      await tester.enterText(field, '');
      await tester.enterText(
        find.byKey(const Key('sync_endpoint')),
        'https://other.example/sync/',
      );
      await tester.ensureVisible(find.byKey(const Key('sync_save')));
      await tester.tap(find.byKey(const Key('sync_save')));
      await tester.pumpAndSettle();
      expect(fakeStore.currentConfig!.encryptionPassword, isEmpty);
      expect(fakeService.synchronizeCount, 0);
    });
    testWidgets(
      'unconfigured state displays unconfigured chip, inputs, and only save button',
      (tester) async {
        fakeStore.currentConfig = null;

        await tester.pumpWidget(buildTestWidget());
        await tester.pumpAndSettle();

        // 验证未配置状态指示及产品标题
        expect(find.text('跨设备同步'), findsOneWidget);
        expect(find.byKey(const Key('sync_status_chip')), findsOneWidget);
        expect(find.text('未配置'), findsOneWidget);

        // 验证各表单项存在且输入框为空
        final endpointField = tester.widget<TextField>(
          find.byKey(const Key('sync_endpoint')),
        );
        expect(endpointField.controller?.text, isEmpty);

        final usernameField = tester.widget<TextField>(
          find.byKey(const Key('sync_username')),
        );
        expect(usernameField.controller?.text, isEmpty);

        final passwordField = tester.widget<TextField>(
          find.byKey(const Key('sync_password')),
        );
        expect(passwordField.controller?.text, isEmpty);
        expect(passwordField.obscureText, isTrue);

        // 验证操作按钮：未配置时不显示立即同步和禁用按钮
        expect(find.byKey(const Key('sync_save')), findsOneWidget);
        expect(find.byKey(const Key('sync_now')), findsNothing);
        expect(find.byKey(const Key('sync_disable')), findsNothing);

        // 绝不发生自动网络同步调用
        expect(fakeService.synchronizeCount, equals(0));
      },
    );

    testWidgets(
      'configured state: secret password is NEVER prefilled in text field',
      (tester) async {
        fakeStore.currentConfig = SyncConfiguration(
          endpoint: testEndpoint,
          username: 'alice',
          password: 'myTopSecretPassword123',
        );

        await tester.pumpWidget(buildTestWidget());
        await tester.pumpAndSettle();

        // 状态 Chip 显示已配置
        expect(find.text('已配置'), findsOneWidget);

        // 端点与用户名已填充
        final endpointField = tester.widget<TextField>(
          find.byKey(const Key('sync_endpoint')),
        );
        expect(endpointField.controller?.text, equals(testEndpoint.toString()));

        final usernameField = tester.widget<TextField>(
          find.byKey(const Key('sync_username')),
        );
        expect(usernameField.controller?.text, equals('alice'));

        // 密码输入框严格为空，绝不向 UI 回显机密密码
        final passwordField = tester.widget<TextField>(
          find.byKey(const Key('sync_password')),
        );
        expect(passwordField.controller?.text, isEmpty);

        // 按钮均处于就绪状态
        expect(find.byKey(const Key('sync_now')), findsOneWidget);
        expect(find.byKey(const Key('sync_save')), findsOneWidget);
        expect(find.byKey(const Key('sync_disable')), findsOneWidget);

        // 绝不发生自动网络同步调用
        expect(fakeService.synchronizeCount, equals(0));
      },
    );

    testWidgets(
      'password retention regression: blank password retains old password ONLY when endpoint & username match',
      (tester) async {
        fakeStore.currentConfig = SyncConfiguration(
          endpoint: testEndpoint,
          username: 'alice',
          password: 'keptSecretPassword',
        );

        await tester.pumpWidget(buildTestWidget());
        await tester.pumpAndSettle();

        // 1. 端点与用户名均未改变，密码留空 => 保留旧密码
        await tester.tap(find.byKey(const Key('sync_save')));
        await tester.pumpAndSettle();
        expect(fakeStore.currentConfig?.password, equals('keptSecretPassword'));

        // 2. 修改端点但密码留空 => 绝不向新主机泄露旧服务密码，密码清空为空字符串
        final differentEndpoint = Uri.parse('https://other.server.com/sync/');
        await tester.enterText(
          find.byKey(const Key('sync_endpoint')),
          differentEndpoint.toString(),
        );
        await tester.tap(find.byKey(const Key('sync_save')));
        await tester.pumpAndSettle();

        expect(fakeStore.currentConfig?.endpoint, equals(differentEndpoint));
        expect(fakeStore.currentConfig?.password, equals(''));

        // 3. 修改用户名但密码留空 => 绝不向新用户泄露旧用户密码，密码清空为空字符串
        fakeStore.currentConfig = SyncConfiguration(
          endpoint: differentEndpoint,
          username: 'alice',
          password: 'aliceSecretPassword',
        );
        await tester.pumpWidget(buildTestWidget());
        await tester.pumpAndSettle();

        await tester.enterText(find.byKey(const Key('sync_username')), 'bob');
        await tester.tap(find.byKey(const Key('sync_save')));
        await tester.pumpAndSettle();

        expect(fakeStore.currentConfig?.username, equals('bob'));
        expect(fakeStore.currentConfig?.password, equals(''));
      },
    );

    testWidgets(
      'recoverable error banner when sync configuration reading fails',
      (tester) async {
        fakeStore.throwOnRead = true;

        await tester.pumpWidget(buildTestWidget());
        await tester.pumpAndSettle();

        // 展示安全错误 Banner
        expect(
          find.byKey(const Key('sync_config_error_banner')),
          findsOneWidget,
        );
        expect(find.text('读取同步安全配置失败，配置可能损坏'), findsOneWidget);
        expect(find.byKey(const Key('sync_retry_config_read')), findsOneWidget);
        expect(
          find.byKey(const Key('sync_clear_damaged_config')),
          findsOneWidget,
        );

        // 点击清除损坏配置
        await tester.tap(find.byKey(const Key('sync_clear_damaged_config')));
        await tester.pumpAndSettle();
        expect(fakeStore.deleteCount, equals(1));
      },
    );

    testWidgets('validation error displays when saving with empty endpoint', (
      tester,
    ) async {
      fakeStore.currentConfig = null;

      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      // 未输入端点直接点击保存
      await tester.tap(find.byKey(const Key('sync_save')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('sync_error_text')), findsOneWidget);
      expect(find.text('请输入 WebDAV 端点地址'), findsOneWidget);
      expect(fakeStore.currentConfig, isNull);
    });

    testWidgets(
      'validation error displays when endpoint has dot segments or credentials',
      (tester) async {
        fakeStore.currentConfig = null;

        await tester.pumpWidget(buildTestWidget());
        await tester.pumpAndSettle();

        // 输入包含相对点路径段的不安全端点
        await tester.enterText(
          find.byKey(const Key('sync_endpoint')),
          'https://dav.example.com/sync/../private',
        );
        await tester.tap(find.byKey(const Key('sync_save')));
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('sync_error_text')), findsOneWidget);
        expect(find.textContaining('无效的点路径段'), findsOneWidget);
      },
    );

    testWidgets('sync now executes synchronize and displays report details', (
      tester,
    ) async {
      fakeStore.currentConfig = SyncConfiguration(endpoint: testEndpoint);
      fakeService.reportToReturn = const SyncReport(
        uploaded: 4,
        downloaded: 6,
        applied: 5,
        pending: 1,
        localOnly: 2,
      );

      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('sync_now')));
      await tester.pumpAndSettle();

      expect(fakeService.synchronizeCount, equals(1));
      expect(find.byKey(const Key('sync_report_text')), findsOneWidget);
      expect(
        find.textContaining('上传 4 条，下载 6 条，应用 5 条，待匹配 1 条，仅本地 2 条'),
        findsOneWidget,
      );
    });

    testWidgets('sync failure displays sanitized static safe error message', (
      tester,
    ) async {
      fakeStore.currentConfig = SyncConfiguration(
        endpoint: testEndpoint,
        username: 'bob',
        password: 'myPassword!',
      );
      fakeService.errorToThrow = const SyncException('WebDAV 服务响应 503 临时不可用');

      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('sync_now')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('sync_error_text')), findsOneWidget);
      expect(find.text('WebDAV 服务响应 503 临时不可用'), findsOneWidget);
    });

    testWidgets('disable button deletes config and clears input controllers', (
      tester,
    ) async {
      fakeStore.currentConfig = SyncConfiguration(
        endpoint: testEndpoint,
        username: 'bob',
      );

      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('sync_disable')));
      await tester.pumpAndSettle();

      expect(fakeStore.deleteCount, equals(1));
      expect(fakeStore.currentConfig, isNull);

      // 输入框已被清空
      final endpointField = tester.widget<TextField>(
        find.byKey(const Key('sync_endpoint')),
      );
      expect(endpointField.controller?.text, isEmpty);

      // 状态恢复为未配置
      expect(find.text('未配置'), findsOneWidget);
      expect(find.text('已禁用并清除同步配置'), findsOneWidget);
    });

    testWidgets(
      'responsive layout on 320px mobile viewport with 1.5x text scale without overflow',
      (tester) async {
        fakeStore.currentConfig = SyncConfiguration(
          endpoint: testEndpoint,
          username: 'mobile_user',
        );

        // 设置 320x600 超小屏规格及 1.5x 大字体无溢出验证
        await tester.pumpWidget(
          buildTestWidget(screenSize: const Size(320, 600), textScale: 1.5),
        );
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('sync_now')), findsOneWidget);
        expect(find.byKey(const Key('sync_save')), findsOneWidget);
        expect(find.byKey(const Key('sync_disable')), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'responsive layout on 1280px desktop viewport without overflow',
      (tester) async {
        fakeStore.currentConfig = SyncConfiguration(
          endpoint: testEndpoint,
          username: 'desktop_user',
        );

        // 设置 1280x900 桌面大屏规格
        await tester.pumpWidget(
          buildTestWidget(screenSize: const Size(1280, 900)),
        );
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('sync_now')), findsOneWidget);
        expect(find.byKey(const Key('sync_save')), findsOneWidget);
        expect(find.byKey(const Key('sync_disable')), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  });
}
