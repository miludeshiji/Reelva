import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reelva/features/sync/application/sync_providers.dart';
import 'package:reelva/features/sync/application/sync_service.dart';
import 'package:reelva/features/sync/domain/sync_models.dart';
import 'package:reelva/features/sync/domain/sync_transport.dart';
import 'package:reelva/features/sync/infrastructure/sync_configuration_store.dart';
import 'package:reelva/features/sync/infrastructure/sync_repository.dart';

class _FakeSyncConfigurationStore implements SyncConfigurationStore {
  SyncConfiguration? currentConfig;
  bool throwOnSave = false;
  bool throwOnRead = false;
  int readCount = 0;
  int saveCount = 0;
  int deleteCount = 0;

  @override
  Future<SyncConfiguration?> read() async {
    readCount++;
    if (throwOnRead) {
      throw const SyncException('安全存储读取失败');
    }
    return currentConfig;
  }

  @override
  Future<void> save(SyncConfiguration config) async {
    saveCount++;
    if (throwOnSave) {
      throw const SyncException('安全存储写入失败');
    }
    currentConfig = config;
  }

  @override
  Future<void> delete() async {
    deleteCount++;
    currentConfig = null;
  }
}

class _FakeSyncRepository implements SyncRepository {
  int resetTransportCount = 0;
  List<String> callLog = [];

