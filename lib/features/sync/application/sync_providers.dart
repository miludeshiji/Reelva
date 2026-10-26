import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../sources/application/source_providers.dart';
import '../../player/application/player_settings_provider.dart';
import '../../metadata/application/metadata_providers.dart';
import '../domain/application_sync.dart';
import '../infrastructure/application_sync_store.dart';
import '../domain/sync_models.dart';
import '../domain/sync_transport.dart';
import '../infrastructure/sync_configuration_store.dart';
import '../infrastructure/sync_repository.dart';
import '../infrastructure/webdav_sync_transport.dart';
import 'sync_service.dart';
import 'application_sync_service.dart';

/// 同步仓库 Provider
final syncRepositoryProvider = Provider<SyncRepository>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return SyncRepository(db);
});

/// 同步配置安全存储 Provider
final syncConfigurationStoreProvider = Provider<SyncConfigurationStore>((ref) {
  return SyncConfigurationStore();
});

/// 异步读取已配置的同步凭据 Provider（仅读取安全存储，绝不触发自动网络请求）
final syncConfigurationProvider = FutureProvider<SyncConfiguration?>((
  ref,
) async {
  final store = ref.watch(syncConfigurationStoreProvider);
  return store.read();
});

final applicationSyncStoreProvider = Provider<ApplicationSyncStore>((ref) {
  return ApplicationSyncStore(
    repository: ref.watch(mediaLibraryRepositoryProvider),
    credentials: ref.watch(remoteCredentialsStoreProvider),
    tmdb: ref.watch(tmdbTokenStoreProvider),
    player: ref.watch(playerSettingsStoreProvider),
    deviceId: ref.watch(syncRepositoryProvider).deviceId,
  );
});

final pendingSourceBindingsProvider =
    FutureProvider<List<PendingSourceBinding>>((ref) async {
      final config = await ref.watch(syncConfigurationProvider.future);
      if (config == null || config.encryptionPassword.isEmpty) return [];
      return ref
          .watch(applicationSyncStoreProvider)
          .pendingSources(config.endpoint.toString());
    });

/// 基于配置构建的 WebDAV 同步传输层 Provider
final syncTransportProvider = Provider.family<SyncTransport, SyncConfiguration>(
  (ref, config) {
    final http = ref.watch(remoteHttpClientProvider);
    return WebDavSyncTransport(http: http, configuration: config);
  },
);

/// 基于配置构建的同步应用层服务 Provider
final syncServiceProvider = Provider.family<SyncService, SyncConfiguration>((
  ref,
  config,
) {
  final repository = ref.watch(syncRepositoryProvider);
  final transport = ref.watch(syncTransportProvider(config));
  return SyncService(
    repository: repository,
    transport: transport,
    applicationSync: config.encryptionPassword.isEmpty
        ? null
        : ApplicationSyncService(
            store: ref.watch(applicationSyncStoreProvider),
            transport: WebDavSyncTransport(
              http: ref.watch(remoteHttpClientProvider),
              configuration: config,
            ),
            scope: config.endpoint.toString(),
            password: config.encryptionPassword,
            onApplied: () async {
              await ref.read(playerSettingsProvider.notifier).reload();
              ref.invalidate(tmdbCredentialConfiguredProvider);
              ref.invalidate(pendingSourceBindingsProvider);
            },
          ),
  );
});

/// 同步状态实体
class SyncState {
  final bool running;
  final bool configuring;
  final SyncReport? report;
  final String? error;

  const SyncState({
    this.running = false,
    this.configuring = false,
    this.report,
    this.error,
  });

  bool get isRunning => running;
  bool get isConfiguring => configuring;
  bool get isBusy => running || configuring;
  bool get hasReport => report != null;
  bool get hasError => error != null;

