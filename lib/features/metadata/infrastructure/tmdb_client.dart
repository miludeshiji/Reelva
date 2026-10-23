import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';

import '../../../core/logging/app_logger.dart';
import '../domain/tmdb_models.dart';
import 'tmdb_cache.dart';
import 'tmdb_token_store.dart';

/// TMDB 官方 HTTP 客户端
///
/// 封装 TMDB v3 API 交互，集成：
/// 1. Drift 本地元数据缓存（优先新鲜缓存，离线/无 Key 时回退陈旧缓存，缓存键绝不包含凭据）
/// 2. 请求串行化（默认 300ms 间隔）
/// 3. 429 Retry-After 有限次数重试与安全熔断
/// 4. 禁用重定向防止 Token 泄露
/// 5. 统一脱敏与安全异常映射
class TmdbClient {
  final Dio _dio;
  final TmdbTokenStore tokenStore;
  final TmdbCache? cache;
  final String _baseUrl;
  final Duration requestInterval;

  static const Duration _maxBoundedRetryWait = Duration(seconds: 10);
  DateTime _lastRequestTime = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _nextAllowedRequestTime = DateTime.fromMillisecondsSinceEpoch(0);
  Future<void> _queue = Future.value();
  TmdbClient({
    required this.tokenStore,
    this.cache,
    Dio? dio,
    String? baseUrl,
    this.requestInterval = const Duration(milliseconds: 300),
  }) : _dio = dio ?? Dio(),
       _baseUrl = baseUrl ?? 'https://api.themoviedb.org/3' {
    _dio.options.baseUrl = _baseUrl;
    _dio.options.connectTimeout = const Duration(seconds: 10);
    _dio.options.receiveTimeout = const Duration(seconds: 15);
    _dio.options.followRedirects = false;
    _dio.options.maxRedirects = 0;
  }

  /// 串行化请求调度器，保证相邻请求至少间隔 [_requestInterval]
  Future<T> _serialized<T>(Future<T> Function() action) {
    final completer = Completer<T>();
    _queue = _queue.then((_) async {
      try {
        final now = DateTime.now();
        // 必须等到满足 429 冷却允许时间
        if (now.isBefore(_nextAllowedRequestTime)) {
          await Future<void>.delayed(_nextAllowedRequestTime.difference(now));
        }
        final afterWaitNow = DateTime.now();
        final elapsed = afterWaitNow.difference(_lastRequestTime);
        if (elapsed < requestInterval) {
          await Future<void>.delayed(requestInterval - elapsed);
        }
        _lastRequestTime = DateTime.now();
        final result = await action();
        completer.complete(result);
      } catch (e, st) {
        completer.completeError(e, st);
      }
    });
    return completer.future;
  }

