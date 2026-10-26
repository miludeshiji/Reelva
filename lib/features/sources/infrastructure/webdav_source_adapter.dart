import 'dart:typed_data';
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:xml/xml.dart';
import 'package:xml/xml_events.dart';

import '../../../core/logging/app_logger.dart';
import '../../player/domain/playback_resource.dart';
import '../domain/media_source_adapter.dart';
import '../domain/media_sidecar_adapter.dart';
import '../domain/source_models.dart';
import 'remote_credentials_store.dart';
import 'remote_http_client.dart';
import 'remote_playback_bridge.dart';

/// WebDAV 媒体源适配器
///
/// 遵循 RFC 4918 规范与 M5 架构契约：
/// - Depth 1 流式目录枚举（ResponseType.stream + package:xml streaming events），避免全量 DOM 缓冲大目录；
/// - Depth 0 条目状态查询（ResponseType.plain 小 DOM）；
/// - 严密处理多命名空间（DAV:、D:、d: 或默认命名空间）与 207 Multi-Status 结构；
/// - 严格校验根目录约束，拒绝跨源、凭据/查询参数/片段注入或路径穿越逃逸；
/// - 稳定支持包含特殊字符（空格、Unicode、字面量 % 与 # 等）的媒体条目，不进行二次编码；
/// - 生成跨平台、跨重挂载稳定的 Clean 相对路径作为 externalId；
/// - 从安全存储读取 Basic Auth 凭据，并在起播/重试时重新读取；
/// - 遇到枚举异常或子项拒绝访问 (403) 时显式失败，绝不静默返回假空列表，避免误删媒体库旧数据；
/// - 在外部扫描流取消时联动取消底层 HTTP 请求与数据流。
class WebDavSourceAdapter implements MediaSourceAdapter, MediaSidecarAdapter {
  WebDavSourceAdapter({
    required this.credentials,
    required this.http,
    required this.playback,
  });

  final RemoteCredentialsStore credentials;
  final RemoteHttpClient http;
  final RemotePlaybackBridge playback;

  static const String _propfindXml =
      '<?xml version="1.0" encoding="utf-8" ?>\n'
      '<D:propfind xmlns:D="DAV:">\n'
      '  <D:prop>\n'
      '    <D:displayname/>\n'
      '    <D:resourcetype/>\n'
      '    <D:getcontentlength/>\n'
      '    <D:getlastmodified/>\n'
      '    <D:getetag/>\n'
      '  </D:prop>\n'
      '</D:propfind>';

  @override
  String get kind => 'webdav';

  @override
  Future<DirectorySelection?> pickDirectory({String? initialLocator}) async {
    throw const MediaSourceException(
      'WebDAV 媒体源需通过配置对话框进行添加',
      code: 'remote_configuration_required',
    );
  }

