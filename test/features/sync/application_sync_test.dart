import 'dart:convert';

import 'package:drift/native.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reelva/core/database/app_database.dart';
import 'package:reelva/features/library/infrastructure/media_library_repository.dart';
import 'package:reelva/features/metadata/infrastructure/tmdb_token_store.dart';
import 'package:reelva/features/player/domain/player_settings.dart';
import 'package:reelva/features/player/infrastructure/player_settings_store.dart';
import 'package:reelva/features/sources/infrastructure/remote_credentials_store.dart';
import 'package:reelva/features/sync/application/application_sync_service.dart';
import 'package:reelva/features/sync/domain/application_sync.dart';
import 'package:reelva/features/sync/domain/sync_models.dart';
import 'package:reelva/features/sync/infrastructure/application_sync_store.dart';
import 'package:reelva/features/sync/infrastructure/sync_cipher.dart';

import 'sync_configuration_store_test.dart' show FakeFlutterSecureStorage;

const _scope = 'https://sync.example/reelva/';
const _password = 'reelva-test-encryption-password';
final _token = ''.padLeft(32, 'a');

class _Device {
  _Device(String id, {this.platform = TargetPlatform.windows}) {
    repository = MediaLibraryRepository(db);
    credentials = RemoteCredentialsStore(storage: storage);
    tmdb = TmdbTokenStore(storage: storage);
    player = PlayerSettingsStore(storage: storage);
    store = ApplicationSyncStore(
      repository: repository,
      credentials: credentials,
      tmdb: tmdb,
      player: player,
      deviceId: () async => id,
      storage: storage,
      platform: platform,
      clock: () => time,
    );
  }
  final db = AppDatabase(executor: NativeDatabase.memory());
  final storage = FakeFlutterSecureStorage();
  final TargetPlatform platform;
  DateTime time = DateTime.fromMillisecondsSinceEpoch(1000);
  late final MediaLibraryRepository repository;
  late final RemoteCredentialsStore credentials;
  late final TmdbTokenStore tmdb;
  late final PlayerSettingsStore player;
  late final ApplicationSyncStore store;
}

class _Transport implements ApplicationSyncTransport {
  String? body;
  int revision = 0;
  bool conflictOnce = false;
  int puts = 0;

  @override
  Future<ApplicationSyncSnapshot?> downloadApplicationData() async =>
      body == null ? null : ApplicationSyncSnapshot(body!, '"$revision"');

