import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';

import '../domain/source_models.dart';

/// 远程媒体源 HTTP 客户端
///
/// 遵循 M5 安全传输规范：
/// - 严格校验 HTTP/HTTPS 协议、非空 Host 与无明文 userInfo 凭据；
/// - 有界重定向（上限 5 次）；
/// - 严禁从 HTTPS 降级为 HTTP 重定向；
/// - 跨源重定向剥离 Authorization 等敏感认证头；
/// - 拒绝跨源携带请求体或写操作重定向；
/// - PROPFIND/同源 307/308 保留原始方法与请求体（满足 WebDAV 等语义，仅 POST 在 301/302 转 GET）；
/// - 流式错误响应立即关闭流，绝不耗尽大文件下载；
/// - 映射安全的 [MediaSourceException]，严禁在异常中回显原始异常信息、URL 或未经脱敏的内容。
class RemoteHttpClient {
  RemoteHttpClient({Dio? dio})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              connectTimeout: const Duration(seconds: 15),
              receiveTimeout: const Duration(seconds: 30),
              sendTimeout: const Duration(seconds: 30),
              followRedirects: false,
              validateStatus: (_) => true,
            ),
          );

  final Dio _dio;

  static const int _maxRedirects = 5;

  /// 发起 HTTP 请求
  ///
  /// [allowedStatusCodes] 允许指定非 2xx/207 的特定状态码（如 416）正常返回而不抛出异常。
  Future<Response<dynamic>> request(
    Uri uri, {
    String method = 'GET',
    Map<String, String> headers = const {},
    Object? data,
    ResponseType responseType = ResponseType.json,
    CancelToken? cancelToken,
    Set<int> allowedStatusCodes = const {},
  }) async {
    _validateUri(uri);

    Uri currentUri = uri;
    String currentMethod = method.toUpperCase();
    final currentHeaders = Map<String, String>.from(headers);
    Object? currentData = data;
    int redirectCount = 0;

    while (true) {
      final options = Options(
        method: currentMethod,
        headers: currentHeaders,
        responseType: responseType,
        followRedirects: false,
        validateStatus: (_) => true,
      );

      final Response<dynamic> response;
      try {
        response = await _dio.requestUri<dynamic>(
          currentUri,
          data: currentData,
          options: options,
          cancelToken: cancelToken,
        );
      } on DioException catch (e) {
        _closeResponseBody(e.response?.data);
        throw _mapDioException(e);
      } catch (e) {
        if (e is MediaSourceException) rethrow;
        throw const MediaSourceException(
          '网络请求发生异常，请检查网络连接',
          code: 'network_error',
        );
      }

      final statusCode = response.statusCode ?? 0;

      // 检查是否为 3xx 重定向
      final isRedirectCode =
          statusCode == HttpStatus.movedPermanently ||
          statusCode == HttpStatus.found ||
          statusCode == HttpStatus.seeOther ||
          statusCode == HttpStatus.temporaryRedirect ||
          statusCode == HttpStatus.permanentRedirect;

      final locationHeader =
          response.headers.value(HttpHeaders.locationHeader) ??
          response.headers.value('location');

      if (isRedirectCode &&
          locationHeader != null &&
          locationHeader.trim().isNotEmpty) {
        try {
          redirectCount++;
          if (redirectCount > _maxRedirects) {
            throw const MediaSourceException(
              '重定向次数过多，已终止请求',
              code: 'too_many_redirects',
            );
          }

          final nextUri = currentUri.resolve(locationHeader.trim());
          _validateUri(nextUri);

          // 拒绝 HTTPS 降级为 HTTP
          if (currentUri.isScheme('https') && !nextUri.isScheme('https')) {
            throw const MediaSourceException(
              '拒绝从 HTTPS 降级为 HTTP 重定向',
              code: 'tls_downgrade_rejected',
            );
          }

          final isSameOrigin =
              currentUri.scheme.toLowerCase() == nextUri.scheme.toLowerCase() &&
              currentUri.host.toLowerCase() == nextUri.host.toLowerCase() &&
              currentUri.port == nextUri.port;

          // 跨源重定向拒绝携带请求体或非 GET/HEAD 语义
          if (!isSameOrigin &&
              (currentData != null ||
                  (currentMethod != 'GET' && currentMethod != 'HEAD'))) {
            throw const MediaSourceException(
              '跨源重定向拒绝携带请求体或写操作',
              code: 'cross_origin_redirect_rejected',
            );
          }

          // 跨源剥离凭据与认证头
          if (!isSameOrigin) {
            currentHeaders.removeWhere((k, _) {
              final lower = k.toLowerCase();
              return lower == 'authorization' ||
                  lower == 'cookie' ||
                  lower == 'proxy-authorization';
            });
          }

          // 重定向方法与数据调整
          if (statusCode == HttpStatus.seeOther) {
            currentMethod = 'GET';
            currentData = null;
            currentHeaders.removeWhere((k, _) {
              final lower = k.toLowerCase();
              return lower == 'content-length' || lower == 'content-type';
            });
          } else if (statusCode == HttpStatus.movedPermanently ||
              statusCode == HttpStatus.found) {
            // RFC 仅针对 POST 在 301/302 转 GET；PROPFIND 等 WebDAV/自定义方法同源保留
            if (currentMethod == 'POST') {
              currentMethod = 'GET';
              currentData = null;
              currentHeaders.removeWhere((k, _) {
                final lower = k.toLowerCase();
                return lower == 'content-length' || lower == 'content-type';
              });
            }
          }
          // 307 / 308 及非 POST 301/302 保留 currentMethod 与 currentData

          currentUri = nextUri;
        } finally {
          _closeResponseBody(response.data);
        }
        continue;
      }

      // 非重定向，校验响应状态
      final isSuccess =
          (statusCode >= 200 && statusCode < 300) ||
          statusCode == 207 ||
          allowedStatusCodes.contains(statusCode);

      if (isSuccess) {
        return response;
      }

      // 错误响应，安全关闭流式数据，绝不耗尽大文件
      _closeResponseBody(response.data);

      switch (statusCode) {
        case HttpStatus.unauthorized:
          throw const MediaSourceException(
            '访问媒体源认证失败，凭据无效',
            code: 'unauthorized',
          );
        case HttpStatus.forbidden:
          throw const MediaSourceException(
            '无权访问该资源 (403 Forbidden)',
            code: 'forbidden',
          );
        case HttpStatus.notFound:
          throw const MediaSourceException(
            '请求的文件或资源不存在 (404)',
            code: 'file_missing',
          );
        case HttpStatus.requestedRangeNotSatisfiable:
          throw const MediaSourceException(
            '请求范围超出文件大小 (416)',
            code: 'range_not_satisfiable',
          );
        case HttpStatus.tooManyRequests:
          throw const MediaSourceException(
            '请求过于频繁，已被限流 (429)',
            code: 'rate_limited',
          );
        default:
          throw MediaSourceException(
            'HTTP 请求失败: 状态码 $statusCode',
            code: 'http_error',
          );
      }
    }
  }

  /// 关闭底层 HTTP 连接池与资源
  void close({bool force = false}) {
    _dio.close(force: force);
  }

  static void _validateUri(Uri u) {
    final scheme = u.scheme.toLowerCase();
    if (scheme != 'http' && scheme != 'https') {
      throw const MediaSourceException(
        '不支持的媒体源网络协议，仅支持 HTTP 或 HTTPS',
        code: 'invalid_uri_scheme',
      );
    }
    if (u.host.isEmpty) {
      throw const MediaSourceException(
        '媒体源网络地址无效，缺少主机信息',
        code: 'invalid_uri_host',
      );
    }
    if (u.userInfo.isNotEmpty) {
      throw const MediaSourceException(
        '媒体源网络地址不安全，严禁携带明文用户凭据',
        code: 'invalid_uri_userinfo',
      );
    }
  }

  static void _closeResponseBody(dynamic data) {
    if (data is ResponseBody) {
      try {
        data.stream.listen(null).cancel();
      } catch (_) {}
    }
  }

  static MediaSourceException _mapDioException(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.transformTimeout:
        return const MediaSourceException(
          '网络连接超时，请检查网络设置',
          code: 'network_timeout',
        );
      case DioExceptionType.cancel:
        return const MediaSourceException('网络请求已取消', code: 'cancelled');
      case DioExceptionType.badCertificate:
        return const MediaSourceException(
          'TLS 证书验证失败',
          code: 'tls_certificate_error',
        );
      case DioExceptionType.connectionError:
        final inner = e.error;
        if (inner is HandshakeException || inner is TlsException) {
          return const MediaSourceException(
            'TLS 握手失败，安全连接未建立',
            code: 'tls_handshake_error',
          );
        }
        return const MediaSourceException(
          '网络连接失败，请检查网络连接',
          code: 'network_timeout',
        );
      case DioExceptionType.badResponse:
        final status = e.response?.statusCode;
        return MediaSourceException('HTTP 响应错误: $status', code: 'http_error');
      case DioExceptionType.unknown:
        final inner = e.error;
        if (inner is SocketException) {
          return const MediaSourceException(
            '网络连接失败，请检查网络或媒体源地址',
            code: 'network_error',
          );
        }
        return const MediaSourceException('网络请求发生未知异常', code: 'network_error');
    }
  }
}