  @override
  Stream<MediaEntry> listEntries(
    MediaSourceConfig source,
    String directoryId,
  ) async* {
    var targetUri = _resolveUri(source, directoryId);
    if (!targetUri.path.endsWith('/')) {
      targetUri = targetUri.replace(path: '${targetUri.path}/');
    }

    final rootUri = _normalizeRootUri(source.rootLocator);
    _validateContainment(targetUri, rootUri);

    final headers = await _buildHeaders(source, depth: 1);
    final cancelToken = CancelToken();

    try {
      final Response<dynamic> response;
      try {
        response = await http.request(
          targetUri,
          method: 'PROPFIND',
          headers: headers,
          data: _propfindXml,
          responseType: ResponseType.stream,
          cancelToken: cancelToken,
        );
      } catch (e, st) {
        if (e is MediaSourceException) rethrow;
        AppLogger.instance.error(
          'WebDAV listEntries PROPFIND 失败',
          error: e,
          stackTrace: st,
        );
        throw const MediaSourceException(
          '列出 WebDAV 目录条目失败',
          code: 'network_error',
        );
      }

      final stringStream = _toStringStream(response.data);
      final responseNodes = stringStream
          .toXmlEvents()
          .selectSubtreeEvents(
            (event) => event.localName.toLowerCase() == 'response',
          )
          .toXmlNodes()
          .flatten();

      final targetSegments = targetUri.pathSegments
          .where((s) => s.isNotEmpty)
          .toList();
      final rootSegments = rootUri.pathSegments
          .where((s) => s.isNotEmpty)
          .toList();

      bool foundSuccessfulSelf = false;

      await for (final node in responseNodes) {
        if (node is! XmlElement) {
          continue;
        }

        final parsed = _parseResponse(node, targetUri, rootUri);
        final itemUri = parsed.uri;
        final itemSegments = itemUri.pathSegments
            .where((s) => s.isNotEmpty)
            .toList();

        // 判断是否为目录自身
        if (itemSegments.length == targetSegments.length) {
          bool isSelf = true;
          for (int i = 0; i < targetSegments.length; i++) {
            if (itemSegments[i] != targetSegments[i]) {
              isSelf = false;
              break;
            }
          }
          if (isSelf) {
            foundSuccessfulSelf = true;
            continue;
          }
        }

        // 仅保留 targetUri 的直接子项（层级严格等于 targetSegments.length + 1）
        if (itemSegments.length != targetSegments.length + 1) {
          continue;
        }
        bool isDirectChild = true;
        for (int i = 0; i < targetSegments.length; i++) {
          if (itemSegments[i] != targetSegments[i]) {
            isDirectChild = false;
            break;
          }
        }
        if (!isDirectChild) {
          continue;
        }

        final name = itemSegments.last;
        final relSegments = itemSegments.sublist(rootSegments.length);
        final cleanRelativePath = relSegments.join('/');

        yield MediaEntry(
          externalId: cleanRelativePath,
          locator: cleanRelativePath,
          name: name,
          isDirectory: parsed.isDirectory,
          size: parsed.isDirectory ? null : parsed.size,
          modifiedAt: parsed.modifiedAt,
          etag: parsed.etag,
        );
      }

      if (!foundSuccessfulSelf) {
        throw const MediaSourceException(
          'WebDAV 响应中未包含目标目录自身的状态或目标目录访问被拒绝',
          code: 'invalid_response',
        );
      }
    } finally {
      cancelToken.cancel();
    }
  }

  @override
  Future<MediaStat> stat(MediaSourceConfig source, String entryId) async {
    final targetUri = _resolveUri(source, entryId);
    final rootUri = _normalizeRootUri(source.rootLocator);
    _validateContainment(targetUri, rootUri);

    final headers = await _buildHeaders(source, depth: 0);

    final Response<dynamic> response;
    try {
      response = await http.request(
        targetUri,
        method: 'PROPFIND',
        headers: headers,
        data: _propfindXml,
        responseType: ResponseType.plain,
      );
    } on MediaSourceException catch (e) {
      if (e.code == 'file_missing') {
        throw const MediaSourceException('媒体文件或目录不存在', code: 'not_found');
      }
      rethrow;
    } catch (e, st) {
      AppLogger.instance.error(
        'WebDAV stat PROPFIND 失败',
        error: e,
        stackTrace: st,
      );
      throw const MediaSourceException('获取 WebDAV 条目状态失败', code: 'stat_error');
    }

    final rawData = response.data;
    if (rawData == null || (rawData is String && rawData.trim().isEmpty)) {
      throw const MediaSourceException(
        'WebDAV 服务器返回了空的状态响应',
        code: 'not_found',
      );
    }

    final String xmlString = rawData is List<int>
        ? utf8.decode(rawData)
        : rawData.toString();

    final XmlDocument doc;
    try {
      doc = XmlDocument.parse(xmlString);
    } catch (e) {
      throw const MediaSourceException(
        '解析 WebDAV 服务器状态 XML 失败',
        code: 'xml_parse_error',
      );
    }

    final responseElements = _findResponses(doc);
    if (responseElements.isEmpty) {
      throw const MediaSourceException('WebDAV 响应中未找到条目状态', code: 'not_found');
    }

    // 严密匹配请求路径对应的 response 节点，绝不盲目获取第一个不相关节点
    _ParsedWebDavResponse? matchingItem;
    for (final responseEl in responseElements) {
      final parsed = _parseResponse(responseEl, targetUri, rootUri);
      if (_isPathMatch(parsed.uri, targetUri)) {
        matchingItem = parsed;
        break;
      }
    }

    if (matchingItem == null) {
      throw const MediaSourceException('媒体文件或目录不存在', code: 'not_found');
    }

    return MediaStat(
      size: matchingItem.isDirectory ? null : matchingItem.size,
      modifiedAt: matchingItem.modifiedAt,
      etag: matchingItem.etag,
    );
  }

