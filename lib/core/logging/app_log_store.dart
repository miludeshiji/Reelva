import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'app_log_entry.dart';
import 'redactor.dart';

/// 日志独立于影视库保存；所有文件操作串行执行，清空和导出也进入同一队列。
class AppLogStore extends ChangeNotifier with WidgetsBindingObserver {
  AppLogStore({
    this.maxEntries = 500,
    this.maxFileBytes = 2 * 1024 * 1024,
    this.fileCount = 3,
  }) : assert(maxEntries > 0),
       assert(maxFileBytes > 0),
       assert(fileCount > 0);

  static final instance = AppLogStore();

  final int maxEntries;
  final int maxFileBytes;
  final int fileCount;
  final DateTime startedAt = DateTime.now();
  final _entries = ListQueue<AppLogEntry>();
  Future<void> _queue = Future<void>.value();
  Future<void>? _initialization;
  Directory? _directory;
  RandomAccessFile? _file;
  int _fileBytes = 0;
  Timer? _flushTimer;
  bool _closed = false;
  bool _notificationPending = false;
  String? _storageError;

  List<AppLogEntry> get entries => List.unmodifiable(_entries);
  String? get storageError => _storageError;

  Future<void> initialize({Directory? directory}) {
    if (_initialization != null) return _initialization!;
    final earlyEntries = entries;
    return _initialization = _enqueue(() async {
      _directory =
          directory ??
          Directory(
            p.join((await getApplicationSupportDirectory()).path, 'logs'),
          );
      await _directory!.create(recursive: true);
      final history = await _readHistory();
      final current = entries;
      _entries.clear();
      for (final entry in [...history, ...current]) {
        _remember(entry);
      }
      await _openFile();
      for (final entry in earlyEntries) {
        await _append(entry);
      }
      if (!_closed) {
        WidgetsBinding.instance.addObserver(this);
        _flushTimer = Timer.periodic(
          const Duration(seconds: 2),
          (_) => unawaited(flush()),
        );
      }
      _changed();
    });
  }

  void add(AppLogEntry entry) {
    if (_closed) return;
    _remember(entry);
    _changed();
    if (_initialization != null) unawaited(_enqueue(() => _append(entry)));
  }

  void _remember(AppLogEntry entry) {
    _entries.addLast(entry);
    if (_entries.length > maxEntries) _entries.removeFirst();
  }

  void _changed() {
    if (_closed || _notificationPending) return;
    _notificationPending = true;
    scheduleMicrotask(() {
      _notificationPending = false;
      if (!_closed) notifyListeners();
    });
  }

  Future<void> _enqueue(Future<void> Function() action) {
    return _queue = _queue.then((_) async {
      try {
        await action();
      } catch (error, stack) {
        _storageError = '日志文件暂不可用，当前日志仍可查看和复制。';
        final failedFile = _file;
        _file = null;
        try {
          await failedFile?.close();
        } on FileSystemException {
          // 原始写入失败已在下方记录，避免再次通过日志文件报告。
        }
        developer.log(
          '日志文件操作失败',
          name: 'Reelva',
          level: 900,
          error: Redactor.redact(error.toString()),
          stackTrace: Redactor.redactStackTrace(stack),
        );
        _changed();
      }
    });
  }

  File _logFile(int index) =>
      File(p.join(_directory!.path, 'reelva.$index.jsonl'));

  Future<List<AppLogEntry>> _readHistory() async {
    final result = ListQueue<AppLogEntry>();
    for (var index = fileCount - 1; index >= 0; index--) {
      final file = _logFile(index);
      if (!await file.exists()) continue;
      await for (final line
          in file
              .openRead()
              .transform(const Utf8Decoder(allowMalformed: true))
              .transform(const LineSplitter())) {
        final entry = AppLogEntry.tryParse(line);
        if (entry == null) continue;
        result.add(entry);
        if (result.length > maxEntries) result.removeFirst();
      }
    }
    return result.toList();
  }

  Future<void> _openFile() async {
    final file = _logFile(0);
    // 写入中断留下的半行以换行隔开，避免吞掉下一条有效日志。
    if (await file.exists() && await file.length() > 0) {
      final reader = await file.open();
      try {
        await reader.setPosition(await reader.length() - 1);
        if (await reader.readByte() != 10) {
          await file.writeAsString('\n', mode: FileMode.append);
        }
      } finally {
        await reader.close();
      }
    }
    _file = await file.open(mode: FileMode.append);
    _fileBytes = await _file!.length();
  }

  Future<void> _append(AppLogEntry entry) async {
    if (_file == null) return;
    final bytes = utf8.encode('${entry.toJsonLine()}\n');
    if (_fileBytes + bytes.length > maxFileBytes && _fileBytes > 0) {
      await _file!.close();
      _file = null;
      final oldest = _logFile(fileCount - 1);
      if (await oldest.exists()) await oldest.delete();
      for (var index = fileCount - 2; index >= 0; index--) {
        final file = _logFile(index);
        if (await file.exists()) await file.rename(_logFile(index + 1).path);
      }
      await _openFile();
    }
    await _file!.writeFrom(bytes);
    _fileBytes += bytes.length;
    if (entry.level == AppLogLevel.error) await _file!.flush();
  }

  Future<void> flush() => _enqueue(() async {
    await _file?.flush();
  });

  /// 新日志在清空请求之后继续保留，已有的落盘任务在删除前完成。
  Future<void> clear() {
    _entries.clear();
    _changed();
    if (_initialization == null) return Future<void>.value();
    return _enqueue(() async {
      await _file?.close();
      _file = null;
      if (_directory == null) return;
      for (var index = 0; index < fileCount; index++) {
        final file = _logFile(index);
        if (await file.exists()) await file.delete();
      }
      await _openFile();
      _storageError = null;
      _changed();
    });
  }

  Future<String> exportText({required String appVersion}) async {
    final output = StringBuffer()
      ..writeln('Reelva $appVersion')
      ..writeln(
        '系统：${Platform.operatingSystem} ${Platform.operatingSystemVersion}',
      )
      ..writeln('本次启动：${startedAt.toLocal().toIso8601String()}')
      ..writeln('导出时间：${DateTime.now().toLocal().toIso8601String()}')
      ..writeln();
    if (_initialization == null || _storageError != null) {
      for (final entry in entries) {
        output
          ..writeln(entry.text)
          ..writeln();
      }
      return output.toString();
    }
    var result = '';
    await _enqueue(() async {
      await _file?.flush();
      final saved = <AppLogEntry>[];
      if (_directory != null && _storageError == null) {
        for (var index = fileCount - 1; index >= 0; index--) {
          final file = _logFile(index);
          if (!await file.exists()) continue;
          await for (final line
              in file
                  .openRead()
                  .transform(const Utf8Decoder(allowMalformed: true))
                  .transform(const LineSplitter())) {
            final entry = AppLogEntry.tryParse(line);
            if (entry != null) saved.add(entry);
          }
        }
      }
      for (final entry in saved.isEmpty ? entries : saved) {
        output
          ..writeln(entry.text)
          ..writeln();
      }
      result = output.toString();
    });
    if (result.isEmpty) throw const FileSystemException('无法读取日志文件');
    return result;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) unawaited(flush());
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _flushTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    if (_initialization == null) {
      super.dispose();
      return;
    }
    await _enqueue(() async {
      await _file?.flush();
      await _file?.close();
      _file = null;
    });
    super.dispose();
  }
}
