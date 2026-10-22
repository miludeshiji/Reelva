import 'package:flutter_test/flutter_test.dart';
import 'package:reelva/core/logging/app_logger.dart';

void main() {
  group('AppLogger 不可变脱敏日志器测试', () {
    test('构造注入的 sink 正确接收脱敏后的消息、异常与堆栈', () {
      String? capturedMessage;
      Object? capturedError;
      StackTrace? capturedStackTrace;

      final logger = AppLogger(
        sink: (message, {error, stackTrace}) {
          capturedMessage = message;
          capturedError = error;
          capturedStackTrace = stackTrace;
        },
      );

      const sentinelToken = 'synthetic_log_tok_7001';
      const sentinelPass = 'synthetic_log_pass_7002';
      const sentinelUrlKey = 'synthetic_url_key_7003';

      final fakeStackTrace = StackTrace.fromString(
        '#0  Auth.login (https://auth.reelva.dev/oauth?key=$sentinelUrlKey)',
      );

      logger.error(
        '请求失败: Authorization: Bearer $sentinelToken',
        error: 'DioException: password: $sentinelPass',
        stackTrace: fakeStackTrace,
      );

      // 验证 message 中同一 sentinel 绝对缺席
      expect(capturedMessage, isNotNull);
      expect(capturedMessage!.contains(sentinelToken), isFalse);
      expect(
        capturedMessage!.contains('Authorization: Bearer [REDACTED]'),
        isTrue,
      );

      // 验证 error 中同一 sentinel 绝对缺席
      expect(capturedError, isNotNull);
      expect(capturedError.toString().contains(sentinelPass), isFalse);
      expect(capturedError.toString().contains('password: [REDACTED]'), isTrue);

      // 验证 stackTrace 中 URL 敏感参数绝对缺席
      expect(capturedStackTrace, isNotNull);
      expect(capturedStackTrace.toString().contains(sentinelUrlKey), isFalse);
      expect(capturedStackTrace.toString().contains('[REDACTED_URL]'), isTrue);
    });
  });
}
