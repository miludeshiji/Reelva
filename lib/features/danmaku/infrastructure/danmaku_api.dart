import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:xml/xml.dart';

import '../domain/danmaku.dart';
import 'danmaku_store.dart';

class DanmakuException implements Exception {
  const DanmakuException(this.message);
  final String message;
  @override
  String toString() => message;
}

String dandanSignature(
  String appId,
  String secret,
  int timestamp,
  String path,
) => base64Encode(
  sha256.convert(utf8.encode('$appId$timestamp$path$secret')).bytes,
);

class DanmakuApi {
  DanmakuApi({
    required this.store,
    Dio? dio,
    this.appId = const String.fromEnvironment(
      'DANDANPLAY_APP_ID',
      defaultValue: 'fz8wr374v3',
    ),
    this.appSecret = const String.fromEnvironment('DANDANPLAY_APP_SECRET'),
    this.dandanBase = 'https://api.dandanplay.net',
    this.bilibiliBase = 'https://api.bilibili.com',
    DateTime Function()? now,
  }) : _dio =
           dio ??
           Dio(
             BaseOptions(
               connectTimeout: const Duration(seconds: 10),
               receiveTimeout: const Duration(seconds: 20),
             ),
           ),
       _now = now ?? DateTime.now;

  final DanmakuStore store;
  final Dio _dio;
  final DateTime Function() _now;
  final String appId;
  final String appSecret;
  final String dandanBase;
  final String bilibiliBase;
  bool get dandanConfigured => appId.isNotEmpty && appSecret.isNotEmpty;
  void dispose() => _dio.close(force: true);

  Future<Map<String, dynamic>> _request(
    String url, {
    Map<String, dynamic>? query,
    Map<String, dynamic>? headers,
    Object? data,
    CancelToken? cancelToken,
  }) async {
    try {
      var response = await _dio.request<dynamic>(
        url,
        queryParameters: query,
        data: data,
        cancelToken: cancelToken,
        options: Options(
          method: data == null ? 'GET' : 'POST',
          headers: headers,
          followRedirects: false,
          responseType: ResponseType.json,
          validateStatus: (status) =>
              status != null && status >= 200 && status < 400,
        ),
      );
      for (
        var redirects = 0;
        response.statusCode == 302 || response.statusCode == 307;
        redirects++
      ) {
        if (redirects >= 3) throw const DanmakuException('弹幕服务重定向过多');
        final location = response.headers.value('location');
        final target = location == null
            ? null
            : response.realUri.resolve(location);
        if (target == null ||
            target.scheme != 'https' ||
            target.host.isEmpty ||
            target.userInfo.isNotEmpty) {
          throw const DanmakuException('弹幕服务返回了无效的下载地址');
        }
        // CDN 请求不携带 API 签名或其他来源的认证信息。
        response = await _dio.get<dynamic>(
          target.toString(),
          cancelToken: cancelToken,
          options: Options(
            followRedirects: false,
            responseType: ResponseType.json,
            validateStatus: (status) =>
                status != null && status >= 200 && status < 400,
          ),
        );
      }
      final payload = response.data;
      final json = payload is String ? jsonDecode(payload) : payload;
      if (json is! Map<String, dynamic>) {
        throw const DanmakuException('弹幕服务返回了无效的数据');
      }
      if (json['success'] == false) {
        throw const DanmakuException('弹弹play请求失败，请检查应用授权或稍后重试');
      }
      if (json['code'] != null && json['code'] != 0) {
        throw const DanmakuException('哔哩哔哩请求受限，请稍后重试或改用弹弹play');
      }
      return json;
    } on DioException catch (error) {
      if (CancelToken.isCancel(error)) rethrow;
      if (error.response?.statusCode == 401 ||
          error.response?.statusCode == 403) {
        throw const DanmakuException('弹幕服务未授权，请检查应用凭据');
      }
      throw const DanmakuException('弹幕服务连接失败，请稍后重试');
    }
  }

