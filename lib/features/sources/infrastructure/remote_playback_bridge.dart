import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../../player/domain/playback_resource.dart';
import '../domain/source_models.dart';
import 'remote_http_client.dart';

/// 远程播放目标描述
@immutable
class RemotePlaybackTarget {
  const RemotePlaybackTarget({
    required this.uri,
    this.headers = const {},
    this.expiresAt,
  });

  final Uri uri;
  final Map<String, String> headers;
  final DateTime? expiresAt;

  bool get isExpired => expiresAt != null && DateTime.now().isAfter(expiresAt!);
}

/// 远程字节流读取器抽象接口（供 SMB 或非 HTTP 远程协议使用）
abstract interface class RemoteByteReader {
  /// 总字节长度（未知则为 null）
  int? get length;

  /// 是否支持 Byte Range 分段随机读取
  bool get supportsRanges;

  /// 读取指定范围字节流
  ///
  /// [start] 为起始字节偏移量（含）；
  /// [endExclusive] 为结束字节偏移量（不含），为 null 时读至末尾。
  Stream<List<int>> read(int start, int? endExclusive);

  /// 关闭读取器并释放底层网络或连接句柄
  Future<void> close();
}

/// 远程媒体播放桥接器
///
/// 遵循 M5 规范：
/// - 仅绑定 IPv4 回环地址 (127.0.0.1)；
/// - 为每个播放会话分配不透明、随机的不重复路由路径（使用 Uri pathSegments 构造以完整保留 #, % 等特殊字符）；
/// - 探测 upstream Range (bytes=0-0) 支持能力并严格校验 206 Content-Range (bytes 0-0/positiveTotal) 与 Content-Length 1；
/// - 416 仅在 bytes */0 空文件时有效，其余情况视为探测异常；
/// - 绝不凭 Accept-Ranges 单独断定 seekability；
/// - 分段 GET 强制校验 206 与 Content-Range (start, end, total) 完整匹配；若服务器忽略 Range 返回 200 则明确拒绝为 not_seekable，严禁当作成功跳转；
/// - 严格校验 206 响应的 Content-Length 等于预期 (end - start + 1)，严禁盲目转发错误/未经验证的 Content-Length；
/// - 有界反压管道流式转发，对有限读取进行完整性校验，若流意外中断截断或超长则安全发出错误通知；
/// - 在解析器 (resolve) 调用前预先分配并追踪 CancelToken，与 release 竞争以防挂起在异步凭据读取；
/// - 监听 HttpResponse.done，播放器断开连接时立即主动取消停滞的上游连接；
/// - 在所有错误与提前返回路径上安全关闭上游响应流，彻底杜绝连接与带宽泄漏；
/// - 目标过期或返回 401/403 时单次刷新解析器并重试；
/// - 强制 Accept-Encoding: identity，拒绝压缩分段；
/// - 错误流仅广播经过脱敏的常量安全文本，严禁泄漏原始系统异常、内部 URL 或明文内容。
class RemotePlaybackBridge {
  RemotePlaybackBridge({RemoteHttpClient? http})
    : _http = http ?? RemoteHttpClient();

  final RemoteHttpClient _http;

