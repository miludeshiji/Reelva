import 'dart:developer' as developer;

import 'app_log_entry.dart';
import 'app_log_store.dart';
import 'redactor.dart';

/// 日志输出接收函数，供测试或自定义捕获使用
typedef LogOutputSink = void Function(
  String message, {
  Object? error,
  StackTrace? stackTrace,
});

/// Reelva 统一脱敏日志入口。
///
/// 统一且仅在此处执行一次脱敏，严禁原始异常或凭据直接穿透至输出。
class AppLogger {
  const AppLogger({this.sink, this.store});

  final LogOutputSink? sink;
  final AppLogStore? store;

  /// 全局共享不可变单例
  static const AppLogger instance = AppLogger();

  void info(String message, {String module = '应用'}) =>
      _write(AppLogLevel.info, message, module: module);

  void warning(
    String message, {
    String module = '应用',
    Object? error,
    StackTrace? stackTrace,
  }) => _write(
    AppLogLevel.warning,
    message,
    module: module,
    error: error,
    stackTrace: stackTrace,
  );

  void error(
    String message, {
    String module = '应用',
    Object? error,
    StackTrace? stackTrace,
  }) => _write(
    AppLogLevel.error,
    message,
    module: module,
    error: error,
    stackTrace: stackTrace,
  );

  static String _sanitize(String value, int limit) {
    final safe = Redactor.redact(value);
    return safe.length <= limit ? safe : '${safe.substring(0, limit)}…[已截断]';
  }

  void _write(
    AppLogLevel level,
    String message, {
    required String module,
    Object? error,
    StackTrace? stackTrace,
  }) {
    final sanitizedMessage = _sanitize(message, 4000);
    final sanitizedError = error != null
        ? _sanitize(error.toString(), 4000)
        : null;
    final sanitizedStackTrace = stackTrace != null
        ? StackTrace.fromString(_sanitize(stackTrace.toString(), 8000))
        : null;
    final entry = AppLogEntry(
      time: DateTime.now(),
      level: level,
      module: _sanitize(module, 80),
      message: sanitizedMessage,
      error: sanitizedError,
      stackTrace: sanitizedStackTrace?.toString(),
    );

    final targetSink = sink;
    if (store != null || targetSink == null) {
      (store ?? AppLogStore.instance).add(entry);
    }
    if (targetSink != null) {
      targetSink(
        sanitizedMessage,
        error: sanitizedError,
        stackTrace: sanitizedStackTrace,
      );
    } else {
      developer.log(
        sanitizedMessage,
        name: 'Reelva.${entry.module}',
        level: switch (level) {
          AppLogLevel.info => 800,
          AppLogLevel.warning => 900,
          AppLogLevel.error => 1000,
        },
        error: sanitizedError,
        stackTrace: sanitizedStackTrace,
      );
    }
  }
}
