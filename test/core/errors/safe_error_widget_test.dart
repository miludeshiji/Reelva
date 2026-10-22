import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reelva/core/errors/error_handling.dart';
import 'package:reelva/core/logging/app_logger.dart';

void main() {
  group('SafeErrorWidget 真实崩溃安全 UI 测试', () {
    setUp(() {
      final origFlutter = FlutterError.onError;
      final origPlatform = PlatformDispatcher.instance.onError;
      final origBuilder = ErrorWidget.builder;

      addTearDown(() {
        FlutterError.onError = origFlutter;
        PlatformDispatcher.instance.onError = origPlatform;
        ErrorWidget.builder = origBuilder;
      });
    });

    testWidgets('全局安装后，组件 build 崩溃时呈现 SafeErrorWidget 且绝不展示敏感凭据', (
      tester,
    ) async {
      final logger = AppLogger(sink: (msg, {error, stackTrace}) {});
      installErrorHandling(logger: logger);

      const sentinelSecret = 'synthetic_build_secret_9001';

      final faultyWidget = Builder(
        builder: (context) {
          throw StateError('Build failed with token: $sentinelSecret');
        },
      );

      await tester.pumpWidget(MaterialApp(home: Scaffold(body: faultyWidget)));

      // 用户可见树中展示安全通用中文提示
      expect(find.text('界面加载遇到问题'), findsOneWidget);
      expect(find.text('请稍后重试'), findsOneWidget);

      // 严格隐私断言：敏感凭据在整个界面中绝不呈现
      expect(find.textContaining(sentinelSecret), findsNothing);
      expect(find.textContaining('StateError'), findsNothing);
    });
  });
}
