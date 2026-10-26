import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../domain/source_models.dart';

/// 远程媒体源凭据模型
///
/// 包含用户名、密码、SMB域以及可选的播放请求头信息。
/// [toString] 绝不输出任何敏感字段，以防泄漏至日志。
@immutable
class RemoteCredentials {
  const RemoteCredentials({
    this.username = '',
    this.password = '',
    this.domain = '',
    this.playbackHeaders = const {},
  });

  const RemoteCredentials.anonymous()
    : username = '',
      password = '',
      domain = '',
      playbackHeaders = const {};

  final String username;
  final String password;
  final String domain;
  final Map<String, String> playbackHeaders;

  bool get isAnonymous =>
      username.isEmpty &&
      password.isEmpty &&
      domain.isEmpty &&
      playbackHeaders.isEmpty;

  Map<String, dynamic> toJson() => {
    'username': username,
    'password': password,
    'domain': domain,
    'playbackHeaders': playbackHeaders,
  };

  factory RemoteCredentials.fromJson(Map<String, dynamic> json) {
    final headersRaw = json['playbackHeaders'];
    final headers = <String, String>{};
    if (headersRaw is Map) {
      for (final entry in headersRaw.entries) {
        if (entry.key is String && entry.value is String) {
          headers[entry.key as String] = entry.value as String;
        }
      }
    }
    return RemoteCredentials(
      username: json['username'] as String? ?? '',
      password: json['password'] as String? ?? '',
      domain: json['domain'] as String? ?? '',
      playbackHeaders: headers,
    );
  }

  RemoteCredentials copyWith({
    String? username,
    String? password,
    String? domain,
    Map<String, String>? playbackHeaders,
  }) {
    return RemoteCredentials(
      username: username ?? this.username,
      password: password ?? this.password,
      domain: domain ?? this.domain,
      playbackHeaders: playbackHeaders ?? this.playbackHeaders,
    );
  }

  @override
  String toString() => 'RemoteCredentials([REDACTED])';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RemoteCredentials &&
          runtimeType == other.runtimeType &&
          username == other.username &&
          password == other.password &&
          domain == other.domain &&
          mapEquals(playbackHeaders, other.playbackHeaders);

  @override
  int get hashCode => Object.hash(
    username,
    password,
    domain,
    Object.hashAll(
      playbackHeaders.entries.map((e) => Object.hash(e.key, e.value)),
    ),
  );
}

/// 远程媒体源安全凭据存储
class RemoteCredentialsStore {
  RemoteCredentialsStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;
  static int _refCounter = 0;

  /// 生成安全唯一的凭据引用标识符
  static String generateReference(String kind) {
    final timestamp = DateTime.now().microsecondsSinceEpoch;
    final seq = ++_refCounter;
    return 'cred_${kind}_${timestamp}_$seq';
  }

  /// 读取指定引用关联的凭据。
  /// [reference] 为 null 或为空时，返回匿名凭据。
  /// 若指定了非空 [reference] 但存储中不存在，抛出安全的 credential_not_found 异常。
  Future<RemoteCredentials> read(String? reference) async {
    if (reference == null || reference.trim().isEmpty) {
      return const RemoteCredentials.anonymous();
    }
    final key = reference.trim();
    String? raw;
    try {
      raw = await _storage.read(key: key);
    } catch (e) {
      throw const MediaSourceException(
        '安全存储读取失败',
        code: 'credential_storage_failed',
      );
    }

    if (raw == null) {
      throw const MediaSourceException(
        '凭据不存在或已失效',
        code: 'credential_not_found',
      );
    }

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) {
        throw const FormatException('Expected JSON map');
      }
      return RemoteCredentials.fromJson(Map<String, dynamic>.from(decoded));
    } catch (_) {
      throw const MediaSourceException('凭据数据损坏', code: 'credential_corrupt');
    }
  }

  /// 写入凭据到安全存储
  Future<void> write(String reference, RemoteCredentials credentials) async {
    if (reference.trim().isEmpty) {
      throw const MediaSourceException(
        '凭据引用标识不能为空',
        code: 'invalid_credential_ref',
      );
    }
    final key = reference.trim();
    try {
      final jsonStr = jsonEncode(credentials.toJson());
      await _storage.write(key: key, value: jsonStr);
    } catch (e) {
      throw const MediaSourceException(
        '安全存储写入失败',
        code: 'credential_storage_failed',
      );
    }
  }

  /// 从安全存储删除凭据
  Future<void> delete(String reference) async {
    if (reference.trim().isEmpty) return;
    try {
      await _storage.delete(key: reference.trim());
    } catch (e) {
      throw const MediaSourceException(
        '安全存储删除失败',
        code: 'credential_storage_failed',
      );
    }
  }
}
