import 'dart:convert';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reelva/core/database/app_database.dart';
import 'package:reelva/features/library/infrastructure/media_library_repository.dart';
import 'package:reelva/features/metadata/infrastructure/tmdb_token_store.dart';
import 'package:reelva/features/player/infrastructure/player_settings_store.dart';
import 'package:reelva/features/sources/domain/openlist_models.dart';
import 'package:reelva/features/sources/domain/source_models.dart';
import 'package:reelva/features/sources/infrastructure/openlist_rpc.dart';
import 'package:reelva/features/sources/infrastructure/openlist_service.dart';
import 'package:reelva/features/sources/infrastructure/remote_credentials_store.dart';
import 'package:reelva/features/sync/domain/application_sync.dart';
import 'package:reelva/features/sync/domain/sync_models.dart';
import 'package:reelva/features/sync/infrastructure/application_sync_store.dart';

import 'sync_configuration_store_test.dart' show FakeFlutterSecureStorage;

const _scope = 'https://sync.example/cloud/';
const _account = 'cccccccccccccccccccccccccccccccc';
const _deviceA = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const _deviceB = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';

RemoteCredentials _authorization(
  String token, {
  String driver = '115 Open',
  int? updatedAt,
}) => RemoteCredentials(
  openListDriver: driver,
  openListAuthorization: driver == '123 Open'
      ? {
          'AccessToken': '$token-access',
          'RefreshToken': token,
          if (updatedAt != null) ...{
            'token_updated_at': updatedAt,
            'access_token_expires_at': updatedAt + 3600000,
          },
        }
      : {'refresh_token': token},
);

class _Rpc implements OpenListRpcClient {
  final methods = <String>[];
  final accounts = <String, Map<String, dynamic>>{};

  void setAccount(RemoteCredentials secret) {
    accounts[_account] = {
      'id': _account,
      'driver': secret.openListDriver,
      'name': '网盘',
      'addition': secret.openListAuthorization,
    };
  }

  @override
  Future<Map<String, dynamic>> invoke(
    String method,
    Map<String, dynamic> arguments,
  ) async {
    methods.add(method);
    switch (method) {
      case 'initialize':
      case 'close':
        return {'data': <String, dynamic>{}};
      case 'accounts':
        return {
          'data': {'accounts': accounts.values.toList()},
        };
      case 'deleteAccount':
        accounts.remove(arguments['id']);
        return {'data': <String, dynamic>{}};
      default:
        throw StateError('Unexpected core operation: $method');
    }
  }
}

class _Device {
  _Device(this.id, {bool withCore = true}) {
    repository = MediaLibraryRepository(db);
    credentials = RemoteCredentialsStore(storage: storage);
    core = OpenListService(
      rpc: rpc,
      credentials: credentials,
      dataDirectory: () async => 'unused-test-directory',
      activeAccountIds: () async => {
        for (final row in await db.select(db.mediaSources).get())
          if (row.enabled && row.kind == 'openlist')
            OpenListRoot.parse(row.rootLocator).accountId,
      },
    );
    store = ApplicationSyncStore(
      repository: repository,
      credentials: credentials,
      tmdb: TmdbTokenStore(storage: storage),
      player: PlayerSettingsStore(storage: storage),
      deviceId: () async => id,
      storage: storage,
      platform: TargetPlatform.windows,
      clock: () => time,
      openList: withCore ? core : null,
    );
  }

  final String id;
  final db = AppDatabase(executor: NativeDatabase.memory());
  final storage = FakeFlutterSecureStorage();
  final rpc = _Rpc();
  DateTime time = DateTime.fromMillisecondsSinceEpoch(1000);
  late final MediaLibraryRepository repository;
  late final RemoteCredentialsStore credentials;
  late final OpenListService core;
  late final ApplicationSyncStore store;

  Future<MediaSourceConfig> addSource(String path) => repository.upsertSource(
    kind: 'openlist',
    name: '影视',
    rootLocator: buildOpenListRoot(_account, path),
    credentialRef: OpenListService.credentialReference(_account),
  );

  Future<void> close() async {
    await core.close();
    await db.close();
  }
}

