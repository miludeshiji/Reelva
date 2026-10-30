import 'dart:convert';

const _loginDrivers = <String, String>{
  'BaiduNetdisk': 'baiduyun_go',
  '115 Open': '115cloud_go',
  '123 Open': '123cloud_oa',
};

Uri openListLoginUri(String driver) {
  final loginDriver = _loginDrivers[driver];
  if (loginDriver == null) throw ArgumentError.value(driver, 'driver');
  return Uri.https(
    'api.oplist.org',
    '/${loginDriver.split('_').first}/requests',
    {
      'driver_txt': loginDriver,
      'server_use': 'true',
      'client_uid': '',
      'client_key': '',
    },
  );
}

Map<String, dynamic>? parseOpenListLoginCallback(
  String url, {
  required String driver,
}) {
  if (!_loginDrivers.containsKey(driver)) return null;
  final uri = Uri.tryParse(url);
  if (uri == null ||
      uri.scheme != 'https' ||
      uri.host != 'api.oplist.org' ||
      uri.port != 443 ||
      uri.userInfo.isNotEmpty ||
      uri.path != '/' ||
      uri.fragment.isEmpty) {
    return null;
  }
  final value = parseOpenListAuthorization(url, driver: driver);
  final error = value.remove('message_err');
  if (error != null && '$error'.isNotEmpty) {
    throw const FormatException('网盘授权未完成，请重新登录');
  }
  if (value['driver_txt'] != _loginDrivers[driver]) {
    throw const FormatException('授权结果与所选网盘不一致');
  }
  _validateTokens(value, driver);
  value['server_use'] = true;
  final clientKeys = driver == '123 Open'
      ? ['ClientID', 'ClientSecret']
      : ['client_id', 'client_secret'];
  for (final key in clientKeys) {
    value[key] = '';
  }
  if (driver != '115 Open') {
    value['use_online_api'] = true;
    value['api_url_address'] = Uri.https(
      'api.oplist.org',
      '/${_loginDrivers[driver]!.split('_').first}/renewapi',
    ).toString();
  }
  return value;
}

Map<String, dynamic> parseOpenListAuthorization(
  String text, {
  required String driver,
}) {
  var payload = text.trim();
  final hash = payload.indexOf('#');
  if (hash >= 0) payload = payload.substring(hash + 1);
  try {
    payload = Uri.decodeFull(payload);
    Object? decoded;
    try {
      decoded = jsonDecode(payload);
    } on FormatException {
      decoded = jsonDecode(
        utf8.decode(base64Url.decode(base64Url.normalize(payload))),
      );
    }
    if (decoded is! Map<String, dynamic>) throw const FormatException();
    final value = normalizeOpenListAuthorization(decoded, driver: driver);
    if (driver == '123 Open') {
      final now = DateTime.now().millisecondsSinceEpoch;
      final rawExpiresIn = value.remove('expires_in');
      final expiresIn = rawExpiresIn is num
          ? rawExpiresIn.toInt()
          : int.tryParse('$rawExpiresIn') ?? 0;
      value['token_updated_at'] ??= now;
      value['access_token_expires_at'] ??= expiresIn > 0
          ? now + expiresIn * 1000
          : 0;
    }
    return value;
  } on FormatException {
    throw const FormatException('授权结果格式无效，请重新登录或手动填写凭据');
  }
}

Map<String, dynamic> buildOpenListAuthorization({
  required String driver,
  String accessToken = '',
  String refreshToken = '',
  String cookie = '',
  Map<String, dynamic> previous = const {},
}) {
  final value = Map<String, dynamic>.from(previous);
  if (driver == 'Quark') {
    value.remove('Cookie');
    value['cookie'] = cookie.trim();
  } else {
    for (final key in [
      'AccessToken',
      'RefreshToken',
      'access_token',
      'refresh_token',
    ]) {
      value.remove(key);
    }
    value['access_token'] = accessToken.trim();
    value['refresh_token'] = refreshToken.trim();
  }
  final result = normalizeOpenListAuthorization(value, driver: driver);
  _validateTokens(result, driver);
  if (driver == '123 Open') {
    final original = normalizeOpenListAuthorization(previous, driver: driver);
    if (const [
      'AccessToken',
      'RefreshToken',
    ].any((key) => _text(original[key]) != _text(result[key]))) {
      result['token_updated_at'] = DateTime.now().millisecondsSinceEpoch;
      if (_text(original['AccessToken']) != _text(result['AccessToken'])) {
        result['access_token_expires_at'] = 0;
      }
    }
    result.remove('expires_in');
  }
  return result;
}

Map<String, dynamic> normalizeOpenListAuthorization(
  Map<String, dynamic> source, {
  required String driver,
}) {
  if (!const {
    'BaiduNetdisk',
    'Quark',
    '115 Open',
    '123 Open',
  }.contains(driver)) {
    throw ArgumentError.value(driver, 'driver');
  }
  final value = Map<String, dynamic>.from(source);
  if (driver == 'Quark') {
    _move(value, 'Cookie', 'cookie');
    return value;
  }
  final callbackDriver = value.remove('driver') ?? value['driver_txt'];
  if (callbackDriver is String && callbackDriver.isNotEmpty) {
    value['driver_txt'] = callbackDriver;
  }
  _move(value, 'AccessToken', 'access_token');
  _move(value, 'RefreshToken', 'refresh_token');
  _move(value, 'ClientID', 'client_id');
  _move(value, 'ClientSecret', 'client_secret');
  _move(value, 'client_uid', 'client_id');
  _move(value, 'client_key', 'client_secret');
  if (driver != '115 Open') value['use_online_api'] ??= true;
  if (driver == '123 Open') {
    _move(value, 'access_token', 'AccessToken');
    _move(value, 'refresh_token', 'RefreshToken');
    _move(value, 'client_id', 'ClientID');
    _move(value, 'client_secret', 'ClientSecret');
    value['driver_txt'] ??= '123cloud_oa';
    value['server_use'] ??= true;
  } else if (driver == 'BaiduNetdisk') {
    _move(value, 'access_token', 'AccessToken');
  }
  return value;
}

void _validateTokens(Map<String, dynamic> value, String driver) {
  if (driver == 'Quark') {
    if (_text(value['cookie']).isEmpty) {
      throw const FormatException('请填写夸克网盘 Cookie');
    }
    return;
  }
  final refreshKey = driver == '123 Open' ? 'RefreshToken' : 'refresh_token';
  if (_text(value[refreshKey]).isEmpty) {
    throw const FormatException('请填写 Refresh Token');
  }
  if (driver == '115 Open' && _text(value['access_token']).isEmpty) {
    throw const FormatException('115 网盘需要 Access Token 和 Refresh Token');
  }
}

String _text(Object? value) => value is String ? value.trim() : '';

void _move(Map<String, dynamic> value, String source, String destination) {
  final item = value.remove(source);
  if (item != null &&
      item != '' &&
      (value[destination] == null || value[destination] == '')) {
    value[destination] = item;
  }
}
