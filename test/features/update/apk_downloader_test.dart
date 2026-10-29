import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:reelva/features/update/domain/app_release.dart';
import 'package:reelva/features/update/infrastructure/apk_downloader.dart';

import 'update_test_helpers.dart';

void main() {
  late Directory directory;
  late ApkDownloader downloader;
  late ReleaseAsset asset;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('reelva-update-test-');
    asset = AppRelease.fromJson(
      releaseJson('0.2.0'),
      AppVersion.tryParse('0.2.0')!,
    ).assets.first;
    downloader = ApkDownloader(
      dio: Dio()
        ..httpClientAdapter = UpdateHttpAdapter(
          (_) => ResponseBody.fromString(
            'abc',
            200,
            headers: {
              Headers.contentLengthHeader: ['3'],
            },
          ),
        ),
      temporaryDirectory: () async => directory,
    );
  });

  tearDown(() async {
    downloader.close();
    await directory.delete(recursive: true);
  });

  test('按实际安装版本清理当前和旧版 APK，保留待安装包及其他文件', () async {
    final updates = await Directory(p.join(directory.path, 'updates')).create();
    const removed = [
      'Reelva-0.1.0-android-arm64-v8a.apk',
      'Reelva-0.2.0-beta10-android-arm64-v8a.apk',
      'Reelva-0.2.0-android-arm64-v8a.apk',
      'Reelva-0.2.0-android-x86_64.apk',
    ];
    const retained = [
      'Reelva-0.2.1-beta1-android-arm64-v8a.apk',
      'Reelva-0.3.0-android-arm64-v8a.apk',
      'Reelva-invalid-android-arm64-v8a.apk',
      'Reelva-0.1.0-windows-x64-installer.exe',
      'Reelva-0.1.0-android-arm64-v8a.apk.part',
      'other.apk',
    ];
    for (final name in [...removed, ...retained]) {
      await File(p.join(updates.path, name)).writeAsString('apk');
    }
    final scratch = await Directory(p.join(updates.path, 'download-active'))
        .create();
    final partial = await File(p.join(scratch.path, removed.first))
        .writeAsString('partial');
    final unrelated = await File(p.join(directory.path, removed.first))
        .writeAsString('outside updates');

    await downloader.removeInstalledApks('0.2.0');

    for (final name in removed) {
      expect(await File(p.join(updates.path, name)).exists(), isFalse);
    }
    for (final name in retained) {
      expect(await File(p.join(updates.path, name)).exists(), isTrue);
    }
    expect(await partial.exists(), isTrue);
    expect(await unrelated.exists(), isTrue);
  });

  test('Beta 更新成功后只清理已安装 Beta 及更早版本，可重复清理', () async {
    final updates = await Directory(p.join(directory.path, 'updates')).create();
    final old = await File(
      p.join(updates.path, 'Reelva-0.2.0-beta2-android-arm64-v8a.apk'),
    ).writeAsString('old');
    final installed = await File(
      p.join(updates.path, 'Reelva-0.2.0-beta10-android-arm64-v8a.apk'),
    ).writeAsString('installed');
    final newerBeta = await File(
      p.join(updates.path, 'Reelva-0.2.0-beta11-android-arm64-v8a.apk'),
    ).writeAsString('newer beta');
    final stable = await File(
      p.join(updates.path, 'Reelva-0.2.0-android-arm64-v8a.apk'),
    ).writeAsString('stable');

    await downloader.removeInstalledApks('0.2.0-beta10');
    await downloader.removeInstalledApks('0.2.0-beta10');

    expect(await old.exists(), isFalse);
    expect(await installed.exists(), isFalse);
    expect(await newerBeta.exists(), isTrue);
    expect(await stable.exists(), isTrue);
  });

  test('尚未下载更新时清理不创建目录，无法识别安装版本时保留 APK', () async {
    await downloader.removeInstalledApks('0.1.0');
    final updates = Directory(p.join(directory.path, 'updates'));
    expect(await updates.exists(), isFalse);
    await updates.create();
    final file = await File(p.join(updates.path, asset.name))
        .writeAsString('apk');

    await downloader.removeInstalledApks('unknown');

    expect(await file.exists(), isTrue);
  });

  test('验证大小和 SHA256 后再交付 APK，并提供下载进度', () async {
    var received = 0;
    final file = await downloader.download(
      asset,
      cancelToken: CancelToken(),
      onProgress: (value, _) => received = value,
    );
    expect(await file.readAsString(), 'abc');
    expect(file.path, endsWith('.apk'));
    expect(received, 3);
    expect(await File('${file.path}.part').exists(), isFalse);
  });

  test('不完整或摘要错误的文件不会成为可安装 APK，失败后可以重试', () async {
    for (final bad in [
      ReleaseAsset(
        name: asset.name,
        url: asset.url,
        size: 4,
        digest: asset.digest,
      ),
      ReleaseAsset(
        name: asset.name,
        url: asset.url,
        size: 3,
        digest: 'sha256:wrong',
      ),
    ]) {
      await expectLater(
        downloader.download(
          bad,
          cancelToken: CancelToken(),
          onProgress: (_, _) {},
        ),
        throwsFormatException,
      );
      expect(
        await directory
            .list(recursive: true)
            .where((entity) => entity is File)
            .toList(),
        isEmpty,
      );
    }
    final file = await downloader.download(
      asset,
      cancelToken: CancelToken(),
      onProgress: (_, _) {},
    );
    expect(await file.exists(), isTrue);
  });

  test('取消下载会清理临时文件，不交付安装包', () async {
    final token = CancelToken();
    await expectLater(
      downloader.download(
        asset,
        cancelToken: token,
        onProgress: (_, _) => token.cancel(),
      ),
      throwsA(
        isA<DioException>().having(
          (e) => e.type,
          'type',
          DioExceptionType.cancel,
        ),
      ),
    );
    expect(
      await File(p.join(directory.path, 'updates', asset.name)).exists(),
      isFalse,
    );
    expect(
      await directory
          .list(recursive: true)
          .where((entity) => entity is File)
          .toList(),
      isEmpty,
    );
  });
}
