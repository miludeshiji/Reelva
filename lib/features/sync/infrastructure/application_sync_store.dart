import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:cryptography/cryptography.dart';

import '../../library/infrastructure/media_library_repository.dart';
import '../../metadata/infrastructure/tmdb_token_store.dart';
import '../../player/domain/player_settings.dart';
import '../../player/domain/player_shortcuts.dart';
import '../../player/infrastructure/player_settings_store.dart';
import '../../sources/domain/source_models.dart';
import '../../sources/infrastructure/remote_credentials_store.dart';
import '../domain/application_sync.dart';
import '../domain/sync_models.dart';
import '../../../core/database/app_database.dart';
import 'library_index_store.dart';

/// 配置同步的基线与凭据均留在安全存储，SQLite 仅保留现有的凭据引用。
class ApplicationSyncStore {
  ApplicationSyncStore({
    required this.repository,
    required this.credentials,
    required this.tmdb,
    required this.player,
    required this.deviceId,
    FlutterSecureStorage? storage,
    TargetPlatform? platform,
    DateTime Function()? clock,
    Set<int> Function()? activeScans,
  }) : _storage = storage ?? const FlutterSecureStorage(),
       platform = platform ?? defaultTargetPlatform,
       _clock = clock ?? DateTime.now,
       _activeScans = activeScans ?? _noScans;

  final MediaLibraryRepository repository;
  final RemoteCredentialsStore credentials;
  final TmdbTokenStore tmdb;
  final PlayerSettingsStore player;
  final Future<String> Function() deviceId;
  final FlutterSecureStorage _storage;
  final TargetPlatform platform;
  final DateTime Function() _clock;
  final Set<int> Function() _activeScans;
  static Set<int> _noScans() => {};
  static const _storageKey = 'reelva_application_sync_state_v1';
  static const _indexStorageKey = 'library_index_sync_v1';

  Future<_LocalState> _read(String scope) async {
    final raw = await _storage.read(key: _storageKey);
    if (raw == null) return _LocalState(scope);
    final json = jsonDecode(raw) as Map<String, dynamic>;
    if (json['scope'] != scope) return _LocalState(scope);
    var document = ApplicationSyncDocument.fromJson(
      json['document'] as Map<String, dynamic>,
    );
    final cached = await (repository.db.select(
      repository.db.syncState,
    )..where((row) => row.key.equals(_indexStorageKey))).getSingleOrNull();
    if (cached != null) {
      final indexes = jsonDecode(cached.value) as Map<String, dynamic>;
      if (indexes['scope'] == scope) {
        document = document.merge(
          ApplicationSyncDocument.fromJson(
            indexes['document'] as Map<String, dynamic>,
          ),
        );
      }
    }
    return _LocalState(
      scope,
      document: document,
      observed: (json['observed'] as Map<String, dynamic>)
          .cast<String, String>(),
      bindings: (json['bindings'] as Map<String, dynamic>)
          .cast<String, String>(),
    );
  }

  Future<void> _save(_LocalState state) async {
    final records = state.document.records;
    await _storage.write(
      key: _storageKey,
      value: jsonEncode({
        'scope': state.scope,
        'document': ApplicationSyncDocument({
          for (final e in records.entries)
            if (!e.key.startsWith('index:')) e.key: e.value,
        }).toJson(),
        'observed': state.observed,
        'bindings': state.bindings,
      }),
    );
    await repository.db
        .into(repository.db.syncState)
        .insertOnConflictUpdate(
          SyncStateCompanion.insert(
            key: _indexStorageKey,
            value: jsonEncode({
              'scope': state.scope,
              'document': ApplicationSyncDocument({
                for (final e in records.entries)
                  if (e.key.startsWith('index:')) e.key: e.value,
              }).toJson(),
            }),
          ),
        );
  }

  static Future<String> _signature(String key, Object? value) async {
    final json = canonicalJson(value);
    if (!key.startsWith('index:')) return json;
    return (await Sha256().hash(utf8.encode(json))).bytes
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
  }

  static String _identity(String kind, String root) => '$kind:$root';