  @override
  Future<String?> parentDirectory(
    MediaSourceConfig source,
    String entryId,
  ) async {
    final uri = _resolveUri(source, entryId);
    final root = _normalizeRootUri(source.rootLocator);
    _validateContainment(uri, root);
    final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
    if (segments.length <=
        root.pathSegments.where((s) => s.isNotEmpty).length) {
      return null;
    }
    return uri
        .replace(pathSegments: [...segments.take(segments.length - 1), ''])
        .toString();
  }

  Future<Map<String, String>> _sidecarHeaders(MediaSourceConfig source) async {
    final creds = await credentials.read(source.credentialRef);
    return {
      if (creds.username.isNotEmpty || creds.password.isNotEmpty)
        'Authorization':
            'Basic ${base64Encode(utf8.encode('${creds.username}:${creds.password}'))}',
    };
  }

  @override
  Future<Uint8List> readBytes(
    MediaSourceConfig source,
    String entryId, {
    int maxBytes = 2 * 1024 * 1024,
  }) async {
    final uri = _resolveUri(source, entryId);
    _validateContainment(uri, _normalizeRootUri(source.rootLocator));
    final response = await http.request(
      uri,
      headers: await _sidecarHeaders(source),
      responseType: ResponseType.stream,
    );
    final body = response.data as ResponseBody;
    return collectSidecarBytes(body.stream, maxBytes);
  }

  @override
  Future<void> writeBytes(
    MediaSourceConfig source,
    String directoryId,
    String name,
    Uint8List bytes, {
    String? expectedEtag,
    bool createOnly = false,
  }) async {
    validateSidecarName(name);
    final directory = _resolveUri(source, directoryId);
    final uri = directory.replace(
      pathSegments: [
        ...directory.pathSegments.where((s) => s.isNotEmpty),
        name,
      ],
    );
    _validateContainment(uri, _normalizeRootUri(source.rootLocator));
    await http.request(
      uri,
      method: 'PUT',
      headers: {
        ...await _sidecarHeaders(source),
        'Content-Type': name.toLowerCase().endsWith('.nfo')
            ? 'application/xml; charset=utf-8'
            : 'application/octet-stream',
        'Content-Length': '${bytes.length}',
        if (createOnly) 'If-None-Match': '*',
        if (!createOnly && expectedEtag != null) 'If-Match': expectedEtag,
      },
      data: Stream.value(bytes),
      responseType: ResponseType.plain,
    );
  }

  @override
  Future<PlaybackResource> resolvePlayback(
    MediaSourceConfig source,
    String entryId,
  ) async {
    final targetUri = _resolveUri(source, entryId);
    final rootUri = _normalizeRootUri(source.rootLocator);
    _validateContainment(targetUri, rootUri);

    final displayName = _extractDisplayName(targetUri, entryId);

    return PlaybackResource(
      uri: targetUri,
      displayName: displayName,
      prepare: () async {
        try {
          return await playback.open(
            displayName: displayName,
            resolve: ({required bool refresh, CancelToken? cancelToken}) async {
              if (cancelToken?.isCancelled == true) {
                throw const PlaybackResourceException(
                  '操作已取消',
                  code: 'cancelled',
                );
              }
              final creds = await credentials.read(source.credentialRef);
              if (cancelToken?.isCancelled == true) {
                throw const PlaybackResourceException(
                  '操作已取消',
                  code: 'cancelled',
                );
              }

              final headers = <String, String>{};
              if (creds.username.isNotEmpty || creds.password.isNotEmpty) {
                final auth = base64Encode(
                  utf8.encode('${creds.username}:${creds.password}'),
                );
                headers['Authorization'] = 'Basic $auth';
              }
              return RemotePlaybackTarget(uri: targetUri, headers: headers);
            },
          );
        } on PlaybackResourceException {
          rethrow;
        } on DioException catch (e) {
          if (e.type == DioExceptionType.cancel) {
            throw const PlaybackResourceException('操作已取消', code: 'cancelled');
          }
          throw const PlaybackResourceException(
            '准备 WebDAV 播放资源失败',
            code: 'playback_prepare_failed',
          );
        } on MediaSourceException catch (e) {
          throw PlaybackResourceException(e.message, code: e.code);
        } catch (e, st) {
          AppLogger.instance.error(
            '准备 WebDAV 播放资源失败',
            error: e,
            stackTrace: st,
          );
          throw const PlaybackResourceException(
            '准备 WebDAV 播放资源失败',
            code: 'playback_prepare_failed',
          );
        }
      },
    );
  }