  /// 基于动态目标解析器打开远程 HTTP 播放资源
  Future<PlaybackResource> open({
    required String displayName,
    required Future<RemotePlaybackTarget> Function({
      required bool refresh,
      CancelToken? cancelToken,
    })
    resolve,
  }) async {
    try {
      final initialProbeToken = CancelToken();
      final _ProbeResult probeResult;
      try {
        var target = await resolve(
          refresh: false,
          cancelToken: initialProbeToken,
        );
        if (target.isExpired) {
          target = await resolve(refresh: true, cancelToken: initialProbeToken);
        }

        // 1. 严格探测 Range: bytes=0-0
        probeResult = await _probeTarget(target, resolve, initialProbeToken);
      } finally {
        initialProbeToken.cancel();
      }

      final validatedTarget = probeResult.target;
      final supportsRanges = probeResult.supportsRanges;
      final totalLength = probeResult.totalLength;

      // 2. 绑定 IPv4 回环服务
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final sessionId = _generateSessionToken();
      final safeName = _sanitizeFilename(displayName);

      // 使用 Uri(pathSegments: ...) 构造，完整支持包含 #, %, 空格等特殊字符的名称
      final loopbackUri = Uri(
        scheme: 'http',
        host: '127.0.0.1',
        port: server.port,
        pathSegments: [sessionId, safeName],
      );

      final errorsController = StreamController<String>.broadcast();
      final activeTokens = <CancelToken>{};
      final activeHandlers = <Future<void>>{};
      var currentTarget = validatedTarget;
      bool isClosed = false;

      void safeAddError(String message) {
        if (!isClosed && !errorsController.isClosed) {
          try {
            errorsController.add(message);
          } catch (_) {}
        }
      }

      Future<void> handleRequest(HttpRequest request) async {
        if (isClosed) {
          try {
            await request.response.close();
          } catch (_) {}
          return;
        }

        // 校验路径段中的 session 标识符
        if (request.uri.pathSegments.isEmpty ||
            request.uri.pathSegments[0] != sessionId) {
          request.response.statusCode = HttpStatus.notFound;
          await request.response.close();
          return;
        }

        if (request.method != 'GET' && request.method != 'HEAD') {
          request.response.statusCode = HttpStatus.methodNotAllowed;
          await request.response.close();
          return;
        }

        final rangeHeader = request.headers.value(HttpHeaders.rangeHeader);
        final parsed = _parseRange(rangeHeader, totalLength);

        if (parsed.isInvalid) {
          request.response.statusCode = HttpStatus.requestedRangeNotSatisfiable;
          if (totalLength != null) {
            request.response.headers.set(
              HttpHeaders.contentRangeHeader,
              'bytes */$totalLength',
            );
          }
          await request.response.close();
          return;
        }

        if (parsed.start > 0 && !supportsRanges) {
          safeAddError('远程媒体源不支持跳转播放 (not_seekable)');
          request.response.statusCode = HttpStatus.requestedRangeNotSatisfiable;
          await request.response.close();
          return;
        }

        if (request.method == 'HEAD') {
          request.response.statusCode = HttpStatus.ok;
          request.response.headers.set(
            HttpHeaders.acceptRangesHeader,
            supportsRanges ? 'bytes' : 'none',
          );
          if (totalLength != null) {
            request.response.headers.set(
              HttpHeaders.contentLengthHeader,
              totalLength,
            );
          }
          request.response.headers.set(
            HttpHeaders.contentTypeHeader,
            'video/mp4',
          );
          await request.response.close();
          return;
        }

        // GET 请求：在任何解析/请求之前预分配并登记 cancelToken
        final cancelToken = CancelToken();
        if (isClosed) {
          cancelToken.cancel();
          try {
            await request.response.close();
          } catch (_) {}
          return;
        }

        activeTokens.add(cancelToken);

        // 显式监听客户端断开，prompt 取消停滞的上游连接
        request.response.done.then(
          (_) {
            cancelToken.cancel();
          },
          onError: (_) {
            cancelToken.cancel();
          },
        );

        try {
          if (currentTarget.isExpired) {
            try {
              currentTarget = await _raceResolve(
                resolve: resolve,
                refresh: true,
                cancelToken: cancelToken,
                isClosedCheck: () => isClosed,
              );
            } catch (_) {
              if (!isClosed && !cancelToken.isCancelled) {
                safeAddError('刷新媒体播放凭据失败');
                request.response.statusCode = HttpStatus.badGateway;
                try {
                  await request.response.close();
                } catch (_) {}
              }
              return;
            }
          }

          if (isClosed || cancelToken.isCancelled) {
            try {
              await request.response.close();
            } catch (_) {}
            return;
          }

          final upstreamHeaders = Map<String, String>.from(
            currentTarget.headers,
          );
          upstreamHeaders['Accept-Encoding'] = 'identity';
          if (parsed.isRange) {
            upstreamHeaders['Range'] = parsed.end != null
                ? 'bytes=${parsed.start}-${parsed.end}'
                : 'bytes=${parsed.start}-';
          }

          Response<dynamic> response;
          try {
            response = await _http.request(
              currentTarget.uri,
              method: 'GET',
              headers: upstreamHeaders,
              responseType: ResponseType.stream,
              cancelToken: cancelToken,
              allowedStatusCodes: const {
                HttpStatus.requestedRangeNotSatisfiable,
              },
            );
          } on MediaSourceException catch (e) {
            if (e.code == 'unauthorized' || e.code == 'forbidden') {
              if (isClosed || cancelToken.isCancelled) {
                try {
                  await request.response.close();
                } catch (_) {}
                return;
              }
              // 凭据过期或被拒，尝试单次刷新
              currentTarget = await _raceResolve(
                resolve: resolve,
                refresh: true,
                cancelToken: cancelToken,
                isClosedCheck: () => isClosed,
              );
              if (isClosed || cancelToken.isCancelled) {
                try {
                  await request.response.close();
                } catch (_) {}
                return;
              }
              final retryHeaders = Map<String, String>.from(
                currentTarget.headers,
              );
              retryHeaders['Accept-Encoding'] = 'identity';
              if (parsed.isRange) {
                retryHeaders['Range'] = parsed.end != null
                    ? 'bytes=${parsed.start}-${parsed.end}'
                    : 'bytes=${parsed.start}-';
              }
              response = await _http.request(
                currentTarget.uri,
                method: 'GET',
                headers: retryHeaders,
                responseType: ResponseType.stream,
                cancelToken: cancelToken,
                allowedStatusCodes: const {
                  HttpStatus.requestedRangeNotSatisfiable,
                },
              );
            } else {
              rethrow;
            }
          }

          if (isClosed || cancelToken.isCancelled) {
            _closeResponseBody(response.data);
            try {
              await request.response.close();
            } catch (_) {}
            return;
          }

          final statusCode = response.statusCode ?? HttpStatus.badGateway;

          if (statusCode == HttpStatus.requestedRangeNotSatisfiable) {
            _closeResponseBody(response.data);
            request.response.statusCode =
                HttpStatus.requestedRangeNotSatisfiable;
            await request.response.close();
            return;
          }

          // 如果请求了 Range 且 start > 0，但上游忽略并返回 200，严禁转发作为成功 seek，必须明确失败
          if (parsed.isRange &&
              parsed.start > 0 &&
              statusCode == HttpStatus.ok) {
            _closeResponseBody(response.data);
            safeAddError('远程媒体源不支持跳转播放 (not_seekable)');
            request.response.statusCode =
                HttpStatus.requestedRangeNotSatisfiable;
            await request.response.close();
            return;
          }

          if (statusCode != HttpStatus.ok &&
              statusCode != HttpStatus.partialContent) {
            _closeResponseBody(response.data);
            request.response.statusCode = statusCode;
            await request.response.close();
            return;
          }

          final expectedChunkLength =
              statusCode == HttpStatus.partialContent && parsed.end != null
              ? (parsed.end! - parsed.start + 1)
              : null;

          // 严格校验 206 响应的 Content-Range (start, end, total 完整校验)
          if (statusCode == HttpStatus.partialContent) {
            final cr = response.headers.value(HttpHeaders.contentRangeHeader);
            if (cr == null ||
                !_matchesRequestedRange(
                  cr,
                  parsed.start,
                  parsed.end,
                  totalLength,
                )) {
              _closeResponseBody(response.data);
              safeAddError('远程媒体分段范围不匹配');
              request.response.statusCode = HttpStatus.badGateway;
              await request.response.close();
              return;
            }

            // 严格校验 Content-Length（若存在）等于预期的 (end - start + 1)
            final cl = response.headers.value(HttpHeaders.contentLengthHeader);
            if (cl != null && expectedChunkLength != null) {
              final parsedCl = int.tryParse(cl.trim());
              if (parsedCl != expectedChunkLength) {
                _closeResponseBody(response.data);
                safeAddError('远程媒体分段长度不匹配');
                request.response.statusCode = HttpStatus.badGateway;
                await request.response.close();
                return;
              }
            }
          }

          final contentEncoding = response.headers.value(
            HttpHeaders.contentEncodingHeader,
          );
          if (contentEncoding != null && contentEncoding != 'identity') {
            _closeResponseBody(response.data);
            safeAddError('服务器返回了压缩的媒体分段，无法保证精确定位');
            request.response.statusCode = HttpStatus.badGateway;
            await request.response.close();
            return;
          }

          request.response.statusCode = statusCode;
          request.response.headers.set(
            HttpHeaders.acceptRangesHeader,
            supportsRanges ? 'bytes' : 'none',
          );
          final ct = response.headers.value(HttpHeaders.contentTypeHeader);
          if (ct != null) {
            request.response.headers.set(HttpHeaders.contentTypeHeader, ct);
          }
          final cr = response.headers.value(HttpHeaders.contentRangeHeader);
          if (cr != null) {
            request.response.headers.set(HttpHeaders.contentRangeHeader, cr);
          }

          // 设置经验证的明确长度，避免复制上游任意错误头
          if (expectedChunkLength != null) {
            request.response.headers.set(
              HttpHeaders.contentLengthHeader,
              expectedChunkLength,
            );
          } else {
            final cl = response.headers.value(HttpHeaders.contentLengthHeader);
            if (cl != null) {
              request.response.headers.set(
                HttpHeaders.contentLengthHeader,
                cl.trim(),
              );
            }
          }

          final bodyStream = (response.data as ResponseBody).stream;
          int pipedBytes = 0;
          try {
            await for (final chunk in bodyStream) {
              if (cancelToken.isCancelled || isClosed) break;
              pipedBytes += chunk.length;
              if (expectedChunkLength != null &&
                  pipedBytes > expectedChunkLength) {
                cancelToken.cancel();
                safeAddError('远程媒体分段流超长');
                break;
              }
              request.response.add(chunk);
              await request.response.flush();
            }

            if (!cancelToken.isCancelled &&
                !isClosed &&
                expectedChunkLength != null) {
              if (pipedBytes < expectedChunkLength) {
                safeAddError('远程媒体流传输中断，数据未完整接收');
              }
            }
          } catch (_) {
            cancelToken.cancel();
          } finally {
            try {
              await request.response.close();
            } catch (_) {}
          }
        } catch (_) {
          if (!cancelToken.isCancelled && !isClosed) {
            safeAddError('网络媒体流传输异常，请检查连接');
            try {
              request.response.statusCode = HttpStatus.badGateway;
              await request.response.close();
            } catch (_) {}
          }
        } finally {
          activeTokens.remove(cancelToken);
        }
      }

      final sub = server.listen((HttpRequest request) {
        final handlerFuture = handleRequest(request);
        activeHandlers.add(handlerFuture);
        handlerFuture.whenComplete(() => activeHandlers.remove(handlerFuture));
      });

      Future<void> releaseLease() async {
        if (isClosed) return;
        isClosed = true;
        for (final token in activeTokens) {
          token.cancel();
        }
        activeTokens.clear();
        await sub.cancel();
        await server.close(force: true);
        if (activeHandlers.isNotEmpty) {
          await Future.wait(
            activeHandlers.toList(),
          ).catchError((_) => <void>[]);
        }
        if (!errorsController.isClosed) {
          await errorsController.close();
        }
      }

      // 具体租约不携带 prepare（避免已关闭/特定租约被重新执行，逻辑描述符才拥有 prepare）
      return PlaybackResource(
        uri: loopbackUri,
        displayName: displayName,
        release: releaseLease,
        errors: errorsController.stream,
      );
    } on PlaybackResourceException {
      rethrow;
    } on MediaSourceException catch (e) {
      throw PlaybackResourceException(e.message, code: e.code);
    } catch (_) {
      throw const PlaybackResourceException('准备远程媒体资源失败，请检查网络或凭据');
    }
  }

