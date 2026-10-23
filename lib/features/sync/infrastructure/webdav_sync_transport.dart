import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:xml/xml.dart';

import '../../sources/domain/source_models.dart';
import '../../sources/infrastructure/remote_http_client.dart';
import '../domain/sync_models.dart';
import '../domain/sync_transport.dart';
import 'sync_configuration_store.dart';

/// WebDAV 同步传输实现
///
/// 遵循 M6 契约规范：
/// - 基于 RFC 4918 WebDAV 协议；
/// - 自动通过 MKCOL 创建 `reelva-sync-v1` 同步专用集合目录；
/// - 通过 PROPFIND (Depth 1) 枚举远程批次；严格校验 207 Multi-Status 与根节点；
/// - 仅接受属于 syncDirUri 同源直接子级项的批次文件，排除跨源、凭据/参数注入、目录与非同步文件，并执行去重；
/// - 条件 PUT (`If-None-Match: *`) 写入不可变批次文件；
/// - 412 Precondition Failed 时自动拉取远程批次比对语义内容，支持崩溃安全重试；
/// - 严密校验批次文件名、JSON 格式及设备 ID / 序列号；
/// - 错误安全脱敏：严禁在异常中暴露未过滤的原始异常、凭据或敏感信息。
class WebDavSyncTransport implements SyncTransport {
  WebDavSyncTransport({required this.http, required this.configuration});

  final RemoteHttpClient http;
  final SyncConfiguration configuration;

  bool _collectionEnsured = false;

  static final RegExp _batchFileNameRegex = RegExp(
    r'^([0-9a-f]{32})-([1-9][0-9]*)\.json$',
  );

  static const String _propfindXml =
      '<?xml version="1.0" encoding="utf-8" ?>\n'
      '<D:propfind xmlns:D="DAV:">\n'
      '  <D:prop>\n'
      '    <D:resourcetype/>\n'
      '  </D:prop>\n'
      '</D:propfind>';

  Uri get _syncDirUri => configuration.endpoint.resolve('reelva-sync-v1/');

  Uri _batchUri(String fileName) => _syncDirUri.resolve(fileName);

  Map<String, String> _buildHeaders({
    String? contentType,
    int? depth,
    String? ifNoneMatch,
  }) {
    final headers = <String, String>{};
    if (configuration.username.isNotEmpty ||
        configuration.password.isNotEmpty) {
      final rawAuth = '${configuration.username}:${configuration.password}';
      final token = base64Encode(utf8.encode(rawAuth));
      headers[HttpHeaders.authorizationHeader] = 'Basic $token';
    }
    if (contentType != null) {
      headers[HttpHeaders.contentTypeHeader] = contentType;
    }
    if (depth != null) {
      headers['Depth'] = depth.toString();
    }
    if (ifNoneMatch != null) {
      headers[HttpHeaders.ifNoneMatchHeader] = ifNoneMatch;
    }
    return headers;
  }

  /// 确保远程 `reelva-sync-v1/` 目录集合已创建
  Future<void> _ensureCollectionExists() async {
    if (_collectionEnsured) return;

    try {
      final response = await http.request(
        _syncDirUri,
        method: 'MKCOL',
        headers: _buildHeaders(),
        allowedStatusCodes: {
          HttpStatus.created, // 201 Created
          HttpStatus.methodNotAllowed, // 405 Method Not Allowed (集合已存在)
          HttpStatus.ok, // 200 OK
          HttpStatus.noContent, // 204 No Content
          HttpStatus.conflict, // 409 Conflict
        },
      );

      final status = response.statusCode ?? 0;
      if (status == HttpStatus.conflict) {
        throw const SyncException('WebDAV 同步集合创建失败: 父目录不存在 (409 Conflict)');
      }
      _collectionEnsured = true;
    } on MediaSourceException catch (e) {
      throw SyncException('WebDAV 创建同步集合失败: ${e.message}');
    } catch (e) {
      if (e is SyncException) rethrow;
      throw const SyncException('WebDAV 创建同步集合失败');
    }
  }