  @override
  Future<void> resetTransport() async {
    resetTransportCount++;
    callLog.add('resetTransport');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeSyncService implements SyncService {
  _FakeSyncService({required this.repository, required this.transport});

  @override
  final SyncRepository repository;

  @override
  final SyncTransport transport;

  int syncCallCount = 0;
  Future<SyncReport> Function()? customSyncHandler;

  @override
  Future<SyncReport> synchronize() async {
    syncCallCount++;
    if (customSyncHandler != null) {
      return await customSyncHandler!();
    }
    return const SyncReport(
      uploaded: 2,
      downloaded: 3,
      applied: 3,
      pending: 0,
      localOnly: 1,
    );
  }
}

class _FakeSyncTransport implements SyncTransport {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('SyncController Unit and Boundary Tests', () {
    late _FakeSyncConfigurationStore fakeStore;
    late _FakeSyncRepository fakeRepo;
    late _FakeSyncService fakeService;
    late _FakeSyncTransport fakeTransport;
    late ProviderContainer container;

    final testEndpointA = Uri.parse('https://dav.example.com/sync/');
    final testEndpointB = Uri.parse('https://backup.example.com/sync/');

    setUp(() {
      fakeStore = _FakeSyncConfigurationStore();
      fakeRepo = _FakeSyncRepository();
      fakeTransport = _FakeSyncTransport();
      fakeService = _FakeSyncService(
        repository: fakeRepo,
        transport: fakeTransport,
      );

      container = ProviderContainer(
        overrides: [
          syncConfigurationStoreProvider.overrideWithValue(fakeStore),
          syncRepositoryProvider.overrideWithValue(fakeRepo),
          syncTransportProvider.overrideWith((ref, config) => fakeTransport),
          syncServiceProvider.overrideWith((ref, config) => fakeService),
        ],
      );
    });

    tearDown(() {
      container.dispose();
    });

    test('synchronize without configured endpoint throws SyncException and sets state.error', () async {
      fakeStore.currentConfig = null;
      final controller = container.read(syncControllerProvider.notifier);

      await expectLater(
        controller.synchronize(),
        throwsA(
          isA<SyncException>().having(
            (e) => e.message,
            'message',
            contains('未配置 WebDAV 同步服务'),
          ),
        ),
      );

      final state = container.read(syncControllerProvider);
      expect(state.running, isFalse);
      expect(state.error, contains('未配置 WebDAV 同步服务'));
    });

    test(
      'synchronize with read failure writes safe visible error in state',
      () async {
        fakeStore.throwOnRead = true;
        final controller = container.read(syncControllerProvider.notifier);

        await expectLater(
          controller.synchronize(),
          throwsA(
            isA<SyncException>().having(
              (e) => e.message,
              'message',
              contains('安全存储读取失败'),
            ),
          ),
        );

        final state = container.read(syncControllerProvider);
        expect(state.running, isFalse);
        expect(state.error, equals('安全存储读取失败'));
      },
    );

    test('concurrent synchronize calls return the same active Future synchronously (single-flight)', () async {
      fakeStore.currentConfig = SyncConfiguration(
        endpoint: testEndpointA,
        username: 'user1',
        password: 'pwd',
      );
      final completer = Completer<SyncReport>();
      fakeService.customSyncHandler = () => completer.future;

      final controller = container.read(syncControllerProvider.notifier);

      // 验证在初次调用 synchronize 时，running 立即被同步设置为 true
      final future1 = controller.synchronize();
      expect(container.read(syncControllerProvider).running, isTrue);

      final future2 = controller.synchronize();
      expect(identical(future1, future2), isTrue); // 同步返回同一活跃 Future
      await Future<void>.value();
      expect(fakeService.syncCallCount, equals(1)); // 仅触发一次真实执行

      const expectedReport = SyncReport(
        uploaded: 5,
        downloaded: 1,
        applied: 1,
        pending: 0,
        localOnly: 0,
      );
      completer.complete(expectedReport);

      final res1 = await future1;
      final res2 = await future2;
      expect(res1, equals(expectedReport));
      expect(res2, equals(expectedReport));
      expect(container.read(syncControllerProvider).running, isFalse);
    });

    test('synchronize failure with unexpected non-SyncException uses fixed static generic message', () async {
      fakeStore.currentConfig = SyncConfiguration(
        endpoint: testEndpointA,
        username: 'alice',
        password: 'supersecretpassword',
      );
      fakeService.customSyncHandler = () async {
        throw const FormatException(
          'Corrupted response with credentials https://alice:supersecretpassword@dav.example.com',
        );
      };

      final controller = container.read(syncControllerProvider.notifier);
      await expectLater(
        controller.synchronize(),
        throwsA(isA<SyncException>()),
      );

      final state = container.read(syncControllerProvider);
      expect(state.running, isFalse);
      expect(state.error, isNotNull);
      // 绝不泄露任何异常中的机密凭据，统一使用固定安全文案
      expect(state.error, equals('同步操作失败，请检查网络或服务配置'));
      expect(state.error, isNot(contains('supersecretpassword')));
    });

    test(
      'saveConfiguration is blocked during active sync or configuring',
      () async {
        fakeStore.currentConfig = SyncConfiguration(endpoint: testEndpointA);
        final completer = Completer<SyncReport>();
        fakeService.customSyncHandler = () => completer.future;

        final controller = container.read(syncControllerProvider.notifier);
        final syncFuture = controller.synchronize();

        expect(
          () => controller.saveConfiguration(
            SyncConfiguration(endpoint: testEndpointB),
          ),
          throwsA(
            isA<SyncException>().having(
              (e) => e.message,
              'message',
              contains('同步或配置进行中，无法修改配置'),
            ),
          ),
        );

        completer.complete(
          const SyncReport(
            uploaded: 0,
            downloaded: 0,
            applied: 0,
            pending: 0,
            localOnly: 0,
          ),
        );
        await syncFuture;
      },
    );

    test('saveConfiguration with endpoint change executes resetTransport before saving', () async {
      fakeStore.currentConfig = SyncConfiguration(
        endpoint: testEndpointA,
        username: 'userA',
      );
      final controller = container.read(syncControllerProvider.notifier);

      final newConfig = SyncConfiguration(
        endpoint: testEndpointB,
        username: 'userB',
      );

      await controller.saveConfiguration(newConfig);

      // 验证重置传输端点记账被调用
      expect(fakeRepo.resetTransportCount, equals(1));
      expect(fakeStore.saveCount, equals(1));
      expect(fakeStore.currentConfig?.endpoint, equals(testEndpointB));
    });

    test(
      'saveConfiguration with same endpoint does not reset transport',
      () async {
        fakeStore.currentConfig = SyncConfiguration(
          endpoint: testEndpointA,
          username: 'userA',
          password: 'oldPassword',
        );
        final controller = container.read(syncControllerProvider.notifier);

        final updatedConfig = SyncConfiguration(
          endpoint: testEndpointA,
          username: 'userA',
          password: 'newPassword',
        );

        await controller.saveConfiguration(updatedConfig);

        // 端点未变，绝不重置传输记录
        expect(fakeRepo.resetTransportCount, equals(0));
        expect(fakeStore.saveCount, equals(1));
        expect(fakeStore.currentConfig?.password, equals('newPassword'));
      },
    );

    test('saveConfiguration order: resetTransport occurs even if secure save fails later', () async {
      fakeStore.currentConfig = SyncConfiguration(endpoint: testEndpointA);
      fakeStore.throwOnSave = true; // 模拟保存失败

      final controller = container.read(syncControllerProvider.notifier);

      await expectLater(
        controller.saveConfiguration(
          SyncConfiguration(endpoint: testEndpointB),
        ),
        throwsA(isA<SyncException>()),
      );

      // 确认重置先于保存执行完毕，防止新端点遗留旧游标
      expect(fakeRepo.resetTransportCount, equals(1));
    });

    test('disable is blocked during active sync', () async {
      fakeStore.currentConfig = SyncConfiguration(endpoint: testEndpointA);
      final completer = Completer<SyncReport>();
      fakeService.customSyncHandler = () => completer.future;

      final controller = container.read(syncControllerProvider.notifier);
      final syncFuture = controller.synchronize();

      expect(
        () => controller.disable(),
        throwsA(
          isA<SyncException>().having(
            (e) => e.message,
            'message',
            contains('同步或配置进行中，无法禁用同步'),
          ),
        ),
      );

      completer.complete(
        const SyncReport(
          uploaded: 0,
          downloaded: 0,
          applied: 0,
          pending: 0,
          localOnly: 0,
        ),
      );
      await syncFuture;
    });

    test('disable deletes configuration from store and resets state', () async {
      fakeStore.currentConfig = SyncConfiguration(
        endpoint: testEndpointA,
        username: 'user1',
      );
      final controller = container.read(syncControllerProvider.notifier);

      await controller.disable();

      expect(fakeStore.deleteCount, equals(1));
      expect(fakeStore.currentConfig, isNull);

      final state = container.read(syncControllerProvider);
      expect(state.running, isFalse);
      expect(state.configuring, isFalse);
      expect(state.report, isNull);
      expect(state.error, isNull);
    });
  });
}
