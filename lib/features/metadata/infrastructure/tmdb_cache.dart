import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';

/// TMDB 缓存抽象接口
abstract class TmdbCache {
  /// 读取缓存条目（包含过期与未过期）
  Future<MetadataCacheData?> get(String key);

  /// 写入或更新缓存条目
  Future<void> put({
    required String key,
    required String payloadJson,
    String? etag,
    required Duration ttl,
  });

  /// 删除指定缓存条目
  Future<void> delete(String key);

  /// 清理已过期的缓存条目
  Future<void> clearExpired();
}

/// 基于 Drift AppDatabase 表查询的 TMDB 缓存实现
class DriftTmdbCache implements TmdbCache {
  final AppDatabase _db;

  const DriftTmdbCache(this._db);

  @override
  Future<MetadataCacheData?> get(String key) {
    return (_db.select(
      _db.metadataCaches,
    )..where((t) => t.cacheKey.equals(key))).getSingleOrNull();
  }

  @override
  Future<void> put({
    required String key,
    required String payloadJson,
    String? etag,
    required Duration ttl,
  }) {
    final now = DateTime.now();
    final expiresAt = now.add(ttl);

    return _db
        .into(_db.metadataCaches)
        .insertOnConflictUpdate(
          MetadataCachesCompanion.insert(
            cacheKey: key,
            provider: 'tmdb',
            payloadJson: payloadJson,
            etag: Value(etag),
            expiresAt: expiresAt,
            updatedAt: Value(now),
          ),
        );
  }

  @override
  Future<void> delete(String key) {
    return (_db.delete(
      _db.metadataCaches,
    )..where((t) => t.cacheKey.equals(key))).go();
  }

  @override
  Future<void> clearExpired() {
    final now = DateTime.now();
    return (_db.delete(
      _db.metadataCaches,
    )..where((t) => t.expiresAt.isSmallerThanValue(now))).go();
  }
}
