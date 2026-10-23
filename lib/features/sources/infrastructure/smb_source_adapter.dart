import 'dart:async';
import 'dart:math';

import 'package:dart_smb2/dart_smb2.dart';
import 'package:flutter/foundation.dart';

import '../../../core/logging/app_logger.dart';
import '../../player/domain/playback_resource.dart';
import '../domain/media_source_adapter.dart';
import '../domain/source_models.dart';
import 'remote_credentials_store.dart';
import 'remote_playback_bridge.dart';

/// SMB 字节块读取函数签名
typedef SmbChunkReader = Future<Uint8List> Function({
  required int offset,
  required int length,
  Smb2CancelToken? cancelToken,
});

/// SMB 句柄关闭函数签名
typedef SmbHandleCloser = Future<void> Function();

/// SMB 连接池断开函数签名
typedef SmbPoolDisconnector = Future<void> Function();

/// 解析后的 SMB 根定位符信息
@immutable
class ParsedSmbLocator {
  const ParsedSmbLocator({
    required this.host,
    required this.share,
    required this.rootPath,
    required this.rawUri,
  });

  /// 主机（含端口，如 '127.0.0.1:1445' 或 'nas.local'）
  final String host;

  /// 共享名（如 'MEDIA'）
  final String share;

  /// 共享内规范根路径（以 '/' 开头，如 '/' 或 '/Movies'）
  final String rootPath;

  /// 原始 Uri 对象
  final Uri rawUri;
}

/// SMB (Server Message Block / CIFS) 媒体源适配器
///
/// 遵循 M5 架构规范：
/// - 基于 `dart_smb2` (libsmb2) 实现原语支持，强制协商 SMB2+（SMB 2.0.2 至 3.1.1），不使用 SMB1；
/// - 根定位符格式为 `smb://host[:port]/share/root`，严禁包含 query/userInfo/fragment；
/// - 复用 `sanitizeAndValidateRootLocator` 规范化根目录，拒绝相对路径段；
/// - 维护共享内稳定的规范相对路径 ID（以 '/' 开头），严格执行根目录边界防逃逸校验；
/// - 支持包含字面量 %、#、空格与 Unicode 的真实文件名，生成合规 RFC 3986 的 URI 编码表示；
/// - 绝对不使用 `dart:io` 的 `File(smb://)`；
/// - 使用 `Smb2Pool` 工作隔离区 (worker isolates)，目录列表与状态查询使用 1 个 worker，播放流按需使用 2 个 worker；
/// - 超时时间严格限定为 15 秒；
/// - 支持 NTLM 认证（username/password/domain）及匿名连接；
/// - 结构化映射 `Smb2Exception` 至安全的常量文本 `MediaSourceException`，严禁泄漏原始异常消息与系统凭据；
/// - `listEntries` 生成流在取消时立即取消底层请求并调用 `pool.disconnect()`；
/// - `resolvePlayback` 返回轻量、可重用的逻辑描述符；`prepare` 触发时按需连接、以 `openFileWithSize` 打开句柄，
///   并将有界随机偏移读取器交付给 `playback.openReader`；
/// - 读取器分片大小最大 256 KiB 并提供背压，为每次分段读取维护独立的 `Smb2CancelToken`，短读/文件截断严格抛出 `unexpected_eof`；
/// - 读取器关闭时依序取消在途读取 -> 关闭文件句柄 -> 断开 pool，彻底杜绝孤儿 isolate 泄漏；`prepare` 失败确保关闭 pool。
class SmbSourceAdapter implements MediaSourceAdapter {
  SmbSourceAdapter({required this.credentials, required this.playback});

  final RemoteCredentialsStore credentials;
  final RemotePlaybackBridge playback;

  @override
  String get kind => 'smb';

  @override
  Future<DirectorySelection?> pickDirectory({String? initialLocator}) async {
    throw const MediaSourceException(
      'SMB 媒体源需通过配置对话框进行添加',
      code: 'remote_configuration_required',
    );
  }

