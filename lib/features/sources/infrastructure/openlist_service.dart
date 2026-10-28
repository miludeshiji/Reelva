import 'dart:async';
import 'dart:math';

import 'package:path_provider/path_provider.dart';

import '../domain/openlist_models.dart';
import '../domain/source_models.dart';
import 'openlist_rpc.dart';
import 'remote_credentials_store.dart';

/// 内核数据库保存实时授权；安全存储保存可迁移快照，导出前从内核回读。
class OpenListService {
  OpenListService({
    required this.rpc,
    required this.credentials,
    Future<String> Function()? dataDirectory,
    this.activeAccountIds,
  }) : _dataDirectory = dataDirectory ?? _defaultDirectory;

  final OpenListRpcClient rpc;
  final RemoteCredentialsStore credentials;
  final Future<String> Function() _dataDirectory;
  final Future<Set<String>> Function()? activeAccountIds;
  Future<void>? _initializing;
  final Map<String, Future<void>> _accountQueues = {};
  final Map<String, String> _tasks = {};
  final Set<String> _cancelledTasks = {};
  bool _closed = false;
  int _sequence = 0;

  static Future<String> _defaultDirectory() async =>
      '${(await getApplicationSupportDirectory()).path}/openlist';
  static String credentialReference(String accountId) =>
      'cred_openlist_$accountId';

  Future<void> initialize() {
    if (_closed) {
      throw const MediaSourceException('网盘内核已关闭', code: 'core_closed');
    }
    return _initializing ??= _initialize().catchError((Object error) {
      _initializing = null;
      throw error;
    });
  }

  Future<void> _initialize() async {
    await _data('initialize', {'dataDir': await _dataDirectory()});
    final active = await activeAccountIds?.call();
    if (active != null) {
      for (final account in await _nativeAccounts()) {
        final id = account['id'] as String;
        if (!active.contains(id)) {
          await _data('deleteAccount', {'id': id});
          await credentials.delete(credentialReference(id));
        }
      }
    }
  }

  Future<T> _serialize<T>(String id, Future<T> Function() action) async {
    final previous = _accountQueues[id] ?? Future<void>.value();
    final done = Completer<void>();
    _accountQueues[id] = done.future;
    try {
      await previous;
      if (_closed) {
        throw const MediaSourceException('网盘内核已关闭', code: 'core_closed');
      }
      return await action();
    } finally {
      done.complete();
      if (identical(_accountQueues[id], done.future)) _accountQueues.remove(id);
    }
  }

  Future<List<Map<String, dynamic>>> _nativeAccounts() async {
    final result = await _data('accounts', const {});
    final raw = result['accounts'];
    if (raw is! List) {
      throw const MediaSourceException('网盘账号响应无效', code: 'invalid_response');
    }
    return raw.map((value) => Map<String, dynamic>.from(value as Map)).toList();
  }

  Future<Map<String, dynamic>?> _nativeAccount(String id) async =>
      (await _nativeAccounts()).where((value) => value['id'] == id).firstOrNull;

  RemoteCredentials _nativeCredentials(Map<String, dynamic> account) {
    final driver = account['driver'];
    final addition = account['addition'];
    if (driver is! String ||
        !openListDrivers.containsKey(driver) ||
        addition is! Map) {
      throw const MediaSourceException(
        '网盘账号配置无效',
        code: 'invalid_cloud_account',
      );
    }
    return RemoteCredentials(
      openListDriver: driver,
      openListAuthorization: Map<String, dynamic>.from(addition),
    );
  }

  Future<RemoteCredentials> _readSaved(String id) =>
      credentials.read(credentialReference(id));

  Future<RemoteCredentials> _ensureAccount(String id) async {
    await initialize();
    final native = await _nativeAccount(id);
    if (native != null) return _nativeCredentials(native);
    final saved = await _readSaved(id);
    _validate(saved);
    await _data('saveAccount', {
      'id': id,
      'driver': saved.openListDriver,
      'name': openListDrivers[saved.openListDriver],
      'addition': saved.openListAuthorization,
    });
    final created = await _nativeAccount(id);
    if (created == null) {
      throw const MediaSourceException('网盘账号不存在', code: 'credential_not_found');
    }
    return _nativeCredentials(created);
  }

  Future<String> saveAccount({
    String? accountId,
    required String driver,
    required String name,
    required Map<String, dynamic> addition,
  }) async {
    final id =
        accountId ??
        List<int>.generate(
          16,
          (_) => Random.secure().nextInt(256),
        ).map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
    buildOpenListRoot(id, '/');
    _validate(
      RemoteCredentials(
        openListDriver: driver,
        openListAuthorization: addition,
      ),
    );
    return _serialize(id, () async {
      await initialize();
      final previous = await _nativeAccount(id);
      try {
        await _data('saveAccount', {
          'id': id,
          'driver': driver,
          'name': name,
          'addition': addition,
        });
        final updated = await _nativeAccount(id);
        if (updated == null) {
          throw const MediaSourceException(
            '网盘账号保存失败',
            code: 'invalid_response',
          );
        }
        await credentials.write(
          credentialReference(id),
          _nativeCredentials(updated),
        );
      } catch (_) {
        if (previous == null && await _nativeAccount(id) != null) {
          await _data('deleteAccount', {'id': id});
        }
        rethrow;
      }
      return id;
    });
  }

