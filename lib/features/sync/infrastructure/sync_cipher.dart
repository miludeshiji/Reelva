import 'dart:convert';
import 'dart:isolate';
import 'dart:math';

import 'package:cryptography/cryptography.dart';

import '../domain/sync_models.dart';

/// 配置与凭据使用独立密码加密；密钥推导在后台 isolate 执行。
class SyncCipher {
  static const _format = 'reelva-application-sync-v1';
  static const _iterations = 600000;

  Future<String> encrypt(Map<String, dynamic> value, String password) =>
      Isolate.run(() async {
        final salt = List<int>.generate(
          16,
          (_) => Random.secure().nextInt(256),
        );
        final key = await _key(password, salt);
        final box = await AesGcm.with256bits().encrypt(
          utf8.encode(jsonEncode(value)),
          secretKey: key,
          aad: utf8.encode(_format),
        );
        return jsonEncode({
          'format': _format,
          'salt': base64Encode(salt),
          'nonce': base64Encode(box.nonce),
          'mac': base64Encode(box.mac.bytes),
          'data': base64Encode(box.cipherText),
        });
      });

  Future<Map<String, dynamic>> decrypt(String text, String password) =>
      Isolate.run(() async {
        try {
          if (text.length > 8 * 1024 * 1024) throw const FormatException();
          final envelope = jsonDecode(text) as Map<String, dynamic>;
          if (envelope['format'] != _format) throw const FormatException();
          final salt = base64Decode(envelope['salt'] as String);
          final nonce = base64Decode(envelope['nonce'] as String);
          final mac = base64Decode(envelope['mac'] as String);
          if (salt.length != 16 || nonce.length != 12 || mac.length != 16) {
            throw const FormatException();
          }
          final clear = await AesGcm.with256bits().decrypt(
            SecretBox(
              base64Decode(envelope['data'] as String),
              nonce: nonce,
              mac: Mac(mac),
            ),
            secretKey: await _key(password, salt),
            aad: utf8.encode(_format),
          );
          return jsonDecode(utf8.decode(clear)) as Map<String, dynamic>;
        } catch (_) {
          throw const SyncException('配置解密失败，请检查各设备的同步加密密码是否一致');
        }
      });

  static Future<SecretKey> _key(String password, List<int> salt) =>
      Pbkdf2.hmacSha256(
        iterations: _iterations,
        bits: 256,
      ).deriveKeyFromPassword(password: password, nonce: salt);
}