  /// 基于字节流读取器打开远程播放资源（用于 SMB 等自定义协议）
  Future<PlaybackResource> openReader({
    required String displayName,
    required RemoteByteReader reader,
  }) async {
    try {
      final totalLength = reader.length;
      final supportsRanges = reader.supportsRanges;

      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final sessionId = _generateSessionToken();
      final safeName = _sanitizeFilename(displayName);

      final loopbackUri = Uri(
        scheme: 'http',
        host: '127.0.0.1',
        port: server.port,
        pathSegments: [sessionId, safeName],
      );

      final errorsController = StreamController<String>.broadcast();
      final activeReaderHandlers = <Future<void>>{};
      bool isClosed = false;

      void safeAddError(String message) {
        if (!isClosed && !errorsController.isClosed) {
          try {
            errorsController.add(message);
          } catch (_) {}
        }
      }

      Future<void> handleReaderRequest(HttpRequest request) async {
        if (isClosed) {
          try {
            await request.response.close();
          } catch (_) {}
          return;
        }

        if (request.uri.pathSegments.isEmpty ||
            request.uri.pathSegments[0] != sessionId) {
          request.response.statusCode = HttpStatus.notFound;
          await request.response.close();
          return;
        }

        if (request.method != 'GET' && request.method != 'HEAD') {
          request.response.statusCode = HttpStatus.methodNotAllowed;
          await request.response.close();
          return;
        }

        final rangeHeader = request.headers.value(HttpHeaders.rangeHeader);
        final parsed = _parseRange(rangeHeader, totalLength);

        if (parsed.isInvalid) {
          request.response.statusCode = HttpStatus.requestedRangeNotSatisfiable;
          if (totalLength != null) {
            request.response.headers.set(
              HttpHeaders.contentRangeHeader,
              'bytes */$totalLength',
            );
          }
          await request.response.close();
          return;
        }

        if (parsed.start > 0 && !supportsRanges) {
          safeAddError('该远程媒体不支持跳转播放 (not_seekable)');
          request.response.statusCode = HttpStatus.requestedRangeNotSatisfiable;
          await request.response.close();
          return;
        }

        if (request.method == 'HEAD') {
          request.response.statusCode = HttpStatus.ok;
          request.response.headers.set(
            HttpHeaders.acceptRangesHeader,
            supportsRanges ? 'bytes' : 'none',
          );
          if (totalLength != null) {
            request.response.headers.set(
              HttpHeaders.contentLengthHeader,
              totalLength,
            );
          }
          request.response.headers.set(
            HttpHeaders.contentTypeHeader,
            'video/mp4',
          );
          await request.response.close();
          return;
        }

        // GET 响应
        final start = parsed.start;
        final endExclusive = parsed.end != null ? parsed.end! + 1 : null;
        final contentLength = parsed.end != null
            ? (parsed.end! - start + 1)
            : (totalLength != null ? (totalLength - start) : null);

        request.response.statusCode = parsed.isRange
            ? HttpStatus.partialContent
            : HttpStatus.ok;
        request.response.headers.set(
          HttpHeaders.acceptRangesHeader,
          supportsRanges ? 'bytes' : 'none',
        );
        request.response.headers.set(
          HttpHeaders.contentTypeHeader,
          'video/mp4',
        );

        if (parsed.isRange) {
          final endDisplay =
              parsed.end ?? (totalLength != null ? totalLength - 1 : '');
          request.response.headers.set(
            HttpHeaders.contentRangeHeader,
            'bytes $start-$endDisplay/${totalLength ?? '*'}',
          );
        }
        if (contentLength != null) {
          request.response.headers.set(
            HttpHeaders.contentLengthHeader,
            contentLength,
          );
        }

        final stream = reader.read(start, endExclusive);
        int pipedBytes = 0;
        try {
          await for (final chunk in stream) {
            if (isClosed) break;
            pipedBytes += chunk.length;
            if (contentLength != null && pipedBytes > contentLength) {
              safeAddError('读取媒体数据流超出预期长度');
              break;
            }
            request.response.add(chunk);
            await request.response.flush();
          }

          if (!isClosed && contentLength != null) {
            if (pipedBytes < contentLength) {
              safeAddError('读取媒体数据流未完整接收');
            }
          }
        } catch (_) {
          if (!isClosed) {
            safeAddError('读取媒体数据流失败');
          }
        } finally {
          try {
            await request.response.close();
          } catch (_) {}
        }
      }

      final sub = server.listen((HttpRequest request) {
        final handlerFuture = handleReaderRequest(request);
        activeReaderHandlers.add(handlerFuture);
        handlerFuture.whenComplete(
          () => activeReaderHandlers.remove(handlerFuture),
        );
      });

      Future<void> releaseLease() async {
        if (isClosed) return;
        isClosed = true;
        await sub.cancel();
        await server.close(force: true);
        await reader.close();
        if (activeReaderHandlers.isNotEmpty) {
          await Future.wait(
            activeReaderHandlers.toList(),
          ).catchError((_) => <void>[]);
        }
        if (!errorsController.isClosed) {
          await errorsController.close();
        }
      }

      // openReader 具体租约严禁附带 prepare（已关闭的 reader 绝不能被重用）
      return PlaybackResource(
        uri: loopbackUri,
        displayName: displayName,
        release: releaseLease,
        errors: errorsController.stream,
      );
    } on PlaybackResourceException {
      rethrow;
    } on MediaSourceException catch (e) {
      throw PlaybackResourceException(e.message, code: e.code);
    } catch (_) {
      throw const PlaybackResourceException('准备媒体读取流失败，请重试');
    }
  }

