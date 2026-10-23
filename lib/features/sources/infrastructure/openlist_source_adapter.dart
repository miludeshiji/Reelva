import 'dart:convert';

import 'package:dio/dio.dart';

import '../../../core/logging/app_logger.dart';
import '../../player/domain/playback_resource.dart';
import '../domain/media_source_adapter.dart';
import '../domain/source_models.dart';
import 'remote_credentials_store.dart';
import 'remote_http_client.dart';
import 'remote_playback_bridge.dart';

/// OpenList (前身 Alist 等) 媒体源适配器
///
/// 遵循 M5 规范与 OpenList API 契约：
/// - 基于 POST /api/fs/list 进行目录分页枚举（最大每页 100 项），严格校验分页数据一致性；
/// - 基于 POST /api/fs/get 进行条目 stat 元数据查询与播放地址解析；
/// - 根定位符为标准 URL 附带 fragment 路径，子条目使用跨会话稳定的规范绝对 POSIX 路径；
/// - 严格校验源根目录边界约束，拒绝任何形式的跨源与路径穿越逃逸；
/// - API 认证仅在与受信任 API 端点交互时携带原始 Token（无 Bearer 前缀），从凭据读取目录密码；
/// - 绝不将 API Token 转发至媒体播放 URL（即使同主机也严格剥离）；
/// - 播放头仅透传显式配置的 User-Agent 与 Referer，将响应中的 header 视为 HTML 目录说明而非 HTTP 头；
/// - 杜绝伪造 /fs/link 等不存在的端点，尊重直链或反代 raw_url；
/// - 遇到未知过期或 401/403 时通过 Bridge 刷新解析器获取最新播放地址。
class OpenListSourceAdapter implements MediaSourceAdapter {
  OpenListSourceAdapter({
    required this.credentials,
    required this.http,
    required this.playback,
  });

  final RemoteCredentialsStore credentials;
  final RemoteHttpClient http;
  final RemotePlaybackBridge playback;

  static const int _pageSize = 100;

  @override
  String get kind => 'openlist';

  @override
  Future<DirectorySelection?> pickDirectory({String? initialLocator}) async {
    throw const MediaSourceException(
      'OpenList 媒体源需通过配置对话框进行添加',
      code: 'remote_configuration_required',
    );
  }

