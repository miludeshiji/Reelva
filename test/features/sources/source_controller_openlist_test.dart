import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reelva/core/database/app_database.dart';
import 'package:reelva/features/library/infrastructure/media_library_repository.dart';
import 'package:reelva/features/sources/application/source_providers.dart';
import 'package:reelva/features/sources/domain/openlist_models.dart';
import 'package:reelva/features/sources/domain/source_models.dart';
import 'package:reelva/features/sources/infrastructure/openlist_rpc.dart';
import 'package:reelva/features/sources/infrastructure/openlist_service.dart';
import 'package:reelva/features/sources/infrastructure/remote_credentials_store.dart';

import 'infrastructure/remote_credentials_store_test.dart';
import 'source_controller_remote_test.dart' show FakeRemoteSourceAdapter;

const _accountId = '0123456789abcdef0123456789abcdef';

class _AccountRpc implements OpenListRpcClient {
  final accounts = <String, Map<String, dynamic>>{};
  final deleted = <String>[];

  @override
  Future<Map<String, dynamic>> invoke(
    String method,
    Map<String, dynamic> arguments,
  ) async {
    switch (method) {
      case 'initialize':
        return const {
          'data': {'ready': true},
        };
      case 'accounts':
        return {
          'data': {'accounts': accounts.values.toList()},
        };
      case 'saveAccount':
        final id = arguments['id'] as String;
        accounts[id] = {
          'id': id,
          'name': arguments['name'],
          'driver': arguments['driver'],
          'addition': Map<String, dynamic>.from(arguments['addition'] as Map),
        };
        return {
          'data': {'id': id},
        };
      case 'deleteAccount':
        final id = arguments['id'] as String;
        deleted.add(id);
        accounts.remove(id);
        return const {'data': <String, dynamic>{}};
      case 'close':
        return const {'data': <String, dynamic>{}};
      default:
        throw StateError('Unexpected RPC method: $method');
    }
  }
}

class _ScanAdapter extends FakeRemoteSourceAdapter {
  _ScanAdapter() : super(kind: 'openlist');

  final started = Completer<void>();

