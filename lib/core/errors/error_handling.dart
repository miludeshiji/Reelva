import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../logging/app_logger.dart';
import 'safe_error_widget.dart';

/// 安装全局统一错误处理与日志收集
///
/// 应在 [WidgetsFlutterBinding.ensureInitialized()] 之后、[runApp()] 之前调用。
///
/// 1. 路由 [FlutterError.onError] 与 [PlatformDispatcher.instance.onError] 至 [logger]；
/// 2. 脱敏由 [logger] 统一处理，hooks 不进行重复脱敏；
/// 3. 设置 [ErrorWidget.builder] 返回通用友好的 [SafeErrorWidget]；
/// 4. 移除生产级全局还原状态，测试环境由测试用例自行保存/还原全局钩子。
void installErrorHandling({AppLogger? logger}) {
  final targetLogger = logger ?? AppLogger.instance;

  FlutterError.onError = (FlutterErrorDetails details) {
    targetLogger.error(
      'Flutter framework error: ${details.summary}',
      error: details.exception,
      stackTrace: details.stack,
    );
  };

  PlatformDispatcher.instance.onError =
      (Object exception, StackTrace stackTrace) {
        targetLogger.error(
          'Platform unhandled error',
          error: exception,
          stackTrace: stackTrace,
        );
        return true;
      };

  ErrorWidget.builder = (FlutterErrorDetails details) {
    return const SafeErrorWidget();
  };
}