  /// 执行安全请求并自动管理缓存
  Future<Map<String, dynamic>> _fetchJson({
    required String path,
    required String cacheKey,
    required Duration ttl,
    Map<String, dynamic>? queryParameters,
    int max429Retries = 2,
  }) async {
    // 1. 检查本地缓存（优先新鲜缓存）
    final cached = await cache?.get(cacheKey);
    if (cached != null && !DateTime.now().isAfter(cached.expiresAt)) {
      try {
        final decoded = jsonDecode(cached.payloadJson);
        if (decoded is Map<String, dynamic>) {
          return decoded;
        }
      } catch (e) {
        AppLogger.instance.error(
          '解析本地元数据缓存失败: $cacheKey',
          error: e.runtimeType,
        );
      }
    }

    // 2. 检查凭据配置
    final token = await tokenStore.read();
    if (token == null || token.isEmpty) {
      // 无 Key 时如果存在陈旧缓存，允许安全回退
      if (cached != null) {
        try {
          final decoded = jsonDecode(cached.payloadJson);
          if (decoded is Map<String, dynamic>) {
            return decoded;
          }
        } catch (_) {}
      }
      throw const MetadataException('未配置 TMDB API 密钥，请在设置中配置', code: 'no_key');
    }

    // 3. 构建请求选项
    final qParams = Map<String, dynamic>.from(queryParameters ?? const {});
    final headers = <String, dynamic>{};

    if (TmdbTokenStore.isBearerToken(token)) {
      headers['Authorization'] = 'Bearer $token';
    } else {
      qParams['api_key'] = token;
    }

    // 4. 发送网络请求（包含串行调度与 429 智能重试）
    int attempts = 0;
    while (true) {
      attempts++;
      try {
        final response = await _serialized(
          () => _dio.get<Map<String, dynamic>>(
            path,
            queryParameters: qParams,
            options: Options(headers: headers),
          ),
        );

        final data = response.data ?? const <String, dynamic>{};

        // 成功获取后写入缓存（绝不含 token）
        try {
          await cache?.put(
            key: cacheKey,
            payloadJson: jsonEncode(data),
            ttl: ttl,
          );
        } catch (e) {
          AppLogger.instance.error(
            '保存元数据至缓存异常: $cacheKey',
            error: e.runtimeType,
          );
        }

        return data;
      } on DioException catch (dioErr) {
        final statusCode = dioErr.response?.statusCode;

        // 429 Rate Limit 处理：更新共享允许时间，有界范围内重试，超限绝不过早重试
        if (statusCode == 429) {
          int waitSeconds = 2;
          final retryAfterHeader = dioErr.response?.headers.value(
            'retry-after',
          );
          if (retryAfterHeader != null) {
            final parsed = int.tryParse(retryAfterHeader);
            if (parsed != null && parsed > 0) {
              waitSeconds = parsed;
            }
          }
          final waitDuration = Duration(seconds: waitSeconds);
          final now = DateTime.now();
          final targetNextTime = now.add(waitDuration);
          if (targetNextTime.isAfter(_nextAllowedRequestTime)) {
            _nextAllowedRequestTime = targetNextTime;
          }

          // 超过有界等待阈值（如 10 秒）绝不能过早重试，直接抛出 rate_limit
          if (waitDuration > _maxBoundedRetryWait || attempts > max429Retries) {
            throw MetadataException(
              'TMDB 请求速率受限 (429)，重试冷却时间过长: ${waitSeconds}s',
              code: 'rate_limit',
            );
          }

          // 在允许的有界等待范围内，下次循环调用 _serialized 会在 _nextAllowedRequestTime 之后执行
          continue;
        }

        // 离线/网络故障回退陈旧缓存
        if (dioErr.type == DioExceptionType.connectionError ||
            dioErr.type == DioExceptionType.connectionTimeout ||
            dioErr.type == DioExceptionType.receiveTimeout ||
            dioErr.type == DioExceptionType.sendTimeout ||
            statusCode == 503) {
          if (cached != null) {
            try {
              final decoded = jsonDecode(cached.payloadJson);
              if (decoded is Map<String, dynamic>) {
                return decoded;
              }
            } catch (_) {}
          }
          throw const MetadataException('网络连接超时或不可用，且无可用本地缓存', code: 'offline');
        }

        if (statusCode == 401 || statusCode == 403) {
          throw const MetadataException(
            'TMDB API 密钥无效或未授权 (401/403)，请在设置中检查',
            code: 'unauthorized',
          );
        }

        if (statusCode == 429) {
          throw const MetadataException(
            'TMDB 请求速率受限 (429)，请稍后重试',
            code: 'rate_limit',
          );
        }

        if (statusCode == 404) {
          if (cached != null) {
            try {
              final decoded = jsonDecode(cached.payloadJson);
              if (decoded is Map<String, dynamic>) {
                return decoded;
              }
            } catch (_) {}
          }
          throw const MetadataException('未找到对应条目 (404)', code: 'not_found');
        }

        // 其他未知网络错误尝试回退缓存
        if (cached != null) {
          try {
            final decoded = jsonDecode(cached.payloadJson);
            if (decoded is Map<String, dynamic>) {
              return decoded;
            }
          } catch (_) {}
        }

        throw MetadataException(
          'TMDB 网络请求失败: ${dioErr.type}',
          code: 'network_error',
        );
      } catch (e) {
        if (e is MetadataException) rethrow;

        if (cached != null) {
          try {
            final decoded = jsonDecode(cached.payloadJson);
            if (decoded is Map<String, dynamic>) {
              return decoded;
            }
          } catch (_) {}
        }

        throw MetadataException(
          'TMDB 处理异常: ${e.runtimeType}',
          code: 'network_error',
        );
      }
    }
  }