  Future<Map<String, dynamic>> _dandan(
    String path, {
    Map<String, dynamic>? query,
    Object? data,
    CancelToken? cancelToken,
  }) async {
    if (!dandanConfigured) {
      throw const DanmakuException('此构建未配置弹弹play凭据，可使用哔哩哔哩来源');
    }
    final cacheable = data == null && !path.startsWith('/api/v2/comment/');
    final key = 'danmaku-api:v1:$path:${jsonEncode(query)}';
    if (cacheable) {
      try {
        final cached = await store.readCache(key);
        if (cached != null) return jsonDecode(cached) as Map<String, dynamic>;
      } catch (_) {
        /* 在线请求可继续。 */
      }
    }
    final timestamp = _now().millisecondsSinceEpoch ~/ 1000;
    final result = await _request(
      '$dandanBase$path',
      query: query,
      data: data,
      cancelToken: cancelToken,
      headers: {
        'X-AppId': appId,
        'X-Timestamp': '$timestamp',
        'X-Signature': dandanSignature(appId, appSecret, timestamp, path),
      },
    );
    if (cacheable) {
      try {
        await store.writeCache(
          key,
          jsonEncode(result),
          ttl: const Duration(hours: 2),
        );
      } catch (_) {
        /* 搜索结果仍可使用。 */
      }
    }
    return result;
  }

  Future<Map<String, dynamic>> _bilibili(
    String path, {
    Map<String, dynamic>? query,
    CancelToken? cancelToken,
  }) => _request(
    '$bilibiliBase$path',
    query: query,
    cancelToken: cancelToken,
    headers: {
      'User-Agent': 'Mozilla/5.0',
      'Referer': 'https://www.bilibili.com/',
    },
  );

  Future<List<DanmakuShow>> search(
    String keyword,
    DanmakuSource source, {
    int? tmdbId,
    bool movie = false,
    CancelToken? cancelToken,
  }) async {
    if (source == DanmakuSource.bilibili) {
      final video = RegExp(r'^(BV[0-9A-Za-z]+|av\d+|ss\d+|ep\d+)$')
          .firstMatch(keyword.trim());
      final uri = Uri.tryParse(keyword.trim());
      final token =
          video?.group(1) ??
          (uri != null &&
                  (uri.host == 'bilibili.com' ||
                      uri.host.endsWith('.bilibili.com'))
              ? RegExp(r'(BV[0-9A-Za-z]+|av\d+|ss\d+|ep\d+)')
                    .firstMatch(uri.path)
                    ?.group(1)
              : null);
      if (token != null) {
        return [DanmakuShow(source: source, id: token, title: token)];
      }
      final results = await Future.wait(
        ['media_bangumi', 'media_ft'].map(
          (type) => _bilibili(
            '/x/web-interface/search/type',
            query: {'search_type': type, 'keyword': keyword},
            cancelToken: cancelToken,
          ),
        ),
      );
      final shows = <String, DanmakuShow>{};
      for (final result in results) {
        final body = result['data'] as Map<String, dynamic>?;
        for (final item in _maps(body?['result'])) {
          final id = '${item['season_id']}';
          if (id == 'null') continue;
          final year = item['pubtime'] is num
              ? DateTime.fromMillisecondsSinceEpoch(
                  (item['pubtime'] as num).toInt() * 1000,
                ).year
              : null;
          shows[id] = DanmakuShow(
            source: source,
            id: 'ss$id',
            title: _plain('${item['title'] ?? ''}'),
            year: year,
          );
        }
      }
      return shows.values.toList();
    }
    final json = await _dandan(
      '/api/v2/search/episodes',
      query: {
        if (tmdbId == null) 'anime': keyword,
        'tmdbId': ?tmdbId,
        if (tmdbId != null) 'tmdbIdType': movie ? 1 : 0,
        'v2': true,
      },
      cancelToken: cancelToken,
    );
    return [
      for (final show in _maps(json['animes']))
        DanmakuShow(
          source: source,
          id: '${show['animeId']}',
          title: '${show['animeTitle']}',
          tmdbMatched: tmdbId != null,
        ),
    ];
  }

