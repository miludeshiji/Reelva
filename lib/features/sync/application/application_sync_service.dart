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
      final remote = snapshot == null
          ? const ApplicationSyncDocument({})
          : ApplicationSyncDocument.fromJson(
              await cipher.decrypt(snapshot.body, password),
            );
      local = local.merge(remote);
      if (canonicalJson(local.toJson()) != canonicalJson(remote.toJson())) {
        final body = await cipher.encrypt(local.toJson(), password);
        if (!await transport.uploadApplicationData(
          body,
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