  Future<RemoteCredentials> readAccount(String accountId) =>
      _serialize(accountId, () async {
        await initialize();
        final native = await _nativeAccount(accountId);
        final current = native == null
            ? await _readSaved(accountId)
            : _nativeCredentials(native);
        _validate(current);
        await credentials.write(credentialReference(accountId), current);
        return current;
      });

  /// 配置恢复不触网，不用旧备份覆盖设备上已有授权；使用时再加载到内核。
  Future<RemoteCredentials> restoreAccount({
    required String accountId,
    required String name,
    required RemoteCredentials credentials,
  }) => _serialize(accountId, () async {
    buildOpenListRoot(accountId, '/');
    _validate(credentials);
    try {
      final current = await _readSaved(accountId);
      if (current.openListDriver != null &&
          current.openListAuthorization.isNotEmpty) {
        return current;
      }
    } on MediaSourceException catch (error) {
      if (error.code != 'credential_not_found') rethrow;
    }
    await this.credentials.write(credentialReference(accountId), credentials);
    return credentials;
  });

  Future<void> deleteAccount(String accountId) =>
      _serialize(accountId, () async {
        if ((await activeAccountIds?.call())?.contains(accountId) ?? false) {
          return;
        }
        await initialize();
        if (await _nativeAccount(accountId) != null) {
          await _data('deleteAccount', {'id': accountId});
        }
        await credentials.delete(credentialReference(accountId));
      });

  String newTaskId() =>
      'reelva-${DateTime.now().microsecondsSinceEpoch}-${_sequence++}';

  Future<Map<String, dynamic>> operation(
    String method,
    String accountId,
    Map<String, dynamic> arguments, {
    String? taskId,
  }) async {
    final id = taskId ?? newTaskId();
    _tasks[id] = accountId;
    try {
      await _serialize(accountId, () => _ensureAccount(accountId));
      if (_cancelledTasks.contains(id)) {
        throw const MediaSourceException('网盘操作已取消', code: 'cancelled');
      }
      return await _data(method, {
        'accountId': accountId,
        ...arguments,
        'taskId': id,
      });
    } finally {
      _tasks.remove(id);
      _cancelledTasks.remove(id);
      if (_initializing != null) {
        await _data('releaseTask', {'accountId': accountId, 'taskId': id});
      }
    }
  }

  Future<List<OpenListEntry>> list(
    String accountId,
    String path, {
    bool refresh = false,
    String? taskId,
  }) async {
    final data = await operation('list', accountId, {
      'path': normalizeOpenListPath(path),
      'refresh': refresh,
    }, taskId: taskId);
    final entries = data['entries'];
    if (entries is! List) {
      throw const MediaSourceException('网盘目录响应无效', code: 'invalid_response');
    }
    return entries
        .map(
          (entry) =>
              OpenListEntry.fromJson(Map<String, dynamic>.from(entry as Map)),
        )
        .toList();
  }

  Future<OpenListEntry> stat(String accountId, String path) async =>
      OpenListEntry.fromJson(
        await operation('stat', accountId, {
          'path': normalizeOpenListPath(path),
        }),
      );

  Future<Map<String, dynamic>> link(
    String accountId,
    String path, {
    String? taskId,
  }) => operation('link', accountId, {
    'path': normalizeOpenListPath(path),
  }, taskId: taskId);

  Future<void> cancel(String taskId) async {
    final account = _tasks[taskId];
    if (account == null) return;
    _cancelledTasks.add(taskId);
    if (_initializing != null) {
      await _data('cancel', {'accountId': account, 'taskId': taskId});
    }
  }

  Future<void> cancelAccount(String accountId) async {
    for (final task
        in _tasks.entries.where((entry) => entry.value == accountId).toList()) {
      await cancel(task.key);
    }
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    final initialization = _initializing;
    if (initialization == null) return;
    try {
      await initialization;
      await _data('close', const {});
    } finally {
      _initializing = null;
    }
  }

  static void _validate(RemoteCredentials value) {
    if (!openListDrivers.containsKey(value.openListDriver) ||
        value.openListAuthorization.isEmpty) {
      throw const MediaSourceException(
        '网盘授权信息不完整，请重新登录',
        code: 'invalid_cloud_account',
      );
    }
  }

  Future<Map<String, dynamic>> _data(
    String method,
    Map<String, dynamic> arguments,
  ) async {
    final response = await rpc.invoke(method, arguments);
    final error = response['error'];
    if (error is Map) {
      final rawCode = error['code'];
      final code =
          const {
            'unauthorized',
            'invalid_token',
            'not_found',
            'cancelled',
            'operation_failed',
            'invalid_response',
            'invalid_request',
            'internal',
            'unavailable',
          }.contains(rawCode)
          ? rawCode as String
          : 'operation_failed';
      throw MediaSourceException(switch (code) {
        'unauthorized' || 'invalid_token' => '网盘登录已失效，请重新授权',
        'not_found' => '网盘文件或目录不存在',
        'cancelled' => '网盘操作已取消',
        _ => '网盘操作失败，请检查网络或重新授权',
      }, code: code);
    }
    final value = response['data'];
    return value is Map ? Map<String, dynamic>.from(value) : const {};
  }
}
