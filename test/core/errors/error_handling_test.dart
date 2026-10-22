import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reelva/core/errors/error_handling.dart';
import 'package:reelva/core/logging/app_logger.dart';

void main() {
  group('installErrorHandling 全局异常路由与脱敏测试', () {
    late String? capturedMessage;
    late Object? capturedError;
    late StackTrace? capturedStack;
    late AppLogger testLogger;

    setUp(() {
      capturedMessage = null;
      capturedError = null;
      capturedStack = null;
      testLogger = AppLogger(
        sink: (message, {error, stackTrace}) {
          capturedMessage = message;
          capturedError = error;
          capturedStack = stackTrace;
        },
      );

      // 测试自身保存 3 个全局钩子并在 tearDown 中干净还原
      final origFlutterOnError = FlutterError.onError;
      final origPlatformOnError = PlatformDispatcher.instance.onError;
      final origErrorWidgetBuilder = ErrorWidget.builder;

      addTearDown(() {
        FlutterError.onError = origFlutterOnError;
        PlatformDispatcher.instance.onError = origPlatformOnError;
        ErrorWidget.builder = origErrorWidgetBuilder;
      });
    });

    test('FlutterError.onError 路由至注入的 logger 并完成脱敏', () {
      installErrorHandling(logger: testLogger);

      const sentinelToken = 'synthetic_flutter_tok_8001';
      final details = FlutterErrorDetails(
        exception: Exception(
          'Layout failed with Authorization: Bearer $sentinelToken',
        ),
        library: 'widgets',
        context: ErrorDescription('during layout'),
      );

      FlutterError.onError!(details);

      expect(capturedMessage, isNotNull);
      expect(capturedError, isNotNull);
      expect(capturedError.toString().contains(sentinelToken), isFalse);
      expect(
        capturedError.toString().contains('Authorization: Bearer [REDACTED]'),
        isTrue,
      );
    });

    test('PlatformDispatcher.instance.onError 拦截异常、脱敏堆栈并保留 frame', () {
      installErrorHandling(logger: testLogger);

      const sentinelCookie = 'synthetic_platform_cookie_8002';
      const sentinelStackKey = 'synthetic_stack_key_8003';
      final fakeStack = StackTrace.fromString(
        '#0  AuthService.fetch (https://api.reelva.dev/v1/auth?key=$sentinelStackKey)\n#1  main (package:reelva/main.dart:10:5)',
      );

      final handler = PlatformDispatcher.instance.onError;
      expect(handler, isNotNull);

      final handled = handler!(
        Exception('Network socket error: Cookie: session=$sentinelCookie'),
        fakeStack,
      );

      expect(handled, isTrue);
      expect(capturedError, isNotNull);
      expect(capturedError.toString().contains(sentinelCookie), isFalse);
      expect(capturedError.toString().contains('Cookie: [REDACTED]'), isTrue);

      // capturedStack 验证实际堆栈 URL 凭据不泄露且保留 frame 诊断
      expect(capturedStack, isNotNull);
      final stackStr = capturedStack.toString();
      expect(stackStr.contains(sentinelStackKey), isFalse);
      expect(stackStr.contains('[REDACTED_URL]'), isTrue);
      expect(stackStr.contains('AuthService.fetch'), isTrue);
      expect(stackStr.contains('package:reelva/main.dart:10:5'), isTrue);
    });
  });
}