  @override
  Stream<MediaEntry> listEntries(
    MediaSourceConfig source,
    String directoryId,
  ) async* {
    final rootPath = _parseRootPath(source.rootLocator);
    final currentPath = _resolveAndValidatePath(source, directoryId, rootPath);
    final apiBaseUri = _getApiBaseUri(source.rootLocator);
    final listUri = _buildApiUri(apiBaseUri, '/api/fs/list');
    final creds = await credentials.read(source.credentialRef);
    final headers = <String, String>{'Content-Type': 'application/json'};
    if (creds.token.trim().isNotEmpty) {
      headers['Authorization'] = creds.token.trim();
    }

    int page = 1;
    int? reportedTotal;
    final seenChildPaths = <String>{};

    while (true) {
      final Response<dynamic> response;
      try {
        response = await http.request(
          listUri,
          method: 'POST',
          headers: headers,
          data: jsonEncode({
            'path': currentPath,
            'password': creds.password,
            'page': page,
            'per_page': _pageSize,
            'refresh': false,
          }),
          responseType: ResponseType.json,
        );
      } catch (e, st) {
        if (e is MediaSourceException) rethrow;
        AppLogger.instance.error(
          'OpenList listEntries 请求失败: $listUri',
          error: e,
          stackTrace: st,
        );
        throw const MediaSourceException(
          '列出 OpenList 目录条目失败',
          code: 'network_error',
        );
      }

      final body = _parseEnvelope(response.data);
      final data = body['data'];

      // 拒绝缺失或非 Map 的 data（官方空目录为 data: {total: 0, content: null}）
      if (data == null || data is! Map<String, dynamic>) {
        throw const MediaSourceException(
          'OpenList 响应缺少有效数据',
          code: 'invalid_response',
        );
      }

      if (data['total'] != null) {
        final rawTotal = data['total'];
        if (rawTotal is! num || rawTotal < 0) {
          throw const MediaSourceException(
            'OpenList 返回了非法的 total 计数',
            code: 'invalid_response',
          );
        }
        final t = rawTotal.toInt();
        if (reportedTotal != null && reportedTotal != t) {
          throw const MediaSourceException(
            'OpenList 分页总数发生冲突',
            code: 'pagination_error',
          );
        }
        reportedTotal = t;
      }

      final rawContent = data['content'];
      final List<dynamic> content;
      if (rawContent == null) {
        content = const <dynamic>[];
      } else if (rawContent is List) {
        content = rawContent;
      } else {
        throw const MediaSourceException(
          'OpenList content 必须为列表或 null',
          code: 'invalid_response',
        );
      }

      // 如果内容为空（包括第 1 页），但 reportedTotal 大于已获取条目数，明确拒绝为不一致，防止误清空库
      if (content.isEmpty) {
        if (reportedTotal != null && seenChildPaths.length < reportedTotal) {
          throw const MediaSourceException(
            'OpenList 分页数据不一致: 预期条目数与实际获取条目数不匹配',
            code: 'pagination_error',
          );
        }
        break;
      }

      for (final item in content) {
        if (item is! Map<String, dynamic>) {
          throw const MediaSourceException(
            'OpenList 条目格式错误',
            code: 'invalid_response',
          );
        }

        final rawName = item['name'];
        if (rawName is! String || rawName.trim().isEmpty) {
          throw const MediaSourceException(
            'OpenList 条目名称缺失或格式错误',
            code: 'invalid_response',
          );
        }

        final name = rawName;
        if (name == '.' ||
            name == '..' ||
            name.contains('/') ||
            name.contains(r'\')) {
          throw const MediaSourceException(
            'OpenList 条目名称包含非法字符或相对路径',
            code: 'invalid_response',
          );
        }

        final rawIsDir = item['is_dir'];
        if (rawIsDir is! bool) {
          throw const MediaSourceException(
            'OpenList 条目 is_dir 属性非布尔类型',
            code: 'invalid_response',
          );
        }
        final isDir = rawIsDir;

        final int? size;
        if (isDir) {
          size = null;
        } else {
          final rawSize = item['size'];
          if (rawSize is! num || rawSize < 0) {
            throw const MediaSourceException(
              'OpenList 文件大小非法',
              code: 'invalid_response',
            );
          }
          size = rawSize.toInt();
        }

        final childPath = currentPath == '/' ? '/$name' : '$currentPath/$name';

        // 记录并防范重复条目/重复分页 (避免重放页被误计入 total，导致漏掉未见条目)
        if (!seenChildPaths.add(childPath)) {
          throw const MediaSourceException(
            'OpenList 分页返回了重复条目',
            code: 'pagination_error',
          );
        }

        // 条目数不得超过 reportedTotal 限制
        if (reportedTotal != null && seenChildPaths.length > reportedTotal) {
          throw const MediaSourceException(
            'OpenList 分页条目数量超出 total 限制',
            code: 'pagination_error',
          );
        }

        final modifiedAt = _parseDateTime(item['modified']);
        final etag = _extractEtag(item);

        yield MediaEntry(
          externalId: childPath,
          locator: childPath,
          name: name,
          isDirectory: isDir,
          size: size,
          modifiedAt: modifiedAt,
          etag: etag,
        );
      }

      if (reportedTotal != null) {
        if (seenChildPaths.length >= reportedTotal) {
          break;
        }
        if (content.length < _pageSize) {
          throw const MediaSourceException(
            'OpenList 分页提前截断: 预期条目数未达到',
            code: 'pagination_error',
          );
        }
      } else {
        if (content.length < _pageSize) {
          break;
        }
      }

      page++;
    }

    if (reportedTotal != null && seenChildPaths.length != reportedTotal) {
      throw const MediaSourceException(
        'OpenList 分页获取总数与 total 不一致',
        code: 'pagination_error',
      );
    }
  }

  @override
  Future<MediaStat> stat(MediaSourceConfig source, String entryId) async {
    final rootPath = _parseRootPath(source.rootLocator);
    final targetPath = _resolveAndValidatePath(source, entryId, rootPath);
    final apiBaseUri = _getApiBaseUri(source.rootLocator);
    final getUri = _buildApiUri(apiBaseUri, '/api/fs/get');
    final creds = await credentials.read(source.credentialRef);
    final headers = <String, String>{'Content-Type': 'application/json'};
    if (creds.token.trim().isNotEmpty) {
      headers['Authorization'] = creds.token.trim();
    }

    final Response<dynamic> response;
    try {
      response = await http.request(
        getUri,
        method: 'POST',
        headers: headers,
        data: jsonEncode({'path': targetPath, 'password': creds.password}),
        responseType: ResponseType.json,
      );
    } on MediaSourceException catch (e) {
      if (e.code == 'file_missing' || e.code == 'not_found') {
        throw const MediaSourceException('媒体文件或目录不存在', code: 'not_found');
      }
      rethrow;
    } catch (e, st) {
      AppLogger.instance.error(
        'OpenList stat 请求失败: $getUri',
        error: e,
        stackTrace: st,
      );
      throw const MediaSourceException(
        '获取 OpenList 条目状态失败',
        code: 'stat_error',
      );
    }

    final Map<String, dynamic> body;
    try {
      body = _parseEnvelope(response.data);
    } on MediaSourceException catch (e) {
      if (e.code == 'file_missing' || e.code == 'not_found') {
        throw const MediaSourceException('媒体文件或目录不存在', code: 'not_found');
      }
      rethrow;
    }

    final data = body['data'];
    if (data is! Map<String, dynamic>) {
      throw const MediaSourceException('媒体文件或目录不存在', code: 'not_found');
    }

    final rawIsDir = data['is_dir'];
    if (rawIsDir is! bool) {
      throw const MediaSourceException(
        'OpenList 条目 is_dir 属性非布尔类型',
        code: 'invalid_response',
      );
    }
    final isDir = rawIsDir;

    final int? size;
    if (isDir) {
      size = null;
    } else {
      final rawSize = data['size'];
      if (rawSize is! num || rawSize < 0) {
        throw const MediaSourceException(
          'OpenList 文件大小非法',
          code: 'invalid_response',
        );
      }
      size = rawSize.toInt();
    }
    final modifiedAt = _parseDateTime(data['modified']);
    final etag = _extractEtag(data);

    return MediaStat(size: size, modifiedAt: modifiedAt, etag: etag);
  }

  @override
  Future<PlaybackResource> resolvePlayback(
    MediaSourceConfig source,
    String entryId,
  ) async {
    final rootPath = _parseRootPath(source.rootLocator);
    final targetPath = _resolveAndValidatePath(source, entryId, rootPath);
    final apiBaseUri = _getApiBaseUri(source.rootLocator);
    final displayName = _extractDisplayName(targetPath);

    final logicalUri = apiBaseUri.replace(fragment: targetPath);

    return PlaybackResource(
      uri: logicalUri,
      displayName: displayName,
      prepare: () async {
        try {
          return await playback.open(
            displayName: displayName,
            resolve: ({required bool refresh, CancelToken? cancelToken}) async {
              if (cancelToken?.isCancelled == true) {
                throw cancelToken!.cancelError!;
              }
              final creds = await credentials.read(source.credentialRef);
              if (cancelToken?.isCancelled == true) {
                throw cancelToken!.cancelError!;
              }
              final getUri = _buildApiUri(apiBaseUri, '/api/fs/get');

              final headers = <String, String>{
                'Content-Type': 'application/json',
              };
              if (creds.token.trim().isNotEmpty) {
                headers['Authorization'] = creds.token.trim();
              }

              final Response<dynamic> response;
              try {
                response = await http.request(
                  getUri,
                  method: 'POST',
                  headers: headers,
                  data: jsonEncode({
                    'path': targetPath,
                    'password': creds.password,
                  }),
                  responseType: ResponseType.json,
                  cancelToken: cancelToken,
                );
              } catch (e, st) {
                if (e is MediaSourceException) rethrow;
                AppLogger.instance.error(
                  'OpenList resolvePlayback /api/fs/get 请求失败: $getUri',
                  error: e,
                  stackTrace: st,
                );
                throw const MediaSourceException(
                  '获取 OpenList 播放地址失败',
                  code: 'network_error',
                );
              }

              final body = _parseEnvelope(response.data);
              final data = body['data'];
              if (data is! Map<String, dynamic>) {
                throw const MediaSourceException(
                  'OpenList 未返回有效的条目详情',
                  code: 'invalid_response',
                );
              }

              final rawUrlStr = data['raw_url']?.toString();
              if (rawUrlStr == null || rawUrlStr.trim().isEmpty) {
                throw const MediaSourceException(
                  'OpenList 未提供媒体播放链接',
                  code: 'raw_url_missing',
                );
              }

              final resolvedUri = _resolveAndValidateMediaUri(
                apiBaseUri,
                rawUrlStr.trim(),
              );

              final playbackHeaders = <String, String>{};
              for (final entry in creds.playbackHeaders.entries) {
                final key = entry.key.toLowerCase();
                if (key == 'user-agent') {
                  playbackHeaders['User-Agent'] = entry.value;
                } else if (key == 'referer') {
                  playbackHeaders['Referer'] = entry.value;
                }
              }

              final expiresAt = _extractExpiry(resolvedUri);

              return RemotePlaybackTarget(
                uri: resolvedUri,
                headers: playbackHeaders,
                expiresAt: expiresAt,
              );
            },
          );
        } on PlaybackResourceException {
          rethrow;
        } on MediaSourceException catch (e) {
          throw PlaybackResourceException(e.message, code: e.code);
        } catch (e, st) {
          AppLogger.instance.error(
            '准备 OpenList 播放资源失败',
            error: e,
            stackTrace: st,
          );
          throw const PlaybackResourceException('准备 OpenList 播放资源失败');
        }
      },
    );
  }

  /// 提取并校验根路径（从 rootLocator 的 fragment 中提取）
  String _parseRootPath(String rootLocator) {
    final uri = Uri.tryParse(rootLocator.trim());
    if (uri == null ||
        !uri.hasScheme ||
        (!uri.isScheme('http') && !uri.isScheme('https')) ||
        uri.host.isEmpty) {
      throw const MediaSourceException(
        'OpenList 根定位符必须为有效的 http 或 https URL',
        code: 'invalid_url',
      );
    }
    if (uri.userInfo.isNotEmpty) {
      throw const MediaSourceException(
        'OpenList 根目录 URL 中包含用户名或密码，请移除并在下方凭据输入框中填写',
        code: 'credentials_in_url',
      );
    }
    if (uri.hasQuery) {
      throw const MediaSourceException(
        'OpenList 根目录 URL 不支持携带 Query 参数，请移除',
        code: 'query_in_url',
      );
    }

    var rootPath = uri.fragment.trim();
    if (rootPath.isEmpty) {
      rootPath = '/';
    } else {
      rootPath = _safeDecodePath(rootPath);
    }

    if (!rootPath.startsWith('/')) {
      rootPath = '/$rootPath';
    }

    while (rootPath.length > 1 && rootPath.endsWith('/')) {
      rootPath = rootPath.substring(0, rootPath.length - 1);
    }

    final segments = rootPath.split('/');
    for (final seg in segments) {
      if (seg == '..' || seg == '.') {
        throw const MediaSourceException(
          'OpenList 根路径不得包含相对路径段',
          code: 'path_escape',
        );
      }
    }

    return rootPath;
  }

  /// 提取纯净的 API Base URL（不包含 userInfo、query 与 fragment）
  Uri _getApiBaseUri(String rootLocator) {
    final uri = Uri.tryParse(rootLocator.trim());
    if (uri == null ||
        !uri.hasScheme ||
        (!uri.isScheme('http') && !uri.isScheme('https')) ||
        uri.host.isEmpty) {
      throw const MediaSourceException(
        'OpenList 根定位符必须为有效的 http 或 https URL',
        code: 'invalid_url',
      );
    }
    if (uri.userInfo.isNotEmpty) {
      throw const MediaSourceException(
        'OpenList 根目录 URL 中包含用户名或密码，请移除并在下方凭据输入框中填写',
        code: 'credentials_in_url',
      );
    }
    if (uri.hasQuery) {
      throw const MediaSourceException(
        'OpenList 根目录 URL 不支持携带 Query 参数，请移除',
        code: 'query_in_url',
      );
    }

    var basePath = uri.path;
    while (basePath.endsWith('/') && basePath.length > 1) {
      basePath = basePath.substring(0, basePath.length - 1);
    }
    if (basePath == '/') {
      basePath = '';
    }

    return Uri(
      scheme: uri.scheme.toLowerCase(),
      host: uri.host.toLowerCase(),
      port: uri.hasPort ? uri.port : null,
      path: basePath.isEmpty ? null : basePath,
    );
  }

  /// 解析目标路径并严格校验根目录约束与防路径穿越
  String _resolveAndValidatePath(
    MediaSourceConfig source,
    String idOrLocator,
    String rootPath,
  ) {
    final trimmed = idOrLocator.trim();
    if (trimmed.isEmpty ||
        trimmed == source.rootLocator.trim() ||
        trimmed == rootPath) {
      return rootPath;
    }

    String path;
    if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
      final parsed = Uri.tryParse(trimmed);
      if (parsed == null) {
        throw const MediaSourceException(
          '无效的 OpenList 定位符',
          code: 'invalid_url',
        );
      }
      final apiBase = _getApiBaseUri(source.rootLocator);
      if (parsed.scheme.toLowerCase() != apiBase.scheme ||
          parsed.authority.toLowerCase() != apiBase.authority) {
        throw const MediaSourceException('访问路径逃出媒体源根目录', code: 'path_escape');
      }

      if (parsed.hasFragment && parsed.fragment.isNotEmpty) {
        path = _safeDecodePath(parsed.fragment.trim());
      } else {
        path = parsed.path;
      }
    } else {
      path = trimmed;
    }

    if (!path.startsWith('/')) {
      path = '/$path';
    }

    while (path.length > 1 && path.endsWith('/')) {
      path = path.substring(0, path.length - 1);
    }

    final segments = path.split('/');
    for (final seg in segments) {
      if (seg == '..' || seg == '.') {
        throw const MediaSourceException('访问路径逃出媒体源根目录', code: 'path_escape');
      }
    }

    final bool isContained;
    if (rootPath == '/') {
      isContained = path.startsWith('/');
    } else {
      isContained = path == rootPath || path.startsWith('$rootPath/');
    }

    if (!isContained) {
      throw const MediaSourceException('访问路径逃出媒体源根目录', code: 'path_escape');
    }

    return path;
  }