  @override
  Stream<MediaEntry> listEntries(
    MediaSourceConfig source,
    String directoryId,
  ) async* {
    if (!started.isCompleted) started.complete();
    yield* super.listEntries(source, directoryId);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase database;
  late MediaLibraryRepository repository;
  late FakeFlutterSecureStorage storage;
  late RemoteCredentialsStore credentials;
  late _AccountRpc rpc;
  late OpenListService service;
  late _ScanAdapter adapter;
  late ProviderContainer container;
  late SourceController controller;

  setUp(() async {
    database = AppDatabase(executor: NativeDatabase.memory());
    repository = MediaLibraryRepository(database);
    storage = FakeFlutterSecureStorage();
    credentials = RemoteCredentialsStore(storage: storage);
    rpc = _AccountRpc();
    adapter = _ScanAdapter();
    service = OpenListService(
      rpc: rpc,
      credentials: credentials,
      dataDirectory: () async => '/test/reelva/openlist',
      activeAccountIds: () async {
        final sources = await database.select(database.mediaSources).get();
        return {
          for (final source in sources)
            if (source.kind == 'openlist' && source.enabled)
              OpenListRoot.parse(source.rootLocator).accountId,
        };
      },
    );
    container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(database),
        mediaLibraryRepositoryProvider.overrideWithValue(repository),
        remoteCredentialsStoreProvider.overrideWithValue(credentials),
        openListServiceProvider.overrideWithValue(service),
        sourceAdaptersProvider.overrideWithValue({'openlist': adapter}),
      ],
    );
    controller = container.read(sourceControllerProvider.notifier);
    await service.saveAccount(
      accountId: _accountId,
      driver: 'Quark',
      name: '夸克账号',
      addition: const {'cookie': '__pus=initial; __puus=initial'},
    );
  });

  tearDown(() async {
    final gate = adapter.scanGate;
    if (gate != null && !gate.isCompleted) gate.complete();
    final running = container
        .read(sourceControllerProvider)
        .entries
        .where((entry) => entry.value.running)
        .map((entry) => entry.key)
        .toList();
    for (final id in running) {
      await controller.refreshSource(id);
    }
    await service.close();
    container.dispose();
    await database.close();
  });

  test('添加网盘源保留稳定根目录与凭据引用，保存后在后台扫描', () async {
    adapter.scanGate = Completer<void>();
    final source = await controller.addOpenListSource(
      accountId: _accountId,
      directory: '/Movies/中文 电影',
      name: '我的电影',
    );
    expect(source.kind, 'openlist');
    expect(source.rootLocator, buildOpenListRoot(_accountId, '/Movies/中文 电影'));
    expect(
      source.credentialRef,
      OpenListService.credentialReference(_accountId),
    );
    expect(
      container.read(sourceControllerProvider)[source.id]!.running,
      isTrue,
    );
    expect((await repository.getSource(source.id)).enabled, isTrue);
    expect(
      (await credentials.read(source.credentialRef)).openListAuthorization,
      {'cookie': '__pus=initial; __puus=initial'},
    );
    adapter.scanGate!.complete();
    await controller.refreshSource(source.id);
    final saved = await repository.getSource(source.id);
    expect(saved.rootLocator, source.rootLocator);
    expect(saved.lastScanAt, isNotNull);
    expect(
      container.read(sourceControllerProvider)[source.id]!.running,
      isFalse,
    );
  });

  test('重新授权等待旧扫描结束，保留账号与根目录并更新双端凭据', () async {
    adapter.scanGate = Completer<void>();
    final source = await controller.addOpenListSource(
      accountId: _accountId,
      directory: '/Movies',
    );
    await adapter.started.future;
    var finished = false;
    final reauthorize = controller
        .reauthorizeOpenListSource(source.id, const {
          'cookie': '__pus=renewed; __puus=renewed',
        })
        .then((_) => finished = true);
    await Future<void>.delayed(Duration.zero);
    expect(finished, isFalse);
    expect(rpc.accounts[_accountId]!['addition'], {
      'cookie': '__pus=initial; __puus=initial',
    });
    adapter.scanGate!.complete();
    await reauthorize;
    await controller.refreshSource(source.id);
    final updated = await repository.getSource(source.id);
    expect(updated.id, source.id);
    expect(updated.rootLocator, source.rootLocator);
    expect(updated.credentialRef, source.credentialRef);
    expect(rpc.accounts.keys, [_accountId]);
    expect(rpc.accounts[_accountId]!['addition'], {
      'cookie': '__pus=renewed; __puus=renewed',
    });
    expect(
      (await credentials.read(updated.credentialRef)).openListAuthorization,
      {'cookie': '__pus=renewed; __puus=renewed'},
    );
    expect(updated.lastScanAt, isNotNull);
  });

  test('同账号多目录只在最后一个源移除后清理内核及安全凭据', () async {
    final first = await controller.addOpenListSource(
      accountId: _accountId,
      directory: '/Movies',
    );
    final second = await controller.addOpenListSource(
      accountId: _accountId,
      directory: '/Series',
    );
    expect(first.credentialRef, second.credentialRef);
    await controller.removeSource(first.id);
    expect((await repository.getSource(first.id)).enabled, isFalse);
    expect((await repository.getSource(first.id)).credentialRef, isNull);
    expect((await repository.getSource(second.id)).enabled, isTrue);
    expect(rpc.accounts.containsKey(_accountId), isTrue);
    expect(rpc.deleted, isEmpty);
    expect(
      (await credentials.read(second.credentialRef)).openListDriver,
      'Quark',
    );

    await controller.removeSource(second.id);
    expect((await repository.getSource(second.id)).enabled, isFalse);
    expect((await repository.getSource(second.id)).credentialRef, isNull);
    expect(rpc.accounts, isEmpty);
    expect(rpc.deleted, [_accountId]);
    await expectLater(
      credentials.read(second.credentialRef),
      throwsA(
        isA<MediaSourceException>().having(
          (error) => error.code,
          'code',
          'credential_not_found',
        ),
      ),
    );
    expect(await repository.watchSources().first, isEmpty);
  });

  test('安全凭据删除失败恢复源为启用状态，允许重试完成清理', () async {
    final source = await controller.addOpenListSource(
      accountId: _accountId,
      directory: '/Movies',
      name: '保留重试',
      extensions: const ['mkv'],
      excludedDirectories: const ['Extras'],
    );
    await controller.refreshSource(source.id);
    storage.shouldThrowOnDelete = true;
    await expectLater(
      controller.removeSource(source.id),
      throwsA(
        isA<MediaSourceException>().having(
          (error) => error.code,
          'code',
          'credential_storage_failed',
        ),
      ),
    );
    final retained = await repository.getSource(source.id);
    expect(retained.enabled, isTrue);
    expect(retained.rootLocator, source.rootLocator);
    expect(retained.credentialRef, source.credentialRef);
    expect(retained.name, '保留重试');
    expect(retained.extensions, ['mkv']);
    expect(retained.excludedDirectories, ['Extras']);
    expect(
      (await credentials.read(retained.credentialRef)).openListDriver,
      'Quark',
    );
    expect((await repository.watchSources().first).single.id, source.id);

    storage.shouldThrowOnDelete = false;
    await controller.removeSource(source.id);
    final removed = await repository.getSource(source.id);
    expect(removed.enabled, isFalse);
    expect(removed.credentialRef, isNull);
    expect(rpc.accounts, isEmpty);
    await expectLater(
      credentials.read(source.credentialRef),
      throwsA(isA<MediaSourceException>()),
    );
  });
}