  /// 将流式/非流式响应体转换为字符串流
  Stream<String> _toStringStream(dynamic data) {
    if (data is ResponseBody) {
      return data.stream.cast<List<int>>().transform(utf8.decoder);
    }
    if (data is Stream<List<int>>) {
      return data.transform(utf8.decoder);
    }
    if (data is Stream<String>) {
      return data;
    }
    if (data is String) {
      return Stream.value(data);
    }
    if (data is List<int>) {
      return Stream.value(utf8.decode(data));
    }
    throw const MediaSourceException(
      'WebDAV 服务器返回了空的多状态响应',
      code: 'invalid_response',
    );
  }

  /// 规整并严格校验根目录 URL
  Uri _normalizeRootUri(String rootLocator) {
    final trimmed = rootLocator.trim();
    if (trimmed.isEmpty) {
      throw const MediaSourceException('WebDAV 根定位符不能为空', code: 'invalid_url');
    }

    _checkRawDotSegments(trimmed, 'WebDAV 根定位符');

    final uri = Uri.tryParse(trimmed);
    if (uri == null ||
        !uri.hasScheme ||
        (!uri.isScheme('http') && !uri.isScheme('https')) ||
        uri.host.isEmpty) {
      throw const MediaSourceException(
        'WebDAV 根定位符必须为有效的 http 或 https URL',
        code: 'invalid_url',
      );
    }
    // 严禁包含凭据、查询参数或片段标识符
    if (uri.userInfo.isNotEmpty || uri.hasQuery || uri.hasFragment) {
      throw const MediaSourceException(
        'WebDAV 根定位符格式不安全，严禁携带凭据、参数或片段',
        code: 'invalid_url',
      );
    }

    // 严禁包含点段
    for (final segment in uri.pathSegments) {
      if (segment == '.' || segment == '..') {
        throw const MediaSourceException(
          'WebDAV 根定位符包含无效的点路径段',
          code: 'invalid_url',
        );
      }
    }

    if (!uri.path.endsWith('/')) {
      return uri.replace(path: '${uri.path}/');
    }
    return uri;
  }

  /// 检查原始路径字符串中是否包含相对点段，防止 Uri.tryParse 预先消解 ..
  static void _checkRawDotSegments(String raw, String contextName) {
    var pathPart = raw;
    final schemeEnd = pathPart.indexOf('://');
    if (schemeEnd != -1) {
      pathPart = pathPart.substring(schemeEnd + 3);
      final firstSlash = pathPart.indexOf('/');
      if (firstSlash != -1) {
        pathPart = pathPart.substring(firstSlash);
      } else {
        pathPart = '';
      }
    }
    final queryIndex = pathPart.indexOf('?');
    if (queryIndex != -1) {
      pathPart = pathPart.substring(0, queryIndex);
    }
    final hashIndex = pathPart.indexOf('#');
    if (hashIndex != -1) {
      pathPart = pathPart.substring(0, hashIndex);
    }
    final segments = pathPart.split(RegExp(r'[/\\]'));
    for (final rawSegment in segments) {
      final normalized = rawSegment.replaceAll(
        RegExp(r'%2e', caseSensitive: false),
        '.',
      );
      if (normalized == '.' || normalized == '..') {
        throw MediaSourceException(
          '$contextName包含无效的点路径段',
          code: 'invalid_url',
        );
      }
    }
  }