  /// 构造 API 端点 URL
  Uri _buildApiUri(Uri apiBaseUri, String endpoint) {
    final basePath = apiBaseUri.path.endsWith('/')
        ? apiBaseUri.path.substring(0, apiBaseUri.path.length - 1)
        : apiBaseUri.path;
    final cleanEndpoint = endpoint.startsWith('/') ? endpoint : '/$endpoint';
    return apiBaseUri.replace(
      path: '$basePath$cleanEndpoint',
      query: null,
      fragment: null,
    );
  }

  /// 校验并解析媒体原始 URL（支持相对路径与绝对 URL）
  Uri _resolveAndValidateMediaUri(Uri apiBaseUri, String rawUrlStr) {
    final parsed = Uri.tryParse(rawUrlStr);
    if (parsed == null) {
      throw const MediaSourceException(
        'OpenList 返回了无法解析的播放链接',
        code: 'invalid_raw_url',
      );
    }

    final resolved = parsed.hasScheme ? parsed : apiBaseUri.resolveUri(parsed);

    if (!resolved.hasScheme ||
        (!resolved.isScheme('http') && !resolved.isScheme('https')) ||
        resolved.host.isEmpty) {
      throw const MediaSourceException(
        'OpenList 返回了非法的 HTTP/HTTPS 播放链接',
        code: 'invalid_raw_url',
      );
    }

    // 剔除 userInfo 避免意外泄露
    if (resolved.userInfo.isNotEmpty) {
      return resolved.replace(userInfo: '');
    }

    return resolved;
  }

