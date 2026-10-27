import 'dart:convert';

import '../domain/application_sync.dart';
import '../domain/sync_models.dart';
import '../infrastructure/application_sync_store.dart';
import '../infrastructure/sync_cipher.dart';

class ApplicationSyncService {
  ApplicationSyncService({
    required this.store,
    required this.transport,
    required this.scope,
    required this.password,
    this.onApplied,
  });

  final ApplicationSyncStore store;
  final ApplicationSyncTransport transport;
  final String scope;
  final String password;
  final Future<void> Function()? onApplied;

  Future<int> synchronize() async {
    var local = await store.capture(scope);
    final cipher = SyncCipher();
    for (var attempt = 0; attempt < 3; attempt++) {
      final snapshot = await transport.downloadApplicationData();
      var remote = const ApplicationSyncDocument({});
      var encrypted = false;
      for (final body
          in snapshot == null
              ? <String>[]
              : [snapshot.body, ...snapshot.updates]) {
        final remoteJson = jsonDecode(body) as Map<String, dynamic>;
        final isEncrypted = remoteJson.containsKey('format');
        if (isEncrypted && password.isEmpty) {
          throw const SyncException('远端配置已加密，请填写原同步加密密码后重试');
        }
        encrypted = encrypted || isEncrypted;
        remote = remote.merge(
          ApplicationSyncDocument.fromJson(
            isEncrypted ? await cipher.decrypt(body, password) : remoteJson,
          ),
        );
      }
      local = local.merge(remote);
      if (snapshot == null ||
          canonicalJson(local.toJson()) != canonicalJson(remote.toJson()) ||
          encrypted != password.isNotEmpty) {
        final body = password.isEmpty
            ? jsonEncode(local.toJson())
            : await cipher.encrypt(local.toJson(), password);
        if (!await transport.uploadApplicationData(
          body,
          deviceId: await store.deviceId(),
          etag: snapshot?.etag,
        )) {
          continue;
        }
      }
      final applied = await store.apply(scope, local);
      await onApplied?.call();
      return applied;
    }
    throw const SyncException('其他设备正在更新配置，请稍后重新同步');
  }
}
