import 'dart:async';

import '../../../core/logging/app_logger.dart';
import '../domain/sync_models.dart';
import '../domain/sync_transport.dart';
import '../infrastructure/sync_repository.dart';
import 'application_sync_service.dart';

/// 跨设备同步应用层服务
///
/// 遵循 M6 契约规范：
/// - 单飞 (Single-Flight) 机制：同一服务实例在同步进行时，新的调用直接复用当前的 Future；
/// - 严格的执行顺序：
///   1. captureLocalChanges（捕获本地观看进度变更）；
///   2. 准备持久化发件箱批次并上传（upload -> acknowledgeUpload 循环直至无未发送批次）；
///   3. 列出远程批次（listBatches），基于本地游标（readCursors）过滤增量批次；
///   4. 严格按序列下载（download）并事务合并（acceptBatch），更新游标；
///   5. 执行 applyPending，将等待本地匹配的远程记录应用至最新匹配项；
///   6. 统计上报 SyncReport（uploaded/downloaded 记录数、applied 来自仓库、pending 与 localOnly 统计）。
class SyncService {
  SyncService({
    required this.repository,
    required this.transport,
    this.applicationSync,
  });

  final SyncRepository repository;
  final SyncTransport transport;
  final ApplicationSyncService? applicationSync;

  Future<SyncReport>? _activeSync;

  /// 执行一次完整的双向增量同步
  Future<SyncReport> synchronize() {
    if (_activeSync != null) {
      return _activeSync!;
    }

    final watch = Stopwatch()..start();
    AppLogger.instance.info('开始跨设备同步', module: '同步');
    final future = _doSynchronize()
        .then(
          (report) {
            AppLogger.instance.info(
              '同步完成：上传=${report.uploaded}，下载=${report.downloaded}，应用=${report.applied}，待应用=${report.pending}，耗时=${watch.elapsedMilliseconds}ms',
              module: '同步',
            );
            return report;
          },
          onError: (Object error, StackTrace stack) {
            AppLogger.instance.error(
              '跨设备同步失败，耗时=${watch.elapsedMilliseconds}ms',
              module: '同步',
              error: error,
              stackTrace: stack,
            );
            Error.throwWithStackTrace(error, stack);
          },
        )
        .whenComplete(() {
          _activeSync = null;
        });
    _activeSync = future;
    return future;
  }

  Future<SyncReport> _doSynchronize() async {
    AppLogger.instance.info('同步应用配置与影视库索引', module: '同步');
    final configurationApplied = await applicationSync?.synchronize() ?? 0;
    // 1. 捕获本地最新变更至出站待同步记录
    await repository.captureLocalChanges();

    // 2. 依次读取并上传发件箱批次
    int uploadedRecords = 0;
    AppLogger.instance.info('上传观看进度增量', module: '同步');
    while (true) {
      final batch = await repository.prepareUpload();
      if (batch == null) {
        break;
      }
      await transport.upload(batch);
      await repository.acknowledgeUpload(batch);
      uploadedRecords += batch.records.length;
    }

    // 3. 列出远程批次并读取本地各设备游标
    final remoteBatches = await transport.listBatches();
    AppLogger.instance.info(
      '下载并合并观看进度：远端批次=${remoteBatches.length}',
      module: '同步',
    );
    final cursors = await repository.readCursors();

    // 4. 游标增量过滤：仅保留序号大于本地已持久化游标的批次
    final eligibleBatches = remoteBatches.where((b) {
      final lastSeq = cursors[b.deviceId] ?? 0;
      return b.sequence > lastSeq;
    }).toList();

    // 5. 确定性排序：先按设备标识升序，同设备严格按序列号递增应用
    eligibleBatches.sort((a, b) {
      final c = a.deviceId.compareTo(b.deviceId);
      if (c != 0) return c;
      return a.sequence.compareTo(b.sequence);
    });

    // 6. 下载并合入远端批次
    int downloadedRecords = 0;
    int appliedCount = 0;

    for (final remoteBatch in eligibleBatches) {
      final batch = await transport.download(remoteBatch);
      downloadedRecords += batch.records.length;
      final count = await repository.acceptBatch(batch);
      appliedCount += count;
    }

    // 7. 尝试将积压的 pending 记录应用到新近匹配 TMDB 的本地条目
    final pendingApplied = await repository.applyPending();
    appliedCount += pendingApplied;

    // 8. 统计当前等待匹配与纯本地记录总数
    final pendingCount = await repository.pendingCount();
    final localOnlyCount = await repository.localOnlyCount();

    return SyncReport(
      uploaded: uploadedRecords,
      downloaded: downloadedRecords,
      applied: appliedCount,
      pending: pendingCount,
      localOnly: localOnlyCount,
      configurationApplied: configurationApplied,
    );
  }
}