  /// 搜索电影
  Future<List<TmdbWork>> searchMovie(
    String query, {
    int? year,
    int page = 1,
    String language = 'zh-CN',
  }) async {
    final cleanQuery = query.trim();
    if (cleanQuery.isEmpty) return const [];

    final cacheKey = 'search:movie:$language:$cleanQuery:${year ?? ''}:$page';
    final qParams = <String, dynamic>{
      'query': cleanQuery,
      'language': language,
      'page': page,
      'year': ?year,
    };

    final json = await _fetchJson(
      path: '/search/movie',
      cacheKey: cacheKey,
      ttl: const Duration(days: 7),
      queryParameters: qParams,
    );

    final results = json['results'];
    if (results is! List) return const [];

    return results
        .whereType<Map<String, dynamic>>()
        .map((e) => TmdbWork.fromJson(e, typeOverride: 'movie'))
        .toList();
  }

  /// 搜索电视剧 / 剧集
  Future<List<TmdbWork>> searchTv(
    String query, {
    int? year,
    int page = 1,
    String language = 'zh-CN',
  }) async {
    final cleanQuery = query.trim();
    if (cleanQuery.isEmpty) return const [];

    final cacheKey = 'search:tv:$language:$cleanQuery:${year ?? ''}:$page';
    final qParams = <String, dynamic>{
      'query': cleanQuery,
      'language': language,
      'page': page,
      'first_air_date_year': ?year,
    };

    final json = await _fetchJson(
      path: '/search/tv',
      cacheKey: cacheKey,
      ttl: const Duration(days: 7),
      queryParameters: qParams,
    );

    final results = json['results'];
    if (results is! List) return const [];

    return results
        .whereType<Map<String, dynamic>>()
        .map((e) => TmdbWork.fromJson(e, typeOverride: 'series'))
        .toList();
  }

  /// 获取电影详情（附加 alternative_titles 别名）
  Future<TmdbWork> getMovieDetails(int id, {String language = 'zh-CN'}) async {
    final cacheKey = 'details:movie:$language:$id';
    final qParams = <String, dynamic>{
      'language': language,
      'append_to_response': 'alternative_titles',
    };

    final json = await _fetchJson(
      path: '/movie/$id',
      cacheKey: cacheKey,
      ttl: const Duration(days: 14),
      queryParameters: qParams,
    );

    final aliases = <String>[];
    final altTitles = json['alternative_titles'];
    if (altTitles is Map<String, dynamic>) {
      final list = altTitles['titles'];
      if (list is List) {
        for (final item in list) {
          if (item is Map<String, dynamic> && item['title'] != null) {
            final t = item['title'].toString().trim();
            if (t.isNotEmpty && !aliases.contains(t)) {
              aliases.add(t);
            }
          }
        }
      }
    }

    final work = TmdbWork.fromJson(json, typeOverride: 'movie');
    return work.copyWith(aliases: aliases);
  }

  /// 获取电视剧详情（附加 alternative_titles 别名）
  Future<TmdbWork> getTvDetails(int id, {String language = 'zh-CN'}) async {
    final cacheKey = 'details:tv:$language:$id';
    final qParams = <String, dynamic>{
      'language': language,
      'append_to_response': 'alternative_titles',
    };

    final json = await _fetchJson(
      path: '/tv/$id',
      cacheKey: cacheKey,
      ttl: const Duration(days: 14),
      queryParameters: qParams,
    );

    final aliases = <String>[];
    final altTitles = json['alternative_titles'];
    if (altTitles is Map<String, dynamic>) {
      final list = altTitles['results'];
      if (list is List) {
        for (final item in list) {
          if (item is Map<String, dynamic> && item['title'] != null) {
            final t = item['title'].toString().trim();
            if (t.isNotEmpty && !aliases.contains(t)) {
              aliases.add(t);
            }
          }
        }
      }
    }

    final work = TmdbWork.fromJson(json, typeOverride: 'series');
    return work.copyWith(aliases: aliases);
  }

  /// 获取电视剧某季的所有分集列表
  Future<List<TmdbEpisode>> getTvSeasonEpisodes(
    int tvId,
    int seasonNumber, {
    String language = 'zh-CN',
  }) async {
    final cacheKey = 'tv:season:$language:$tvId:$seasonNumber';
    final qParams = <String, dynamic>{'language': language};

    final json = await _fetchJson(
      path: '/tv/$tvId/season/$seasonNumber',
      cacheKey: cacheKey,
      ttl: const Duration(days: 14),
      queryParameters: qParams,
    );

    final episodes = json['episodes'];
    if (episodes is! List) return const [];

    return episodes
        .whereType<Map<String, dynamic>>()
        .map((e) => TmdbEpisode.fromJson(e))
        .toList();
  }

  /// 释放底层 HTTP 客户端资源
  void dispose() {
    _dio.close();
  }
}
