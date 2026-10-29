import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:reelva/features/sources/domain/openlist_models.dart';
import 'package:reelva/features/sources/domain/source_models.dart';
import 'package:reelva/features/sources/infrastructure/openlist_rpc.dart';
import 'package:reelva/features/sources/infrastructure/openlist_service.dart';
import 'package:reelva/features/sources/infrastructure/remote_credentials_store.dart';

const _accountId = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const _secondAccountId = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';

class _MemoryCredentials extends RemoteCredentialsStore {
  final values = <String, RemoteCredentials>{};
  final deleted = <String>[];
  bool failWrites = false;

  @override
  Future<RemoteCredentials> read(String? reference) async {
    final value = values[reference];
    if (value == null) {
      throw const MediaSourceException('凭据不存在', code: 'credential_not_found');
    }
    return value;
  }

  @override
  Future<void> write(String reference, RemoteCredentials credentials) async {
    if (failWrites) {
      throw const MediaSourceException(
        '安全存储失败',
        code: 'credential_storage_failed',
      );
    }
    values[reference] = credentials;
  }

  @override
  Future<void> delete(String reference) async {
    deleted.add(reference);
    values.remove(reference);
  }
}

class _Rpc implements OpenListRpcClient {
  final accounts = <String, Map<String, dynamic>>{};
  final calls = <({String method, Map<String, dynamic> arguments})>[];
  FutureOr<Map<String, dynamic>> Function(String, Map<String, dynamic>)?
  fileOperation;
  Map<String, dynamic> Function(Map<String, dynamic>)? savedAddition;

  void putAccount(String id, String driver, Map<String, dynamic> addition) {
    accounts[id] = {
      'id': id,
      'driver': driver,
      'name': driver,
      'addition': addition,
    };
  }

  @override
  Future<Map<String, dynamic>> invoke(
    String method,
    Map<String, dynamic> arguments,
  ) async {
    calls.add((
      method: method,
      arguments: Map<String, dynamic>.from(arguments),
    ));
    switch (method) {
      case 'initialize':
        return {
          'data': {'ready': true},
        };
      case 'accounts':
        return {
          'data': {'accounts': accounts.values.toList()},
        };
      case 'saveAccount':
        final addition = Map<String, dynamic>.from(
          arguments['addition'] as Map,
        );
        putAccount(
          arguments['id'] as String,
          arguments['driver'] as String,
          savedAddition?.call(addition) ?? addition,
        );
        return {
          'data': {'id': arguments['id']},
        };
      case 'deleteAccount':
        accounts.remove(arguments['id']);
        return const {'data': <String, dynamic>{}};
      case 'releaseTask':
      case 'cancel':
      case 'close':
        return const {'data': <String, dynamic>{}};
      default:
        return await fileOperation?.call(method, arguments) ??
            const {'data': <String, dynamic>{}};
    }
  }
}