  /// 解析 OpenList API 通用响应包络
  Map<String, dynamic> _parseEnvelope(dynamic rawData) {
    if (rawData == null) {
      throw const MediaSourceException(
        'OpenList 服务器返回了空响应',
        code: 'invalid_response',
      );
    }

    final Map<String, dynamic> body;
    if (rawData is Map<String, dynamic>) {
      body = rawData;
    } else if (rawData is Map) {
      body = Map<String, dynamic>.from(rawData);
    } else if (rawData is String) {
      final trimmed = rawData.trim();
      if (trimmed.isEmpty) {
        throw const MediaSourceException(
          'OpenList 服务器返回了空文本响应',
          code: 'invalid_response',
        );
      }
      try {
        final decoded = jsonDecode(trimmed);
        if (decoded is Map<String, dynamic>) {
          body = decoded;
        } else if (decoded is Map) {
          body = Map<String, dynamic>.from(decoded);
        } else {
          throw const MediaSourceException(
            'OpenList 响应格式不是 JSON 对象',
            code: 'invalid_response',
          );
        }
      } catch (e) {
        if (e is MediaSourceException) rethrow;
        throw const MediaSourceException(
          '解析 OpenList 服务器响应 JSON 失败',
          code: 'invalid_response',
        );
      }
    } else {
      throw const MediaSourceException(
        'OpenList 响应数据类型未知',
        code: 'invalid_response',
      );
    }

    final code = body['code'];
    if (code == null) {
      throw const MediaSourceException(
        'OpenList 响应缺少 code 字段',
        code: 'invalid_response',
      );
    }

    if (code != 200) {
      final msg = body['message']?.toString() ?? '';
      if (code == 401) {
        throw const MediaSourceException(
          'OpenList 认证失败: 未授权',
          code: 'unauthorized',
        );
      } else if (code == 403) {
        throw const MediaSourceException(
          'OpenList 访问被拒绝: 密码错误或权限不足',
          code: 'forbidden',
        );
      } else if (code == 404 || msg.toLowerCase().contains('not found')) {
        throw const MediaSourceException(
          'OpenList 目标条目不存在',
          code: 'file_missing',
        );
      } else {
        throw const MediaSourceException(
          'OpenList API 请求失败',
          code: 'api_error',
        );
      }
    }

    return body;
  }

