import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reelva/features/library/infrastructure/media_library_repository.dart';
import 'package:reelva/features/metadata/application/metadata_providers.dart';
import 'package:reelva/features/metadata/domain/tmdb_models.dart';
import 'package:reelva/features/metadata/infrastructure/tmdb_token_store.dart';
import 'package:reelva/features/sources/application/source_providers.dart';

class FakeFlutterSecureStorage extends FlutterSecureStorage {
  final Map<String, String> _data = {};

  @override
  Future<String?> read({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async => _data[key];

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
  }) async => _data.remove(key);
}

class FakeMediaLibraryRepository implements MediaLibraryRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeMetadataService implements MetadataService {
  MetadataRefreshResult resultToReturn = const MetadataRefreshResult(
    matched: 3,
  );
  Object? errorToThrow;
  Future<MetadataRefreshResult> Function()? customRefreshHandler;
  int refreshCallCount = 0;

  @override
  Future<MetadataRefreshResult> refresh() async {
    refreshCallCount++;
    if (customRefreshHandler != null) {
      return customRefreshHandler!();
    }
    if (errorToThrow != null) {
      throw errorToThrow!;
    }
    return resultToReturn;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('MetadataController Boundary Tests', () {
    late FakeFlutterSecureStorage fakeStorage;
    late TmdbTokenStore tokenStore;
    late FakeMetadataService fakeService;
    late FakeMediaLibraryRepository fakeRepo;
    late ProviderContainer container;

    setUp(() {
      fakeStorage = FakeFlutterSecureStorage();
      tokenStore = TmdbTokenStore(storage: fakeStorage);
      fakeService = FakeMetadataService();
      fakeRepo = FakeMediaLibraryRepository();

      container = ProviderContainer(
        overrides: [
          tmdbTokenStoreProvider.overrideWithValue(tokenStore),
          metadataServiceProvider.overrideWithValue(fakeService),
          mediaLibraryRepositoryProvider.overrideWithValue(fakeRepo),
        ],
      );
    });

    tearDown(() {
      container.dispose();
    });

    test(
      'refresh executes successfully and updates state without throwing',
      () async {
        final notifier = container.read(metadataControllerProvider.notifier);
        await notifier.refresh();

        final state = container.read(metadataControllerProvider);
        expect(state.running, isFalse);
        expect(state.result?.matched, equals(3));
        expect(state.error, isNull);
        expect(fakeService.refreshCallCount, equals(1));
      },
    );

    test(
      'refresh safely captures errors into state.error without escaping',
      () async {
        fakeService.errorToThrow = const MetadataException(
          'TMDB 连接失败 (429)',
          code: 'rate_limit',
        );

        final notifier = container.read(metadataControllerProvider.notifier);
        await notifier.refresh();

        final state = container.read(metadataControllerProvider);
        expect(state.running, isFalse);
        expect(state.error, contains('TMDB 连接失败 (429)'));
      },
    );

    test('queued refresh executes when concurrent refresh requested during active run', () async {
      final completer = Completer<MetadataRefreshResult>();
      bool firstCall = true;

      fakeService.customRefreshHandler = () {
        if (firstCall) {
          firstCall = false;
          return completer.future;
        }
        return Future.value(const MetadataRefreshResult(matched: 7));
      };

      final notifier = container.read(metadataControllerProvider.notifier);
      final firstFuture = notifier.refresh();

      expect(container.read(metadataControllerProvider).running, isTrue);

      // 处于运行中时再次请求刷新，触发 queued refresh 标记
      final secondFuture = notifier.refresh();

      completer.complete(const MetadataRefreshResult(matched: 2));
      await firstFuture;
      await secondFuture;

      final finalState = container.read(metadataControllerProvider);
      expect(finalState.running, isFalse);
      expect(finalState.result?.matched, equals(7));
      expect(fakeService.refreshCallCount, equals(2));
    });
  });
}