  Future<List<DanmakuEpisode>> episodes(
    DanmakuShow show, {
    CancelToken? cancelToken,
  }) async {
    if (show.source == DanmakuSource.dandanplay) {
      final json = await _dandan(
        '/api/v2/bangumi/${show.id}',
        cancelToken: cancelToken,
      );
      final bangumi = json['bangumi'] as Map<String, dynamic>?;
      return [
        for (final episode in _maps(bangumi?['episodes']))
          DanmakuEpisode(
            source: show.source,
            id: '${episode['episodeId']}',
            title: show.title,
            episodeTitle: '${episode['episodeTitle'] ?? ''}',
            number: danmakuEpisodeNumber('${episode['episodeTitle'] ?? ''}'),
          ),
      ];
    }
    if (show.id.startsWith('BV') || show.id.startsWith('av')) {
      final json = await _bilibili(
        '/x/web-interface/view',
        query: {
          if (show.id.startsWith('BV'))
            'bvid': show.id
          else
            'aid': show.id.substring(2),
        },
        cancelToken: cancelToken,
      );
      final data = json['data'] as Map<String, dynamic>;
      return [
        for (final page in _maps(data['pages']))
          DanmakuEpisode(
            source: show.source,
            id: '${page['cid']}',
            title: '${data['title']}',
            episodeTitle: '${page['part']}',
            number: page['page'] as int?,
          ),
      ];
    }
    final json = await _bilibili(
      '/pgc/view/web/season',
      query: {
        show.id.startsWith('ep') ? 'ep_id' : 'season_id': show.id.substring(2),
      },
      cancelToken: cancelToken,
    );
    final result = json['result'] as Map<String, dynamic>;
    final episodes = <DanmakuEpisode>[];
    void add(Object? value) {
      for (final episode in _maps(value)) {
        if (episode['cid'] == null) continue;
        episodes.add(
          DanmakuEpisode(
            source: show.source,
            id: '${episode['cid']}',
            title: '${result['title'] ?? show.title}',
            episodeTitle: [
              '${episode['title'] ?? ''}',
              '${episode['long_title'] ?? ''}',
            ].where((part) => part.isNotEmpty).join(' · '),
            number: int.tryParse('${episode['title']}'),
          ),
        );
      }
    }

    add(result['episodes']);
    for (final section in _maps(result['section'])) {
      add(section['episodes']);
    }
    return episodes;
  }

  Future<DanmakuEpisode?> matchFile(
    DanmakuQuery query, {
    CancelToken? cancelToken,
  }) async {
    if (query.localPath == null || !dandanConfigured) return null;
    final file = await compute(_hashVideo, query.localPath!);
    if (file == null) return null;
    if (cancelToken?.isCancelled ?? false) throw cancelToken!.cancelError!;
    final json = await _dandan(
      '/api/v2/match',
      data: {
        'fileName': p.basenameWithoutExtension(query.fileName),
        'fileHash': file.$1,
        'fileSize': file.$2,
        'videoDuration': query.duration.inSeconds,
        'matchMode': 'hashOnly',
      },
      cancelToken: cancelToken,
    );
    final matches = _maps(json['matches']);
    if (json['isMatched'] != true || matches.length != 1) return null;
    final match = matches.single;
    return DanmakuEpisode(
      source: DanmakuSource.dandanplay,
      id: '${match['episodeId']}',
      title: '${match['animeTitle']}',
      episodeTitle: '${match['episodeTitle']}',
      shiftSeconds: (match['shift'] as num?)?.toDouble() ?? 0,
    );
  }