  /// 从 URL 查询参数或 sign 中提取可能的签名过期时间戳
  DateTime? _extractExpiry(Uri uri) {
    for (final key in ['expires', 'Expires', 'x-oss-expires', 'expiry']) {
      final val = uri.queryParameters[key];
      if (val != null) {
        final sec = int.tryParse(val);
        if (sec != null && sec > 1000000000 && sec < 5000000000) {
          return DateTime.fromMillisecondsSinceEpoch(sec * 1000, isUtc: true);
        }
      }
    }

    final sign = uri.queryParameters['sign'];
    if (sign != null) {
      final parts = sign.split(RegExp(r'[:-]'));
      for (final part in parts) {
        final sec = int.tryParse(part);
        if (sec != null && sec > 1000000000 && sec < 5000000000) {
          return DateTime.fromMillisecondsSinceEpoch(sec * 1000, isUtc: true);
        }
      }
    }

    return null;
  }

  /// 提取条目的展示名
  String _extractDisplayName(String path) {
    final clean = path.endsWith('/') && path.length > 1
        ? path.substring(0, path.length - 1)
        : path;
    final segments = clean.split('/').where((s) => s.isNotEmpty).toList();
    if (segments.isEmpty) {
      return 'root';
    }
    return segments.last;
  }

  /// 安全解码 URL 路径段
  String _safeDecodePath(String input) {
    try {
      return Uri.decodeComponent(input);
    } catch (_) {
      return input;
    }
  }

