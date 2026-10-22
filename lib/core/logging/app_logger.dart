import 'dart:developer' as developer;

import 'redactor.dart';

/// 日志输出接收函数，供测试或自定义捕获使用
typedef LogOutputSink = void Function(
  String message, {
  Object? error,
  StackTrace? stackTrace,
});

/// Reelva 统一脱敏日志器（不可变）
///
/// 统一且仅在此处执行一次脱敏，严禁原始异常或凭据直接穿透至输出。
class AppLogger {
  const AppLogger({this.sink});

  final LogOutputSink? sink;

  /// 全局共享不可变单例
  static const AppLogger instance = AppLogger();

  /// 记录错误日志（自动对 message、error 及 stackTrace 进行单次脱敏）
  void error(String message, {Object? error, StackTrace? stackTrace}) {
    final sanitizedMessage = Redactor.redact(message);
    final sanitizedError = error != null
        ? Redactor.redact(error.toString())
        : null;
    final sanitizedStackTrace = Redactor.redactStackTrace(stackTrace);

    final targetSink = sink;
    if (targetSink != null) {
      targetSink(
        sanitizedMessage,
        error: sanitizedError,
        stackTrace: sanitizedStackTrace,
      );
    } else {
      developer.log(
        sanitizedMessage,
        name: 'Reelva',
        level: 1000,
        error: sanitizedError,
        stackTrace: sanitizedStackTrace,
      );
    }
  }
}
