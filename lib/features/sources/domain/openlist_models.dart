import 'source_models.dart';

const openListDrivers = <String, String>{
  'BaiduNetdisk': '百度网盘',
  'Quark': '夸克网盘',
  '115 Open': '115 网盘',
  '123 Open': '123 云盘',
};

String normalizeOpenListPath(String value) {
  if (value.contains('\\') || value.contains('\u0000')) {
    throw const MediaSourceException('网盘路径无效', code: 'invalid_cloud_path');
  }
  final parts = value.split('/').where((part) => part.isNotEmpty).toList();
  if (parts.any((part) => part == '.' || part == '..')) {
    throw const MediaSourceException(
      '网盘路径不能包含相对跳转',
      code: 'invalid_cloud_path',
    );
  }
  return parts.isEmpty ? '/' : '/${parts.join('/')}';
}

String buildOpenListRoot(String accountId, String path) {
  if (!RegExp(r'^[0-9a-f]{32}$').hasMatch(accountId)) {
    throw const MediaSourceException('网盘账号标识无效', code: 'invalid_cloud_account');
  }
  final normalized = normalizeOpenListPath(path);
  return Uri(
    scheme: 'openlist',
    host: accountId,
    pathSegments: [
      ...normalized.split('/').where((part) => part.isNotEmpty),
      '',
    ],
  ).toString();
}

class OpenListRoot {
  const OpenListRoot(this.accountId, this.path);

  factory OpenListRoot.parse(String locator) {
    final uri = Uri.tryParse(locator);
    if (uri == null ||
        uri.scheme != 'openlist' ||
        uri.userInfo.isNotEmpty ||
        uri.hasPort ||
        uri.hasQuery ||
        uri.hasFragment ||
        !RegExp(r'^[0-9a-f]{32}$').hasMatch(uri.host) ||
        uri.pathSegments.any(
          (part) => part.contains('/') || part.contains('\\'),
        )) {
      throw const MediaSourceException('网盘根目录无效', code: 'invalid_cloud_root');
    }
    return OpenListRoot(
      uri.host,
      normalizeOpenListPath(uri.pathSegments.join('/')),
    );
  }

  final String accountId;
  final String path;

  String resolve(String entryId, String rootLocator) {
    if (entryId == rootLocator || entryId.isEmpty) return path;
    if (entryId.startsWith('/') || entryId.contains('://')) {
      throw const MediaSourceException('媒体条目不在网盘根目录中', code: 'outside_root');
    }
    return normalizeOpenListPath('${path == '/' ? '' : path}/$entryId');
  }

  String relative(String absolutePath) {
    final normalized = normalizeOpenListPath(absolutePath);
    final prefix = path == '/' ? '/' : '$path/';
    if (!normalized.startsWith(prefix) || normalized == path) {
      throw const MediaSourceException('媒体条目不在网盘根目录中', code: 'outside_root');
    }
    return normalized.substring(prefix.length);
  }
}

class OpenListEntry {
  const OpenListEntry({
    required this.name,
    required this.path,
    required this.isDirectory,
    this.size,
    this.modifiedAt,
  });
  final String name;
  final String path;
  final bool isDirectory;
  final int? size;
  final DateTime? modifiedAt;

  factory OpenListEntry.fromJson(Map<String, dynamic> json) {
    final name = json['name'];
    final path = json['path'];
    if (name is! String ||
        name.isEmpty ||
        path is! String ||
        name.contains('/') ||
        name.contains('\\') ||
        name == '.' ||
        name == '..' ||
        name.contains('\u0000') ||
        json['isDirectory'] is! bool) {
      throw const MediaSourceException('网盘返回的目录条目无效', code: 'invalid_response');
    }
    return OpenListEntry(
      name: name,
      path: normalizeOpenListPath(path),
      isDirectory: json['isDirectory'] as bool,
      size: (json['size'] as num?)?.toInt(),
      modifiedAt: json['modifiedAt'] is num
          ? DateTime.fromMillisecondsSinceEpoch(
              (json['modifiedAt'] as num).toInt(),
            )
          : null,
    );
  }
}