  Future<_ProbeResult> _probeTarget(
    RemotePlaybackTarget target,
    Future<RemotePlaybackTarget> Function({
      required bool refresh,
      CancelToken? cancelToken,
    })
    resolve,
    CancelToken cancelToken,
  ) async {
    final headers = Map<String, String>.from(target.headers);
    headers['Range'] = 'bytes=0-0';
    headers['Accept-Encoding'] = 'identity';

    Response<dynamic> response;
    var currentTarget = target;

    try {
      response = await _http.request(
        currentTarget.uri,
        method: 'GET',
        headers: headers,
        responseType: ResponseType.stream,
        cancelToken: cancelToken,
        allowedStatusCodes: const {HttpStatus.requestedRangeNotSatisfiable},
      );
    } on MediaSourceException catch (e) {
      if (e.code == 'unauthorized' || e.code == 'forbidden') {
        currentTarget = await resolve(refresh: true, cancelToken: cancelToken);
        final retryHeaders = Map<String, String>.from(currentTarget.headers);
        retryHeaders['Range'] = 'bytes=0-0';
        retryHeaders['Accept-Encoding'] = 'identity';
        response = await _http.request(
          currentTarget.uri,
          method: 'GET',
          headers: retryHeaders,
          responseType: ResponseType.stream,
          cancelToken: cancelToken,
          allowedStatusCodes: const {HttpStatus.requestedRangeNotSatisfiable},
        );
      } else {
        rethrow;
      }
    }

    final statusCode = response.statusCode ?? HttpStatus.badGateway;

    // 严禁耗尽 200 全量文件下载，在任何分支均确保立即关闭探测流
    _closeResponseBody(response.data);

    final contentEncoding = response.headers.value(
      HttpHeaders.contentEncodingHeader,
    );
    if (contentEncoding != null && contentEncoding != 'identity') {
      throw const PlaybackResourceException(
        '服务器返回了压缩的媒体分段，无法保证精确定位',
        code: 'compressed_range_rejected',
      );
    }

    bool supportsRanges = false;
    int? totalLength;

    if (statusCode == HttpStatus.partialContent) {
      // 必须严格校验 206 响应包含正确的 Content-Range: bytes 0-0/positiveTotal
      final cr = response.headers.value(HttpHeaders.contentRangeHeader);
      if (cr == null) {
        throw const PlaybackResourceException(
          '媒体服务器返回 206 但缺少 Content-Range 头',
          code: 'invalid_content_range',
        );
      }

      final match = RegExp(r'^bytes\s+0-0/(\d+)$').firstMatch(cr.trim());
      if (match == null) {
        throw const PlaybackResourceException(
          '媒体服务器返回了非法的 Content-Range 范围',
          code: 'invalid_content_range',
        );
      }

      final parsedTotal = int.tryParse(match.group(1)!);
      if (parsedTotal == null || parsedTotal <= 0) {
        throw const PlaybackResourceException(
          '媒体服务器返回了无效的文件总大小',
          code: 'invalid_content_range',
        );
      }
      totalLength = parsedTotal;

      // 若提供了 Content-Length，探测 0-0 必须且只能为 1
      final cl = response.headers.value(HttpHeaders.contentLengthHeader);
      if (cl != null) {
        final parsedCl = int.tryParse(cl.trim());
        if (parsedCl != 1) {
          throw const PlaybackResourceException(
            '媒体服务器 Range 探测返回的字节长度异常',
            code: 'invalid_content_length',
          );
        }
      }

      supportsRanges = true;
    } else if (statusCode == HttpStatus.ok) {
      supportsRanges = false;
      final cl = response.headers.value(HttpHeaders.contentLengthHeader);
      if (cl != null) {
        totalLength = int.tryParse(cl.trim());
      }
    } else if (statusCode == HttpStatus.requestedRangeNotSatisfiable) {
      // 416 仅在 bytes */0 空文件时视为合法
      final cr = response.headers.value(HttpHeaders.contentRangeHeader);
      if (cr != null && RegExp(r'^bytes\s+\*/0$').hasMatch(cr.trim())) {
        supportsRanges = true;
        totalLength = 0;
      } else {
        throw const PlaybackResourceException(
          '媒体服务器返回 416 Range 无法满足',
          code: 'range_not_satisfiable',
        );
      }
    } else {
      throw const PlaybackResourceException(
        '媒体服务器返回异常状态码，探测失败',
        code: 'probe_failed',
      );
    }

    return _ProbeResult(
      target: currentTarget,
      supportsRanges: supportsRanges,
      totalLength: totalLength,
    );
  }

