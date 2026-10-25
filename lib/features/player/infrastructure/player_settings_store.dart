import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../domain/player_settings.dart';

/// 复用现有本机存储，不参与观看进度同步。
class PlayerSettingsStore {
  const PlayerSettingsStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;
  static const storageKey = 'reelva_player_settings_v1';

  Future<PlayerSettings> read() async {
    final defaults = PlayerSettings.defaultsFor(defaultTargetPlatform);
    final raw = await _storage.read(key: storageKey);
    if (raw == null) return defaults;
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
