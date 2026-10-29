import 'package:flutter/foundation.dart';

import 'openlist_models.dart';

const List<String> defaultVideoExtensions = [
  'mkv',
  'mp4',
  'avi',
  'mov',
  'm4v',
  'ts',
  'webm',
];

const List<String> defaultExcludedDirectories = [
  '.cache',
  r'$RECYCLE.BIN',
  'System Volume Information',
];

@immutable
class MediaSourceConfig {
  const MediaSourceConfig({
    required this.id,
    required this.kind,
    required this.name,
    required this.rootLocator,
    this.credentialRef,
    this.enabled = true,
    this.extensions = defaultVideoExtensions,
    this.excludedDirectories = defaultExcludedDirectories,
    this.scanRevision = 0,
    this.lastScanAt,
    this.errorMessage,
  });

  final int id;
  final String kind;
  final String name;
  final String rootLocator;
  final String? credentialRef;
  final bool enabled;
  final List<String> extensions;
  final List<String> excludedDirectories;
  final int scanRevision;
  final DateTime? lastScanAt;
  final String? errorMessage;

  MediaSourceConfig copyWith({
    int? id,
    String? kind,
    String? name,
    String? rootLocator,
    String? credentialRef,
    bool clearCredentialRef = false,
    bool? enabled,
    List<String>? extensions,
    List<String>? excludedDirectories,
    int? scanRevision,
    DateTime? lastScanAt,
    String? errorMessage,
    bool clearErrorMessage = false,
  }) {
    return MediaSourceConfig(
      id: id ?? this.id,
      kind: kind ?? this.kind,
      name: name ?? this.name,
      rootLocator: rootLocator ?? this.rootLocator,
      credentialRef: clearCredentialRef
          ? null
          : (credentialRef ?? this.credentialRef),
      enabled: enabled ?? this.enabled,
      extensions: extensions ?? this.extensions,
      excludedDirectories: excludedDirectories ?? this.excludedDirectories,
      scanRevision: scanRevision ?? this.scanRevision,
      lastScanAt: lastScanAt ?? this.lastScanAt,
      errorMessage: clearErrorMessage
          ? null
          : (errorMessage ?? this.errorMessage),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MediaSourceConfig &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          kind == other.kind &&
          name == other.name &&
          rootLocator == other.rootLocator &&
          credentialRef == other.credentialRef &&
          enabled == other.enabled &&
          listEquals(extensions, other.extensions) &&
          listEquals(excludedDirectories, other.excludedDirectories) &&
          scanRevision == other.scanRevision &&
          lastScanAt == other.lastScanAt &&
          errorMessage == other.errorMessage;

  @override
  int get hashCode => Object.hash(
    id,
    kind,
    name,
    rootLocator,
    credentialRef,
    enabled,
    Object.hashAll(extensions),
    Object.hashAll(excludedDirectories),
    scanRevision,
    lastScanAt,
    errorMessage,
  );

  @override
  String toString() =>
      'MediaSourceConfig(id: $id, kind: $kind, name: $name, rootLocator: $rootLocator, credentialRef: $credentialRef, enabled: $enabled, scanRevision: $scanRevision, lastScanAt: $lastScanAt, errorMessage: $errorMessage)';
}

@immutable
class DirectorySelection {
  const DirectorySelection({
    required this.kind,
    required this.rootLocator,
    required this.name,
  });

  final String kind;
  final String rootLocator;
  final String name;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DirectorySelection &&
          runtimeType == other.runtimeType &&
          kind == other.kind &&
          rootLocator == other.rootLocator &&
          name == other.name;

  @override
  int get hashCode => Object.hash(kind, rootLocator, name);

  @override
  String toString() =>
      'DirectorySelection(kind: $kind, rootLocator: $rootLocator, name: $name)';
}

@immutable
class MediaEntry {
  const MediaEntry({
    required this.externalId,
    required this.locator,
    required this.name,
    required this.isDirectory,
    this.size,
    this.modifiedAt,
    this.etag,
  });

  final String externalId;
  final String locator;
  final String name;
  final bool isDirectory;
  final int? size;
  final DateTime? modifiedAt;
  final String? etag;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MediaEntry &&
          runtimeType == other.runtimeType &&
          externalId == other.externalId &&
          locator == other.locator &&
          name == other.name &&
          isDirectory == other.isDirectory &&
          size == other.size &&
          modifiedAt == other.modifiedAt &&
          etag == other.etag;

  @override
  int get hashCode => Object.hash(
    externalId,
    locator,
    name,
    isDirectory,
    size,
    modifiedAt,
    etag,
  );

  @override
  String toString() =>
      'MediaEntry(externalId: $externalId, locator: $locator, name: $name, isDirectory: $isDirectory, size: $size, modifiedAt: $modifiedAt, etag: $etag)';
}

@immutable
class MediaStat {
  const MediaStat({this.size, this.modifiedAt, this.etag});

  final int? size;
  final DateTime? modifiedAt;
  final String? etag;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MediaStat &&
          runtimeType == other.runtimeType &&
          size == other.size &&
          modifiedAt == other.modifiedAt &&
          etag == other.etag;

  @override
  int get hashCode => Object.hash(size, modifiedAt, etag);

  @override
  String toString() =>
      'MediaStat(size: $size, modifiedAt: $modifiedAt, etag: $etag)';
}

@immutable
class LibraryVideo {
  const LibraryVideo({
    required this.fileId,
    required this.sourceId,
    required this.externalId,
    required this.locator,
    required this.title,
    required this.fileName,
    required this.sourceName,
    required this.available,
    this.sourceError,
  });

  final int fileId;
  final int sourceId;
  final String externalId;
  final String locator;
  final String title;
  final String fileName;
  final String sourceName;
  final bool available;
  final String? sourceError;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LibraryVideo &&
          runtimeType == other.runtimeType &&
          fileId == other.fileId &&
          sourceId == other.sourceId &&
          externalId == other.externalId &&
          locator == other.locator &&
          title == other.title &&
          fileName == other.fileName &&
          sourceName == other.sourceName &&
          available == other.available &&
          sourceError == other.sourceError;

  @override
  int get hashCode => Object.hash(
    fileId,
    sourceId,
    externalId,
    locator,
    title,
    fileName,
    sourceName,
    available,
    sourceError,
  );

  @override
  String toString() =>
      'LibraryVideo(fileId: $fileId, sourceId: $sourceId, externalId: $externalId, locator: $locator, title: $title, fileName: $fileName, sourceName: $sourceName, available: $available, sourceError: $sourceError)';
}

class MediaSourceException implements Exception {
  const MediaSourceException(this.message, {this.code});

  final String message;
  final String? code;

  @override
  String toString() => code == null
      ? 'MediaSourceException: $message'
      : 'MediaSourceException($code): $message';
}

void _checkRawDotSegments(String raw, String contextName) {
  var pathPart = raw.trim();
  final schemeEnd = pathPart.indexOf('://');
  if (schemeEnd != -1) {
    pathPart = pathPart.substring(schemeEnd + 3);
    final firstSlash = pathPart.indexOf('/');
    if (firstSlash != -1) {
      pathPart = pathPart.substring(firstSlash);
    } else {
      pathPart = '';
    }
  } else if (pathPart.startsWith(r'\\') || pathPart.startsWith('//')) {
    pathPart = pathPart.substring(2);
    final firstSlash = pathPart.indexOf(RegExp(r'[/\\]'));
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
        '$contextName不能包含相对路径或点段 (.)/(..)',
        code: 'invalid_path_segments',
      );
    }
  }
}