  @override
  Future<List<SyncRemoteBatch>> listBatches() async {
    final headers = _buildHeaders(
      contentType: 'application/xml; charset="utf-8"',
      depth: 1,
    );
    headers[HttpHeaders.acceptHeader] = 'application/xml, text/xml, */*';

    final Response<dynamic> response;
    try {
      response = await http.request(
        _syncDirUri,
        method: 'PROPFIND',
        headers: headers,
        data: _propfindXml,
        responseType: ResponseType.plain,
        allowedStatusCodes: {
          HttpStatus.notFound, // 404 (目录尚不存在，返回空批次列表)
        },
      );
    } on MediaSourceException catch (e) {
      throw SyncException('列出 WebDAV 同步批次失败: ${e.message}');
    } catch (e) {
      if (e is SyncException) rethrow;
      throw const SyncException('列出 WebDAV 同步批次失败');
    }

    if (response.statusCode == HttpStatus.notFound) {
      return <SyncRemoteBatch>[];
    }

    // 严格要求 207 Multi-Status
    if (response.statusCode != 207) {
      throw const SyncException('WebDAV PROPFIND 响应状态非 207 Multi-Status');
    }

    final dynamic bodyData = response.data;
    if (bodyData == null || bodyData is! String || bodyData.trim().isEmpty) {
      throw const SyncException('WebDAV PROPFIND 响应内容为空');
    }

    final XmlDocument doc;
    try {
      doc = XmlDocument.parse(bodyData);
    } catch (_) {
      throw const SyncException('解析 WebDAV PROPFIND 响应 XML 失败');
    }

    final root = doc.rootElement;
    if (root.localName != 'multistatus' || root.namespaceUri != 'DAV:') {
      throw const SyncException('WebDAV 响应不是有效的 DAV multistatus');
    }

    final responseElements = doc.descendants
        .whereType<XmlElement>()
        .where((e) => e.localName.toLowerCase() == 'response')
        .toList();

    final syncSegments = _syncDirUri.pathSegments
        .where((s) => s.isNotEmpty)
        .toList();

    final deduplicatedBatches = <String, SyncRemoteBatch>{};

    for (final resp in responseElements) {
      final hrefEl = resp.descendants
          .whereType<XmlElement>()
          .where((e) => e.localName.toLowerCase() == 'href')
          .firstOrNull;
      if (hrefEl == null || hrefEl.innerText.trim().isEmpty) {
        throw const SyncException('WebDAV 响应条目缺少 href 元素');
      }

      final rawHref = hrefEl.innerText.trim();
      final Uri itemUri;
      try {
        itemUri = _syncDirUri.resolve(rawHref);
      } catch (_) {
        throw const SyncException('WebDAV 响应条目 href 无法解析');
      }

      // 忽略目录集合类型节点与目录自身
      final isCollection = resp.descendants.whereType<XmlElement>().any(
        (e) =>
            e.localName.toLowerCase() == 'resourcetype' &&
            e.descendants.whereType<XmlElement>().any(
              (child) => child.localName.toLowerCase() == 'collection',
            ),
      );
      if (isCollection || itemUri.path.endsWith('/')) {
        continue;
      }

      // 必须同源且无 query/fragment/userInfo
      if (itemUri.scheme != _syncDirUri.scheme ||
          itemUri.authority != _syncDirUri.authority ||
          itemUri.userInfo.isNotEmpty ||
          itemUri.hasQuery ||
          itemUri.hasFragment) {
        continue;
      }

      final itemSegments = itemUri.pathSegments
          .where((s) => s.isNotEmpty)
          .toList();

      // 严格要求为 syncDirUri 的直接子级条目（层级严格为 syncSegments.length + 1）
      if (itemSegments.length != syncSegments.length + 1) {
        continue;
      }

      bool isDirectChild = true;
      for (int i = 0; i < syncSegments.length; i++) {
        if (itemSegments[i] != syncSegments[i]) {
          isDirectChild = false;
          break;
        }
      }
      if (!isDirectChild) {
        continue;
      }

      final fileName = itemSegments.last;
      final match = _batchFileNameRegex.firstMatch(fileName);
      if (match == null) {
        // 刻意跳过非同步批次命名的文件
        continue;
      }

      // 校验该批次节点的 propstat 或 response 状态
      final respStatusEl = resp.children
          .whereType<XmlElement>()
          .where((e) => e.localName.toLowerCase() == 'status')
          .firstOrNull;
      if (respStatusEl != null) {
        final text = respStatusEl.innerText.trim();
        if (!text.contains(' 200') && !text.startsWith('200')) {
          throw SyncException('WebDAV 批次条目访问失败: $fileName');
        }
      }

      final propstats = resp.descendants.whereType<XmlElement>().where(
        (e) => e.localName.toLowerCase() == 'propstat',
      );
      if (propstats.isNotEmpty) {
        bool hasSuccessfulPropstat = false;
        for (final ps in propstats) {
          final psStatusEl = ps.descendants
              .whereType<XmlElement>()
              .where((e) => e.localName.toLowerCase() == 'status')
              .firstOrNull;
          if (psStatusEl != null) {
            final text = psStatusEl.innerText.trim();
            if (text.contains(' 200') ||
                text.startsWith('200') ||
                text.contains(' 207') ||
                text.startsWith('207')) {
              hasSuccessfulPropstat = true;
              break;
            }
          }
        }
        if (!hasSuccessfulPropstat) {
          throw SyncException('WebDAV 批次条目属性状态异常: $fileName');
        }
      }

      final deviceId = match.group(1)!;
      final sequence = int.parse(match.group(2)!);
      final batchKey = '$deviceId-$sequence';

      // 相同批次去重
      deduplicatedBatches[batchKey] = SyncRemoteBatch(
        deviceId: deviceId,
        sequence: sequence,
      );
    }

    return deduplicatedBatches.values.toList();
  }

