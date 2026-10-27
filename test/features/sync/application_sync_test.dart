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
import 'package:reelva/features/sync/infrastructure/library_index_store.dart';
import 'package:reelva/features/metadata/domain/tmdb_models.dart';
import 'package:reelva/features/sources/domain/source_models.dart';
import 'package:reelva/features/progress/infrastructure/playback_progress_repository.dart';
import 'package:reelva/features/sync/infrastructure/sync_repository.dart';
import 'package:reelva/features/metadata/application/nfo_service.dart'
    show sourceArtworkLocator;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:reelva/features/sync/application/sync_providers.dart';
import 'package:reelva/features/sync/infrastructure/sync_configuration_store.dart';

import 'sync_configuration_store_test.dart' show FakeFlutterSecureStorage;

const _scope = 'https://sync.example/reelva/';
const _password = 'reelva-test-encryption-password';
final _token = ''.padLeft(32, 'a');

Future<MediaSourceConfig> _indexedSource(
  _Device device, {
  String kind = 'webdav',
  String root = 'https://media.example/library/',
}) async {
  final source = await device.repository.upsertSource(
    kind: kind,
    rootLocator: root,
    name: '影视',
  );
  final revision = await device.repository.beginScan(source.id);
  await device.repository.applyScanBatch(source.id, revision, [
    const MediaEntry(
      externalId: 'Movies',
      locator: 'Movies',
      name: 'Movies',
      isDirectory: true,
    ),
    const MediaEntry(
      externalId: 'Movies/Movie.mkv',
      locator: 'Movies/Movie.mkv',
      name: 'Movie.mkv',
      isDirectory: false,
      size: 1024,
    ),
    const MediaEntry(
      externalId: 'Show.S01E01.mkv',
      locator: 'Show.S01E01.mkv',
      name: 'Show.S01E01.mkv',
      isDirectory: false,
      size: 2048,
    ),
  ]);
  await device.repository.finishScan(source.id, revision);
  final files = await device.repository.metadataFiles(
    sourceId: source.id,
    matchedOnly: false,
  );
  final movie = files.singleWhere((f) => f.name == 'Movie.mkv');
  final work = await device.repository.applyMetadataToFiles(
    {movie.fileId: null},
    const TmdbWork(
      id: 27205,
      type: 'movie',
      title: '电影',
      year: 2010,
      overview: '电影简介',
    ),
  );
  await device.repository.setWorkArtwork(
    work!,
    poster: sourceArtworkLocator(source.id, 'Movies/poster.jpg', version: '1'),
  );
  await device.repository.applyMetadataToFiles({
    files
        .singleWhere((f) => f.name == 'Show.S01E01.mkv')
        .fileId: const TmdbEpisode(
      tmdbId: 100,
      seasonNumber: 1,
      episodeNumber: 1,
      title: '第一集',
      overview: '分集简介',
    ),
  }, const TmdbWork(id: 42, type: 'series', title: '电视剧'));
  await PlaybackProgressRepository(db: device.db).saveProgress(
    fileId: movie.fileId,
    position: const Duration(seconds: 60),
    duration: const Duration(seconds: 120),
  );
  return device.repository.getSource(source.id);
}

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
  Future<bool> uploadApplicationData(
    String body, {
    required String deviceId,
    String? etag,
  }) async {
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

class _SnapshotTransport implements ApplicationSyncTransport {
  String? legacy;
  final files = <String, String>{};
  int puts = 0;

  @override
  Future<ApplicationSyncSnapshot?> downloadApplicationData() async {
    if (legacy == null && files.isEmpty) return null;
    return ApplicationSyncSnapshot(
      legacy ?? files.values.first,
      null,
      updates: legacy == null
          ? files.values.skip(1).toList()
          : files.values.toList(),
    );
  }

  @override
  Future<bool> uploadApplicationData(
    String body, {
    required String deviceId,
    String? etag,
  }) async {
    puts++;
    files[deviceId] = body;
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

  test('无 ETag 的旧配置与多设备快照按记录合并，删除记录生效且不重复上传', () async {
    await a.tmdb.save(_token);
    final transport = _SnapshotTransport()
      ..legacy = jsonEncode((await a.store.capture(_scope)).toJson());
    final settings = PlayerSettings.defaultsFor(TargetPlatform.windows);
    await b.player.save(
      settings.copyWith(input: settings.input.copyWith(seekSeconds: 5)),
    );
    transport.files['bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb'] = jsonEncode(
      (await b.store.capture(_scope)).toJson(),
    );
    ApplicationSyncService service(_Device d) => ApplicationSyncService(
      store: d.store,
      transport: transport,
      scope: _scope,
      password: '',
    );
    await service(a).synchronize();
    expect(await a.tmdb.read(), _token);
    expect((await a.player.read()).input.seekSeconds, 5);
    expect(transport.puts, 0);
    a.time = DateTime.fromMillisecondsSinceEpoch(2000);
    await a.tmdb.delete();
    await service(a).synchronize();
    expect(transport.puts, 1);
    expect(transport.files, hasLength(2));
    expect(transport.legacy, contains(_token));
    await service(b).synchronize();
    expect((await b.store.capture(_scope)).records['tmdb']!.value, isNull);
    expect((await b.player.read()).input.seekSeconds, 5);
    expect(transport.puts, 1);
  });

  test('独立快照中的加密配置仍需密码，不因其他明文文件而跳过', () async {
    await a.tmdb.save(_token);
    final transport = _SnapshotTransport()
      ..files['aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'] = await SyncCipher().encrypt(
        (await a.store.capture(_scope)).toJson(),
        _password,
      )
      ..legacy = jsonEncode(const ApplicationSyncDocument({}).toJson());
    final service = ApplicationSyncService(
      store: b.store,
      transport: transport,
      scope: _scope,
      password: '',
    );
    await expectLater(service.synchronize(), throwsA(isA<SyncException>()));
    expect(transport.puts, 0);
    expect(await b.tmdb.read(), isNull);
    await ApplicationSyncService(
      store: b.store,
      transport: transport,
      scope: _scope,
      password: _password,
    ).synchronize();
    expect(await b.tmdb.read(), _token);
    expect(transport.puts, 0);
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('不设置密码也同步配置、凭据和完整索引，新设备直接获得作品与续播记录', () async {
    await _indexedSource(a);
    await a.tmdb.save(_token);
    // 目标设备已有其他条目，确保所有数据库编号都需要重新映射。
    final unrelated = await b.repository.upsertSource(
      kind: 'local',
      rootLocator: 'C:/Other',
      name: '其他',
    );
    await b.repository.indexSourceFiles(unrelated.id, [
      const MediaEntry(
        externalId: 'other.mkv',
        locator: 'other.mkv',
        name: 'other.mkv',
        isDirectory: false,
      ),
    ]);
    final transport = _Transport();
    ApplicationSyncService service(_Device d) => ApplicationSyncService(
      store: d.store,
      transport: transport,
      scope: _scope,
      password: '',
    );
    await service(a).synchronize();
    final plain = jsonDecode(transport.body!) as Map<String, dynamic>;
    expect(plain.containsKey('format'), isFalse);
    final document = ApplicationSyncDocument.fromJson(plain);
    final indexKey = document.records.keys.singleWhere(
      (key) => key.startsWith('index:'),
    );
    await service(b).synchronize();
    expect(await b.tmdb.read(), _token);
    final works = await b.repository.watchWorks(matchedOnly: true).first;
    expect(works.map((w) => w.title).toSet(), {'电影', '电视剧'});
    final show = works.singleWhere((w) => w.type == 'series');
    final details = (await b.repository.getWorkDetails(show.id))!;
    expect(details.versions.single.seasonNumber, 1);
    expect(details.versions.single.episodeNumber, 1);
    expect(details.versions.single.episodeTitle, '第一集');
    final source = (await b.repository.watchSources().first).singleWhere(
      (s) => s.kind == 'webdav',
    );
    expect(source.lastScanAt, isNotNull);
    final captured = await b.store.capture(_scope);
    expect(
      canonicalJson(captured.records[indexKey]!.toJson()),
      canonicalJson(document.records[indexKey]!.toJson()),
    );
    final aProgress = SyncRepository(a.db);
    await aProgress.captureLocalChanges();
    final batch = (await aProgress.prepareUpload())!;
    expect(await SyncRepository(b.db).acceptBatch(batch), 1);
    final movie = (await b.repository.metadataFiles(sourceId: source.id))
        .singleWhere((f) => f.metadata.type == 'movie');
    expect(
      (await PlaybackProgressRepository(db: b.db).getProgress(movie.fileId))!
          .position,
      const Duration(seconds: 60),
    );
    expect(
      Uri.parse(
        (await b.db.select(b.db.works).get())
            .singleWhere((w) => w.id == movie.workId)
            .posterLocator!,
      ).host,
      '${source.id}',
    );
    expect(await b.db.customSelect('PRAGMA foreign_key_check').get(), isEmpty);
    final count = (await b.db.select(b.db.mediaFiles).get()).length;
    await b.store.apply(_scope, captured);
    expect((await b.db.select(b.db.mediaFiles).get()).length, count);
  });

  test('本地索引待绑定期间保留，绑定后无需扫描即可使用并能重关联 Android 文档', () async {
    await _indexedSource(a, kind: 'local', root: 'F:/Movies');
    final document = await a.store.capture(_scope);
    await b.store.apply(_scope, document);
    expect(await b.repository.watchWorks(matchedOnly: true).first, isEmpty);
    final pending = (await b.store.pendingSources(_scope)).single;
    final source = await b.repository.upsertSource(
      kind: 'androidSaf',
      rootLocator: 'content://provider/tree/local',
      name: pending.name,
    );
    await b.store.bindSource(_scope, pending.key, source);
    expect(
      await b.repository.watchWorks(matchedOnly: true).first,
      hasLength(2),
    );
    final before = await b.db.select(b.db.mediaFiles).get();
    final indexKey = 'index:${pending.key}';
    expect(
      canonicalJson((await b.store.capture(_scope)).records[indexKey]!.value),
      canonicalJson(document.records[indexKey]!.value),
    );
    final revision = await b.repository.beginScan(source.id);
    await b.repository.applyScanBatch(source.id, revision, [
      MediaEntry(
        externalId: 'content://provider/tree/local/document/movie',
        locator: Uri(
          scheme: 'reelva-index',
          pathSegments: ['Movies', 'Movie.mkv'],
        ).toString(),
        name: 'Movie.mkv',
        isDirectory: false,
        size: 1024,
      ),
    ]);
    expect(
      (await b.db.select(b.db.mediaFiles).get()).map((f) => f.id),
      before.map((f) => f.id),
    );
    expect(
      (await b.repository.getVideo(before.first.id))!.externalId,
      startsWith('content://'),
    );
  });

  test('无密码的设备不会将既有加密配置覆盖为明文，可选密码能加密已有明文', () async {
    await a.tmdb.save(_token);
    final transport = _Transport();
    ApplicationSyncService service(_Device d, String password) =>
        ApplicationSyncService(
          store: d.store,
          transport: transport,
          scope: _scope,
          password: password,
        );
    await service(a, '').synchronize();
    expect(
      (jsonDecode(transport.body!) as Map<String, dynamic>).containsKey(
        'format',
      ),
      isFalse,
    );
    await service(a, _password).synchronize();
    final encrypted = transport.body;
    expect(
      (jsonDecode(encrypted!) as Map<String, dynamic>).containsKey('format'),
      isTrue,
    );
    await expectLater(
      service(b, '').synchronize(),
      throwsA(isA<SyncException>()),
    );
    expect(transport.body, encrypted);
    expect(await b.tmdb.read(), isNull);
    await service(b, _password).synchronize();
    expect(await b.tmdb.read(), _token);
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('损坏的索引引用在恢复前拒绝，既有数据库内容保持完整', () async {
    final source = await _indexedSource(a);
    final snapshot = (await LibraryIndexStore(a.db).capture(source))!;
    (snapshot['files'] as List<dynamic>).first['entryId'] = 99999;
    final document = ApplicationSyncDocument({
      'index:source:invalid': ApplicationSyncRecord(
        version: const SyncVersion(
          stamp: 1,
          deviceId: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        ),
        value: snapshot,
      ),
    });
    expect(
      () => ApplicationSyncDocument.fromJson(document.toJson()),
      throwsA(isA<SyncException>()),
    );
    expect(await b.db.select(b.db.mediaEntries).get(), isEmpty);
  });

  test('未设置密码也启用配置同步并显示待绑定目录', () async {
    await a.repository.upsertSource(
      kind: 'local',
      rootLocator: 'F:/Movies',
      name: '目录',
    );
    await b.store.apply(_scope, await a.store.capture(_scope));
    final configurationStore = SyncConfigurationStore(storage: b.storage);
    final config = SyncConfiguration(endpoint: Uri.parse(_scope));
    await configurationStore.save(config);
    final container = ProviderContainer(
      overrides: [
        syncConfigurationStoreProvider.overrideWithValue(configurationStore),
        syncRepositoryProvider.overrideWithValue(SyncRepository(b.db)),
        applicationSyncStoreProvider.overrideWithValue(b.store),
      ],
    );
    try {
      expect(
        container.read(syncServiceProvider(config)).applicationSync,
        isNotNull,
      );
      expect(
        await container.read(pendingSourceBindingsProvider.future),
        hasLength(1),
      );
    } finally {
      container.dispose();
    }
  });

  test('扫描中的来源只同步配置，完成后才生成索引快照', () async {
    final source = await _indexedSource(a);
    final active = <int>{source.id};
    final store = ApplicationSyncStore(
      repository: a.repository,
      credentials: a.credentials,
      tmdb: a.tmdb,
      player: a.player,
      deviceId: () async => 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      storage: a.storage,
      activeScans: () => active,
    );
    expect(
      (await store.capture(_scope)).records.keys
          .any((key) => key.startsWith('index:')),
      isFalse,
    );
    active.clear();
    final captured = await store.capture(_scope);
    expect(
      captured.records.keys.where((key) => key.startsWith('index:')),
      hasLength(1),
    );
  });

  test('恢复索引保留本机较新的人工匹配，不把不同 TMDB 身份合并', () async {
    await _indexedSource(a);
    final document = await a.store.capture(_scope);
    final source = await b.repository.upsertSource(
      kind: 'webdav',
      rootLocator: 'https://media.example/library/',
      name: '影视',
    );
    final files = await b.repository.indexSourceFiles(source.id, [
      const MediaEntry(
        externalId: 'Movies/Movie.mkv',
        locator: 'Movies/Movie.mkv',
        name: 'Movie.mkv',
        isDirectory: false,
      ),
    ]);
    final fileId = files.values.single;
    final workId = (await b.repository.applyMetadataToFiles({
      fileId: null,
    }, const TmdbWork(id: 999, type: 'movie', title: '本机手动匹配')))!;
    await b.db.customStatement(
      'UPDATE works SET updated_at = updated_at + 60 WHERE id = ?',
      [workId],
    );
    await PlaybackProgressRepository(db: b.db).saveProgress(
      fileId: fileId,
      position: const Duration(seconds: 30),
      duration: const Duration(seconds: 120),
    );
    final remote = ApplicationSyncDocument({
      for (final entry in document.records.entries)
        entry.key: entry.key.startsWith('index:')
            ? ApplicationSyncRecord(
                version: const SyncVersion(
                  stamp: 9999,
                  deviceId: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
                ),
                value: entry.value.value,
              )
            : entry.value,
    });
    await b.store.apply(_scope, remote);
    final movie = (await b.repository.metadataFiles(sourceId: source.id))
        .singleWhere((f) => f.name == 'Movie.mkv');
    expect(movie.metadata.tmdbId, 999);
    expect(movie.metadata.title, '本机手动匹配');
    final ids = await b.db
        .customSelect(
          'SELECT provider_entity_id FROM external_ids WHERE work_id = $workId',
        )
        .get();
    expect(ids.map((row) => row.read<String>('provider_entity_id')), [
      'movie:999',
    ]);
    expect(
      (await PlaybackProgressRepository(db: b.db).getProgress(fileId))!
          .position,
      const Duration(seconds: 30),
    );
  });

  test('无 TMDB 身份的剧集更新索引时复用本机季集并保留观看进度', () async {
    await _indexedSource(a);
    await a.db.customStatement(
      "DELETE FROM external_ids WHERE provider_entity_id = 'series:42'",
    );
    await b.store.apply(_scope, await a.store.capture(_scope));
    final episodeFile = (await b.repository.metadataFiles()).singleWhere(
      (f) => f.metadata.type == 'series',
    );
    final progress = PlaybackProgressRepository(db: b.db);
    await progress.saveProgress(
      fileId: episodeFile.fileId,
      position: const Duration(seconds: 30),
      duration: const Duration(seconds: 120),
    );
    await a.db.customStatement("UPDATE episodes SET title = '更新后的分集标题'");
    a.time = DateTime.fromMillisecondsSinceEpoch(2000);
    await b.store.apply(_scope, await a.store.capture(_scope));
    final restored = (await b.repository.metadataFiles()).singleWhere(
      (f) => f.metadata.type == 'series',
    );
    expect(restored.workId, episodeFile.workId);
    expect(restored.episode!.title, '更新后的分集标题');
    expect(await b.db.select(b.db.works).get(), hasLength(2));
    expect(
      (await progress.getProgress(episodeFile.fileId))!.position,
      const Duration(seconds: 30),
    );
    expect(await b.db.customSelect('PRAGMA foreign_key_check').get(), isEmpty);
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
