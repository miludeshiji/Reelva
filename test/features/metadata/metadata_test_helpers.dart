import 'package:reelva/core/database/app_database.dart';
import 'package:reelva/features/metadata/infrastructure/tmdb_cache.dart';

/// 内存版 TMDB 缓存（供单元测试快速执行）
class MemoryTmdbCache implements TmdbCache {
  final Map<String, MetadataCacheData> _entries = {};

  @override
  Future<MetadataCacheData?> get(String key) async {
    return _entries[key];
  }

  @override
  Future<void> put({
    required String key,
    required String payloadJson,
    String? etag,
    required Duration ttl,
  }) async {
    final now = DateTime.now();
    _entries[key] = MetadataCacheData(
      cacheKey: key,
      provider: 'tmdb',
      payloadJson: payloadJson,
      etag: etag,
      expiresAt: now.add(ttl),
      updatedAt: now,
    );
  }

  @override
  Future<void> delete(String key) async {
    _entries.remove(key);
  }

  @override
  Future<void> clearExpired() async {
    final now = DateTime.now();
    _entries.removeWhere((_, entry) => now.isAfter(entry.expiresAt));
  }
}
