/// 日志与异常文本脱敏工具类
///
/// 对网络 URL、常见认证头、Cookie、Bearer/Basic Token、凭据字典/JSON/键值对进行确定性脱敏，
/// 严禁凭据、签名直链或密码输出至日志。
class Redactor {
  const Redactor._();

  static const String redactedPlaceholder = '[REDACTED]';
  static const String redactedUrlPlaceholder = '[REDACTED_URL]';

  // 1. 整段网络 URL（吞掉至空白、引号或 < >，覆盖 IPv6、文件名括号与任意签名参数/fragment，避免早期截断泄漏）
  static final RegExp _networkUrlRegex = RegExp(
    r"""(?:https?|ftp|wss?):\/\/[^\s<>"'`]+""",
    caseSensitive: false,
  );

  // 2. 双引号 JSON 敏感字段
  static final RegExp _jsonDoubleQuoteRegex = RegExp(
    r'''("(?:authorization|proxy-authorization|cookie|set-cookie|api[_-]?key|access[_-]?token|refresh[_-]?token|auth[_-]?token|token|password|passwd|client[_-]?secret|secret|credential[s]?|session[_-]?id|signature|sig)"\s*:\s*)"([^"\\]*(?:\\.[^"\\]*)*)"''',
    caseSensitive: false,
  );

  // 3. 单引号 JSON / Map 敏感字段
  static final RegExp _jsonSingleQuoteRegex = RegExp(
    r"""('(?:authorization|proxy-authorization|cookie|set-cookie|api[_-]?key|access[_-]?token|refresh[_-]?token|auth[_-]?token|token|password|passwd|client[_-]?secret|secret|credential[s]?|session[_-]?id|signature|sig)'\s*:\s*)'([^'\\]*(?:\\.[^'\\]*)*)'""",
    caseSensitive: false,
  );

  // 4. HTTP Authorization / Proxy-Authorization 报头（单行或 Map，不区分大小写）
  static final RegExp _authHeaderRegex = RegExp(
    r"""((?:authorization|proxy-authorization)\s*[:=]\s*(?:bearer\s+|basic\s+)?)(?!\[REDACTED\])(?:[^\r\n{}'"]+?(?=(?:,\s*[a-zA-Z0-9_-]+\s*:|}|\r?\n|$)))""",
    caseSensitive: false,
  );

  // 5. HTTP Cookie / Set-Cookie 报头（覆盖多值逗号与分号，终止于下个报头或 Map 条目）
  static final RegExp _cookieHeaderRegex = RegExp(
    r"""((?:cookie|set-cookie)\s*[:=]\s*)(?!\[REDACTED\])(?:[^\r\n{}'"]+?(?=(?:,\s*[a-zA-Z0-9_-]+\s*:|}|\r?\n|$)))""",
    caseSensitive: false,
  );

  // 6. Map / 键值对形式的未加引号敏感凭据
  static final RegExp _mapSensitiveKeyRegex = RegExp(
    r"""\b(api[_-]?key|access[_-]?token|refresh[_-]?token|auth[_-]?token|token|password|passwd|client[_-]?secret|secret|credential[s]?|session[_-]?id|signature|sig)(\s*[:=]\s*)(?!\[REDACTED\])([^,\s{}()\[\];'"]+)""",
    caseSensitive: false,
  );

  // 7. 独立 Bearer / Basic Token（覆盖 short Bearer 如 Bearer abc）
  static final RegExp _bearerBasicTokenRegex = RegExp(
    r"""\b(bearer|basic)\s+(?!\[REDACTED\])([A-Za-z0-9\-_.~+/=]+)""",
    caseSensitive: false,
  );

  /// 对文本进行脱敏处理
  static String redact(String? input) {
    if (input == null || input.isEmpty) {
      return '';
    }

    var result = input;

    // 步骤 1：整段网络 URL 脱敏
    result = result.replaceAll(_networkUrlRegex, redactedUrlPlaceholder);

    // 步骤 2：双引号 JSON 脱敏
    result = result.replaceAllMapped(
      _jsonDoubleQuoteRegex,
      (m) => '${m[1]}"$redactedPlaceholder"',
    );

    // 步骤 3：单引号 JSON / Map 脱敏
    result = result.replaceAllMapped(
      _jsonSingleQuoteRegex,
      (m) => "${m[1]}'$redactedPlaceholder'",
    );

    // 步骤 4：Authorization / Proxy-Authorization 报头脱敏
    result = result.replaceAllMapped(
      _authHeaderRegex,
      (m) => '${m[1]}$redactedPlaceholder',
    );

    // 步骤 5：Cookie / Set-Cookie 报头脱敏
    result = result.replaceAllMapped(
      _cookieHeaderRegex,
      (m) => '${m[1]}$redactedPlaceholder',
    );

    // 步骤 6：未包裹引号的 Map / 键值对脱敏
    result = result.replaceAllMapped(
      _mapSensitiveKeyRegex,
      (m) => '${m[1]}${m[2]}$redactedPlaceholder',
    );

    // 步骤 7：独立 Bearer / Basic Token 脱敏
    result = result.replaceAllMapped(
      _bearerBasicTokenRegex,
      (m) => '${m[1]} $redactedPlaceholder',
    );

    return result;
  }

  /// 脱敏堆栈信息并返回安全的 StackTrace
  static StackTrace? redactStackTrace(StackTrace? stackTrace) {
    if (stackTrace == null) return null;
    final sanitized = redact(stackTrace.toString());
    return StackTrace.fromString(sanitized);
  }
}
