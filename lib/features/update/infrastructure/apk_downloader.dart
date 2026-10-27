import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:dio/dio.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../domain/app_release.dart';

class ApkDownloader {
  ApkDownloader({Dio? dio, Future<Directory> Function()? temporaryDirectory})
    : _dio =
          dio ?? Dio(BaseOptions(connectTimeout: const Duration(seconds: 15))),
      _temporaryDirectory = temporaryDirectory ?? getTemporaryDirectory;

  final Dio _dio;
  final Future<Directory> Function() _temporaryDirectory;

  Future<File> download(
    ReleaseAsset asset, {
    required CancelToken cancelToken,
    required ProgressCallback onProgress,
  }) async {
    if (asset.url.scheme != 'https' ||
        p.basename(asset.name) != asset.name ||
        !asset.name.endsWith('.apk')) {
      throw const FormatException('无效的安装包地址');
    }
    final cache = await _temporaryDirectory();
    final directory = await Directory(p.join(cache.path, 'updates'))
        .create(recursive: true);
    final scratch = await directory.createTemp('download-');
    final partial = File(p.join(scratch.path, '${asset.name}.part'));
    try {
      await _dio.downloadUri(
        asset.url,
        partial.path,
        cancelToken: cancelToken,
        onReceiveProgress: onProgress,
        options: Options(receiveTimeout: const Duration(seconds: 60)),
      );
      if (cancelToken.isCancelled) throw cancelToken.cancelError!;
      if (await partial.length() != asset.size || asset.size <= 0) {
        throw const FormatException('安装包下载不完整，请重试');
      }
      final expected = asset.digest;
      if (expected != null) {
        final sink = Sha256().toSync().newHashSink();
        await for (final chunk in partial.openRead()) {
          if (cancelToken.isCancelled) throw cancelToken.cancelError!;
          sink.add(chunk);
        }
        sink.close();
        final hash = await sink.hash();
        final actual = hash.bytes
            .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
            .join();
        if (expected.toLowerCase() != 'sha256:$actual') {
          throw const FormatException('安装包校验失败，请重新下载');
        }
      }
      if (cancelToken.isCancelled) throw cancelToken.cancelError!;
      return await partial.rename(p.join(directory.path, asset.name));
    } finally {
      await scratch.delete(recursive: true);
    }
  }

  void close() => _dio.close(force: true);
}
