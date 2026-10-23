import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../../core/logging/app_logger.dart';
import '../domain/tmdb_models.dart';

/// TMDB 凭据安全存储
///
/// 使用平台安全存储（Windows Credential Manager / Android KeyStore / iOS Keychain）。
/// 支持 TMDB v3 API Key（32位十六进制）与 v4 API Read Access Bearer Token。
/// 绝不向普通磁盘明文回退，且不向日志输出明文凭据。
class TmdbTokenStore {
  final FlutterSecureStorage _storage;
  static const String _key = 'reelva_tmdb_auth_token';

  const TmdbTokenStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  /// 净化 Token 输入（去首尾空格，去除可能误粘贴的前缀 Bearer）
  static String sanitizeToken(String raw) {
    var token = raw.trim();
    if (token.toLowerCase().startsWith('bearer ')) {
      token = token.substring(7).trim();
    }
    return token;
  }

  /// 校验 Token 是否符合 TMDB v3 API Key（32 位 Hex）或 v4 Bearer Token（JWT 格式）
  static bool isValidToken(String raw) {
    final token = sanitizeToken(raw);
    if (token.isEmpty) return false;

    // 所有 Token 首先严格拒绝任何空白字符（空格、换行、制表符）或不可见控制字符
    if (RegExp(r'[\s\x00-\x1F\x7F]').hasMatch(token)) {
      return false;
    }

    // 1. TMDB v3 API Key: 恰好 32 位 16 进制字符
    if (RegExp(r'^[a-fA-F0-9]{32}$').hasMatch(token)) {
      return true;
    }

    // 2. TMDB v4 Bearer Token: 仅允许严格安全字符集且达到最小有效长度
    if (token.length >= 32 && RegExp(r'^[A-Za-z0-9_\-\.]+$').hasMatch(token)) {
      return true;
    }

    return false;
  }

  /// 判断当前 Token 是否属于 v4 Bearer Token
  static bool isBearerToken(String token) {
    final sanitized = sanitizeToken(token);
    return sanitized.startsWith('eyJ') ||
        !RegExp(r'^[a-fA-F0-9]{32}$').hasMatch(sanitized);
  }

  /// 读取已存储的 TMDB 凭据
  Future<String?> read() async {
    try {
      final value = await _storage.read(key: _key);
      if (value == null || value.trim().isEmpty) {
        return null;
      }
      return sanitizeToken(value);
    } catch (e) {
      AppLogger.instance.error(
        '读取 TMDB 安全凭据异常',
        error: e.runtimeType.toString(),
      );
      throw const MetadataException('读取安全存储凭据失败', code: 'storage_error');
    }
  }

  /// 保存 TMDB 凭据
  Future<void> save(String rawToken) async {
    final token = sanitizeToken(rawToken);
    if (!isValidToken(token)) {
      throw const MetadataException(
        '无效的 TMDB 密钥格式，请提供 32 位 API Key 或 v4 Bearer Token',
        code: 'invalid_token',
      );
    }

    try {
      await _storage.write(key: _key, value: token);
    } catch (e) {
      AppLogger.instance.error(
        '保存 TMDB 安全凭据异常',
        error: e.runtimeType.toString(),
      );
      throw const MetadataException('写入安全存储凭据失败', code: 'storage_error');
    }
  }

  /// 删除已存储的 TMDB 凭据
  Future<void> delete() async {
    try {
      await _storage.delete(key: _key);
    } catch (e) {
      AppLogger.instance.error(
        '删除 TMDB 安全凭据异常',
        error: e.runtimeType.toString(),
      );
      throw const MetadataException('删除安全存储凭据失败', code: 'storage_error');
    }
  }

  /// 检查凭据是否已配置（存储读取失败直接抛出异常，绝不伪装为未配置）
  Future<bool> isConfigured() async {
    final token = await read();
    return token != null && token.isNotEmpty;
  }
}
