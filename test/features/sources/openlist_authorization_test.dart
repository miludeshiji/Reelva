import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:reelva/features/sources/openlist_authorization.dart';

String callback(Map<String, dynamic> payload) =>
    'https://api.oplist.org/#${Uri.encodeComponent(jsonEncode(payload))}';

void main() {
  test('三种网盘授权入口保持驱动参数和同一授权服务', () {
    for (final entry in {
      'BaiduNetdisk': 'baiduyun_go',
      '115 Open': '115cloud_go',
      '123 Open': '123cloud_oa',
    }.entries) {
      final uri = openListLoginUri(entry.key);
      expect(uri.scheme, 'https');
      expect(uri.host, 'api.oplist.org');
      expect(uri.path, '/${entry.value.split('_').first}/requests');
      expect(uri.queryParameters['driver_txt'], entry.value);
      expect(uri.queryParameters['server_use'], 'true');
    }
  });

  test('百度回调保留 AccessToken 大小写并设置在线续期', () {
    final result = parseOpenListLoginCallback(
      callback({
        'driver': 'baiduyun_go',
        'access_token': 'baidu-access',
        'refresh_token': 'baidu-refresh',
        'client_uid': 'old-client',
        'client_key': 'old-secret',
      }),
      driver: 'BaiduNetdisk',
    )!;
    expect(result['AccessToken'], 'baidu-access');
    expect(result['refresh_token'], 'baidu-refresh');
    expect(result.containsKey('access_token'), isFalse);
    expect(result['use_online_api'], isTrue);
    expect(
      result['api_url_address'],
      'https://api.oplist.org/baiduyun/renewapi',
    );
    expect(result['client_id'], '');
    expect(result['client_secret'], '');
  });

  test('115 回调需要两种 Token 并使用 snake_case', () {
    final result = parseOpenListLoginCallback(
      callback({
        'driver_txt': '115cloud_go',
        'AccessToken': 'access',
        'RefreshToken': 'refresh',
      }),
      driver: '115 Open',
    )!;
    expect(result['access_token'], 'access');
    expect(result['refresh_token'], 'refresh');
    expect(result.containsKey('AccessToken'), isFalse);
    expect(result.containsKey('api_url_address'), isFalse);
    expect(
      () => parseOpenListLoginCallback(
        callback({'driver_txt': '115cloud_go', 'refresh_token': 'refresh'}),
        driver: '115 Open',
      ),
      throwsFormatException,
    );
  });

  test('123 支持 base64url 回调并转为实际驱动字段', () {
    final before = DateTime.now().millisecondsSinceEpoch;
    final encoded = base64Url.encode(
      utf8.encode(
        jsonEncode({
          'driver_txt': '123cloud_oa',
          'access_token': 'access',
          'refresh_token': 'refresh',
          'expires_in': '3600',
        }),
      ),
    );
    final result = parseOpenListLoginCallback(
      'https://api.oplist.org/#$encoded',
      driver: '123 Open',
    )!;
    expect(result['AccessToken'], 'access');
    expect(result['RefreshToken'], 'refresh');
    expect(result['ClientID'], '');
    expect(result['ClientSecret'], '');
    expect(result.containsKey('refresh_token'), isFalse);
    expect(result.containsKey('expires_in'), isFalse);
    final after = DateTime.now().millisecondsSinceEpoch;
    expect(result['token_updated_at'], inInclusiveRange(before, after));
    expect(
      result['access_token_expires_at'],
      inInclusiveRange(before + 3600000, after + 3600000),
    );
    expect(
      result['api_url_address'],
      'https://api.oplist.org/123cloud/renewapi',
    );
  });

  test('123 导入已有绝对时间时不重新延长令牌有效期', () {
    final result = parseOpenListAuthorization(
      jsonEncode({
        'AccessToken': 'access',
        'RefreshToken': 'refresh',
        'expires_in': 3600,
        'token_updated_at': 1000,
        'access_token_expires_at': 2000,
      }),
      driver: '123 Open',
    );
    expect(result['token_updated_at'], 1000);
    expect(result['access_token_expires_at'], 2000);
    expect(result.containsKey('expires_in'), isFalse);
  });

  test('123 手动更新仅在换令牌时更新授权时间，更换访问令牌清除旧有效期', () {
    const previous = <String, dynamic>{
      'AccessToken': 'old-access',
      'RefreshToken': 'old-refresh',
      'token_updated_at': 1000,
      'access_token_expires_at': 2000,
    };
    final unchanged = buildOpenListAuthorization(
      driver: '123 Open',
      accessToken: 'old-access',
      refreshToken: 'old-refresh',
      previous: previous,
    );
    expect(unchanged['token_updated_at'], 1000);
    expect(unchanged['access_token_expires_at'], 2000);
    final refreshOnly = buildOpenListAuthorization(
      driver: '123 Open',
      accessToken: 'old-access',
      refreshToken: 'new-refresh',
      previous: previous,
    );
    expect(refreshOnly['token_updated_at'], greaterThan(1000));
    expect(refreshOnly['access_token_expires_at'], 2000);
    final replacement = buildOpenListAuthorization(
      driver: '123 Open',
      accessToken: 'new-access',
      refreshToken: 'new-refresh',
      previous: previous,
    );
    expect(replacement['token_updated_at'], greaterThan(1000));
    expect(replacement['access_token_expires_at'], 0);
    expect(previous['access_token_expires_at'], 2000);
  });

  test('拒绝非授权来源、端口、凭据、路径以及夸克伪回调', () {
    for (final url in [
      'http://api.oplist.org/#payload',
      'https://other.test/#payload',
      'https://api.oplist.org.evil.test/#payload',
      'https://api.oplist.org:8443/#payload',
      'https://user:password@api.oplist.org/#payload',
      'https://api.oplist.org/requests#payload',
      'https://api.oplist.org/',
    ]) {
      expect(parseOpenListLoginCallback(url, driver: 'BaiduNetdisk'), isNull);
    }
    expect(
      parseOpenListLoginCallback(
        callback({'cookie': 'cookie'}),
        driver: 'Quark',
      ),
      isNull,
    );
  });

  test('拒绝跨网盘授权与缺失 Refresh Token', () {
    expect(
      () => parseOpenListLoginCallback(
        callback({
          'driver_txt': '115cloud_go',
          'access_token': 'access',
          'refresh_token': 'refresh',
        }),
        driver: 'BaiduNetdisk',
      ),
      throwsFormatException,
    );
    expect(
      () => parseOpenListLoginCallback(
        callback({'driver_txt': 'baiduyun_go', 'access_token': 'access'}),
        driver: 'BaiduNetdisk',
      ),
      throwsFormatException,
    );
  });

  test('服务端错误和损坏载荷不回显原始内容', () {
    try {
      parseOpenListLoginCallback(
        callback({'message_err': 'access_token=secret-value'}),
        driver: 'BaiduNetdisk',
      );
      fail('Expected safe authorization error');
    } on FormatException catch (error) {
      expect(error.message, '网盘授权未完成，请重新登录');
      expect(error.toString(), isNot(contains('secret-value')));
    }
    expect(
      () => parseOpenListAuthorization(
        '%bad-payload-secret',
        driver: 'BaiduNetdisk',
      ),
      throwsA(
        isA<FormatException>().having(
          (error) => error.toString(),
          'safe message',
          isNot(contains('secret')),
        ),
      ),
    );
  });

  test('手动更新替换旧 Token，保留驱动设置并不修改旧 Map', () {
    final previous = <String, dynamic>{
      'AccessToken': 'old-access',
      'refresh_token': 'old-refresh',
      'root_folder_path': '/Media',
      'download_api': 'official',
    };
    final result = buildOpenListAuthorization(
      driver: 'BaiduNetdisk',
      accessToken: ' new-access ',
      refreshToken: ' new-refresh ',
      previous: previous,
    );
    expect(result['AccessToken'], 'new-access');
    expect(result['refresh_token'], 'new-refresh');
    expect(result['root_folder_path'], '/Media');
    expect(result['download_api'], 'official');
    expect(previous['AccessToken'], 'old-access');
  });

  test('夸克 Cookie 保持完整内容并覆盖旧值', () {
    final result = buildOpenListAuthorization(
      driver: 'Quark',
      cookie: ' __pus=one; __puus=two; secure=value ',
      previous: {'Cookie': 'old', 'root_folder_id': '0'},
    );
    expect(result['cookie'], '__pus=one; __puus=two; secure=value');
    expect(result.containsKey('Cookie'), isFalse);
    expect(result['root_folder_id'], '0');
    expect(
      () => buildOpenListAuthorization(driver: 'Quark', cookie: ''),
      throwsFormatException,
    );
  });

  test('123 手动 Token 与开发者配置转为 PascalCase', () {
    final result = buildOpenListAuthorization(
      driver: '123 Open',
      accessToken: 'access',
      refreshToken: 'refresh',
      previous: {'client_id': 'client', 'client_secret': 'secret'},
    );
    expect(result['AccessToken'], 'access');
    expect(result['RefreshToken'], 'refresh');
    expect(result['ClientID'], 'client');
    expect(result['ClientSecret'], 'secret');
  });
}