  Future<Map<String, Map<String, dynamic>?>> _current(_LocalState state) async {
    final id = await deviceId();
    final token = await tmdb.read();
    final values = <String, Map<String, dynamic>?>{
      'tmdb': token == null ? null : {'token': token},
    };
    final settings = await player.readSaved();
    if (settings != null) {
      values['player:${platform.name}'] = Map<String, dynamic>.from(
        settings.toJson(),
      )..remove('input');
      values['shortcuts'] = Map<String, dynamic>.from(settings.input.toJson());
    }
    final sources = await repository.db
        .select(repository.db.mediaSources)
        .get();
    for (final row in sources) {
      if (!const {'local', 'androidSaf', 'webdav', 'smb'}.contains(row.kind)) {
        continue;
      }
      final identity = _identity(row.kind, row.rootLocator);
      final binding = state.bindings.entries
          .where((entry) => entry.value == identity)
          .firstOrNull;
      final key =
          binding?.key ??
          ApplicationSyncDocument.sourceKey(row.kind, row.rootLocator, id);
      final original = state.document.records[key]?.value;
      final remote = row.kind == 'webdav' || row.kind == 'smb';
      if (!remote) state.bindings[key] = identity;
      values[key] = {
        'kind': original?['kind'] ?? row.kind,
        'rootLocator': original?['rootLocator'] ?? row.rootLocator,
        'originDeviceId': original?['originDeviceId'] ?? id,
        'name': row.name,
        'enabled': row.enabled,
        'extensions': jsonDecode(row.extensions),
        'excludedDirectories': jsonDecode(row.excludedDirectories),
        if (remote)
          'credentials': row.enabled
              ? (await credentials.read(row.credentialRef)).toJson()
              : null,
      };
      if (row.enabled && !_activeScans().contains(row.id)) {
        final index = await LibraryIndexStore(repository.db)
            .capture(await repository.getSource(row.id));
        if (index != null) values['index:$key'] = index;
      }
    }
    return values;
  }

  Future<ApplicationSyncDocument> capture(String scope) async {
    final state = await _read(scope);
    final values = await _current(state);
    final id = await deviceId();
    final records = {...state.document.records};
    for (final entry in values.entries) {
      final signature = await _signature(entry.key, entry.value);
      // 新设备只修改画质等平台设置时，不用默认快捷键覆盖已有通用按键。
      if (entry.key == 'shortcuts' &&
          !state.observed.containsKey(entry.key) &&
          signature == canonicalJson(const PlayerInputSettings().toJson())) {
        continue;
      }
      if (state.observed[entry.key] == signature &&
              records.containsKey(entry.key) ||
          !state.observed.containsKey(entry.key) && entry.value == null) {
        continue;
      }
      final previous = records[entry.key];
      records[entry.key] = ApplicationSyncRecord(
        version: SyncVersion(
          stamp: max(
            _clock().millisecondsSinceEpoch,
            (previous?.version.stamp ?? 0) + 1,
          ),
          deviceId: id,
        ),
        value: entry.value,
      );
      state.observed[entry.key] = signature;
    }
    state.document = ApplicationSyncDocument(records);
    await _save(state);
    return state.document;
  }

  Future<int> apply(String scope, ApplicationSyncDocument incoming) async {
    // 网络等待期间产生的本地修改先登记，再按同一套版本规则合并。
    await capture(scope);
    final state = await _read(scope);
    final merged = state.document.merge(incoming);
    final current = await _current(state);
    var applied = 0;
    for (final entry in merged.records.entries) {
      final key = entry.key;
      if (key.startsWith('index:')) continue;
      final value = entry.value.value;
      if (current.containsKey(key) &&
          canonicalJson(current[key]) == canonicalJson(value)) {
        continue;
      }
      if (key == 'tmdb') {
        if (value == null) {
          await tmdb.delete();
        } else {
          await tmdb.save(value['token'] as String);
        }
      } else if (key == 'player:${platform.name}') {
        final settings = await player.read();
        await player.save(
          PlayerSettings.fromJson(
            value!,
            defaults: settings,
          ).copyWith(input: settings.input),
        );
      } else if (key == 'shortcuts') {
        await player.save(
          (await player.read()).copyWith(
            input: PlayerInputSettings.fromJson(value!),
          ),
        );
      } else if (key.startsWith('source:')) {
        if (!await _applySource(state, key, value!)) continue;
      } else {
        // 其他平台的播放器偏好保留在同步文档中，不应用到当前平台。
        continue;
      }
      state.observed[key] = canonicalJson(value);
      applied++;
    }
    state.document = merged;
    for (final entry in merged.records.entries.where(
      (e) => e.key.startsWith('index:'),
    )) {
      final signature = await _signature(entry.key, entry.value.value);
      if (current.containsKey(entry.key) &&
          await _signature(entry.key, current[entry.key]) == signature) {
        continue;
      }
      final source = await _indexSource(state, entry.key.substring(6));
      if (source == null ||
          !source.enabled ||
          _activeScans().contains(source.id)) {
        continue;
      }
      await LibraryIndexStore(repository.db)
          .restore(source, entry.value.value!);
      state.observed[entry.key] = signature;
      applied++;
    }
    await _save(state);
    return applied;
  }

