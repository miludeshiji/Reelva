import 'package:dio/dio.dart';
import 'package:xml/xml.dart';

import '../domain/app_release.dart';

class GithubReleaseClient {
  GithubReleaseClient({Dio? dio})
    : _dio =
          dio ?? Dio(BaseOptions(connectTimeout: const Duration(seconds: 15)));

  static final repositoryUrl = Uri.parse(
    'https://github.com/miludeshiji/Reelva',
  );
  static const _apiUrl =
      'https://api.github.com/repos/miludeshiji/Reelva/releases';
  final Dio _dio;

  Future<AppRelease?> findUpdate(String currentVersion) async {
    final current = AppVersion.tryParse(currentVersion);
    if (current == null) throw const FormatException('无法读取当前版本');
    final includeBeta = current.beta != null;
    final response = await _dio.get<dynamic>(
      includeBeta ? '$_apiUrl?per_page=100' : '$_apiUrl/latest',
      options: Options(
        headers: {
          'Accept': 'application/vnd.github+json',
          'User-Agent': 'Reelva',
        },
        sendTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 15),
        validateStatus: (status) =>
            status == 200 || status == 403 || status == 404 || status == 429,
      ),
    );
    if (response.statusCode == 404) return null;
    if (response.statusCode == 403 || response.statusCode == 429) {
      return _findFeedUpdate(current);
    }
    final data = response.data;
    final releases = includeBeta ? data as List<dynamic> : [data];
    AppRelease? latest;
    for (final item in releases) {
      final json = item as Map<String, dynamic>;
      if (json['draft'] == true ||
          (!includeBeta && json['prerelease'] == true)) {
        continue;
      }
      final version = AppVersion.tryParse(json['tag_name'] as String);
      if (version == null ||
          (!includeBeta && version.beta != null) ||
          version.compareTo(current) <= 0) {
        continue;
      }
      if (latest == null || version.compareTo(latest.version) > 0) {
        latest = AppRelease.fromJson(json, version);
      }
    }
    return latest;
  }

  Future<AppRelease?> _findFeedUpdate(AppVersion current) async {
    final response = await _dio.get<String>(
      '$repositoryUrl/releases.atom',
      options: Options(
        responseType: ResponseType.plain,
        headers: {'Accept': 'application/atom+xml', 'User-Agent': 'Reelva'},
        sendTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 15),
      ),
    );
    final feed = XmlDocument.parse(response.data!).rootElement;
    if (feed.name.local != 'feed' ||
        feed.namespaceUri != 'http://www.w3.org/2005/Atom') {
      throw const FormatException('无法读取 GitHub 发布订阅');
    }
    final tagPrefix = '$repositoryUrl/releases/tag/';
    AppRelease? latest;
    for (final entry in feed.findElements('entry')) {
      final href = entry
          .findElements('link')
          .where((link) => link.getAttribute('rel') == 'alternate')
          .firstOrNull
          ?.getAttribute('href');
      if (href == null || !href.startsWith(tagPrefix)) continue;
      final version = AppVersion.tryParse(href.substring(tagPrefix.length));
      if (version == null ||
          (current.beta == null && version.beta != null) ||
          version.compareTo(current) <= 0) {
        continue;
      }
      if (latest == null || version.compareTo(latest.version) > 0) {
        // Atom 不提供安装包大小和摘要，交由发布页下载，保留应用内校验要求。
        latest = AppRelease(
          version: version,
          url: Uri.parse(href),
          notes: '请在 GitHub 发布页面查看完整更新说明并下载安装包。',
          assets: const [],
        );
      }
    }
    return latest;
  }

  void close() => _dio.close(force: true);
}
