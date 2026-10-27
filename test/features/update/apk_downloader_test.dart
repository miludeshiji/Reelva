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
