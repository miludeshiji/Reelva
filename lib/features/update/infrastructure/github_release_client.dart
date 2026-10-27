import 'package:dio/dio.dart';

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
        validateStatus: (status) => status == 200 || status == 404,
      ),
    );
    if (response.statusCode == 404) return null;
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

  void close() => _dio.close(force: true);
}