/// 校验并规范化各类媒体源的根目录定位符
///
/// 严格拒绝携带用户名、密码、Query 参数或非预期 Fragment 的 URL；
/// 拒绝编码分隔符 (%2F/%5C) 与点段相对路径 (./..)；规范化重复斜杠；
/// 允许 SMB host:port，正确保留端口与 Unicode 路径。
String sanitizeAndValidateRootLocator({
  required String kind,
  required String rawInput,
}) {
  final trimmed = rawInput.trim();
  if (trimmed.isEmpty) {
    throw const MediaSourceException('根目录地址不能为空', code: 'invalid_url');
  }

  if (trimmed.contains('%2f') ||
      trimmed.contains('%2F') ||
      trimmed.contains('%5c') ||
      trimmed.contains('%5C')) {
    throw const MediaSourceException(
      '根目录路径不能包含编码的目录分隔符 (%2F / %5C)',
      code: 'invalid_path_separators',
    );
  }

  if (kind != 'local' && kind != 'androidSaf') {
    _checkRawDotSegments(trimmed, '根目录路径');
  }

  switch (kind) {
    case 'local':
    case 'androidSaf':
      return trimmed;

    case 'openlist':
      final root = OpenListRoot.parse(trimmed);
      return buildOpenListRoot(root.accountId, root.path);

    case 'webdav':
      final uri = Uri.tryParse(trimmed);
      if (uri == null || (!uri.isScheme('http') && !uri.isScheme('https'))) {
        throw const MediaSourceException(
          'WebDAV 地址必须是以 http:// 或 https:// 开头的有效网址',
          code: 'invalid_url',
        );
      }
      if (uri.host.isEmpty) {
        throw const MediaSourceException(
          'WebDAV 地址主机名不能为空',
          code: 'invalid_url',
        );
      }
      if (uri.userInfo.isNotEmpty) {
        throw const MediaSourceException(
          'WebDAV 根目录 URL 中包含用户名或密码，请移除并在下方凭据输入框中填写',
          code: 'credentials_in_url',
        );
      }
      if (uri.hasQuery) {
        throw const MediaSourceException(
          'WebDAV 根目录 URL 不支持携带 Query 参数，请移除',
          code: 'query_in_url',
        );
      }
      if (uri.hasFragment) {
        throw const MediaSourceException(
          'WebDAV 根目录地址不支持携带 # 片段参数，请移除',
          code: 'fragment_not_allowed',
        );
      }
      for (final segment in uri.pathSegments) {
        if (segment == '.' || segment == '..') {
          throw const MediaSourceException(
            '根目录路径不能包含相对路径或点段 (.)/(..)',
            code: 'invalid_path_segments',
          );
        }
        if (segment.contains(r'\')) {
          throw const MediaSourceException(
            'HTTP 协议路径不能包含反斜杠',
            code: 'invalid_path_separators',
          );
        }
      }

      final cleanSegments = uri.pathSegments
          .where((s) => s.isNotEmpty)
          .toList();
      final cleanUri = Uri(
        scheme: uri.scheme.toLowerCase(),
        host: uri.host.toLowerCase(),
        port: uri.hasPort ? uri.port : null,
        pathSegments: [...cleanSegments, ''],
      );
      return cleanUri.toString();

    case 'smb':
      var normalized = trimmed.replaceAll(r'\', '/');
      if (normalized.startsWith('//')) {
        normalized = normalized.substring(2);
      }
      if (!normalized.toLowerCase().startsWith('smb://')) {
        normalized = 'smb://$normalized';
      }

      final uri = Uri.tryParse(normalized);
      if (uri == null || uri.host.isEmpty) {
        throw const MediaSourceException(
          'SMB 路径格式不正确，主机名不能为空',
          code: 'invalid_smb_path',
        );
      }
      if (uri.userInfo.isNotEmpty) {
        throw const MediaSourceException(
          'SMB 路径中包含用户名或密码，请移除并在下方凭据输入框中填写',
          code: 'credentials_in_url',
        );
      }
      if (uri.hasQuery) {
        throw const MediaSourceException(
          'SMB 路径不支持携带 Query 参数，请移除',
          code: 'query_in_url',
        );
      }
      if (uri.hasFragment) {
        throw const MediaSourceException(
          'SMB 路径不支持携带 # 片段参数，请移除',
          code: 'fragment_not_allowed',
        );
      }
      for (final segment in uri.pathSegments) {
        if (segment == '.' || segment == '..') {
          throw const MediaSourceException(
            'SMB 路径不能包含相对路径或点段 (.)/(..)',
            code: 'invalid_path_segments',
          );
        }
      }

      final cleanSegments = uri.pathSegments
          .where((s) => s.isNotEmpty)
          .toList();
      if (cleanSegments.isEmpty) {
        throw const MediaSourceException(
          'SMB 路径必须指定共享名 (Share)，例如 smb://server/share',
          code: 'invalid_smb_path',
        );
      }

      final cleanUri = Uri(
        scheme: 'smb',
        host: uri.host.toLowerCase(),
        port: uri.hasPort ? uri.port : null,
        pathSegments: cleanSegments,
      );
      return cleanUri.toString();

    default:
      throw MediaSourceException('不支持的媒体源类型: $kind', code: 'unsupported_kind');
  }
}
