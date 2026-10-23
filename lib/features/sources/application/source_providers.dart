import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../../../core/logging/app_logger.dart';
import '../../library/infrastructure/media_library_repository.dart';
import '../domain/media_source_adapter.dart';
import '../domain/source_models.dart';
import '../infrastructure/android_saf_source_adapter.dart';
import '../infrastructure/local_source_adapter.dart';
import 'scan_progress.dart';
import 'source_controller.dart';

export 'scan_progress.dart';
export 'source_controller.dart';

/// 运行时平台覆写 Provider（主要供测试注入）
final platformOverrideProvider = Provider<TargetPlatform?>((ref) => null);

/// 全局 Drift 应用数据库 Provider
///
/// 在 Provider 销毁时安全关闭数据库连接，异常由 [AppLogger] 统一脱敏记录。
final appDatabaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(() async {
    try {
      await db.close();
    } catch (e, st) {
      AppLogger.instance.error('关闭数据库失败', error: e, stackTrace: st);
    }
  });
  return db;
});

/// 媒体库统一数据仓储 Provider
final mediaLibraryRepositoryProvider = Provider<MediaLibraryRepository>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return MediaLibraryRepository(db);
});

/// 媒体源适配器注册表 Provider
///
/// 包含 LocalSourceAdapter 与 AndroidSafSourceAdapter；构造器中不执行任何插件调用。
final sourceAdaptersProvider = Provider<Map<String, MediaSourceAdapter>>((ref) {
  return const {
    'local': LocalSourceAdapter(),
    'androidSaf': AndroidSafSourceAdapter(),
  };
});

/// 活跃媒体源列表流 Provider
final mediaSourcesProvider = StreamProvider<List<MediaSourceConfig>>((ref) {
  final repo = ref.watch(mediaLibraryRepositoryProvider);
  return repo.watchSources();
});

/// 影视库条目列表流 Provider（分页/数量限制）
final libraryVideosProvider = StreamProvider.autoDispose
    .family<List<LibraryVideo>, int>((ref, limit) {
      final repo = ref.watch(mediaLibraryRepositoryProvider);
      return repo.watchLibrary(limit: limit);
    });

/// 媒体源控制器 Provider，暴露实时扫描进度状态 `Map<int, ScanProgress>`
final sourceControllerProvider =
    NotifierProvider<SourceController, Map<int, ScanProgress>>(
      SourceController.new,
    );