void main() {
  late _Rpc rpc;
  late _MemoryCredentials credentials;
  late OpenListService service;

  setUp(() {
    rpc = _Rpc();
    credentials = _MemoryCredentials();
    service = OpenListService(
      rpc: rpc,
      credentials: credentials,
      dataDirectory: () async => '/reelva/openlist',
    );
  });

  tearDown(() async => service.close());

  test('只支持精确的四个驱动名并保存内核返回的授权快照', () async {
    expect(openListDrivers.keys.toSet(), {
      'BaiduNetdisk',
      'Quark',
      '115 Open',
      '123 Open',
    });
    final additions = <String, Map<String, dynamic>>{
      'BaiduNetdisk': {
        'AccessToken': 'baidu-access',
        'refresh_token': 'baidu-refresh',
      },
      'Quark': {'cookie': '__pus=quark-cookie'},
      '115 Open': {
        'access_token': '115-access',
        'refresh_token': '115-refresh',
      },
      '123 Open': {'AccessToken': '123-access', 'RefreshToken': '123-refresh'},
    };
    var index = 0;
    for (final entry in additions.entries) {
      final id = (++index).toRadixString(16).padLeft(32, '0');
      expect(
        await service.saveAccount(
          accountId: id,
          driver: entry.key,
          name: entry.key,
          addition: entry.value,
        ),
        id,
      );
      final native = rpc.accounts[id]!;
      expect(native['driver'], entry.key);
      expect(native['addition'], entry.value);
      final snapshot = await credentials.read(
        OpenListService.credentialReference(id),
      );
      expect(snapshot.openListDriver, entry.key);
      expect(snapshot.openListAuthorization, entry.value);
    }
    await expectLater(
      service.saveAccount(
        driver: 'QuarkOpen',
        name: '夸克',
        addition: const {'token': 'unsupported'},
      ),
      throwsA(
        isA<MediaSourceException>().having(
          (e) => e.code,
          'code',
          'invalid_cloud_account',
        ),
      ),
    );
  });

  test('初始化单飞并使用专属内核目录', () async {
    await Future.wait([
      service.initialize(),
      service.initialize(),
      service.initialize(),
    ]);
    final calls = rpc.calls
        .where((call) => call.method == 'initialize')
        .toList();
    expect(calls, hasLength(1));
    expect(calls.single.arguments, {'dataDir': '/reelva/openlist'});
  });

  test('readAccount 从内核回读轮换后的 Token 和 Cookie 覆盖旧快照', () async {
    credentials.values[OpenListService.credentialReference(
      _accountId,
    )] = const RemoteCredentials(
      openListDriver: '115 Open',
      openListAuthorization: {'refresh_token': 'old-refresh'},
    );
    rpc.putAccount(_accountId, '115 Open', {
      'access_token': 'rotated-access',
      'refresh_token': 'rotated-refresh',
    });
    final current = await service.readAccount(_accountId);
    expect(current.openListAuthorization['refresh_token'], 'rotated-refresh');
    expect(
      await credentials.read(OpenListService.credentialReference(_accountId)),
      current,
    );
    rpc.putAccount(_accountId, 'Quark', {
      'cookie': '__pus=renewed; __puus=new-cookie',
    });
    final cookie = await service.readAccount(_accountId);
    expect(
      cookie.openListAuthorization['cookie'],
      contains('__puus=new-cookie'),
    );
    expect(
      await credentials.read(OpenListService.credentialReference(_accountId)),
      cookie,
    );
  });

  test('保存授权时保留内核初始化过程中轮换的最新凭据', () async {
    rpc.savedAddition = (addition) => {
      ...addition,
      'refresh_token': 'rotated-during-save',
    };
    await service.saveAccount(
      accountId: _accountId,
      driver: '115 Open',
      name: '账号',
      addition: const {'refresh_token': 'login-token'},
    );
    expect(
      (await credentials.read(OpenListService.credentialReference(_accountId)))
          .openListAuthorization['refresh_token'],
      'rotated-during-save',
    );
  });

  test('离线恢复不触发 RPC 且不覆盖已有安全存储授权', () async {
    const current = RemoteCredentials(
      openListDriver: '123 Open',
      openListAuthorization: {'RefreshToken': 'local-current'},
    );
    credentials.values[OpenListService.credentialReference(_accountId)] =
        current;
    final restored = await service.restoreAccount(
      accountId: _accountId,
      name: '导入',
      credentials: const RemoteCredentials(
        openListDriver: '123 Open',
        openListAuthorization: {'RefreshToken': 'old-backup'},
      ),
    );
    expect(restored, current);
    expect(rpc.calls, isEmpty);
    expect(
      await credentials.read(OpenListService.credentialReference(_accountId)),
      current,
    );
  });

  test('首次使用时才将恢复的授权加载到内核', () async {
    await service.restoreAccount(
      accountId: _accountId,
      name: '恢复账号',
      credentials: const RemoteCredentials(
        openListDriver: 'Quark',
        openListAuthorization: {'cookie': '__pus=restored'},
      ),
    );
    expect(rpc.calls, isEmpty);
    rpc.fileOperation = (method, arguments) => {
      'data': {'entries': <Map<String, dynamic>>[]},
    };
    expect(await service.list(_accountId, '/Movies'), isEmpty);
    final saves = rpc.calls.where((call) => call.method == 'saveAccount');
    expect(saves, hasLength(1));
    expect(saves.single.arguments['addition'], {'cookie': '__pus=restored'});
    expect(
      rpc.calls.where((call) => call.method == 'releaseTask'),
      hasLength(1),
    );
  });

  test('已有内核授权优先于旧安全快照，文件访问不会覆盖轮换 Token', () async {
    rpc.putAccount(_accountId, '115 Open', {'refresh_token': 'native-new'});
    await service.restoreAccount(
      accountId: _accountId,
      name: '导入',
      credentials: const RemoteCredentials(
        openListDriver: '115 Open',
        openListAuthorization: {'refresh_token': 'backup-old'},
      ),
    );
    rpc.fileOperation = (_, _) => {
      'data': {'entries': <Map<String, dynamic>>[]},
    };
    await service.list(_accountId, '/');
    expect(rpc.calls.where((call) => call.method == 'saveAccount'), isEmpty);
    expect(rpc.accounts[_accountId]!['addition'], {
      'refresh_token': 'native-new',
    });
    expect(
      (await service.readAccount(_accountId))
          .openListAuthorization['refresh_token'],
      'native-new',
    );
  });

  test('共享账号仍有媒体源引用时不删除，最后引用移除后清理内核及快照', () async {
    final active = <String>{_accountId};
    await service.close();
    service = OpenListService(
      rpc: rpc,
      credentials: credentials,
      dataDirectory: () async => '/reelva/openlist',
      activeAccountIds: () async => active,
    );
    rpc.putAccount(_accountId, 'Quark', {'cookie': '__pus=shared'});
    credentials.values[OpenListService.credentialReference(
      _accountId,
    )] = const RemoteCredentials(
      openListDriver: 'Quark',
      openListAuthorization: {'cookie': '__pus=shared'},
    );
    await service.initialize();
    await service.deleteAccount(_accountId);
    expect(rpc.accounts.containsKey(_accountId), isTrue);
    expect(credentials.deleted, isEmpty);
    active.clear();
    await service.deleteAccount(_accountId);
    expect(rpc.accounts.containsKey(_accountId), isFalse);
    expect(
      credentials.values.containsKey(
        OpenListService.credentialReference(_accountId),
      ),
      isFalse,
    );
    expect(
      rpc.calls.where((call) => call.method == 'deleteAccount'),
      hasLength(1),
    );
  });

  test('启动清理仅处理无源引用的内核账号及其凭据快照', () async {
    await service.close();
    service = OpenListService(
      rpc: rpc,
      credentials: credentials,
      dataDirectory: () async => '/reelva/openlist',
      activeAccountIds: () async => {_accountId},
    );
    rpc.putAccount(_accountId, 'Quark', {'cookie': 'kept'});
    rpc.putAccount(_secondAccountId, 'Quark', {'cookie': 'orphan'});
    credentials.values[OpenListService.credentialReference(
      _secondAccountId,
    )] = const RemoteCredentials(
      openListDriver: 'Quark',
      openListAuthorization: {'cookie': 'orphan'},
    );
    await service.initialize();
    expect(rpc.accounts.keys, [_accountId]);
    expect(credentials.deleted, [
      OpenListService.credentialReference(_secondAccountId),
    ]);
  });

  test('新建账号的安全快照保存失败会移除刚建的内核账号', () async {
    credentials.failWrites = true;
    await expectLater(
      service.saveAccount(
        accountId: _accountId,
        driver: 'Quark',
        name: '新账号',
        addition: const {'cookie': 'new-cookie'},
      ),
      throwsA(
        isA<MediaSourceException>().having(
          (e) => e.code,
          'code',
          'credential_storage_failed',
        ),
      ),
    );
    expect(rpc.accounts, isEmpty);
  });

  test('网盘错误只暴露安全消息，失败目录枚举仍释放任务', () async {
    rpc.putAccount(_accountId, '115 Open', {'refresh_token': 'native-token'});
    rpc.fileOperation = (_, _) => const {
      'error': {
        'code': 'unauthorized',
        'message': 'refresh_token=private-provider-secret https://signed.test/?token=private',
      },
    };
    await expectLater(
      service.list(_accountId, '/Movies'),
      throwsA(
        isA<MediaSourceException>()
            .having((e) => e.code, 'code', 'unauthorized')
            .having(
              (e) => e.toString(),
              'safe text',
              allOf(
                isNot(contains('private-provider-secret')),
                isNot(contains('signed.test')),
              ),
            ),
      ),
    );
    expect(
      rpc.calls.where((call) => call.method == 'releaseTask'),
      hasLength(1),
    );
  });

  test('初始化等待期间取消目录任务不提交 list 并释放任务', () async {
    await service.close();
    final entered = Completer<void>();
    final directory = Completer<String>();
    service = OpenListService(
      rpc: rpc,
      credentials: credentials,
      dataDirectory: () {
        entered.complete();
        return directory.future;
      },
    );
    rpc.putAccount(_accountId, 'Quark', {'cookie': 'active'});
    final listing = service.list(_accountId, '/', taskId: 'initializing-task');
    final cancelled = expectLater(
      listing,
      throwsA(
        isA<MediaSourceException>().having((e) => e.code, 'code', 'cancelled'),
      ),
    );
    await entered.future;
    await service.cancel('initializing-task');
    directory.complete('/reelva/openlist');
    await cancelled;
    expect(rpc.calls.where((call) => call.method == 'list'), isEmpty);
    expect(
      rpc.calls.where((call) => call.method == 'releaseTask').single.arguments,
      {'accountId': _accountId, 'taskId': 'initializing-task'},
    );
  });

  test('初始化尚未启动时立即取消也不提交目录请求', () async {
    rpc.putAccount(_accountId, 'Quark', {'cookie': 'active'});
    final listing = service.list(_accountId, '/', taskId: 'early-task');
    final cancelled = expectLater(
      listing,
      throwsA(
        isA<MediaSourceException>().having((e) => e.code, 'code', 'cancelled'),
      ),
    );
    await service.cancel('early-task');
    await cancelled;
    expect(rpc.calls.where((call) => call.method == 'list'), isEmpty);
    expect(
      rpc.calls.where((call) => call.method == 'releaseTask'),
      hasLength(1),
    );
  });

  test('运行中的目录任务可以取消并在结束后释放', () async {
    rpc.putAccount(_accountId, 'Quark', {'cookie': 'active'});
    final entered = Completer<void>();
    final result = Completer<Map<String, dynamic>>();
    rpc.fileOperation = (_, _) {
      entered.complete();
      return result.future;
    };
    final listing = service.list(_accountId, '/', taskId: 'directory-task');
    await entered.future;
    await service.cancelAccount(_accountId);
    expect(
      rpc.calls.where((call) => call.method == 'cancel').single.arguments,
      {'accountId': _accountId, 'taskId': 'directory-task'},
    );
    result.complete({
      'data': {'entries': <Map<String, dynamic>>[]},
    });
    expect(await listing, isEmpty);
    expect(
      rpc.calls
          .where((call) => call.method == 'releaseTask')
          .single
          .arguments['taskId'],
      'directory-task',
    );
  });
}
