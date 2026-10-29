import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reelva/app/theme/reelva_theme.dart';
import 'package:reelva/core/logging/app_log_store.dart';
import 'package:reelva/core/logging/app_logger.dart';
import 'package:reelva/core/logging/log_exporter.dart';
import 'package:reelva/features/settings/logs_page.dart';

class _Exporter extends LogExporter {
  String? text;

  @override
  Future<bool> export(AppLogStore store) async {
    text = await store.exportText(appVersion: 'test');
    return true;
  }
}

void main() {
  late AppLogStore store;
  late AppLogger logger;
  late _Exporter exporter;
  String? clipboard;

  setUp(() {
    store = AppLogStore();
    logger = AppLogger(store: store, sink: (_, {error, stackTrace}) {});
    exporter = _Exporter();
    clipboard = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') {
            clipboard =
                (call.arguments as Map<Object?, Object?>)['text'] as String;
          }
          return null;
        });
  });
  tearDown(() async {
    await store.close();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  Widget app({double textScale = 1}) => MaterialApp(
    theme: ReelvaTheme.light,
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context)
          .copyWith(textScaler: TextScaler.linear(textScale)),
      child: child!,
    ),
    home: LogsPage(store: store, exporter: exporter),
  );

  testWidgets('实时更新、等级和模块搜索、展开复制以及导出全部日志', (tester) async {
    logger.info('扫描完成', module: '扫描');
    logger.warning('网络超时', module: '网络');
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    logger.error('播放器异常', module: '播放器', error: 'token: synthetic_page_secret');
    await tester.pumpAndSettle();
    expect(find.text('播放器异常'), findsOneWidget);
    await tester.tap(find.widgetWithText(ChoiceChip, '错误'));
    await tester.pumpAndSettle();
    expect(find.text('扫描完成'), findsNothing);
    expect(find.text('播放器异常'), findsOneWidget);
    await tester.tap(find.text('播放器异常'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, '复制'));
    await tester.pumpAndSettle();
    expect(clipboard, contains('token: [REDACTED]'));
    expect(clipboard, isNot(contains('synthetic_page_secret')));
    await tester.tap(find.byKey(const Key('logs_menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('导出全部日志'));
    await tester.pumpAndSettle();
    expect(exporter.text, contains('扫描完成'));
    expect(exporter.text, contains('网络超时'));
    expect(exporter.text, contains('播放器异常'));
    await tester.tap(find.widgetWithText(ChoiceChip, '全部'));
    await tester.enterText(find.byKey(const Key('logs_search')), '网络');
    await tester.pumpAndSettle();
    expect(find.text('网络超时'), findsOneWidget);
    expect(find.text('扫描完成'), findsNothing);
    await tester.enterText(find.byKey(const Key('logs_search')), '找不到');
    await tester.pumpAndSettle();
    expect(find.text('没有符合条件的日志'), findsOneWidget);
  });

  testWidgets('清空后列表和导出都不含旧记录，之后的新日志继续显示', (tester) async {
    logger.info('旧记录');
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('logs_menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('清空全部日志'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '清空'));
    await tester.pumpAndSettle();
    expect(find.text('暂无日志'), findsOneWidget);
    expect(await store.exportText(appVersion: 'test'), isNot(contains('旧记录')));
    logger.info('新记录');
    await tester.pumpAndSettle();
    expect(find.text('新记录'), findsOneWidget);
  });

  testWidgets('窄屏和放大字体可筛选及阅读日志，无布局溢出', (tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    logger.error('较长的播放器错误诊断消息，用于检查日志卡片在窄屏下的换行。', module: '播放器');
    await tester.pumpWidget(app(textScale: 1.5));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ChoiceChip, '错误'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('logs_list')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