  @override
  Future<SyncBatch> download(SyncRemoteBatch batch) async {
    final targetUri = _batchUri(batch.fileName);
    final headers = _buildHeaders();
    headers[HttpHeaders.acceptHeader] = 'application/json, */*';

    final Response<dynamic> response;
    try {
      response = await http.request(
        targetUri,
        method: 'GET',
        headers: headers,
        responseType: ResponseType.plain,
      );
    } on MediaSourceException catch (e) {
      throw SyncException('下载同步批次 ${batch.fileName} 失败: ${e.message}');
    } catch (e) {
      if (e is SyncException) rethrow;
      throw SyncException('下载同步批次 ${batch.fileName} 失败');
    }

    final status = response.statusCode ?? 0;
    if (status != HttpStatus.ok) {
      throw SyncException('下载同步批次 ${batch.fileName} 状态异常: $status');
    }

    final dynamic bodyData = response.data;
    if (bodyData is! String || bodyData.trim().isEmpty) {
      throw SyncException('下载的批次 ${batch.fileName} 数据为空');
    }

    final dynamic decoded;
    try {
      decoded = jsonDecode(bodyData);
    } catch (_) {
      throw SyncException('下载的批次 ${batch.fileName} 不是有效 JSON');
    }

    if (decoded is! Map<String, dynamic>) {
      throw SyncException('下载的批次 ${batch.fileName} 数据结构不符合要求');
    }

    final SyncBatch syncBatch;
    try {
      syncBatch = SyncBatch.fromJson(decoded);
    } on SyncException {
      rethrow;
    } catch (_) {
      throw SyncException('校验同步批次 ${batch.fileName} 数据模型失败');
    }

    if (syncBatch.deviceId != batch.deviceId ||
        syncBatch.sequence != batch.sequence) {
      throw SyncException(
        '批次元数据不一致: 期望 ${batch.fileName}，实际得到 ${syncBatch.fileName}',
      );
    }

    return syncBatch;
  }

  @override
  Future<void> upload(SyncBatch batch) async {
    await _ensureCollectionExists();

    final targetUri = _batchUri(batch.fileName);
    final payload = jsonEncode(batch.toJson());
    final headers = _buildHeaders(
      contentType: 'application/json; charset=utf-8',
      ifNoneMatch: '*',
    );

    final Response<dynamic> response;
    try {
      response = await http.request(
        targetUri,
        method: 'PUT',
        headers: headers,
        data: payload,
        responseType: ResponseType.plain,
        allowedStatusCodes: {
          HttpStatus.preconditionFailed, // 412 Precondition Failed
        },
      );
    } on MediaSourceException catch (e) {
      throw SyncException('上传同步批次 ${batch.fileName} 失败: ${e.message}');
    } catch (e) {
      if (e is SyncException) rethrow;
      throw SyncException('上传同步批次 ${batch.fileName} 失败');
    }

    if (response.statusCode == HttpStatus.preconditionFailed) {
      // 412: 远程已存在该文件，尝试拉取比对语义内容（崩溃安全重试）
      final remoteBatch = await download(
        SyncRemoteBatch(deviceId: batch.deviceId, sequence: batch.sequence),
      );

      if (remoteBatch == batch) {
        // 语义完全一致，视为先前上传已成功落盘
        return;
      }

      throw SyncException('远程同步批次已存在且内容不一致: ${batch.fileName}');
    }

    final status = response.statusCode ?? 0;
    if (status != HttpStatus.created &&
        status != HttpStatus.ok &&
        status != HttpStatus.noContent) {
      throw SyncException('上传同步批次 ${batch.fileName} 返回非成功状态码: $status');
    }
  }
}
