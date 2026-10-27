import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:reelva/features/update/application/app_update_providers.dart';
import 'package:reelva/features/update/infrastructure/github_release_client.dart';
import 'package:reelva/features/update/infrastructure/update_preferences_store.dart';

import 'update_test_helpers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    PackageInfo.setMockInitialValues(
      appName: 'Reelva',
      packageName: 'com.github.miludeshiji.reelva',
      version: '0.1.0',
      buildNumber: '1',
      buildSignature: '',
    );
  });

  test('自动检查默认开启，关闭后跨实例保留，24 小时内不重复自动检查', () async {
    const store = UpdatePreferencesStore();
    final now = DateTime.now();
    expect((await store.read()).shouldCheck(now), isTrue);
    await store.saveLastChecked(now);
    expect(
      (await store.read()).shouldCheck(now.add(const Duration(hours: 23))),
      isFalse,
    );
    expect(
      (await store.read()).shouldCheck(now.add(const Duration(hours: 24))),
      isTrue,
    );
    await store.saveAutomatic(false);
    expect(
      (await const UpdatePreferencesStore().read()).shouldCheck(
        now.add(const Duration(days: 2)),
      ),
      isFalse,
    );
  });

  test('并行的手动与自动检查复用请求，手动检查不受每日限制', () async {
    final response = Completer<ResponseBody>();
    final adapter = UpdateHttpAdapter((_) async {
      await response.future;
      return jsonResponse(releaseJson('0.2.0'));
    });
    final client = GithubReleaseClient(dio: Dio()..httpClientAdapter = adapter);
    addTearDown(client.close);
    final container = ProviderContainer(
      overrides: [githubReleaseClientProvider.overrideWithValue(client)],
    );
    addTearDown(container.dispose);
    final controller = container.read(updateCheckProvider.notifier);
    final first = controller.check();
    final second = controller.check();
    expect(identical(first, second), isTrue);
    response.complete(jsonResponse(releaseJson('0.2.0')));
    expect((await first)!.version.text, '0.2.0');
    expect((await second)!.version.text, '0.2.0');
    expect(adapter.requests, hasLength(1));
    expect(
      (await container.read(updatePreferencesProvider.future)).lastCheckedAt,
      isNotNull,
    );
    await controller.check();
    expect(adapter.requests, hasLength(2));
  });
}