  Future<MediaSourceConfig?> _indexSource(_LocalState state, String key) {
    final value = state.document.records[key]?.value;
    if (value == null) return Future.value(null);
    final kind = value['kind'] as String;
    if (kind == 'webdav' || kind == 'smb') {
      return repository.findSourceByRoot(kind, value['rootLocator'] as String);
    }
    final binding = state.bindings[key];
    if (binding == null) return Future.value(null);
    final split = binding.indexOf(':');
    return repository.findSourceByRoot(
      binding.substring(0, split),
      binding.substring(split + 1),
    );
  }

  Future<bool> _applySource(
    _LocalState state,
    String key,
    Map<String, dynamic> value,
  ) async {
    var kind = value['kind'] as String;
    var root = value['rootLocator'] as String;
    final remote = kind == 'webdav' || kind == 'smb';
    if (!remote) {
      final binding = state.bindings[key];
      if (binding == null) return false;
      final separator = binding.indexOf(':');
      kind = binding.substring(0, separator);
      root = binding.substring(separator + 1);
    }
    final existing = await repository.findSourceByRoot(kind, root);
    if (value['enabled'] == false) {
      if (existing != null) {
        if (existing.credentialRef != null) {
          await credentials.delete(existing.credentialRef!);
        }
        await repository.updateSourceCredentials(existing.id, null);
        await repository.disableSource(existing.id);
      }
      return true;
    }
    String? reference = existing?.credentialRef;
    if (remote) {
      final raw = value['credentials'] as Map<String, dynamic>?;
      final secret = raw == null
          ? const RemoteCredentials.anonymous()
          : RemoteCredentials.fromJson(raw);
      if (secret.isAnonymous) {
        if (reference != null) await credentials.delete(reference);
        reference = null;
      } else {
        reference ??= RemoteCredentialsStore.generateReference(kind);
        await credentials.write(reference, secret);
      }
    }
    try {
      await repository.upsertSource(
        kind: kind,
        rootLocator: root,
        name: value['name'] as String,
        credentialRef: reference,
        clearCredentialRef: reference == null,
        extensions: (value['extensions'] as List<dynamic>).cast<String>(),
        excludedDirectories: (value['excludedDirectories'] as List<dynamic>)
            .cast<String>(),
      );
    } catch (_) {
      if (reference != null && reference != existing?.credentialRef) {
        await credentials.delete(reference);
      }
      rethrow;
    }
    return true;
  }

  Future<List<PendingSourceBinding>> pendingSources(String scope) async {
    final state = await _read(scope);
    return [
      for (final entry in state.document.records.entries)
        if (entry.key.startsWith('source:') &&
            entry.value.value?['enabled'] == true &&
            const {
              'local',
              'androidSaf',
            }.contains(entry.value.value?['kind']) &&
            !state.bindings.containsKey(entry.key))
          PendingSourceBinding(entry.key, entry.value.value!),
    ];
  }

  Future<void> bindSource(
    String scope,
    String key,
    MediaSourceConfig source,
  ) async {
    final state = await _read(scope);
    final identity = _identity(source.kind, source.rootLocator);
    if (state.bindings.entries.any(
      (entry) => entry.key != key && entry.value == identity,
    )) {
      throw const SyncException('该目录已绑定其他同步媒体源');
    }
    state.bindings[key] = identity;
    state.observed[key] = canonicalJson(state.document.records[key]!.value);
    final index = state.document.records['index:$key'];
    if (index != null) {
      await LibraryIndexStore(repository.db).restore(source, index.value!);
      state.observed['index:$key'] = await _signature(
        'index:$key',
        index.value,
      );
    }
    await _save(state);
  }
}

class _LocalState {
  _LocalState(
    this.scope, {
    this.document = const ApplicationSyncDocument({}),
    Map<String, String>? observed,
    Map<String, String>? bindings,
  }) : observed = observed ?? {},
       bindings = bindings ?? {};

  final String scope;
  ApplicationSyncDocument document;
  final Map<String, String> observed;
  final Map<String, String> bindings;
}

String canonicalJson(Object? value) {
  Object? sorted(Object? item) => switch (item) {
    Map<String, dynamic>() => {
      for (final key in item.keys.toList()..sort()) key: sorted(item[key]),
    },
    List<dynamic>() => item.map(sorted).toList(),
    _ => item,
  };
  return jsonEncode(sorted(value));
}