  static Future<RemotePlaybackTarget> _raceResolve({
    required Future<RemotePlaybackTarget> Function({
      required bool refresh,
      CancelToken? cancelToken,
    })
    resolve,
    required bool refresh,
    required CancelToken cancelToken,
    required bool Function() isClosedCheck,
  }) async {
    if (isClosedCheck() || cancelToken.isCancelled) {
      throw const MediaSourceException('操作已取消', code: 'cancelled');
    }

    final cancelCompleter = Completer<RemotePlaybackTarget>();
    void onCancel() {
      if (!cancelCompleter.isCompleted) {
        cancelCompleter.completeError(
          const MediaSourceException('操作已取消', code: 'cancelled'),
        );
      }
    }

    cancelToken.whenCancel.then((_) => onCancel());

    return Future.any([
      resolve(refresh: refresh, cancelToken: cancelToken),
      cancelCompleter.future,
    ]);
  }

  static void _closeResponseBody(dynamic data) {
    if (data is ResponseBody) {
      try {
        data.stream.listen(null).cancel();
      } catch (_) {}
    }
  }

  static bool _matchesRequestedRange(
    String contentRange,
    int expectedStart,
    int? expectedEnd,
    int? totalLength,
  ) {
    final match = RegExp(
      r'^bytes\s+(\d+)-(\d+)/(\d+|\*)$',
    ).firstMatch(contentRange.trim());
    if (match == null) return false;
    final start = int.tryParse(match.group(1)!);
    final end = int.tryParse(match.group(2)!);
    final totalStr = match.group(3)!;

    if (start != expectedStart) return false;
    if (expectedEnd != null && end != expectedEnd) return false;
    if (totalLength != null && totalStr != '*') {
      final total = int.tryParse(totalStr);
      if (total != totalLength) return false;
    }
    return true;
  }

