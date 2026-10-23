import 'sync_models.dart';

/// 远程同步批次元数据
class SyncRemoteBatch {
  const SyncRemoteBatch({required this.deviceId, required this.sequence});

  /// 生成该批次的设备唯一标识符（32位小写十六进制）
  final String deviceId;

  /// 该设备在该批次中的递增序列号（正整数）
  final int sequence;

  /// 远程 WebDAV 文件名
  String get fileName => '$deviceId-$sequence.json';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SyncRemoteBatch &&
          runtimeType == other.runtimeType &&
          deviceId == other.deviceId &&
          sequence == other.sequence;

  @override
  int get hashCode => Object.hash(deviceId, sequence);

  @override
  String toString() =>
      'SyncRemoteBatch(deviceId: $deviceId, sequence: $sequence)';
}

/// 同步传输抽象接口
abstract interface class SyncTransport {
  /// 列出远程所有可用的同步批次
  Future<List<SyncRemoteBatch>> listBatches();

  /// 下载指定的远程批次并完成校验
  Future<SyncBatch> download(SyncRemoteBatch batch);

  /// 上传本地批次（带条件写入及崩溃安全检测）
  Future<void> upload(SyncBatch batch);
}
