import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reelva/features/metadata/domain/tmdb_models.dart';
import 'package:reelva/features/metadata/infrastructure/tmdb_token_store.dart';

class FakeFlutterSecureStorage extends FlutterSecureStorage {
  final Map<String, String> _data = {};
  bool throwOnRead = false;
  bool throwOnWrite = false;
  bool throwOnDelete = false;

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
    if (throwOnRead) {
      throw Exception('Platform secure storage read failure');
    }
    return _data[key];
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
    if (throwOnWrite) {
      throw Exception('Platform secure storage write failure');
    }
    if (value == null) {
      _data.remove(key);
    } else {
      _data[key] = value;
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
    if (throwOnDelete) {
      throw Exception('Platform secure storage delete failure');
    }
    _data.remove(key);
  }

  @override
  Future<bool> containsKey({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    return _data.containsKey(key);
  }
}

void main() {
  group('TmdbTokenStore', () {
    late FakeFlutterSecureStorage fakeStorage;
    late TmdbTokenStore store;

    setUp(() {
      fakeStorage = FakeFlutterSecureStorage();
      store = TmdbTokenStore(storage: fakeStorage);
    });

    test('initial state is unconfigured and read returns null', () async {
      expect(await store.isConfigured(), isFalse);
      expect(await store.read(), isNull);
    });

    test('saves and reads valid 32-hex v3 API Key', () async {
      const v3Key = 'a1b2c3d4e5f60718293a4b5c6d7e8f90';
      await store.save(v3Key);

      expect(await store.isConfigured(), isTrue);
      expect(await store.read(), equals(v3Key));
      expect(TmdbTokenStore.isBearerToken(v3Key), isFalse);
    });

    test('saves and reads valid v4 JWT Bearer Token', () async {
      const jwtToken =
          'eyJhbGciOiJIUzI1NiJ9.eyJhdWQiOiIxMjM0NTYiLCJzdWIiOiI3ODkiLCJzY29wZXMiOlsicmVhZCJdfQ.signature1234567890';
      await store.save(jwtToken);

      expect(await store.isConfigured(), isTrue);
      expect(await store.read(), equals(jwtToken));
      expect(TmdbTokenStore.isBearerToken(jwtToken), isTrue);
    });

    test('strips leading Bearer prefix and whitespace automatically', () async {
      const rawWithBearer =
          '  Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.payload.sig  ';
      await store.save(rawWithBearer);

      final readValue = await store.read();
      expect(
        readValue,
        equals('eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.payload.sig'),
      );
      expect(readValue!.startsWith('Bearer'), isFalse);
    });

    test(
      'rejects invalid or empty token format with safe MetadataException',
      () async {
        expect(
          () => store.save(''),
          throwsA(
            isA<MetadataException>().having(
              (e) => e.code,
              'code',
              'invalid_token',
            ),
          ),
        );

        expect(
          () => store.save('short-token'),
          throwsA(
            isA<MetadataException>().having(
              (e) => e.code,
              'code',
              'invalid_token',
            ),
          ),
        );

        expect(
          () => store.save('not_hex_and_too_short_!@#'),
          throwsA(
            isA<MetadataException>().having(
              (e) => e.code,
              'code',
              'invalid_token',
            ),
          ),
        );
      },
    );
    test('rejects tokens containing newlines, tabs or control chars', () async {
      expect(
        () => store.save(
          'eyJhbGciOiJIUzI1NiJ9.\neyJhdWQiOiIxMjM0NTYifQ.signature1234567890',
        ),
        throwsA(
          isA<MetadataException>().having(
            (e) => e.code,
            'code',
            'invalid_token',
          ),
        ),
      );

      expect(
        () => store.save('0123456789abcdef\t0123456789abcdef'),
        throwsA(
          isA<MetadataException>().having(
            (e) => e.code,
            'code',
            'invalid_token',
          ),
        ),
      );
    });

    test(
      'isConfigured propagates storage_error instead of swallowing as false',
      () async {
        fakeStorage.throwOnRead = true;
        expect(
          () => store.isConfigured(),
          throwsA(
            isA<MetadataException>().having(
              (e) => e.code,
              'code',
              'storage_error',
            ),
          ),
        );
      },
    );

    test('deletes configured token cleanly', () async {
      await store.save('0123456789abcdef0123456789abcdef');
      expect(await store.isConfigured(), isTrue);

      await store.delete();
      expect(await store.isConfigured(), isFalse);
      expect(await store.read(), isNull);
    });

    test('maps storage read/write/delete exceptions to safe MetadataException without token leakage', () async {
      fakeStorage.throwOnWrite = true;
      expect(
        () => store.save('0123456789abcdef0123456789abcdef'),
        throwsA(
          isA<MetadataException>()
              .having((e) => e.code, 'code', 'storage_error')
              .having(
                (e) => e.toString().contains('0123456789abcdef'),
                'no secret in toString',
                isFalse,
              ),
        ),
      );

      fakeStorage.throwOnWrite = false;
      fakeStorage.throwOnRead = true;
      expect(
        () => store.read(),
        throwsA(
          isA<MetadataException>().having(
            (e) => e.code,
            'code',
            'storage_error',
          ),
        ),
      );

      fakeStorage.throwOnRead = false;
      fakeStorage.throwOnDelete = true;
      expect(
        () => store.delete(),
        throwsA(
          isA<MetadataException>().having(
            (e) => e.code,
            'code',
            'storage_error',
          ),
        ),
      );
    });
  });
}