  static String _generateSessionToken() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  static String _sanitizeFilename(String name) {
    final clean = name.replaceAll(RegExp(r'[\\/\r\n]'), '_').trim();
    return clean.isEmpty ? 'media.mp4' : clean;
  }

  static _ParsedRange _parseRange(String? header, int? totalLength) {
    if (header == null || header.trim().isEmpty) {
      return _ParsedRange(
        start: 0,
        end: totalLength != null && totalLength > 0 ? totalLength - 1 : null,
        isRange: false,
        isInvalid: false,
      );
    }

    final trimmed = header.trim();
    if (!trimmed.startsWith('bytes=')) {
      return const _ParsedRange(start: 0, isRange: true, isInvalid: true);
    }

    final spec = trimmed.substring(6).trim();
    if (spec.contains(',')) {
      // 拒绝 multipart 多段 Range 请求，安全返回 416
      return const _ParsedRange(start: 0, isRange: true, isInvalid: true);
    }

    if (spec.startsWith('-')) {
      // 后缀范围: -suffixLength
      final suffix = int.tryParse(spec.substring(1));
      if (suffix == null || suffix <= 0) {
        return const _ParsedRange(start: 0, isRange: true, isInvalid: true);
      }
      if (totalLength == null) {
        return const _ParsedRange(start: 0, isRange: true, isInvalid: true);
      }
      final start = max(0, totalLength - suffix);
      final end = totalLength > 0 ? totalLength - 1 : 0;
      return _ParsedRange(
        start: start,
        end: end,
        isRange: true,
        isInvalid: false,
      );
    }

    final parts = spec.split('-');
    if (parts.length != 2) {
      return const _ParsedRange(start: 0, isRange: true, isInvalid: true);
    }

    final start = int.tryParse(parts[0]);
    if (start == null || start < 0) {
      return const _ParsedRange(start: 0, isRange: true, isInvalid: true);
    }

    int? end;
    if (parts[1].isNotEmpty) {
      end = int.tryParse(parts[1]);
      if (end == null || end < start) {
        return const _ParsedRange(start: 0, isRange: true, isInvalid: true);
      }
    }

    if (totalLength != null) {
      if (start >= totalLength) {
        return const _ParsedRange(start: 0, isRange: true, isInvalid: true);
      }
      if (end != null && end >= totalLength) {
        end = totalLength - 1;
      }
      end ??= totalLength - 1;
    }

    return _ParsedRange(
      start: start,
      end: end,
      isRange: true,
      isInvalid: false,
    );
  }
}

class _ProbeResult {
  const _ProbeResult({
    required this.target,
    required this.supportsRanges,
    this.totalLength,
  });

  final RemotePlaybackTarget target;
  final bool supportsRanges;
  final int? totalLength;
}

class _ParsedRange {
  const _ParsedRange({
    required this.start,
    this.end,
    this.isRange = false,
    this.isInvalid = false,
  });

  final int start;
  final int? end;
  final bool isRange;
  final bool isInvalid;
}