  /// 校验 URI 是否严格包含在根目录之内
  void _validateContainment(Uri itemUri, Uri rootUri) {
    if (itemUri.scheme != rootUri.scheme ||
        itemUri.authority != rootUri.authority) {
      throw const MediaSourceException('访问路径逃出媒体源根目录', code: 'path_escape');
    }

    if (itemUri.userInfo.isNotEmpty ||
        itemUri.hasQuery ||
        itemUri.hasFragment) {
      throw const MediaSourceException('访问路径逃出媒体源根目录', code: 'path_escape');
    }

    final rootSegments = rootUri.pathSegments
        .where((s) => s.isNotEmpty)
        .toList();
    final itemSegments = itemUri.pathSegments
        .where((s) => s.isNotEmpty)
        .toList();

    for (final seg in itemSegments) {
      if (seg == '.' || seg == '..') {
        throw const MediaSourceException('访问路径逃出媒体源根目录', code: 'path_escape');
      }
    }

    if (itemSegments.length < rootSegments.length) {
      throw const MediaSourceException('访问路径逃出媒体源根目录', code: 'path_escape');
    }

    for (int i = 0; i < rootSegments.length; i++) {
      if (itemSegments[i] != rootSegments[i]) {
        throw const MediaSourceException('访问路径逃出媒体源根目录', code: 'path_escape');
      }
    }
  }

  /// 解析请求目标 URI 并严格实施根目录边界约束
  Uri _resolveUri(MediaSourceConfig source, String idOrLocator) {
    final rootUri = _normalizeRootUri(source.rootLocator);
    final trimmed = idOrLocator.trim();

    if (trimmed.isEmpty ||
        trimmed == source.rootLocator.trim() ||
        trimmed == rootUri.toString() ||
        '$trimmed/' == rootUri.toString()) {
      return rootUri;
    }

    // 处理以 http/https 开头的完整 URI
    if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
      final parsed = Uri.tryParse(trimmed);
      if (parsed == null) {
        throw const MediaSourceException('无效的 WebDAV URI', code: 'invalid_uri');
      }

      _validateContainment(parsed, rootUri);
      return parsed;
    }

    // 处理服务端绝对路径
    if (trimmed.startsWith('/')) {
      final resolved = rootUri.resolve(trimmed);
      _validateContainment(resolved, rootUri);
      return resolved;
    }

    // 处理逻辑相对 ID（保留字面量 % 与 #，绝不对逻辑 ID 再次 decodeComponent）
    final isTrailingSlash = trimmed.endsWith('/');
    final relativeSegments = trimmed
        .split('/')
        .where((s) => s.isNotEmpty)
        .toList();

    for (final segment in relativeSegments) {
      if (segment == '..' || segment == '.') {
        throw const MediaSourceException('访问路径逃出媒体源根目录', code: 'path_escape');
      }
    }

    final rootSegments = rootUri.pathSegments
        .where((s) => s.isNotEmpty)
        .toList();
    final allSegments = [
      ...rootSegments,
      ...relativeSegments,
      if (isTrailingSlash) '',
    ];

