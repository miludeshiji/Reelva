import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../metadata/infrastructure/tmdb_token_store.dart';
import '../../player/domain/player_settings.dart';
import '../../player/domain/player_shortcuts.dart';
import '../../sources/domain/source_models.dart';
import '../../sources/infrastructure/remote_credentials_store.dart';
import 'sync_models.dart';

class ApplicationSyncRecord {
  const ApplicationSyncRecord({required this.version, required this.value});

  final SyncVersion version;
  final Map<String, dynamic>? value;

  Map<String, dynamic> toJson() => {
    'version': version.toJson(),
    'value': value,
  };
}

/// 按设置类别、平台及媒体源分别合并，不包含影视元数据或设备运行状态。
class ApplicationSyncDocument {
  const ApplicationSyncDocument(this.records);

  final Map<String, ApplicationSyncRecord> records;

  Map<String, dynamic> toJson() => {
    'version': 1,
    'records': records.map((key, value) => MapEntry(key, value.toJson())),
  };

  factory ApplicationSyncDocument.fromJson(Map<String, dynamic> json) {
    try {
      if (json['version'] != 1) throw const FormatException();
      final raw = json['records'] as Map<String, dynamic>;
      final records = <String, ApplicationSyncRecord>{};
      for (final entry in raw.entries) {
        final record = entry.value as Map<String, dynamic>;
        final value = record['value'] as Map<String, dynamic>?;
        _validate(entry.key, value);
        records[entry.key] = ApplicationSyncRecord(
          version: SyncVersion.fromJson(
            record['version'] as Map<String, dynamic>,
          ),
          value: value,
        );
      }
      return ApplicationSyncDocument(records);
    } catch (_) {
      throw const SyncException('同步的应用配置格式无效');
    }
  }

  ApplicationSyncDocument merge(ApplicationSyncDocument other) {
    final merged = {...records};
    for (final entry in other.records.entries) {
      final current = merged[entry.key];
      if (current == null ||
          entry.value.version.compareTo(current.version) > 0) {
        merged[entry.key] = entry.value;
      }
    }
    return ApplicationSyncDocument(merged);
  }

  static String sourceKey(String kind, String root, String deviceId) =>
      'source:${kind == 'webdav' || kind == 'smb' ? 'network' : deviceId}:'
      '${base64Url.encode(utf8.encode('$kind:$root'))}';

  static void _validate(String key, Map<String, dynamic>? value) {
    if (key == 'tmdb') {
      if (value != null &&
          !TmdbTokenStore.isValidToken(value['token'] as String)) {
        throw const FormatException();
      }
    } else if (key == 'shortcuts') {
      if (value == null) throw const FormatException();
      PlayerInputSettings.fromJson(value).validate();
    } else if (key.startsWith('player:')) {
      final platform = TargetPlatform.values.byName(key.substring(7));
      if (value == null || value.containsKey('input')) {
        throw const FormatException();
      }
      PlayerSettings.fromJson(
        value,
        defaults: PlayerSettings.defaultsFor(platform),
      );
    } else if (key.startsWith('source:')) {
      if (value == null) throw const FormatException();
      final kind = value['kind'] as String;
      final root = value['rootLocator'] as String;
      final origin = value['originDeviceId'] as String;
      if (!const {'local', 'androidSaf', 'webdav', 'smb'}.contains(kind) ||
          !RegExp(r'^[0-9a-f]{32}$').hasMatch(origin) ||
          sourceKey(kind, root, origin) != key ||
          value['name'] is! String ||
          value['enabled'] is! bool) {
        throw const FormatException();
      }
      sanitizeAndValidateRootLocator(kind: kind, rawInput: root);
      (value['extensions'] as List<dynamic>).cast<String>().toList();
      (value['excludedDirectories'] as List<dynamic>).cast<String>().toList();
      final credentials = value['credentials'];
      if (credentials != null) {
        if (kind != 'webdav' && kind != 'smb') throw const FormatException();
        RemoteCredentials.fromJson(credentials as Map<String, dynamic>);
      }
    } else {
      throw const FormatException();
    }
  }
}

class ApplicationSyncSnapshot {
  const ApplicationSyncSnapshot(this.body, this.etag);
  final String body;
  final String etag;
}

abstract interface class ApplicationSyncTransport {
  Future<ApplicationSyncSnapshot?> downloadApplicationData();

  /// 返回 false 表示远端已发生变更，调用方必须重新读取并合并。
  Future<bool> uploadApplicationData(String body, {String? etag});
}

class PendingSourceBinding {
  const PendingSourceBinding(this.key, this.value);
  final String key;
  final Map<String, dynamic> value;
  String get name => value['name'] as String;
  String get rootLocator => value['rootLocator'] as String;
  List<String> get extensions =>
      (value['extensions'] as List<dynamic>).cast<String>();
  List<String> get excludedDirectories =>
      (value['excludedDirectories'] as List<dynamic>).cast<String>();
}
