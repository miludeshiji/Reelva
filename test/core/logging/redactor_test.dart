import 'package:flutter_test/flutter_test.dart';
import 'package:reelva/core/logging/redactor.dart';

void main() {
  group('Redactor 真实隐私与脱敏测试', () {
    test('空值与空文本安全处理', () {
      expect(Redactor.redact(null), isEmpty);
      expect(Redactor.redact(''), isEmpty);
    });

    test('整段网络 URL 脱敏，涵盖 IPv6、文件名括号、签名参数与 fragment', () {
      const sentinelAwsSig = 'synthetic_aws_sig_1001';
      const sentinelIpv6Sig = 'synthetic_ipv6_sig_1002';

      const awsUrl =
          'GET https://s3.amazonaws.com/bucket/video.mp4?X-Amz-Signature=$sentinelAwsSig#frag1';
      const ipv6Url =
          'Error at (https://[::1]/movie(2026).mp4?s=$sentinelIpv6Sig#stream1)';

      final redactedAws = Redactor.redact(awsUrl);
      final redactedIpv6 = Redactor.redact(ipv6Url);

      // 验证同一个 sentinel 变量在结果中绝对缺席
      expect(redactedAws.contains(sentinelAwsSig), isFalse);
      expect(redactedAws.contains('video.mp4'), isFalse);
      expect(redactedAws, equals('GET [REDACTED_URL]'));

      expect(redactedIpv6.contains(sentinelIpv6Sig), isFalse);
      expect(redactedIpv6.contains('movie(2026)'), isFalse);
      expect(redactedIpv6.contains('[::1]'), isFalse);
      expect(redactedIpv6.contains('[REDACTED_URL]'), isTrue);
      expect(redactedIpv6.startsWith('Error at ('), isTrue);
    });

    test('脱敏 Authorization 与 short Bearer / Basic', () {
      const sentinelShortBearer = 'synthetic_short_bearer_2001';
      const sentinelBasic = 'synthetic_basic_2002';

      const input =
          '''
Authorization: Bearer $sentinelShortBearer
authorization: basic $sentinelBasic
''';
      final result = Redactor.redact(input);

      expect(result.contains(sentinelShortBearer), isFalse);
      expect(result.contains(sentinelBasic), isFalse);

      expect(result.contains('Authorization: Bearer [REDACTED]'), isTrue);
      expect(result.contains('authorization: basic [REDACTED]'), isTrue);
    });

    test('脱敏单引号与双引号 JSON 结构，并保留安全上下文', () {
      const sentinelSinglePass = 'synthetic_single_pass_3001';
      const sentinelDoubleKey = 'synthetic_double_key_3002';

      const singleQuoted =
          "{'password': '$sentinelSinglePass', 'title': 'Interstellar'}";
      const doubleQuoted = '{"apiKey": "$sentinelDoubleKey", "status": 200}';

      final resSingle = Redactor.redact(singleQuoted);
      final resDouble = Redactor.redact(doubleQuoted);

      expect(resSingle.contains(sentinelSinglePass), isFalse);
      expect(resSingle.contains("'password': '[REDACTED]'"), isTrue);
      // 安全业务上下文保留
      expect(resSingle.contains("'title': 'Interstellar'"), isTrue);

      expect(resDouble.contains(sentinelDoubleKey), isFalse);
      expect(resDouble.contains('"apiKey": "[REDACTED]"'), isTrue);
      expect(resDouble.contains('"status": 200'), isTrue);
    });

    test('脱敏 Cookie 多值逗号边界与分号报头', () {
      const sentinelSess = 'synthetic_sess_4001';
      const sentinelAuth = 'synthetic_auth_4002';

      const inputLine = 'Cookie: a=$sentinelSess, b=$sentinelAuth';
      final resLine = Redactor.redact(inputLine);

      expect(resLine.contains(sentinelSess), isFalse);
      expect(resLine.contains(sentinelAuth), isFalse);
      expect(resLine, equals('Cookie: [REDACTED]'));

      const inputMap =
          '{Cookie: a=$sentinelSess, b=$sentinelAuth, Content-Type: application/json}';
      final resMap = Redactor.redact(inputMap);

      expect(resMap.contains(sentinelSess), isFalse);
      expect(resMap.contains(sentinelAuth), isFalse);
      expect(resMap.contains('Content-Type: application/json'), isTrue);
      expect(
        resMap.contains('{Cookie: [REDACTED], Content-Type: application/json}'),
        isTrue,
      );
    });

    test('脱敏未加引号的 Map 敏感字段', () {
      const sentinelToken = 'synthetic_token_5001';
      const input = '{token: $sentinelToken, count: 42}';

      final result = Redactor.redact(input);

      expect(result.contains(sentinelToken), isFalse);
      expect(result.contains('token: [REDACTED]'), isTrue);
      expect(result.contains('count: 42'), isTrue);
    });

    test('脱敏 StackTrace 中的网络 URL 同时保留调用栈诊断链路', () {
      const sentinelUrlToken = 'synthetic_stack_tok_6001';
      final fakeStack = StackTrace.fromString('''
#0  ApiClient.request (https://api.reelva.dev/v1/auth?token=$sentinelUrlToken)
#1  main (package:reelva/main.dart:10:5)
''');

      final sanitized = Redactor.redactStackTrace(fakeStack);
      expect(sanitized, isNotNull);

      final stackStr = sanitized.toString();
      expect(stackStr.contains(sentinelUrlToken), isFalse);
      expect(stackStr.contains('[REDACTED_URL]'), isTrue);
      expect(stackStr.contains('ApiClient.request'), isTrue);
      expect(stackStr.contains('package:reelva/main.dart:10:5'), isTrue);
    });
  });
}
