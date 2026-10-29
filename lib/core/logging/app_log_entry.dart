import 'dart:convert';

enum AppLogLevel { info, warning, error }

/// 由 AppLogger 完成脱敏后生成的日志记录。
class AppLogEntry {
  const AppLogEntry({
    required this.time,
    required this.level,
    required this.module,
    required this.message,
    this.error,
    this.stackTrace,
  });

  final DateTime time;
  final AppLogLevel level;
  final String module;
  final String message;
  final String? error;
  final String? stackTrace;

  String get text => [
    '${time.toLocal().toIso8601String()} [${level.name}] [$module] $message',
    ?error,
    ?stackTrace,
  ].join('\n');

  String toJsonLine() => jsonEncode({
    'time': time.toUtc().toIso8601String(),
    'level': level.name,
    'module': module,
    'message': message,
    if (error != null) 'error': error,
    if (stackTrace != null) 'stackTrace': stackTrace,
  });

  /// 进程中断可能留下未写完的一行，读取时跳过该行。
  static AppLogEntry? tryParse(String line) {
    try {
      final data = jsonDecode(line) as Map<String, dynamic>;
      return AppLogEntry(
        time: DateTime.parse(data['time'] as String),
        level: AppLogLevel.values.byName(data['level'] as String),
        module: data['module'] as String,
        message: data['message'] as String,
        error: data['error'] as String?,
        stackTrace: data['stackTrace'] as String?,
      );
    } on FormatException {
      return null;
    } on TypeError {
      return null;
    } on ArgumentError {
      return null;
    }
  }
}