  @override
  Stream<MediaEntry> listEntries(
    MediaSourceConfig source,
    String directoryId,
  ) async* {
    final parsedRoot = parseRootLocator(source.rootLocator);
    final currentWithinSharePath = resolveWithinSharePath(
      parsedRoot,
      directoryId,
      source.rootLocator,
    );
    final shareRelativePath = toShareRelativePath(currentWithinSharePath);

    final cancelToken = Smb2CancelToken();
    Smb2Pool? pool;

    try {
      final creds = await credentials.read(source.credentialRef);
      try {
        pool = await _connectPool(
          parsedRoot: parsedRoot,
          credentials: creds,
          workers: 1,
        );
      } on Smb2Exception catch (e) {
        throw mapSmbException(e);
      }

      final List<Smb2DirEntry> entries;
      try {
        entries = await pool.listDirectory(
          shareRelativePath,
          cancelToken: cancelToken,
        );
      } on Smb2Exception catch (e) {
        throw mapSmbException(e);
      }

      for (final entry in entries) {
        final name = entry.name;
        if (name.isEmpty || name == '.' || name == '..') {
          continue;
        }
        if (name.contains('\u0000') ||
            name.contains('/') ||
            name.contains(r'\')) {
          throw const MediaSourceException(
            'SMB 目录条目名称无效或包含非法分隔符',
            code: 'invalid_entry',
          );
        }

        final childWithinSharePath = currentWithinSharePath == '/'
            ? '/$name'
            : '$currentWithinSharePath/$name';

        yield MediaEntry(
          externalId: childWithinSharePath,
          locator: childWithinSharePath,
          name: name,
          isDirectory: entry.isDirectory,
          size: entry.isDirectory ? null : entry.size,
          modifiedAt: entry.stat.modified,
          etag: null,
        );
      }
    } finally {
      cancelToken.cancel('Listing completed or cancelled');
      if (pool != null) {
        try {
          await pool.disconnect();
        } catch (e, st) {
          AppLogger.instance.error(
            '断开 SMB 连接池异常 (${e.runtimeType})',
            error: e,
            stackTrace: st,
          );
        }
      }
    }
  }

  @override
  Future<MediaStat> stat(MediaSourceConfig source, String entryId) async {
    final parsedRoot = parseRootLocator(source.rootLocator);
    final withinSharePath = resolveWithinSharePath(
      parsedRoot,
      entryId,
      source.rootLocator,
    );
    final shareRelativePath = toShareRelativePath(withinSharePath);

    Smb2Pool? pool;
    try {
      final creds = await credentials.read(source.credentialRef);
      pool = await _connectPool(
        parsedRoot: parsedRoot,
        credentials: creds,
        workers: 1,
      );

      final Smb2Stat entryStat = await pool.stat(shareRelativePath);
      return MediaStat(
        size: entryStat.isDirectory ? null : entryStat.size,
        modifiedAt: entryStat.modified,
        etag: null,
      );
    } on Smb2Exception catch (e) {
      throw mapSmbException(e);
    } finally {
      if (pool != null) {
        try {
          await pool.disconnect();
        } catch (e, st) {
          AppLogger.instance.error(
            '断开 SMB 连接池异常 (${e.runtimeType})',
            error: e,
            stackTrace: st,
          );
        }
      }
    }
  }

  @override
  Future<PlaybackResource> resolvePlayback(
    MediaSourceConfig source,
    String entryId,
  ) async {
    final parsedRoot = parseRootLocator(source.rootLocator);
    final withinSharePath = resolveWithinSharePath(
      parsedRoot,
      entryId,
      source.rootLocator,
    );
    final shareRelativePath = toShareRelativePath(withinSharePath);
    final displayName = extractDisplayName(withinSharePath);
    final logicalUri = buildLogicalUri(
      parsedRoot: parsedRoot,
      withinSharePath: withinSharePath,
    );

    return PlaybackResource(
      uri: logicalUri,
      displayName: displayName,
      prepare: () async {
        Smb2Pool? pool;
        Smb2PoolHandle? handle;
        try {
          final creds = await credentials.read(source.credentialRef);
          pool = await _connectPool(
            parsedRoot: parsedRoot,
            credentials: creds,
            workers: 1,
          );

          final fileStat = await pool.stat(shareRelativePath);
          final fileSize = fileStat.size;
          final openedHandle = await pool.openFile(shareRelativePath);
          handle = openedHandle;

          final reader = SmbByteReader(
            fileSize: fileSize,
            readChunk:
                ({
                  required int offset,
                  required int length,
                  Smb2CancelToken? cancelToken,
                }) => pool!.readFromHandle(
                  handle!,
                  offset: offset,
                  length: length,
                  cancelToken: cancelToken,
                ),
            closeHandle: () => pool!.closeHandle(handle!),
            disconnect: () => pool!.disconnect(),
          );

          return await playback.openReader(
            displayName: displayName,
            reader: reader,
          );
        } on PlaybackResourceException {
          await _safeCleanup(pool: pool, handle: handle);
          rethrow;
        } on MediaSourceException catch (e) {
          await _safeCleanup(pool: pool, handle: handle);
          throw PlaybackResourceException(e.message, code: e.code);
        } on Smb2Exception catch (e) {
          await _safeCleanup(pool: pool, handle: handle);
          final mapped = mapSmbException(e);
          throw PlaybackResourceException(mapped.message, code: mapped.code);
        } catch (e, st) {
          await _safeCleanup(pool: pool, handle: handle);
          AppLogger.instance.error('准备 SMB 播放资源失败', error: e, stackTrace: st);
          throw const PlaybackResourceException(
            '准备 SMB 播放资源失败',
            code: 'playback_prepare_failed',
          );
        }
      },
    );
  }

  Future<Smb2Pool> _connectPool({
    required ParsedSmbLocator parsedRoot,
    required RemoteCredentials credentials,
    required int workers,
  }) async {
    final user = credentials.username.isNotEmpty ? credentials.username : null;
    final password = user != null ? credentials.password : null;
    final domain = credentials.domain.isNotEmpty ? credentials.domain : null;

    return await Smb2Pool.connect(
      host: parsedRoot.host,
      share: parsedRoot.share,
      user: user,
      password: password,
      domain: domain,
      workers: workers,
      timeout: const Duration(seconds: 15),
      version: Smb2Version.any,
    );
  }

  static Future<void> _safeCleanup({
    Smb2Pool? pool,
    Smb2PoolHandle? handle,
  }) async {
    try {
      if (handle != null && pool != null) {
        try {
          await pool.closeHandle(handle);
        } catch (e, st) {
          AppLogger.instance.error(
            '清理 SMB 文件句柄异常 (${e.runtimeType})',
            error: e,
            stackTrace: st,
          );
        }
      }
    } finally {
      if (pool != null) {
        try {
          await pool.disconnect();
        } catch (e, st) {
          AppLogger.instance.error(
            '断开 SMB 连接池异常 (${e.runtimeType})',
            error: e,
            stackTrace: st,
          );
        }
      }
    }
  }
}

/// 解析与验证 SMB 根目录定位符
///
/// 复用统一的 [sanitizeAndValidateRootLocator] 校验逻辑，拒绝非预期参数并提取主机、共享名与根路径。
ParsedSmbLocator parseRootLocator(String rootLocator) {
  final cleanRoot = sanitizeAndValidateRootLocator(
    kind: 'smb',
    rawInput: rootLocator,
  );

  final uri = Uri.parse(cleanRoot);
  final share = uri.pathSegments.first;
  final subSegments = uri.pathSegments.skip(1).toList();
  final rootPath = subSegments.isEmpty ? '/' : '/${subSegments.join('/')}';
  final hostWithPort = uri.hasPort ? '${uri.host}:${uri.port}' : uri.host;

  return ParsedSmbLocator(
    host: hostWithPort,
    share: share,
    rootPath: rootPath,
    rawUri: uri,
  );
}

/// 解析目标条目并在共享内验证根目录约束与防逃逸
///
/// 遵循规则：
/// - 若为完整 `smb://` 定位符，校验主机与共享匹配，提取并进行单次 URL 解码；
/// - 若为共享内相对路径，视为字面文件名字符串（不进行 URL 解码，允许 `%2f` 作为合法文件名文本）；
/// - 严密校验 `.` 与 `..` 点段相对逃逸；
/// - 严格校验 `parsedRoot.rootPath` 边界包含。
String resolveWithinSharePath(
  ParsedSmbLocator parsedRoot,
  String idOrLocator,
  String rawRootLocator,
) {
  final trimmed = idOrLocator.trim();
  if (trimmed.isEmpty ||
      trimmed == rawRootLocator.trim() ||
      trimmed == parsedRoot.rootPath) {
    return parsedRoot.rootPath;
  }

  String candidatePath;
  if (trimmed.toLowerCase().startsWith('smb://')) {
    final uri = Uri.tryParse(trimmed);
    if (uri == null) {
      throw const MediaSourceException(
        '无效的 SMB 资源定位符',
        code: 'invalid_smb_path',
      );
    }
    final hostWithPort = uri.hasPort ? '${uri.host}:${uri.port}' : uri.host;
    if (hostWithPort.toLowerCase() != parsedRoot.host.toLowerCase()) {
      throw const MediaSourceException('访问路径逃出媒体源主机范围', code: 'path_escape');
    }
    if (uri.userInfo.isNotEmpty || uri.hasQuery || uri.hasFragment) {
      throw const MediaSourceException(
        'SMB 定位符包含非预期参数',
        code: 'invalid_smb_path',
      );
    }

    final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
    if (segments.isEmpty ||
        segments.first.toLowerCase() != parsedRoot.share.toLowerCase()) {
      throw const MediaSourceException('访问路径不属于当前媒体源共享', code: 'path_escape');
    }

    final subSegments = segments.skip(1).toList();
    candidatePath = subSegments.isEmpty ? '/' : '/${subSegments.join('/')}';
  } else {
    var normalized = trimmed.replaceAll(r'\', '/');
    if (!normalized.startsWith('/')) {
      normalized = '/$normalized';
    }
    candidatePath = normalized;
  }

  while (candidatePath.length > 1 && candidatePath.endsWith('/')) {
    candidatePath = candidatePath.substring(0, candidatePath.length - 1);
  }

  final segments = candidatePath.split('/').where((s) => s.isNotEmpty).toList();
  for (final seg in segments) {
    if (seg == '.' || seg == '..') {
      throw const MediaSourceException(
        '访问路径包含相对路径段 (.) 或 (..)',
        code: 'path_escape',
      );
    }
  }

  final String cleanPath = segments.isEmpty ? '/' : '/${segments.join('/')}';

  final bool isContained;
  if (parsedRoot.rootPath == '/') {
    isContained = cleanPath.startsWith('/');
  } else {
    isContained =
        cleanPath == parsedRoot.rootPath ||
        cleanPath.startsWith('${parsedRoot.rootPath}/');
  }

  if (!isContained) {
    throw const MediaSourceException('访问路径逃出媒体源根目录', code: 'path_escape');
  }

  return cleanPath;
}

/// 将共享内路径转换为 dart_smb2 的 share-relative path
String toShareRelativePath(String withinSharePath) {
  if (withinSharePath == '/' || withinSharePath.isEmpty) {
    return '';
  }
  return withinSharePath.startsWith('/')
      ? withinSharePath.substring(1)
      : withinSharePath;
}

/// 提取用户友好的媒体文件名/目录名
String extractDisplayName(String withinSharePath) {
  if (withinSharePath == '/' || withinSharePath.isEmpty) {
    return 'SMB';
  }
  final segments = withinSharePath
      .split('/')
      .where((s) => s.isNotEmpty)
      .toList();
  return segments.isNotEmpty ? segments.last : 'SMB';
}

/// 构造标准的逻辑 SMB URI（保证特殊字符如 #, %, 空格与 Unicode 得到严格 URI 编码）
Uri buildLogicalUri({
  required ParsedSmbLocator parsedRoot,
  required String withinSharePath,
}) {
  final cleanSegments = withinSharePath
      .split('/')
      .where((s) => s.isNotEmpty)
      .toList();

  return Uri(
    scheme: 'smb',
    host: parsedRoot.rawUri.host.toLowerCase(),
    port: parsedRoot.rawUri.hasPort ? parsedRoot.rawUri.port : null,
    pathSegments: [parsedRoot.share, ...cleanSegments],
  );
}

/// 检查是否为 SMB 认证相关失败
bool _isAuthFailure(Smb2Exception e) {
  if (e.isAuthError || e.type == Smb2ErrorType.auth) {
    return true;
  }

  // 权威 NTSTATUS 码判定（MS-ERREF 2.3.1）
  final ntStatus = e.ntStatus ?? _extractNtStatus(e.message);
  if (ntStatus != null) {
    const authNtStatuses = <int>{
      0xC0000064, // NO_SUCH_USER
      0xC000006A, // WRONG_PASSWORD
      0xC000006D, // LOGON_FAILURE
      0xC000006E, // ACCOUNT_RESTRICTION
      0xC000006F, // INVALID_LOGON_HOURS
      0xC0000070, // INVALID_WORKSTATION
      0xC0000071, // PASSWORD_EXPIRED
      0xC0000072, // ACCOUNT_DISABLED
      0xC000015B, // LOGON_TYPE_NOT_GRANTED
      0xC0000193, // ACCOUNT_EXPIRED
      0xC0000224, // PASSWORD_MUST_CHANGE
      0xC0000234, // ACCOUNT_LOCKED_OUT
    };
    if (authNtStatuses.contains(ntStatus)) {
      return true;
    }
  }
  // 标准协议状态字符串
  final upper = e.message.toUpperCase();
  if (upper.contains('LOGON_FAILURE') ||
      upper.contains('WRONG_PASSWORD') ||
      upper.contains('NO_SUCH_USER') ||
      upper.contains('ACCOUNT_LOCKED_OUT') ||
      upper.contains('STATUS_LOGON_FAILURE') ||
      upper.contains('STATUS_WRONG_PASSWORD')) {
    return true;
  }

  return false;
}

int? _extractNtStatus(String message) {
  final match =
      RegExp(r'\(0x([0-9a-fA-F]{8})\)').firstMatch(message) ??
      RegExp(r'0x([0-9a-fA-F]{8})').firstMatch(message);
  if (match != null) {
    return int.tryParse(match.group(1)!, radix: 16);
  }
  return null;
}

/// 将 Smb2Exception 映射为安全、脱敏的常量文本 MediaSourceException
MediaSourceException mapSmbException(Smb2Exception e) {
  if (_isAuthFailure(e)) {
    return const MediaSourceException(
      'SMB 认证失败，请检查用户名或密码',
      code: 'authentication_failed',
    );
  }
  if (e.isNotFound) {
    return const MediaSourceException('SMB 共享或资源不存在', code: 'not_found');
  }
  if (e.isCancelled) {
    return const MediaSourceException('SMB 操作已取消', code: 'cancelled');
  }
  switch (e.type) {
    case Smb2ErrorType.accessDenied:
      return const MediaSourceException(
        '访问 SMB 资源被拒绝 (权限不足)',
        code: 'access_denied',
      );
    case Smb2ErrorType.timeout:
      return const MediaSourceException('连接 SMB 服务器超时', code: 'timeout');
    case Smb2ErrorType.connection:
      return const MediaSourceException(
        '无法建立 SMB 会话，请检查网络、账号密码或服务端协议兼容性',
        code: 'connection_failed',
      );
    case Smb2ErrorType.notADirectory:
      return const MediaSourceException(
        '指定的 SMB 路径不是目录',
        code: 'not_a_directory',
      );
    case Smb2ErrorType.isADirectory:
      return const MediaSourceException(
        '指定的 SMB 路径是目录而非文件',
        code: 'is_a_directory',
      );
    case Smb2ErrorType.alreadyExists:
      return const MediaSourceException('SMB 资源已存在', code: 'already_exists');
    case Smb2ErrorType.notEmpty:
      return const MediaSourceException('SMB 目录非空', code: 'not_empty');
    case Smb2ErrorType.inUse:
      return const MediaSourceException(
        'SMB 文件或资源正在被其他进程占用',
        code: 'resource_in_use',
      );
    case Smb2ErrorType.diskFull:
      return const MediaSourceException('SMB 服务器磁盘空间已满', code: 'disk_full');
    case Smb2ErrorType.io:
      return const MediaSourceException('SMB 网络传输发生 I/O 错误', code: 'io_error');
    case Smb2ErrorType.invalidParam:
      return const MediaSourceException('SMB 请求参数无效', code: 'invalid_param');
    case Smb2ErrorType.state:
      return const MediaSourceException('SMB 客户端连接状态异常', code: 'state_error');
    case Smb2ErrorType.notSupported:
      return const MediaSourceException(
        '当前 SMB 操作不受服务器支持',
        code: 'not_supported',
      );
    case Smb2ErrorType.auth:
      return const MediaSourceException(
        'SMB 认证失败，请检查用户名或密码',
        code: 'authentication_failed',
      );
    case Smb2ErrorType.notFound:
      return const MediaSourceException('SMB 共享或资源不存在', code: 'not_found');
    case Smb2ErrorType.cancelled:
      return const MediaSourceException('SMB 操作已取消', code: 'cancelled');
    case Smb2ErrorType.unknown:
      return const MediaSourceException('SMB 操作失败', code: 'smb_error');
  }
}

/// SMB 远程字节流读取器
///
/// 实现 [RemoteByteReader]，支持高效随机读取、分块反压流式读取、精确 EOF 校验与资源优雅释放。
class SmbByteReader implements RemoteByteReader {
  SmbByteReader({
    required this.fileSize,
    required this.readChunk,
    required this.closeHandle,
    required this.disconnect,
  });

  final int fileSize;
  final SmbChunkReader readChunk;
  final SmbHandleCloser closeHandle;
  final SmbPoolDisconnector disconnect;

  /// 单次分块最大尺寸：256 KiB
  static const int maxChunkSize = 256 * 1024;

  final Set<Smb2CancelToken> _activeTokens = {};
  bool _isClosed = false;

  @override
  int? get length => fileSize;

  @override
  bool get supportsRanges => true;

  @override
  Stream<List<int>> read(int start, int? endExclusive) async* {
    if (_isClosed) {
      throw const MediaSourceException('SMB 读取器已关闭', code: 'reader_closed');
    }

    if (start < 0 || start > fileSize) {
      throw const MediaSourceException(
        '请求字节范围超出文件大小',
        code: 'range_not_satisfiable',
      );
    }

    final int targetEnd = endExclusive != null
        ? min(endExclusive, fileSize)
        : fileSize;

    if (start == targetEnd) {
      return;
    }

    int currentOffset = start;
    final token = Smb2CancelToken();
    _activeTokens.add(token);

    try {
      while (currentOffset < targetEnd) {
        if (_isClosed) {
          throw const MediaSourceException('SMB 读取器已关闭', code: 'reader_closed');
        }

        final int bytesToRead = min(maxChunkSize, targetEnd - currentOffset);
        final Uint8List chunk;
        try {
          chunk = await readChunk(
            offset: currentOffset,
            length: bytesToRead,
            cancelToken: token,
          );
        } on Smb2Exception catch (e) {
          if (e.isCancelled) {
            return;
          }
          throw mapSmbException(e);
        }

        if (chunk.isEmpty) {
          throw MediaSourceException(
            'SMB 读取提前遇到文件末尾 EOF (预期读取至 $targetEnd 字节，实际停在 $currentOffset 字节)',
            code: 'unexpected_eof',
          );
        }

        yield chunk;
        currentOffset += chunk.length;
      }
    } finally {
      _activeTokens.remove(token);
      token.cancel('Read stream finished or cancelled');
    }
  }

  @override
  Future<void> close() async {
    if (_isClosed) return;
    _isClosed = true;

    for (final token in _activeTokens.toList()) {
      try {
        token.cancel('Reader closed');
      } catch (e, st) {
        AppLogger.instance.error(
          '取消 SMB 读取 Token 异常 (${e.runtimeType})',
          error: e,
          stackTrace: st,
        );
      }
    }
    _activeTokens.clear();

    try {
      try {
        await closeHandle();
      } catch (e, st) {
        AppLogger.instance.error(
          '关闭 SMB 文件句柄异常 (${e.runtimeType})',
          error: e,
          stackTrace: st,
        );
      }
    } finally {
      try {
        await disconnect();
      } catch (e, st) {
        AppLogger.instance.error(
          '断开 SMB 连接池异常 (${e.runtimeType})',
          error: e,
          stackTrace: st,
        );
      }
    }
  }
}
