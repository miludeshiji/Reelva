import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reelva/features/sources/domain/source_models.dart';
import 'package:reelva/features/sources/infrastructure/remote_credentials_store.dart';

class FakeFlutterSecureStorage extends Fake implements FlutterSecureStorage {
  final Map<String, String> _storage = {};
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
      throw Exception('Hardware storage failure');
    }
    _storage.remove(key);
  }
}

void main() {
  group('RemoteCredentials', () {
    test('toString 强制脱敏，绝不泄漏敏感字段', () {
      const creds = RemoteCredentials(
        username: 'super_admin',
        password: 'my_super_secret_password',
        token: 'secret_token_value',
        domain: 'CORP_DOMAIN',
      );

      final str = creds.toString();
      expect(str, contains('[REDACTED]'));
      expect(str, isNot(contains('my_super_secret_password')));
      expect(str, isNot(contains('secret_token_value')));
      expect(str, isNot(contains('super_admin')));
    });
  });

  group('RemoteCredentialsStore', () {
    late FakeFlutterSecureStorage fakeStorage;
    late RemoteCredentialsStore store;

    setUp(() {
      fakeStorage = FakeFlutterSecureStorage();
      store = RemoteCredentialsStore(storage: fakeStorage);
    });

    test('read(null) 或 read("") 返回匿名凭据且不抛异常', () async {
      final credsNull = await store.read(null);
      expect(credsNull.isAnonymous, isTrue);

      final credsEmpty = await store.read('   ');
      expect(credsEmpty.isAnonymous, isTrue);
    });

    test('非空引用但不存在时抛出 credential_not_found', () async {
      expect(
        () => store.read('non_existent_ref'),
        throwsA(
          isA<MediaSourceException>().having(
            (e) => e.code,
            'code',
            'credential_not_found',
          ),
        ),
      );
    });

    test('write 成功保存并在 read 时正确还原凭据与请求头', () async {
      const creds = RemoteCredentials(
        username: 'webdav_user',
        password: 'webdav_password',
        token: 'openlist_token',
        domain: 'WORKGROUP',
        playbackHeaders: {
          'User-Agent': 'CustomUA/1.0',
          'Referer': 'https://foo',
        },
      );

      await store.write('ref_1', creds);
      final loaded = await store.read('ref_1');

      expect(loaded.username, 'webdav_user');
      expect(loaded.password, 'webdav_password');
      expect(loaded.token, 'openlist_token');
      expect(loaded.domain, 'WORKGROUP');
      expect(loaded.playbackHeaders, {
        'User-Agent': 'CustomUA/1.0',
        'Referer': 'https://foo',
      });
    });

    test('损坏的 JSON 抛出 credential_corrupt', () async {
      await fakeStorage.write(key: 'corrupt_ref', value: 'not a valid json {]');
      expect(
        () => store.read('corrupt_ref'),
        throwsA(
          isA<MediaSourceException>().having(
            (e) => e.code,
            'code',
            'credential_corrupt',
          ),
        ),
      );
    });

    test('delete 移除凭据，后续读取抛出 credential_not_found', () async {
      const creds = RemoteCredentials(username: 'test');
      await store.write('ref_to_delete', creds);
      await store.delete('ref_to_delete');

      expect(
        () => store.read('ref_to_delete'),
        throwsA(
          isA<MediaSourceException>().having(
            (e) => e.code,
            'code',
            'credential_not_found',
          ),
        ),
      );
    });

    test('delete 遇底层异常时映射为 credential_storage_failed', () async {
      fakeStorage.shouldThrowOnDelete = true;
      expect(
        () => store.delete('some_ref'),
        throwsA(
          isA<MediaSourceException>().having(
            (e) => e.code,
            'code',
            'credential_storage_failed',
          ),
        ),
      );
    });
  });
}
