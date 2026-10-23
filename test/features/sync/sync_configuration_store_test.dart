import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reelva/features/sync/domain/sync_models.dart';
import 'package:reelva/features/sync/infrastructure/sync_configuration_store.dart';

class FakeFlutterSecureStorage extends Fake implements FlutterSecureStorage {
  final Map<String, String> _storage = {};
  bool shouldThrowOnRead = false;
  bool shouldThrowOnWrite = false;
  bool shouldThrowOnDelete = false;

  @override
  Future<String?> read({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (shouldThrowOnRead) {
      throw Exception('Storage read error');
    }
    return _storage[key];
  }

  @override
  Future<void> write({
    required String key,
    required String? value,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (shouldThrowOnWrite) {
      throw Exception('Storage write error');
    }
    if (value != null) {
      _storage[key] = value;
    } else {
      _storage.remove(key);
    }
  }

  @override
  Future<void> delete({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (shouldThrowOnDelete) {
      throw Exception('Storage delete error');
    }
    _storage.remove(key);
  }
}

void main() {
  group('SyncConfiguration', () {
    test('normalizes valid endpoint with trailing slash', () {
      final config = SyncConfiguration(
        endpoint: Uri.parse('https://example.com/dav'),
        username: 'alice',
        password: 'secretPassword123',
      );
      expect(config.endpoint.toString(), 'https://example.com/dav/');
      expect(config.username, 'alice');
      expect(config.password, 'secretPassword123');
    });

    test('preserves endpoint that already has trailing slash', () {
      final config = SyncConfiguration(
        endpoint: Uri.parse('http://192.168.1.100:8080/sync/'),
      );
      expect(config.endpoint.toString(), 'http://192.168.1.100:8080/sync/');
      expect(config.username, '');
      expect(config.password, '');
    });

    test('parses root endpoint correctly', () {
      final config = SyncConfiguration(
        endpoint: Uri.parse('http://localhost:8080'),
      );
      expect(config.endpoint.toString(), 'http://localhost:8080/');
    });

    test('rejects non-http/https schemes', () {
      expect(
        () => SyncConfiguration(endpoint: Uri.parse('ftp://example.com/dav/')),
        throwsA(isA<SyncException>()),
      );
      expect(
        () => SyncConfiguration(endpoint: Uri.parse('file:///home/user/dav/')),
        throwsA(isA<SyncException>()),
      );
    });

    test('rejects empty host', () {
      expect(
        () => SyncConfiguration(endpoint: Uri.parse('http:///dav/')),
        throwsA(isA<SyncException>()),
      );
    });

    test('rejects credentials, queries, and fragments in endpoint URL', () {
      expect(
        () => SyncConfiguration(
          endpoint: Uri.parse('http://user:pass@example.com/dav/'),
        ),
        throwsA(isA<SyncException>()),
      );
      expect(
        () => SyncConfiguration(
          endpoint: Uri.parse('http://example.com/dav/?token=123'),
        ),
        throwsA(isA<SyncException>()),
      );
      expect(
        () => SyncConfiguration(
          endpoint: Uri.parse('http://example.com/dav/#section'),
        ),
        throwsA(isA<SyncException>()),
      );
    });

    test('rejects dot segments and percent-encoded dot segments', () {
      expect(
        () => SyncConfiguration.parseEndpoint(
          'http://example.com/dav/../secret/',
        ),
        throwsA(isA<SyncException>()),
      );
      expect(
        () => SyncConfiguration.parseEndpoint(
          'http://example.com/dav/%2e%2e/secret/',
        ),
        throwsA(isA<SyncException>()),
      );
    });

    test('parseEndpoint handles valid string and rejects empty string', () {
      final parsed = SyncConfiguration.parseEndpoint(
        '  https://my.nas.local:5005/webdav  ',
      );
      expect(parsed.toString(), 'https://my.nas.local:5005/webdav/');

      expect(
        () => SyncConfiguration.parseEndpoint(''),
        throwsA(isA<SyncException>()),
      );
      expect(
        () => SyncConfiguration.parseEndpoint('   '),
        throwsA(isA<SyncException>()),
      );
    });

    test('toString redacts username and password secrets', () {
      final config = SyncConfiguration(
        endpoint: Uri.parse('https://example.com/dav/'),
        username: 'alice',
        password: 'superSecretPassword',
      );
      final str = config.toString();
      expect(str, contains('[REDACTED]'));
      expect(str, isNot(contains('superSecretPassword')));
      expect(str, isNot(contains('alice')));
    });
  });

  group('SyncConfigurationStore', () {
    late FakeFlutterSecureStorage fakeStorage;
    late SyncConfigurationStore store;

    setUp(() {
      fakeStorage = FakeFlutterSecureStorage();
      store = SyncConfigurationStore(storage: fakeStorage);
    });

    test('read returns null when storage is empty', () async {
      final result = await store.read();
      expect(result, isNull);
    });

    test('save and read roundtrip persists all fields securely', () async {
      final config = SyncConfiguration(
        endpoint: Uri.parse('https://webdav.server.com:8443/dav/'),
        username: 'sync_user',
        password: 'sync_password_456',
      );

      await store.save(config);
      final loaded = await store.read();

      expect(loaded, isNotNull);
      expect(loaded!.endpoint, config.endpoint);
      expect(loaded.username, config.username);
      expect(loaded.password, config.password);
    });

    test('delete removes configuration from secure storage', () async {
      final config = SyncConfiguration(
        endpoint: Uri.parse('https://webdav.server.com/dav/'),
      );
      await store.save(config);
      expect(await store.read(), isNotNull);

      await store.delete();
      expect(await store.read(), isNull);
    });

    test('read throws SyncException on corrupted storage data', () async {
      await fakeStorage.write(
        key: 'reelva_sync_v1_secure_configuration',
        value: 'not-valid-json',
      );

      expect(() => store.read(), throwsA(isA<SyncException>()));
    });

    test('read throws SyncException on missing endpoint', () async {
      await fakeStorage.write(
        key: 'reelva_sync_v1_secure_configuration',
        value: '{"username":"user","password":"pw"}',
      );

      expect(() => store.read(), throwsA(isA<SyncException>()));
    });

    test('storage failure wraps into SyncException', () async {
      fakeStorage.shouldThrowOnRead = true;
      expect(() => store.read(), throwsA(isA<SyncException>()));

      fakeStorage.shouldThrowOnRead = false;
      fakeStorage.shouldThrowOnWrite = true;
      final config = SyncConfiguration(
        endpoint: Uri.parse('https://example.com/dav/'),
      );
      expect(() => store.save(config), throwsA(isA<SyncException>()));

      fakeStorage.shouldThrowOnWrite = false;
      fakeStorage.shouldThrowOnDelete = true;
      expect(() => store.delete(), throwsA(isA<SyncException>()));
    });
  });
}
