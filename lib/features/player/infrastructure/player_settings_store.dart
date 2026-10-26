import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../domain/player_settings.dart';

/// 播放器偏好保存在本机安全存储，同步时按平台读取已保存的配置。
class PlayerSettingsStore {
  const PlayerSettingsStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;
  static const storageKey = 'reelva_player_settings_v1';

  Future<PlayerSettings> read() async {
    return await readSaved() ??
        PlayerSettings.defaultsFor(defaultTargetPlatform);
  }

  Future<PlayerSettings?> readSaved() async {
    final defaults = PlayerSettings.defaultsFor(defaultTargetPlatform);
    final raw = await _storage.read(key: storageKey);
    if (raw == null) return null;
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('播放器设置格式损坏');
    }
    return PlayerSettings.fromJson(decoded, defaults: defaults);
  }

  Future<void> save(PlayerSettings settings) async {
    settings.validate();
    await _storage.write(key: storageKey, value: jsonEncode(settings.toJson()));
  }
}