    final targetUri = rootUri.replace(pathSegments: allSegments);
    _validateContainment(targetUri, rootUri);
    return targetUri;
  }

  /// 构造 WebDAV 请求头，包括深度与安全凭据
  Future<Map<String, String>> _buildHeaders(
    MediaSourceConfig source, {
    required int depth,
  }) async {
    final headers = <String, String>{
      'Depth': depth.toString(),
      'Content-Type': 'application/xml; charset="utf-8"',
      'Accept': 'application/xml, text/xml, */*',
    };

    final creds = await credentials.read(source.credentialRef);
    if (creds.username.isNotEmpty || creds.password.isNotEmpty) {
      final auth = base64Encode(
        utf8.encode('${creds.username}:${creds.password}'),
      );
      headers['Authorization'] = 'Basic $auth';
    }

    return headers;
  }

  /// 提取展示名称
  String _extractDisplayName(Uri uri, String entryId) {
    final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
    if (segments.isNotEmpty) {
      return segments.last;
    }
    final rawSegments = entryId.split('/').where((s) => s.isNotEmpty).toList();
    if (rawSegments.isNotEmpty) {
      return rawSegments.last;
    }
    return '视频';
  }

  /// 查找 XML 树中所有的 response 节点（忽略前缀与大小写）
  List<XmlElement> _findResponses(XmlDocument doc) {
    return doc.descendants
        .whereType<XmlElement>()
        .where((e) => e.localName.toLowerCase() == 'response')
        .toList();
  }

  /// 解析单个 response 节点，失败或被拒绝时显式抛出安全异常，绝不静默吞没
  _ParsedWebDavResponse _parseResponse(
    XmlElement responseEl,
    Uri targetUri,
    Uri rootUri,
  ) {
    final hrefEl = responseEl.descendants
        .whereType<XmlElement>()
        .firstWhereOrNull((e) => e.localName.toLowerCase() == 'href');
    if (hrefEl == null || hrefEl.innerText.trim().isEmpty) {
      throw const MediaSourceException(
        'WebDAV 响应包含缺少 href 的无效条目',
        code: 'invalid_response',
      );
    }

    final rawHref = hrefEl.innerText.trim();
    final Uri itemUri;
    try {
      itemUri = targetUri.resolve(rawHref);
    } catch (_) {
      throw const MediaSourceException(
        'WebDAV 响应包含无法解析的 href',
        code: 'invalid_response',
      );
    }

    _validateContainment(itemUri, rootUri);

    // 检查是否有顶级直接状态错误
    final directStatusEl = responseEl.children
        .whereType<XmlElement>()
        .firstWhereOrNull((e) => e.localName.toLowerCase() == 'status');
    if (directStatusEl != null) {
      final code = _parseStatusCode(directStatusEl.innerText);
      if (code != null && (code < 200 || code >= 300)) {
        _throwForStatusCode(code);
      }
    }

    final propstats = responseEl.descendants
        .whereType<XmlElement>()
        .where((e) => e.localName.toLowerCase() == 'propstat')
        .toList();

    bool has200Propstat = false;
    int? failureStatusCode;
    int? deniedStatusCode;
    bool hasResourceType = false;

    bool isDirectory = rawHref.endsWith('/');
    int? size;
    DateTime? modifiedAt;
    String? etag;

    for (final propstat in propstats) {
      final statusEl = propstat.descendants
          .whereType<XmlElement>()
          .firstWhereOrNull((e) => e.localName.toLowerCase() == 'status');
      final code = _parseStatusCode(statusEl?.innerText);
      if (code == HttpStatus.unauthorized || code == HttpStatus.forbidden) {
        deniedStatusCode = code;
        break;
      }

      if (code == HttpStatus.ok) {
        has200Propstat = true;
      } else if (code != null &&
          code != HttpStatus.notFound &&
          failureStatusCode == null) {
        failureStatusCode = code;
      }

      if (code != HttpStatus.ok) {
        continue;
      }

      final propEl = propstat.descendants
          .whereType<XmlElement>()
          .firstWhereOrNull((e) => e.localName.toLowerCase() == 'prop');
      if (propEl == null) {
        continue;
      }

      final resTypeEl = propEl.descendants
          .whereType<XmlElement>()
          .firstWhereOrNull((e) => e.localName.toLowerCase() == 'resourcetype');
      if (resTypeEl != null) {
        hasResourceType = true;
        final isCol = resTypeEl.descendants.whereType<XmlElement>().any(
          (e) => e.localName.toLowerCase() == 'collection',
        );
        if (isCol) {
          isDirectory = true;
        }
      }

      final lenEl = propEl.descendants.whereType<XmlElement>().firstWhereOrNull(
        (e) => e.localName.toLowerCase() == 'getcontentlength',
      );
      if (lenEl != null) {
        final parsedLen = int.tryParse(lenEl.innerText.trim());
        if (parsedLen != null) {
          size = parsedLen;
        }
      }

      final modEl = propEl.descendants.whereType<XmlElement>().firstWhereOrNull(
        (e) => e.localName.toLowerCase() == 'getlastmodified',
      );
      if (modEl != null) {
        final parsedDate = _parseHttpDate(modEl.innerText);
        if (parsedDate != null) {
          modifiedAt = parsedDate;
        }
      }

      final etagEl = propEl.descendants
          .whereType<XmlElement>()
          .firstWhereOrNull((e) => e.localName.toLowerCase() == 'getetag');
      if (etagEl != null && etagEl.innerText.trim().isNotEmpty) {
        etag = etagEl.innerText.trim();
      }
    }

    // 严密传播 401/403 权限拒绝：即使部分属性返回 200 也必须传播拒绝
    if (deniedStatusCode != null) {
      _throwForStatusCode(deniedStatusCode);
    }

    if (!has200Propstat) {
      if (failureStatusCode != null) {
        _throwForStatusCode(failureStatusCode);
      }
      throw const MediaSourceException(
        'WebDAV 响应条目缺少有效属性状态',
        code: 'invalid_response',
      );
    }

    // 必须成功获取 resourcetype（或 URI 显式以 / 结尾）才能明确断定条目类型
    if (!hasResourceType && !rawHref.endsWith('/')) {
      throw const MediaSourceException(
        'WebDAV 响应条目缺少明确的 resourcetype 属性，无法判定条目类型',
        code: 'invalid_response',
      );
    }

    return _ParsedWebDavResponse(
      uri: itemUri,
      isDirectory: isDirectory,
      size: isDirectory ? null : size,
      modifiedAt: modifiedAt,
      etag: etag,
    );
  }

  /// 精准解析 HTTP 状态行中的 3 位状态码
  int? _parseStatusCode(String? statusText) {
    if (statusText == null || statusText.trim().isEmpty) return null;
    final parts = statusText.trim().split(RegExp(r'\s+'));
    if (parts.length >= 2) {
      return int.tryParse(parts[1]);
    }
    return int.tryParse(parts[0]);
  }

  /// 依据 HTTP 状态码抛出明确且安全的异常
  Never _throwForStatusCode(int code) {
    switch (code) {
      case HttpStatus.unauthorized:
        throw const MediaSourceException(
          '访问媒体源认证失败，凭据无效',
          code: 'unauthorized',
        );
      case HttpStatus.forbidden:
        throw const MediaSourceException(
          '无权访问 WebDAV 资源 (403 Forbidden)',
          code: 'forbidden',
        );
      case HttpStatus.notFound:
        throw const MediaSourceException(
          '请求的文件或资源不存在 (404)',
          code: 'not_found',
        );
      default:
        throw MediaSourceException(
          'WebDAV 响应条目返回错误状态 ($code)',
          code: 'remote_error',
        );
    }
  }

  /// 比较两个 URI 的路径是否等同（忽略末尾斜杠）
  bool _isPathMatch(Uri a, Uri b) {
    if (a.scheme != b.scheme || a.authority != b.authority) return false;
    final segsA = a.pathSegments.where((s) => s.isNotEmpty).toList();
    final segsB = b.pathSegments.where((s) => s.isNotEmpty).toList();
    if (segsA.length != segsB.length) return false;
    for (int i = 0; i < segsA.length; i++) {
      if (segsA[i] != segsB[i]) return false;
    }
    return true;
  }

  /// 解析 HTTP-date 格式（RFC 1123 或 ISO 8601）
  DateTime? _parseHttpDate(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    final text = raw.trim();
    try {
      return HttpDate.parse(text);
    } catch (_) {}
    try {
      return DateTime.parse(text);
    } catch (_) {}
    return null;
  }
}

class _ParsedWebDavResponse {
  const _ParsedWebDavResponse({
    required this.uri,
    required this.isDirectory,
    this.size,
    this.modifiedAt,
    this.etag,
  });

  final Uri uri;
  final bool isDirectory;
  final int? size;
  final DateTime? modifiedAt;
  final String? etag;
}

extension _IterableFirstWhereOrNull<E> on Iterable<E> {
  E? firstWhereOrNull(bool Function(E element) test) {
    for (final element in this) {
      if (test(element)) return element;
    }
    return null;
  }
}
