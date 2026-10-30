import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reelva/features/update/domain/app_release.dart';
import 'package:reelva/features/update/infrastructure/github_release_client.dart';

import 'update_test_helpers.dart';

void main() {
  test('按数字比较版本和项目 betaN，忽略构建元数据', () {
    for (final pair in [
      ('0.1.10', '0.1.9'),
      ('0.2.0-beta10', '0.2.0-beta2'),
      ('0.2.0', '0.2.0-beta10'),
      ('1.0.0-beta1', '0.9.9'),
    ]) {
      expect(
        AppVersion.tryParse(pair.$1)!.compareTo(AppVersion.tryParse(pair.$2)!),
        greaterThan(0),
      );
    }
    expect(
      AppVersion.tryParse('v0.2.0+3')!
          .compareTo(AppVersion.tryParse('0.2.0+2')!),
      0,
    );
    expect(AppVersion.tryParse('invalid'), isNull);
  });

  test('正式版读取 latest，保留说明、发布日期和附件', () async {
    final adapter = UpdateHttpAdapter(
      (_) => jsonResponse(releaseJson('0.2.0')),
    );
    final client = GithubReleaseClient(dio: Dio()..httpClientAdapter = adapter);
    addTearDown(client.close);
    final release = (await client.findUpdate('0.1.0'))!;
    expect(adapter.requests.single.uri.path, endsWith('/releases/latest'));
    expect(release.version.text, '0.2.0');
    expect(release.notes, contains('支持应用内检查更新'));
    expect(release.publishedAt, DateTime.utc(2026, 10, 27));
    expect(release.url.path, endsWith('/tag/v0.2.0'));
    expect(release.assets, hasLength(5));
  });

  test('Beta 从发布列表选取数值最高的 Beta 或正式版，跳过草稿和无效版本', () async {
    final adapter = UpdateHttpAdapter(
      (_) => jsonResponse([
        releaseJson('0.2.0-beta2', prerelease: true),
        releaseJson('0.2.0-beta10', prerelease: true),
        releaseJson('0.3.0', draft: true),
        releaseJson('invalid'),
      ]),
    );
    final client = GithubReleaseClient(dio: Dio()..httpClientAdapter = adapter);
    addTearDown(client.close);
    expect(
      (await client.findUpdate('0.2.0-beta1'))!.version.text,
      '0.2.0-beta10',
    );
    expect(adapter.requests.single.uri.queryParameters['per_page'], '100');

    final formal = GithubReleaseClient(
      dio: Dio()
        ..httpClientAdapter = UpdateHttpAdapter(
          (_) => jsonResponse([
            releaseJson('0.2.0-beta10', prerelease: true),
            releaseJson('0.2.0'),
          ]),
        ),
    );
    addTearDown(formal.close);
    expect((await formal.findUpdate('0.2.0-beta9'))!.version.text, '0.2.0');
  });

  test('同版本、旧版本、预发布和没有发布均作为无更新，服务端错误仍失败', () async {
    for (final body in [
      releaseJson('0.1.0'),
      releaseJson('0.0.9'),
      releaseJson('0.2.0-beta1', prerelease: true),
    ]) {
      final client = GithubReleaseClient(
        dio: Dio()
          ..httpClientAdapter = UpdateHttpAdapter((_) => jsonResponse(body)),
      );
      expect(await client.findUpdate('0.1.0'), isNull);
      client.close();
    }
    final noRelease = GithubReleaseClient(
      dio: Dio()
        ..httpClientAdapter = UpdateHttpAdapter(
          (_) => jsonResponse({}, status: 404),
        ),
    );
    addTearDown(noRelease.close);
    expect(await noRelease.findUpdate('0.1.0'), isNull);
    final empty = GithubReleaseClient(
      dio: Dio()
        ..httpClientAdapter = UpdateHttpAdapter((_) => jsonResponse([])),
    );
    addTearDown(empty.close);
    expect(await empty.findUpdate('0.2.0-beta1'), isNull);
    final failed = GithubReleaseClient(
      dio: Dio()
        ..httpClientAdapter = UpdateHttpAdapter(
          (_) => jsonResponse({}, status: 503),
        ),
    );
    addTearDown(failed.close);
    await expectLater(failed.findUpdate('0.1.0'), throwsA(isA<DioException>()));
  });

  test('按系统首选架构精确匹配安装包，缺失时不会选错架构或 Debug 包', () {
    final json = releaseJson('0.2.0');
    final release = AppRelease.fromJson(json, AppVersion.tryParse('0.2.0')!);
    expect(
      release.androidApk(['arm64-v8a', 'armeabi-v7a'])!.name,
      endsWith('arm64-v8a.apk'),
    );
    expect(
      release.androidApk(['armeabi-v7a'])!.name,
      endsWith('armeabi-v7a.apk'),
    );
    expect(release.androidApk(['x86_64', 'x86'])!.name, endsWith('x86_64.apk'));
    expect(release.androidApk(['x86']), isNull);
    expect(release.windowsInstaller!.name, endsWith('installer.exe'));
    expect(release.windowsPortable!.name, endsWith('windows-x64.zip'));
    final assets = json['assets'] as List<Map<String, Object>>;
    assets.first['name'] = 'Reelva-0.2.0-android-arm64-v8a-debug.apk';
    final missing = AppRelease.fromJson(json, release.version);
    expect(missing.androidApk(['arm64-v8a', 'armeabi-v7a']), isNull);
  });

  for (final status in [403, 429]) {
    test('$status 时读取发布订阅，按标签选择新版本并提供发布页', () async {
      final adapter = UpdateHttpAdapter((options) {
        if (options.uri.host == 'api.github.com') {
          return jsonResponse({
            'message': 'API rate limit exceeded',
          }, status: status);
        }
        return atomResponse([
          '0.2.0-beta2',
          '0.2.0-beta10',
          'invalid',
          '0.1.0',
        ]);
      });
      final client = GithubReleaseClient(
        dio: Dio()..httpClientAdapter = adapter,
      );
      addTearDown(client.close);
      final release = (await client.findUpdate('0.2.0-beta1'))!;
      expect(release.version.text, '0.2.0-beta10');
      expect(
        release.url.toString(),
        'https://github.com/miludeshiji/Reelva/releases/tag/v0.2.0-beta10',
      );
      expect(release.notes, contains('GitHub 发布页面'));
      expect(release.assets, isEmpty);
      expect(adapter.requests, hasLength(2));
      expect(
        adapter.requests.last.uri.path,
        '/miludeshiji/Reelva/releases.atom',
      );
      expect(adapter.requests.last.headers['Accept'], 'application/atom+xml');
    });
  }

  test('限流后的正式版检查跳过 Beta，按数值选择最高正式版', () async {
    final client = GithubReleaseClient(
      dio: Dio()
        ..httpClientAdapter = UpdateHttpAdapter((options) {
          if (options.uri.host == 'api.github.com') {
            return jsonResponse({}, status: 403);
          }
          return atomResponse(['0.3.0-beta1', '0.1.9', '0.1.10', 'invalid']);
        }),
    );
    addTearDown(client.close);
    expect((await client.findUpdate('0.1.0'))!.version.text, '0.1.10');
  });

  test('限流后的空订阅、同版本、旧版本和正式版遇到 Beta 均不提示更新', () async {
    for (final versions in <List<String>>[
      [],
      ['0.1.0', '0.0.9', '0.2.0-beta1', 'invalid'],
    ]) {
      final client = GithubReleaseClient(
        dio: Dio()
          ..httpClientAdapter = UpdateHttpAdapter((options) {
            return options.uri.host == 'api.github.com'
                ? jsonResponse({}, status: 403)
                : atomResponse(versions);
          }),
      );
      addTearDown(client.close);
      expect(await client.findUpdate('0.1.0'), isNull);
    }
  });

  test('发布订阅请求失败或内容无效时仍报告失败', () async {
    for (final response in [
      jsonResponse({}, status: 503),
      ResponseBody.fromString('<html>访问受限</html>', 200),
      ResponseBody.fromString('<feed', 200),
    ]) {
      final client = GithubReleaseClient(
        dio: Dio()
          ..httpClientAdapter = UpdateHttpAdapter((options) {
            return options.uri.host == 'api.github.com'
                ? jsonResponse({}, status: 403)
                : response;
          }),
      );
      addTearDown(client.close);
      await expectLater(client.findUpdate('0.1.0'), throwsException);
    }
  });
}
