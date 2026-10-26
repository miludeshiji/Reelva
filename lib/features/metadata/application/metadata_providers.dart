import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/logging/app_logger.dart';
import '../../library/domain/library_work.dart';
import '../../sources/application/source_providers.dart';
import '../domain/tmdb_models.dart';
import '../infrastructure/tmdb_cache.dart';
import '../infrastructure/tmdb_client.dart';
import '../infrastructure/tmdb_token_store.dart';
import 'metadata_service.dart';
import 'nfo_providers.dart';

export 'metadata_service.dart';

/// 元数据后台任务状态
@immutable
class MetadataTaskState {
  final bool running;
  final MetadataRefreshResult? result;
  final String? error;
  final MetadataPhase phase;
  final int processed;
  final int? total;
  final int activeCount;

  const MetadataTaskState({
    this.running = false,
    this.result,
    this.error,
    this.phase = MetadataPhase.recognizing,
    this.processed = 0,
    this.total,
    this.activeCount = 0,
  });

  MetadataTaskState copyWith({
    bool? running,
    MetadataRefreshResult? result,
    String? error,
    bool clearError = false,
    MetadataPhase? phase,
    int? processed,
    int? total,
    int? activeCount,
  }) {
    return MetadataTaskState(
      running: running ?? this.running,
      result: result ?? this.result,
      error: clearError ? null : (error ?? this.error),
      phase: phase ?? this.phase,
      processed: processed ?? this.processed,
      total: total ?? this.total,
      activeCount: activeCount ?? this.activeCount,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MetadataTaskState &&
          runtimeType == other.runtimeType &&
          running == other.running &&
          result == other.result &&
          error == other.error &&
          phase == other.phase &&
          processed == other.processed &&
          total == other.total &&
          activeCount == other.activeCount;

  @override
  int get hashCode =>
      Object.hash(running, result, error, phase, processed, total, activeCount);

  @override
  String toString() =>
      'MetadataTaskState(running: $running, result: $result, error: $error)';
}

/// TMDB 凭据安全存储 Provider
final tmdbTokenStoreProvider = Provider<TmdbTokenStore>((ref) {
  return const TmdbTokenStore();
});

/// TMDB 凭据配置状态 Provider
final tmdbCredentialConfiguredProvider = FutureProvider<bool>((ref) async {
  final store = ref.watch(tmdbTokenStoreProvider);
  return (await store.read()) != null;
});

/// TMDB HTTP 客户端 Provider（挂载 Drift 本地缓存）
final tmdbClientProvider = Provider<TmdbClient>((ref) {
  final tokenStore = ref.watch(tmdbTokenStoreProvider);
  final db = ref.watch(appDatabaseProvider);
  final client = TmdbClient(tokenStore: tokenStore, cache: DriftTmdbCache(db));
  ref.onDispose(() {
    client.dispose();
  });
  return client;
});

/// 影视元数据核心服务 Provider
final metadataServiceProvider = Provider<MetadataService>((ref) {
  final client = ref.watch(tmdbClientProvider);
  final repo = ref.watch(mediaLibraryRepositoryProvider);
  final tokenStore = ref.watch(tmdbTokenStoreProvider);
  return MetadataService(
    tmdbClient: client,
    mediaLibraryRepository: repo,
    tokenStore: tokenStore,
    saveMetadataFiles:
        ({
          int? workId,
          List<int>? fileIds,
          bool replaceIdentity = false,
        }) async {
          await ref
              .read(nfoControllerProvider.notifier)
              .export(
                workId: workId,
                fileIds: fileIds,
                replaceIdentity: replaceIdentity,
              );
        },
  );
});

/// 元数据刷新控制器
class MetadataController extends Notifier<MetadataTaskState> {
  bool _hasQueuedRefresh = false;

  @override
  MetadataTaskState build() {
    return const MetadataTaskState();
  }

  /// 触发元数据批量刷新
  ///
  /// 捕获并映射异常至安全错误状态，保证绝不向上层逃逸未捕获异常。
  /// 若当前已有刷新正在执行，标记并确保在当前刷新结束后再次执行，避免漏掉并发扫描完成的源。
  Future<void> refresh() async {
    if (state.running) {
      _hasQueuedRefresh = true;
      return;
    }

    do {
      _hasQueuedRefresh = false;
      if (!ref.mounted) return;
      state = const MetadataTaskState(running: true);

      try {
        final service = ref.read(metadataServiceProvider);
        final res = await service.refresh(
          onProgress: (phase, processed, total) {
            if (!ref.mounted) return;
            state = state.copyWith(
              phase: phase,
              processed: processed,
              total: total,
            );
          },
          onActiveChanged: (active) {
            if (ref.mounted) state = state.copyWith(activeCount: active);
          },
        );
        if (!ref.mounted) return;

        // 成功完成时刷新凭据配置缓存状态
        ref.invalidate(tmdbCredentialConfiguredProvider);

        state = state.copyWith(
          running: false,
          activeCount: 0,
          result: res,
          error: res.errors.isNotEmpty ? res.errors.join('; ') : null,
        );
      } catch (e, st) {
        AppLogger.instance.error('元数据任务执行异常', error: e, stackTrace: st);
        if (!ref.mounted) return;

        final safeMessage = e is MetadataException
            ? e.message
            : '元数据刷新失败，请检查网络或密钥设置';
        state = state.copyWith(
          running: false,
          activeCount: 0,
          error: safeMessage,
        );
      }
    } while (_hasQueuedRefresh && ref.mounted);
  }
}

/// 元数据后台任务控制器 Provider
final metadataControllerProvider =
    NotifierProvider<MetadataController, MetadataTaskState>(
      MetadataController.new,
    );

/// 媒体作品列表流 Provider（分页 / 数量限制）
final libraryWorksProvider = StreamProvider.autoDispose
    .family<List<LibraryWork>, int>((ref, limit) {
      final repo = ref.watch(mediaLibraryRepositoryProvider);
      return repo.watchWorks(limit: limit, matchedOnly: true);
    });

typedef LibraryWorksFilter = ({
  int limit,
  String search,
  String? type,
  bool recentlyAdded,
  bool unmatchedOnly,
});

final filteredLibraryWorksProvider = StreamProvider.autoDispose
    .family<List<LibraryWork>, LibraryWorksFilter>((ref, filter) {
      final repo = ref.watch(mediaLibraryRepositoryProvider);
      return repo.watchWorks(
        limit: filter.limit,
        search: filter.search,
        type: filter.type,
        recentlyAdded: filter.recentlyAdded,
        unmatchedOnly: filter.unmatchedOnly,
        matchedOnly: !filter.unmatchedOnly,
      );
    });

/// 作品详情流 Provider
final workDetailsProvider = StreamProvider.autoDispose
    .family<WorkDetails?, int>((ref, workId) {
      final repo = ref.watch(mediaLibraryRepositoryProvider);
      return repo.watchWorkDetails(workId);
    });
