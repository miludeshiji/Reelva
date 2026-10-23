import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reelva/core/database/app_database.dart';
import 'package:reelva/features/library/infrastructure/media_library_repository.dart';
import 'package:reelva/features/player/domain/playback_resource.dart';
import 'package:reelva/features/sources/application/source_providers.dart';
import 'package:reelva/features/sources/domain/media_source_adapter.dart';
import 'package:reelva/features/sources/domain/source_models.dart';
import 'package:reelva/features/sources/infrastructure/remote_credentials_store.dart';

import 'infrastructure/remote_credentials_store_test.dart';

class FakeRemoteSourceAdapter implements MediaSourceAdapter {
  FakeRemoteSourceAdapter({required this.kind});

  @override
  final String kind;

  PlaybackResource? playbackToReturn;
  int resolveCount = 0;

  @override
  Future<DirectorySelection?> pickDirectory({String? initialLocator}) async {
    throw const MediaSourceException('Remote requires manual configuration');
  }

  @override
  Stream<MediaEntry> listEntries(
    MediaSourceConfig source,
    String directoryId,
  ) async* {}

  @override
  Future<MediaStat> stat(MediaSourceConfig source, String entryId) async {
    return const MediaStat();
  }

  @override
  Future<PlaybackResource> resolvePlayback(
    MediaSourceConfig source,
    String entryId,
  ) async {
    resolveCount++;
    return playbackToReturn ??
        PlaybackResource(
          uri: Uri.parse('http://127.0.0.1:8080/stream/$entryId'),
          displayName: 'Remote Movie',
        );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late MediaLibraryRepository repo;
  late FakeFlutterSecureStorage fakeStorage;
  late RemoteCredentialsStore credStore;
  late FakeRemoteSourceAdapter webdavAdapter;
  late ProviderContainer container;

  setUp(() {
    db = AppDatabase(executor: NativeDatabase.memory());
    repo = MediaLibraryRepository(db);
    fakeStorage = FakeFlutterSecureStorage();
    credStore = RemoteCredentialsStore(storage: fakeStorage);
    webdavAdapter = FakeRemoteSourceAdapter(kind: 'webdav');

    container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        mediaLibraryRepositoryProvider.overrideWithValue(repo),
        remoteCredentialsStoreProvider.overrideWithValue(credStore),
        sourceAdaptersProvider.overrideWithValue({'webdav': webdavAdapter}),
      ],
    );
  });

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  group('SourceController 远程媒体源管理', () {
    test('addRemoteSource 创建 WebDAV 源并安全持久化凭据', () async {
      final controller = container.read(sourceControllerProvider.notifier);

      final source = await controller.addRemoteSource(
        kind: 'webdav',
        rootUrl: 'https://nas.local:5005/dav/media',
        name: 'NAS 电影',
        credentials: const RemoteCredentials(
          username: 'admin',
          password: 'dav_password_456',
        ),
      );

      // 验证定位符已清洗，无密码泄漏
      expect(source.rootLocator, 'https://nas.local:5005/dav/media/');
      expect(source.credentialRef, isNotNull);

      // 验证安全存储已写入对应凭据
      final creds = await credStore.read(source.credentialRef);
      expect(creds.username, 'admin');
      expect(creds.password, 'dav_password_456');

      // 验证数据库记录正确持久化
      final saved = await repo.getSource(source.id);
      expect(saved.name, 'NAS 电影');
      expect(saved.credentialRef, source.credentialRef);
    });

    test('addRemoteSource 重复添加相同根目录更新凭据且不产生孤儿引用', () async {
      final controller = container.read(sourceControllerProvider.notifier);

      final initial = await controller.addRemoteSource(
        kind: 'webdav',
        rootUrl: 'https://dav.test.org/media/',
        name: '初始源',
        credentials: const RemoteCredentials(
          username: 'user1',
          password: 'pass1',
        ),
      );
      final initialRef = initial.credentialRef!;

      // 相同根目录再次添加，但提供新凭据与新名称
      final updated = await controller.addRemoteSource(
        kind: 'webdav',
        rootUrl: 'https://dav.test.org/media/',
        name: '更新后源',
        credentials: const RemoteCredentials(
          username: 'user2',
          password: 'pass2',
        ),
      );

      expect(updated.id, initial.id);
      expect(updated.name, '更新后源');
      expect(updated.credentialRef, initialRef);

      // 读取凭据确认已被覆盖更新
      final creds = await credStore.read(updated.credentialRef);
      expect(creds.username, 'user2');
      expect(creds.password, 'pass2');

      // 数据库中仅有一条源记录
      final allSources = await repo.watchSources().first;
      expect(allSources.length, 1);
    });

    test('updateCredentials 更新凭据并在切换至匿名时删除安全存储记录', () async {
      final controller = container.read(sourceControllerProvider.notifier);

      final source = await controller.addRemoteSource(
        kind: 'webdav',
        rootUrl: 'https://nas.example.com/dav/',
        credentials: const RemoteCredentials(
          username: 'test',
          password: 'secret',
        ),
      );
      final oldRef = source.credentialRef!;

      // 更新为匿名凭据
      await controller.updateCredentials(
        source.id,
        const RemoteCredentials.anonymous(),
      );

      // 原凭据已从存储中安全删除
      expect(
        () => credStore.read(oldRef),
        throwsA(
          isA<MediaSourceException>().having(
            (e) => e.code,
            'code',
            'credential_not_found',
          ),
        ),
      );

      // 数据库中的 credential_ref 置空
      final reloaded = await repo.getSource(source.id);
      expect(reloaded.credentialRef, isNull);
    });

    test('removeSource 删除安全凭据并软停用源，保留历史与数据', () async {
      final controller = container.read(sourceControllerProvider.notifier);

      final source = await controller.addRemoteSource(
        kind: 'webdav',
        rootUrl: 'https://nas.example.com/dav/',
        credentials: const RemoteCredentials(username: 'user', password: 'pwd'),
      );
      final credRef = source.credentialRef!;

      await controller.removeSource(source.id);

      // 安全凭据已删除
      expect(
        () => credStore.read(credRef),
        throwsA(isA<MediaSourceException>()),
      );

      // 媒体源状态变为 enabled = false
      final sources = await repo.watchSources().first;
      expect(sources, isEmpty); // watchSources 仅暴露 enabled == true

      final disabledSource = await repo.getSource(source.id);
      expect(disabledSource.enabled, isFalse);
      expect(disabledSource.credentialRef, isNull);
    });

    test('removeSource 删除安全凭据失败时抛出异常且保留源处于启用状态以便重试', () async {
      final controller = container.read(sourceControllerProvider.notifier);

      final source = await controller.addRemoteSource(
        kind: 'webdav',
        rootUrl: 'https://nas.example.com/dav/',
        credentials: const RemoteCredentials(username: 'user', password: 'pwd'),
      );
      final credRef = source.credentialRef!;

      fakeStorage.shouldThrowOnDelete = true;

      expect(
        () => controller.removeSource(source.id),
        throwsA(
          isA<MediaSourceException>().having(
            (e) => e.code,
            'code',
            'credential_storage_failed',
          ),
        ),
      );

      final remaining = await repo.getSource(source.id);
      expect(remaining.enabled, isTrue);
      expect(remaining.credentialRef, credRef);
    });
  });
}