ApplicationSyncDocument _document({
  String? root,
  String driver = '115 Open',
  bool enabled = true,
  String name = '影视',
  int stamp = 1000,
  RemoteCredentials? authorization,
}) {
  root ??= buildOpenListRoot(_account, '/Movies');
  return ApplicationSyncDocument({
    ApplicationSyncDocument.sourceKey(
      'openlist',
      root,
      _deviceA,
    ): ApplicationSyncRecord(
      version: SyncVersion(stamp: stamp, deviceId: _deviceA),
      value: {
        'kind': 'openlist',
        'rootLocator': root,
        'originDeviceId': _deviceA,
        'name': name,
        'enabled': enabled,
        'extensions': ['mkv'],
        'excludedDirectories': <String>[],
        'credentials': enabled
            ? (authorization ?? _authorization('backup-token', driver: driver))
                  .toJson()
            : null,
      },
    ),
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);
  tearDownAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = false);

  test('网盘使用全局网络身份并只接受四驱动和稳定根目录', () {
    final root = buildOpenListRoot(_account, '/影视');
    expect(
      ApplicationSyncDocument.sourceKey('openlist', root, _deviceA),
      ApplicationSyncDocument.sourceKey('openlist', root, _deviceB),
    );
    expect(
      ApplicationSyncDocument.sourceKey('openlist', root, _deviceA),
      startsWith('source:network:'),
    );
    for (final driver in openListDrivers.keys) {
      expect(
        ApplicationSyncDocument.fromJson(_document(driver: driver).toJson())
            .records,
        hasLength(1),
      );
    }
    for (final document in [
      _document(driver: 'GoogleDrive'),
      _document(root: 'https://download.example/movie.mkv?sign=temporary'),
      _document(root: 'openlist://not-an-account/Movies/'),
      _document(root: 'openlist://$_account/Movies/?token=temporary'),
    ]) {
      expect(
        () => ApplicationSyncDocument.fromJson(document.toJson()),
        throwsA(isA<SyncException>()),
      );
    }
    expect(
      ApplicationSyncDocument.fromJson(_document(enabled: false).toJson())
          .records,
      hasLength(1),
    );
  });

  test('备份从内核回读轮换凭据且同账号多个目录只读取一次', () async {
    final device = _Device(_deviceA);
    addTearDown(device.close);
    await device.credentials.write(
      OpenListService.credentialReference(_account),
      _authorization('old-token'),
    );
    device.rpc.setAccount(_authorization('rotated-token'));
    await device.addSource('/Movies');
    await device.addSource('/Shows');
    final document = await device.store.capture(_scope);
    final text = jsonEncode(document.toJson());
    expect(text, contains('rotated-token'));
    expect(text, isNot(contains('old-token')));
    expect(text, isNot(contains('openlist.db')));
    expect(
      device.rpc.methods.where((method) => method == 'accounts'),
      hasLength(2),
    );
    expect(device.rpc.methods, isNot(contains('saveAccount')));
    final saved = await device.credentials.read(
      OpenListService.credentialReference(_account),
    );
    expect(saved.openListAuthorization['refresh_token'], 'rotated-token');
  });

  test('123 按授权时间合并令牌，同时保留较新的目录设置并统一共享账号', () {
    final newer = _authorization(
      'new-token',
      driver: '123 Open',
      updatedAt: 2000,
    );
    final older = _authorization(
      'old-token',
      driver: '123 Open',
      updatedAt: 1000,
    );
    final tokens = _document(authorization: newer);
    final settings = _document(
      name: '重命名目录',
      stamp: 3000,
      authorization: older,
    );
    final shows = _document(
      root: buildOpenListRoot(_account, '/Shows'),
      stamp: 4000,
      authorization: older,
    );
    final another = _document(
      root: buildOpenListRoot(_deviceB, '/Movies'),
      authorization: older,
    );
    for (final merged in [tokens.merge(settings), settings.merge(tokens)]) {
      final movie = merged.records.values.single;
      expect(movie.version.stamp, 3000);
      expect(movie.value!['name'], '重命名目录');
      expect(movie.value!['credentials'], newer.toJson());
      final combined = ApplicationSyncDocument.fromJson(
        merged.merge(shows).merge(another).toJson(),
      );
      for (final record in combined.records.values) {
        final id = OpenListRoot.parse(record.value!['rootLocator'] as String)
            .accountId;
        expect(
          record.value!['credentials'],
          (id == _account ? newer : older).toJson(),
        );
      }
    }
  });

  for (final withCore in [true, false]) {
    test('123 同步较新授权并阻止旧内核快照回写（内核服务：$withCore）', () async {
      final device = _Device(_deviceB, withCore: withCore);
      addTearDown(device.close);
      final old = _authorization(
        'old-token',
        driver: '123 Open',
        updatedAt: 1000,
      );
      final newer = _authorization(
        'new-token',
        driver: '123 Open',
        updatedAt: 2000,
      );
      final reference = OpenListService.credentialReference(_account);
      await device.credentials.write(reference, old);
      await device.addSource('/Movies');
      device.time = DateTime.fromMillisecondsSinceEpoch(3000);
      if (withCore) device.rpc.setAccount(old);
      await device.store.apply(_scope, _document(authorization: newer));
      expect(await device.credentials.read(reference), newer);
      expect(device.rpc.methods, isNot(contains('saveAccount')));
      final backup = jsonEncode((await device.store.capture(_scope)).toJson());
      expect(backup, contains('new-token'));
      expect(backup, isNot(contains('old-token')));
      await device.store.apply(
        _scope,
        _document(stamp: 4000, authorization: old),
      );
      expect(await device.credentials.read(reference), newer);
      if (!withCore) expect(device.rpc.methods, isEmpty);
    });
  }

  test('新设备恢复授权和相对索引时不触发内核加载或目录扫描', () async {
    final a = _Device(_deviceA);
    final b = _Device(_deviceB);
    addTearDown(a.close);
    addTearDown(b.close);
    a.rpc.setAccount(_authorization('backup-token'));
    final source = await a.addSource('/Movies');
    await a.repository.indexSourceFiles(source.id, const [
      MediaEntry(
        externalId: 'Film/movie.mkv',
        locator: 'Film/movie.mkv',
        name: 'movie.mkv',
        isDirectory: false,
        size: 1024,
      ),
    ]);
    final document = await a.store.capture(_scope);
    await b.store.apply(
      _scope,
      ApplicationSyncDocument.fromJson(document.toJson()),
    );
    expect(b.rpc.methods, isEmpty);
    expect(await b.store.pendingSources(_scope), isEmpty);
    final restored = (await b.repository.watchSources().first).single;
    expect(restored.rootLocator, source.rootLocator);
    expect(
      restored.credentialRef,
      OpenListService.credentialReference(_account),
    );
    expect(
      (await b.credentials.read(restored.credentialRef))
          .openListAuthorization['refresh_token'],
      'backup-token',
    );
    final entry = await b.db.select(b.db.mediaEntries).getSingle();
    expect(entry.externalEntryId, 'Film/movie.mkv');
    expect(entry.relativeLocator, 'Film/movie.mkv');
    expect(await b.db.select(b.db.mediaFiles).get(), hasLength(1));
  });

  test('恢复旧快照保留新设备已有的当前授权', () async {
    final device = _Device(_deviceB);
    addTearDown(device.close);
    await device.credentials.write(
      OpenListService.credentialReference(_account),
      _authorization('current-local-token'),
    );
    await device.store.apply(_scope, _document());
    expect(device.rpc.methods, isEmpty);
    expect(
      (await device.credentials.read(
        OpenListService.credentialReference(_account),
      )).openListAuthorization['refresh_token'],
      'current-local-token',
    );
  });

  test('无服务注入时恢复仍保留安全存储中的本机授权', () async {
    final device = _Device(_deviceB, withCore: false);
    addTearDown(device.close);
    await device.credentials.write(
      OpenListService.credentialReference(_account),
      _authorization('current-local-token'),
    );
    await device.store.apply(_scope, _document());
    expect(device.rpc.methods, isEmpty);
    expect(
      (await device.credentials.read(
        OpenListService.credentialReference(_account),
      )).openListAuthorization['refresh_token'],
      'current-local-token',
    );
  });

  test('同批次换目录先恢复启用源，共享账号仅在最后目录停用后清理', () async {
    final a = _Device(_deviceA);
    final b = _Device(_deviceB);
    addTearDown(a.close);
    addTearDown(b.close);
    a.rpc.setAccount(_authorization('old-token'));
    final oldSource = await a.addSource('/Old');
    await b.store.apply(_scope, await a.store.capture(_scope));
    b.rpc.setAccount(_authorization('rotated-local-token'));
    await b.store.capture(_scope);

    a.time = DateTime.fromMillisecondsSinceEpoch(3000);
    await a.repository.disableSource(oldSource.id);
    final newSource = await a.addSource('/New');
    await b.store.apply(_scope, await a.store.capture(_scope));
    final active = (await b.repository.watchSources().first).single;
    expect(active.rootLocator, newSource.rootLocator);
    expect(b.rpc.accounts, contains(_account));
    expect(b.rpc.methods, isNot(contains('deleteAccount')));
    expect(
      (await b.credentials.read(active.credentialRef))
          .openListAuthorization['refresh_token'],
      'rotated-local-token',
    );

    a.time = DateTime.fromMillisecondsSinceEpoch(5000);
    await a.repository.disableSource(newSource.id);
    await b.store.apply(_scope, await a.store.capture(_scope));
    expect(await b.repository.watchSources().first, isEmpty);
    expect(b.rpc.accounts, isEmpty);
    expect(b.rpc.methods, contains('deleteAccount'));
    expect(
      () => b.credentials.read(OpenListService.credentialReference(_account)),
      throwsA(isA<MediaSourceException>()),
    );
    expect(
      (await b.db.select(b.db.mediaSources).get()).every(
        (source) => source.credentialRef == null,
      ),
      isTrue,
    );
  });
}
