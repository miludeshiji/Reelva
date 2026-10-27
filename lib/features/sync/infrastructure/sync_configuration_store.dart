import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../domain/sync_models.dart';

/// WebDAV 同步服务配置
class SyncConfiguration {
  SyncConfiguration({
    required Uri endpoint,
    this.username = '',
    this.password = '',
    this.encryptionPassword = '',
  }) : endpoint = validateEndpoint(endpoint);

  /// WebDAV 同步服务根端点 URL（严格以 / 结尾）
  final Uri endpoint;

  /// HTTP Basic 认证用户名
  final String username;

  /// HTTP Basic 认证密码
  final String password;

  /// 独立于 WebDAV 登录密码；留空使用普通 JSON，填写后加密配置与索引。
  final String encryptionPassword;

  /// 校验并规整同步根端点 URL
  static Uri validateEndpoint(Uri uri) {
    if (!uri.hasScheme || (!uri.isScheme('http') && !uri.isScheme('https'))) {
      throw const SyncException('同步端点必须为有效的 http 或 https URL');
    }
    if (uri.host.isEmpty) {
      throw const SyncException('同步端点的主机名 (Host) 不能为空');
    }
    if (uri.userInfo.isNotEmpty || uri.hasQuery || uri.hasFragment) {
      throw const SyncException('同步端点格式不安全，严禁携带凭据、查询参数或片段标识');
    }
    _checkDotSegments(uri.path);
    if (!uri.path.endsWith('/')) {
      return uri.replace(path: '${uri.path}/');
    }
    return uri;
  }

  /// 检查路径中是否包含相对点段
  static void _checkDotSegments(String raw) {
    final segments = raw.split(RegExp(r'[/\\]'));
    for (final seg in segments) {
      final normalized = seg.replaceAll(
        RegExp(r'%2e', caseSensitive: false),
        '.',
      );
      if (normalized == '.' || normalized == '..') {
        throw const SyncException('同步端点包含无效的点路径段');
      }
    }
  }

  /// 从字符串解析并校验同步端点 URL
  static Uri parseEndpoint(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) {
      throw const SyncException('同步端点不能为空');
    }
    _checkDotSegments(trimmed);
    final uri = Uri.tryParse(trimmed);
    if (uri == null) {
      throw const SyncException('无法解析同步端点 URL');
    }
    return validateEndpoint(uri);
  }

  @override
  String toString() {
    final userPart = username.isEmpty ? '' : ', username: [REDACTED]';
    final passPart = password.isEmpty ? '' : ', password: [REDACTED]';
    return 'SyncConfiguration(endpoint: $endpoint$userPart$passPart)';
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SyncConfiguration &&
          runtimeType == other.runtimeType &&
          endpoint == other.endpoint &&
          username == other.username &&
          password == other.password &&
          encryptionPassword == other.encryptionPassword;

  @override
  int get hashCode =>
      Object.hash(endpoint, username, password, encryptionPassword);
}

/// 同步配置安全持久化存储
class SyncConfigurationStore {
  SyncConfigurationStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  static const String _storageKey = 'reelva_sync_v1_secure_configuration';

  /// 读取已保存的同步配置；如果未配置则返回 null
  Future<SyncConfiguration?> read() async {
    try {
      final raw = await _storage.read(key: _storageKey);
      if (raw == null || raw.trim().isEmpty) {
        return null;
      }
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        throw const SyncException('安全存储中的同步配置格式损坏');
      }
      final endpointStr = decoded['endpoint'] as String?;
      if (endpointStr == null || endpointStr.trim().isEmpty) {
        throw const SyncException('安全存储中的同步配置缺少 endpoint');
      }
      final endpoint = SyncConfiguration.parseEndpoint(endpointStr);
      final username = (decoded['username'] as String?) ?? '';
      final password = (decoded['password'] as String?) ?? '';
      return SyncConfiguration(
        endpoint: endpoint,
        username: username,
        password: password,
        encryptionPassword: (decoded['encryptionPassword'] as String?) ?? '',
      );
    } on SyncException {
      rethrow;
    } catch (_) {
      throw const SyncException('读取同步配置失败');
    }
  }

  /// 保存同步配置至安全存储
  Future<void> save(SyncConfiguration config) async {
    try {
      final payload = jsonEncode({
        'endpoint': config.endpoint.toString(),
        'username': config.username,
        'password': config.password,
        'encryptionPassword': config.encryptionPassword,
      });
      await _storage.write(key: _storageKey, value: payload);
    } on SyncException {
      rethrow;
    } catch (_) {
      throw const SyncException('保存同步配置失败');
    }
  }

  /// 从安全存储删除同步配置
  Future<void> delete() async {
    try {
      await _storage.delete(key: _storageKey);
    } catch (_) {
      throw const SyncException('删除同步配置失败');
    }
  }
}