  /// 安全解析日期时间字符串或时间戳
  DateTime? _parseDateTime(dynamic value) {
    if (value == null) return null;
    if (value is String) {
      return DateTime.tryParse(value);
    }
    if (value is int) {
      if (value > 100000000000) {
        return DateTime.fromMillisecondsSinceEpoch(value, isUtc: true);
      }
      if (value > 1000000000) {
        return DateTime.fromMillisecondsSinceEpoch(value * 1000, isUtc: true);
      }
    }
    return null;
  }

  /// 从条目中提取稳定哈希元数据（严禁将包含过期凭据的 sign 作为 etag）
  String? _extractEtag(Map<String, dynamic> item) {
    final hashInfo = item['hash_info'] ?? item['hashinfo'];
    if (hashInfo != null) {
      if (hashInfo is String) {
        final trimmed = hashInfo.trim();
        if (trimmed.isNotEmpty && trimmed != 'null') {
          return trimmed;
        }
      } else if (hashInfo is Map) {
        for (final key in ['sha256', 'sha1', 'md5', 'content_hash']) {
          final val = hashInfo[key]?.toString().trim();
          if (val != null && val.isNotEmpty && val != 'null') {
            return val;
          }
        }
      }
    }
    final hash = item['hash']?.toString().trim();
    if (hash != null && hash.isNotEmpty && hash != 'null') {
      return hash;
    }
    return null;
  }
}
