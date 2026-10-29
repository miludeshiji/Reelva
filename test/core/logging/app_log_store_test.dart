import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:reelva/core/logging/app_log_entry.dart';
import 'package:reelva/core/logging/app_log_store.dart';
import 'package:reelva/core/logging/app_logger.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late List<AppLogStore> stores;

  AppLogStore createStore({int maxEntries = 3, int maxFileBytes = 700}) {
    final store = AppLogStore(
      maxEntries: maxEntries,
      maxFileBytes: maxFileBytes,
    );
    stores.add(store);
    return store;
  }

  AppLogger loggerFor(AppLogStore store) =>
      AppLogger(store: store, sink: (_, {error, stackTrace}) {});

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('reelva_logs_');
    stores = [];
  });
  tearDown(() async {
    for (final store in stores) {
      await store.close();
    }
    await directory.delete(recursive: true);
  });

  test('模块、消息、异常和堆栈在内存、文件和导出中均脱敏', () async {
    final store = createStore(maxFileBytes: 128 * 1024);
    await store.initialize(directory: directory);
    final logger = loggerFor(store);
    logger.info('普通记录', module: '扫描');
    logger.warning('Authorization: Bearer synthetic_log_authorization');
    logger.error(
      '访问 https://example.invalid/video?sign=synthetic_log_signature 失败',
      module: 'Cookie: session=synthetic_module_cookie',
      error: 'password: synthetic_log_password',
      stackTrace: StackTrace.fromString(
        '#0 fetch (https://example.invalid/?token=synthetic_stack_token)\n'
        '#1 main (package:reelva/main.dart:10:5)',
      ),
    );
    await store.flush();
    final saved = await File('${directory.path}/reelva.0.jsonl').readAsString();
    final exported = await store.exportText(appVersion: '1.2.3+4');
    for (final output in [
      saved,
      exported,
      ...store.entries.map((e) => e.text),
    ]) {
      for (final secret in [
        'synthetic_log_authorization',
        'synthetic_log_signature',
        'synthetic_module_cookie',
        'synthetic_log_password',
        'synthetic_stack_token',
      ]) {
        expect(output, isNot(contains(secret)));
      }
    }
    expect(store.entries.map((e) => e.level), AppLogLevel.values);
    expect(exported, contains('[REDACTED_URL]'));
    expect(exported, contains('package:reelva/main.dart:10:5'));
    expect(exported, contains('Reelva 1.2.3+4'));
  });

  test('初始化前和初始化期间的日志恰好写入一次', () async {
    final store = createStore();
    final logger = loggerFor(store);
    logger.info('before initialization');
    final initialization = store.initialize(directory: directory);
    logger.info('during initialization');
    await initialization;
    logger.info('after initialization');
    await store.flush();
    final lines = await File('${directory.path}/reelva.0.jsonl').readAsLines();
    expect(lines.map(AppLogEntry.tryParse).map((e) => e!.message), [
      'before initialization',
      'during initialization',
      'after initialization',
    ]);
  });

  test('按字节轮转并限制内存，导出包含全部保留文件，重启恢复最近记录', () async {
    final store = createStore();
    await store.initialize(directory: directory);
    final logger = loggerFor(store);
    for (var i = 0; i < 18; i++) {
      logger.info('event[$i] ${'片' * 35}');
    }
    await store.flush();
    final files = await directory
        .list()
        .where((e) => e is File)
        .cast<File>()
        .toList();
    expect(files, hasLength(3));
    for (final file in files) {
      expect(await file.length(), lessThanOrEqualTo(700));
    }
    expect(store.entries, hasLength(3));
    final retained = <AppLogEntry>[];
    for (var index = 2; index >= 0; index--) {
      final lines = await File('${directory.path}/reelva.$index.jsonl')
          .readAsLines();
      retained.addAll(lines.map(AppLogEntry.tryParse).whereType<AppLogEntry>());
    }
    expect(retained.length, greaterThan(store.entries.length));
    final exported = await store.exportText(appVersion: 'test');
    expect(exported, isNot(contains('event[0]')));
    var previousOffset = -1;
    for (final entry in retained) {
      final offset = exported.indexOf(entry.message);
      expect(offset, greaterThan(previousOffset));
      previousOffset = offset;
    }
    final expected = store.entries.map((e) => e.text).toList();
    await store.close();
    final restored = createStore();
    await restored.initialize(directory: directory);
    expect(restored.entries.map((e) => e.text), expected);
  });

  test('清空等待之前的写入，新记录保留且重启后旧日志不会回来', () async {
    final store = createStore();
    await store.initialize(directory: directory);
    final logger = loggerFor(store);
    for (var i = 0; i < 12; i++) {
      logger.info('old[$i] ${'x' * 80}');
    }
    final clearing = store.clear();
    logger.info('new event');
    await clearing;
    final exported = await store.exportText(appVersion: 'test');
    expect(exported, isNot(contains('old[')));
    expect(exported, contains('new event'));
    expect(store.entries.single.message, 'new event');
    await store.close();
    final restored = createStore();
    await restored.initialize(directory: directory);
    expect(restored.entries.single.message, 'new event');
  });

  test('跳过进程中断留下的半行，后续记录可继续追加并恢复', () async {
    final store = createStore();
    await store.initialize(directory: directory);
    loggerFor(store).info('before interrupted write');
    await store.close();
    await File('${directory.path}/reelva.0.jsonl')
        .writeAsString('{"time":"interrupted', mode: FileMode.append);
    final restarted = createStore();
    await restarted.initialize(directory: directory);
    loggerFor(restarted).info('after interrupted write');
    await restarted.close();
    final restored = createStore();
    await restored.initialize(directory: directory);
    expect(restored.entries.map((e) => e.message), [
      'before interrupted write',
      'after interrupted write',
    ]);
  });

  test('目录不可写时继续在内存留存并导出', () async {
    final blocker = File('${directory.path}/blocked');
    await blocker.writeAsString('not a directory');
    final store = createStore();
    await store.initialize(directory: Directory(blocker.path));
    loggerFor(store).error('still available');
    await store.flush();
    expect(store.storageError, isNotNull);
    expect(store.entries.single.message, 'still available');
    expect(
      await store.exportText(appVersion: 'test'),
      contains('still available'),
    );
  });

  test('先脱敏再截断，日志内容长度有界且保留截断标记', () async {
    final store = createStore();
    loggerFor(store).error(
      '${'a' * 3970} password: ${'synthetic_private_value' * 200}',
      stackTrace: StackTrace.fromString('#0 frame\n${'s' * 10000}'),
    );
    final entry = store.entries.single;
    expect(entry.message, isNot(contains('synthetic_private')));
    expect(entry.message, contains('[REDACTED]'));
    expect(entry.stackTrace, startsWith('#0 frame'));
    expect(entry.stackTrace, endsWith('[已截断]'));
    expect(entry.stackTrace!.length, lessThan(8100));
  });
}