  SyncState copyWith({
    bool? running,
    bool? configuring,
    SyncReport? report,
    String? error,
    bool clearReport = false,
    bool clearError = false,
  }) {
    return SyncState(
      running: running ?? this.running,
      configuring: configuring ?? this.configuring,
      report: clearReport ? null : (report ?? this.report),
      error: clearError ? null : (error ?? this.error),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SyncState &&
          runtimeType == other.runtimeType &&
          running == other.running &&
          configuring == other.configuring &&
          report == other.report &&
          error == other.error;

  @override
  int get hashCode => Object.hash(running, configuring, report, error);

  @override
  String toString() =>
      'SyncState(running: $running, configuring: $configuring, report: $report, error: $error)';
}

/// 同步业务控制器
///
/// 管理手动同步触发、配置更新与服务禁用：
/// - 同步或配置写入进行中严禁相互竞争（isBusy 保护）；
/// - 单飞机制：同步函数立即同步设定 running 并复用活跃 Future；
/// - 端点发生变化时，先重置传输层同步记账（resetTransport），保留本地历史/媒体；再持久化新配置；
/// - 禁用时清除安全存储配置，不再执行任何网络同步。
class SyncController extends Notifier<SyncState> {
  Future<SyncReport>? _activeSync;

  @override
  SyncState build() {
    return const SyncState();
  }

  /// 执行手动同步流程
  ///
  /// 同步函数立即同步设置 running 状态并复用或登记活跃 Future，
  /// 防止 save/disable 在异步等待配置读取时产生竞态。
  Future<SyncReport> synchronize() {
    if (_activeSync != null) {
      return _activeSync!;
    }

    if (state.isBusy) {
      const errorMsg = '正在修改配置，无法同步';
      state = state.copyWith(error: errorMsg);
      return Future.error(const SyncException(errorMsg));
    }

    state = state.copyWith(running: true, clearError: true);

    final future = _doSynchronize().whenComplete(() {
      _activeSync = null;
    });
    _activeSync = future;
    return future;
  }

  Future<SyncReport> _doSynchronize() async {
    try {
      final store = ref.read(syncConfigurationStoreProvider);
      final config = await store.read();
      if (config == null) {
        throw const SyncException('未配置 WebDAV 同步服务');
      }

      final service = ref.read(syncServiceProvider(config));
      final report = await service.synchronize();
      state = state.copyWith(running: false, report: report, clearError: true);
      return report;
    } catch (e) {
      final safeMessage = _sanitizeError(e);
      state = state.copyWith(running: false, error: safeMessage);
      if (e is SyncException) {
        rethrow;
      }
      throw SyncException(safeMessage);
    }
  }

  /// 保存同步配置
  ///
  /// 同步进行中或配置写入中禁止修改配置；
  /// 端点发生变化时，先重置传输记录（避免新端点使用旧游标丢失变更），
  /// 然后持久化新配置到安全存储。
  Future<void> saveConfiguration(SyncConfiguration configuration) async {
    if (state.isBusy || _activeSync != null) {
      const errorMsg = '同步或配置进行中，无法修改配置';
      state = state.copyWith(error: errorMsg);
      throw const SyncException(errorMsg);
    }

    state = state.copyWith(configuring: true, clearError: true);
    final store = ref.read(syncConfigurationStoreProvider);
    final repository = ref.read(syncRepositoryProvider);

    try {
      final existing = await store.read();
      final endpointChanged = existing?.endpoint != configuration.endpoint;

      if (endpointChanged) {
        // 先重置传输记录，防止新端点遗留旧游标
        await repository.resetTransport();
      }

      await store.save(configuration);
      ref.invalidate(syncConfigurationProvider);
      state = state.copyWith(configuring: false);
    } catch (e) {
      final safeMessage = _sanitizeError(e);
      state = state.copyWith(configuring: false, error: safeMessage);
      if (e is SyncException) {
        rethrow;
      }
      throw SyncException(safeMessage);
    }
  }

  /// 禁用并清除同步配置
  ///
  /// 同步进行中或配置写入中禁止禁用；
  /// 成功禁用后删除安全存储，不影响本地媒体与播放数据。
  Future<void> disable() async {
    if (state.isBusy || _activeSync != null) {
      const errorMsg = '同步或配置进行中，无法禁用同步';
      state = state.copyWith(error: errorMsg);
      throw const SyncException(errorMsg);
    }

    state = state.copyWith(configuring: true, clearError: true);
    final store = ref.read(syncConfigurationStoreProvider);

    try {
      await store.delete();
      ref.invalidate(syncConfigurationProvider);
      state = const SyncState();
    } catch (e) {
      final safeMessage = _sanitizeError(e);
      state = state.copyWith(configuring: false, error: safeMessage);
      if (e is SyncException) {
        rethrow;
      }
      throw SyncException(safeMessage);
    }
  }

  /// 错误脱敏：使用已校验的 SyncException 白名单消息，其他异常使用固定安全文案
  static String _sanitizeError(Object error) {
    if (error is SyncException) {
      return error.message;
    }
    return '同步操作失败，请检查网络或服务配置';
  }
}

/// 同步业务控制器 Provider
final syncControllerProvider = NotifierProvider<SyncController, SyncState>(
  SyncController.new,
);
