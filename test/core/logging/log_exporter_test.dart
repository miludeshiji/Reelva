import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:reelva/core/logging/app_log_store.dart';
import 'package:reelva/core/logging/app_logger.dart';
import 'package:reelva/core/logging/log_exporter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('reelva/log_export');
  late AppLogStore store;
  late MethodCall? captured;
  late bool accepted;

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    PackageInfo.setMockInitialValues(
      appName: 'Reelva',
      packageName: 'reelva',
      version: '1.2.3',
      buildNumber: '4',
      buildSignature: '',
    );
    store = AppLogStore();
    captured = null;
    accepted = true;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          captured = call;
          return accepted;
        });
  });
  tearDown(() async {
    await store.close();
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('Android 桥接接收带版本的 UTF-8 脱敏日志和文本文件名', () async {
    AppLogger(
      store: store,
      sink: (_, {error, stackTrace}) {},
    ).error('导出测试 password: synthetic_export_password');
    expect(await const LogExporter().export(store), isTrue);
    expect(captured!.method, 'save');
    final arguments = captured!.arguments as Map<Object?, Object?>;
    expect(arguments['name'], matches(r'^reelva-logs-\d+\.txt$'));
    final text = utf8.decode(arguments['data']! as Uint8List);
    expect(text, contains('Reelva 1.2.3+4'));
    expect(text, contains('导出测试'));
    expect(text, isNot(contains('synthetic_export_password')));
  });

  test('取消保存正常返回 false', () async {
    accepted = false;
    expect(await const LogExporter().export(store), isFalse);
    expect(store.entries, isEmpty);
  });
}