  Future<List<DanmakuComment>> comments(
    DanmakuEpisode episode, {
    CancelToken? cancelToken,
  }) async {
    final key = 'danmaku:v1:${episode.cacheKey}';
    String? cached;
    try {
      cached = await store.readCache(key);
    } catch (_) {
      /* 缓存不可用时仍可在线加载。 */
    }
    String body;
    if (cached != null) {
      body = cached;
    } else {
      try {
        if (episode.source == DanmakuSource.dandanplay) {
          body = jsonEncode(
            await _dandan(
              '/api/v2/comment/${episode.id}',
              query: {'withRelated': true},
              cancelToken: cancelToken,
            ),
          );
        } else {
          final response = await _dio.get<String>(
            'https://comment.bilibili.com/${episode.id}.xml',
            cancelToken: cancelToken,
            options: Options(
              responseType: ResponseType.plain,
              headers: {
                'User-Agent': 'Mozilla/5.0',
                'Referer': 'https://www.bilibili.com/',
              },
              followRedirects: false,
            ),
          );
          body = response.data ?? '';
        }
      } catch (_) {
        if (cancelToken?.isCancelled ?? false) throw cancelToken!.cancelError!;
        String? stale;
        try {
          stale = await store.readCache(key, stale: true);
        } catch (_) {
          /* 保留原始网络失败。 */
        }
        if (stale == null) rethrow;
        body = stale;
      }
      final parsed = await compute(parseDanmakuBody, (episode.source, body));
      try {
        await store.writeCache(key, body);
      } catch (_) {
        /* 缓存失败不影响播放弹幕。 */
      }
      return parsed;
    }
    return compute(parseDanmakuBody, (episode.source, body));
  }
}

List<Map<String, dynamic>> _maps(Object? value) =>
    value is List ? value.whereType<Map<String, dynamic>>().toList() : [];
String _plain(String value) => value
    .replaceAll(RegExp('<[^>]*>'), '')
    .replaceAll('&amp;', '&')
    .replaceAll('&quot;', '"');

Future<(String, int)?> _hashVideo(String path) async {
  try {
    final file = await File(path).open();
    try {
      final length = await file.length();
      return (
        md5.convert(await file.read(16 * 1024 * 1024)).toString(),
        length,
      );
    } finally {
      await file.close();
    }
  } on FileSystemException {
    return null;
  }
}

List<DanmakuComment> parseDanmakuBody((DanmakuSource, String) input) {
  final comments = <DanmakuComment>[];
  void add(String properties, String text, bool bilibili) {
    final fields = properties.split(',');
    if (fields.length < (bilibili ? 4 : 3)) return;
    final time = double.tryParse(fields[0]);
    final mode = int.tryParse(fields[1]);
    final color = int.tryParse(fields[bilibili ? 3 : 2]);
    if (time == null ||
        !time.isFinite ||
        time < 0 ||
        mode == null ||
        ![1, 4, 5].contains(mode) ||
        color == null ||
        text.trim().isEmpty) {
      return;
    }
    comments.add(
      DanmakuComment(
        timeMs: (time * 1000).round(),
        text: text,
        mode: mode,
        color: color & 0xffffff,
        bilibili:
            bilibili ||
            (fields.length > 3 && fields[3].toLowerCase().contains('bilibili')),
      ),
    );
  }

  if (input.$1 == DanmakuSource.bilibili) {
    for (final element in XmlDocument.parse(input.$2).findAllElements('d')) {
      add(element.getAttribute('p') ?? '', element.innerText, true);
    }
  } else {
    final json = jsonDecode(input.$2) as Map<String, dynamic>;
    for (final comment in _maps(json['comments'])) {
      if (comment['p'] is String && comment['m'] is String) {
        add(comment['p'] as String, comment['m'] as String, false);
      }
    }
  }
  comments.sort((a, b) => a.timeMs.compareTo(b.timeMs));
  return comments;
}
