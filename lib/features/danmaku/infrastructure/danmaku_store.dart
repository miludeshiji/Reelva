import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../domain/danmaku.dart';

class DanmakuStore {
  DanmakuStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;
  BaseCacheManager? _cache;
  BaseCacheManager get _manager => _cache ??= CacheManager(
    Config(
      'reelva_danmaku',
      stalePeriod: const Duration(days: 7),
      maxNrOfCacheObjects: 150,
    ),
  );

  String _key(String kind, String identity) =>
      'reelva_danmaku_${kind}_${sha256.convert(utf8.encode(identity))}';

  Future<DanmakuSettings> readSettings() async {
    final raw = await _storage.read(key: 'reelva_danmaku_settings_v1');
    return raw == null
        ? const DanmakuSettings()
        : DanmakuSettings.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  Future<void> saveSettings(DanmakuSettings settings) => _storage.write(
    key: 'reelva_danmaku_settings_v1',
    value: jsonEncode(settings.toJson()),
  );

  Future<DanmakuEpisode?> readBinding(String identity) async {
    final raw = await _storage.read(key: _key('binding', identity));
    return raw == null
        ? null
        : DanmakuEpisode.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  Future<void> saveBinding(String identity, DanmakuEpisode? episode) =>
      episode == null
      ? _storage.delete(key: _key('binding', identity))
      : _storage.write(
          key: _key('binding', identity),
          value: jsonEncode(episode.toJson()),
        );

  Future<double> readOffset(String identity) async =>
      double.tryParse(
        await _storage.read(key: _key('offset', identity)) ?? '',
      ) ??
      0;

  Future<void> saveOffset(String identity, double seconds) =>
      _storage.write(key: _key('offset', identity), value: seconds.toString());

  Future<String?> readCache(String key, {bool stale = false}) async {
    final file = await _manager.getFileFromCache(key);
    if (file == null || (!stale && DateTime.now().isAfter(file.validTill))) {
      return null;
    }
    return file.file.readAsString();
  }

  Future<void> writeCache(
    String key,
    String body, {
    Duration ttl = const Duration(hours: 6),
  }) async {
    await _manager.putFile(
      key,
      utf8.encode(body),
      maxAge: ttl,
      fileExtension: 'json',
    );
  }
}