  @override
  Future<bool> uploadApplicationData(String body, {String? etag}) async {
    puts++;
    if (conflictOnce) {
      conflictOnce = false;
      return false;
    }
    if (etag != (this.body == null ? null : '"$revision"')) return false;
    this.body = body;
    revision++;
    return true;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);
  tearDownAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = false);
  late _Device a;
  late _Device b;
  setUp(() {
    a = _Device('aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa');
    b = _Device('bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb');
  });
  tearDown(() async {
    await a.db.close();
    await b.db.close();
  });

  test('配置、快捷键及凭据在新设备恢复，重捕获不会生成回传变更', () async {
    final settings = PlayerSettings.defaultsFor(TargetPlatform.windows);
    await a.player.save(
      settings.copyWith(input: settings.input.copyWith(seekSeconds: 5)),
    );
    await a.tmdb.save(_token);
    await a.credentials.write(
      'local-reference',
      const RemoteCredentials(username: 'user', password: 'private-secret'),
    );
    await a.repository.upsertSource(
      kind: 'webdav',
      rootLocator: 'https://media.example/movies/',
      name: '家庭影视',
      credentialRef: 'local-reference',
      extensions: ['mkv'],
      excludedDirectories: ['extras'],
    );
    final document = await a.store.capture(_scope);
    final before = canonicalJson(document.toJson());
    expect(before, isNot(contains('local-reference')));
    expect(await b.store.apply(_scope, document), 4);
    final source = (await b.repository.watchSources().first).single;
    expect(source.extensions, ['mkv']);
    expect(source.excludedDirectories, ['extras']);
    expect(source.credentialRef, isNot('local-reference'));
    expect(
      (await b.credentials.read(source.credentialRef)).password,
      'private-secret',
    );
    expect(await b.tmdb.read(), _token);
    expect((await b.player.read()).input.seekSeconds, 5);
    expect(canonicalJson((await b.store.capture(_scope)).toJson()), before);
    expect(await b.db.select(b.db.works).get(), isEmpty);
  });

  test('凭据移除和媒体源停用会传播，保留媒体源记录', () async {
    await a.tmdb.save(_token);
    final source = await a.repository.upsertSource(
      kind: 'smb',
      rootLocator: 'smb://nas/movies',
      name: 'NAS',
    );
    await b.store.apply(_scope, await a.store.capture(_scope));
    a.time = DateTime.fromMillisecondsSinceEpoch(2000);
    await a.tmdb.delete();
    await a.repository.disableSource(source.id);
    await b.store.apply(_scope, await a.store.capture(_scope));
    expect(await b.tmdb.read(), isNull);
    expect(await b.repository.watchSources().first, isEmpty);
    expect(await b.db.select(b.db.mediaSources).get(), hasLength(1));
  });

  test('平台设置各自保留，快捷键跨平台同步', () async {
    await b.db.close();
    b = _Device(
      'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
      platform: TargetPlatform.android,
    );
    final android = PlayerSettings.defaultsFor(TargetPlatform.android);
    await b.player.save(android);
    b.time = DateTime.fromMillisecondsSinceEpoch(5000);
    await b.store.capture(_scope);
    a.time = DateTime.fromMillisecondsSinceEpoch(2000);
    final windows = PlayerSettings.defaultsFor(TargetPlatform.windows);
    await a.player.save(
      windows.copyWith(input: windows.input.copyWith(seekSeconds: 5)),
    );
    await b.store.apply(_scope, await a.store.capture(_scope));
    final restored = await b.player.read();
    expect(restored.cacheSizeMb, 128);
    expect(restored.subtitleFont, android.subtitleFont);
    expect(restored.input.seekSeconds, 5);
  });

  test('本地目录保留为待绑定配置，绑定后使用本机路径且不回传该路径', () async {
    await a.repository.upsertSource(
      kind: 'local',
      rootLocator: 'F:/Movies',
      name: '本地影视',
    );
    final document = await a.store.capture(_scope);
    await b.store.apply(_scope, document);
    expect(await b.repository.watchSources().first, isEmpty);
    final pending = (await b.store.pendingSources(_scope)).single;
    final local = await b.repository.upsertSource(
      kind: 'androidSaf',
      rootLocator: 'content://test/tree/Movies',
      name: pending.name,
    );
    await b.store.bindSource(_scope, pending.key, local);
    expect(await b.store.pendingSources(_scope), isEmpty);
    final captured = await b.store.capture(_scope);
    expect(canonicalJson(captured.toJson()), canonicalJson(document.toJson()));
    expect(canonicalJson(captured.toJson()), isNot(contains('content://test')));
  });

  test('网络等待期间的新本机设置不会被旧下载覆盖', () async {
    await a.tmdb.save(_token);
    final downloaded = await a.store.capture(_scope);
    await b.store.apply(_scope, downloaded);
    b.time = DateTime.fromMillisecondsSinceEpoch(3000);
    final localToken = ''.padLeft(32, 'b');
    await b.tmdb.save(localToken);
    await b.store.apply(_scope, downloaded);
    expect(await b.tmdb.read(), localToken);
    expect(
      (await b.store.capture(_scope)).records['tmdb']!.value!['token'],
      localToken,
    );
  });

  test('新同步目录不携带旧目录保留的其他设备配置', () async {
    await a.repository.upsertSource(
      kind: 'local',
      rootLocator: 'F:/Movies',
      name: '原设备目录',
    );
    await b.store.apply(_scope, await a.store.capture(_scope));
    final fresh = await b.store.capture('https://other.example/');
    expect(fresh.records, isEmpty);
    expect(await b.store.pendingSources('https://other.example/'), isEmpty);
  });

  test('配置文件加密，冲突重试后恢复；错误密码不覆盖远端或本机', () async {
    final transport = _Transport()..conflictOnce = true;
    await a.tmdb.save(_token);
    ApplicationSyncService service(_Device device, String password) =>
        ApplicationSyncService(
          store: device.store,
          transport: transport,
          scope: _scope,
          password: password,
        );
    await service(a, _password).synchronize();
    expect(transport.puts, 2);
    expect(transport.body, isNot(contains(_token)));
    final remote = transport.body;
    await expectLater(
      service(b, 'incorrect-password').synchronize(),
      throwsA(isA<SyncException>()),
    );
    expect(transport.body, remote);
    expect(await b.tmdb.read(), isNull);
    await service(b, _password).synchronize();
    expect(await b.tmdb.read(), _token);
    expect(transport.puts, 2);
    final envelope = jsonDecode(remote!) as Map<String, dynamic>;
    final bytes = base64Decode(envelope['data'] as String);
    bytes[0] ^= 1;
    envelope['data'] = base64Encode(bytes);
    await expectLater(
      SyncCipher().decrypt(jsonEncode(envelope), _password),
      throwsA(isA<SyncException>()),
    );
  }, timeout: const Timeout(Duration(minutes: 2)));
}
