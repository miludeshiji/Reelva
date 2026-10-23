import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../../core/logging/app_logger.dart';
import '../../player/domain/playback_resource.dart';
import '../domain/source_models.dart';
import 'source_providers.dart';
import '../../metadata/application/metadata_providers.dart';

/// 媒体源应用层控制器
///
/// 管理源的增删改、重新授权、增量扫描、取消扫描与播放资源解析。
/// 状态为每个媒体源对应的实时扫描进度 `Map<int, ScanProgress>`。
class SourceController extends Notifier<Map<int, ScanProgress>> {
  final Map<int, Future<void>> _activeScans = {};
  final Map<int, bool> _cancellations = {};
  bool _disposed = false;

  @override
  Map<int, ScanProgress> build() {
    ref.onDispose(() {
      _disposed = true;
      for (final id in _cancellations.keys) {
        _cancellations[id] = true;
      }
    });
    return const <int, ScanProgress>{};
  }

  void _safeSetState(
    Map<int, ScanProgress> Function(Map<int, ScanProgress> current) updater,
  ) {
    if (!_disposed && ref.mounted) {
      state = updater(state);
    }
  }

  /// 添加媒体源目录
  ///
  /// 根据运行平台自动选择 Windows 本地适配器或 Android SAF 适配器；
  /// 用户取消选择则静默退出；选择成功后持久化源并立即触发初次扫描。
  Future<void> addDirectory({
    String? name,
    List<String> extensions = defaultVideoExtensions,
    List<String> excludedDirectories = defaultExcludedDirectories,
  }) async {
    final platform =
        ref.read(platformOverrideProvider) ?? defaultTargetPlatform;
    final kind = platform == TargetPlatform.android ? 'androidSaf' : 'local';

    final adapters = ref.read(sourceAdaptersProvider);
    final adapter = adapters[kind];
    if (adapter == null) {
      throw MediaSourceException(
        '当前平台不支持添加目录媒体源: $kind',
        code: 'unsupported_platform',
      );
    }

    final selection = await adapter.pickDirectory();
    if (selection == null) {
      return;
    }

    final displayName = name != null && name.trim().isNotEmpty
        ? name.trim()
        : selection.name;
    final repo = ref.read(mediaLibraryRepositoryProvider);
    final source = await repo.upsertSource(
      kind: selection.kind,
      rootLocator: selection.rootLocator,
      name: displayName,
      extensions: extensions,
      excludedDirectories: excludedDirectories,
    );

    await refreshSource(source.id);
  }

  /// 触发指定媒体源的增量刷新/重新扫描
  ///
  /// - 单飞机制：同一媒体源并发刷新直接复用正在进行的扫描；
  /// - 异步广度优先遍历子目录，跳过隐藏项、排除目录与已访问目录，防止死循环；
  /// - 批量（~100）提交数据库事务并节流更新进度，避免单文件频繁通知重建；
  /// - 关键异步操作之间及 finishScan 前严格检测取消标志；
  /// - 遇到权限错误或子目录枚举异常时整体失败，不回退为空列表，确保旧数据不被误标记离线。
  Future<void> refreshSource(int id) {
    final inFlight = _activeScans[id];
    if (inFlight != null) {
      return inFlight;
    }

    _cancellations[id] = false;
    final future = _executeScan(id);
    _activeScans[id] = future;
    future.whenComplete(() {
      _activeScans.remove(id);
      _cancellations.remove(id);
    });
    return future;
  }

  /// 取消正在进行的媒体源扫描
  ///
  /// 仅中断目录遍历与批次写入，不会撤销操作系统已授予的目录访问权限。
  void cancelScan(int id) {
    _cancellations[id] = true;
    _safeSetState((s) {
      final current = s[id];
      if (current == null) return s;
      return {...s, id: current.copyWith(cancelled: true)};
    });
  }

  /// 重命名媒体源
  Future<void> renameSource(int id, String name) async {
    final repo = ref.read(mediaLibraryRepositoryProvider);
    await repo.renameSource(id, name);
  }

  /// 移除媒体源（软失效）
  ///
  /// 若有正在运行的扫描任务，先行取消并等待其优雅退出；随后软停用该源，
  /// 物理文件不受影响，影视库历史与观看进度予以保留。
  Future<void> removeSource(int id) async {
    cancelScan(id);
    final inFlight = _activeScans[id];
    if (inFlight != null) {
      try {
        await inFlight;
      } catch (_) {}
    }

    final repo = ref.read(mediaLibraryRepositoryProvider);
    await repo.disableSource(id);
    _safeSetState(
      (s) => {
        ...s,
        id: (s[id] ?? const ScanProgress()).copyWith(
          running: false,
          cancelled: false,
        ),
      },
    );
  }

  /// 重新授权媒体源
  ///
  /// 调用系统选择器，若用户选择的原根目录一致则更新权限并触发刷新；
  /// 若用户选择了不同目录，展示安全的错误提示并引导用户通过“添加媒体源”操作。
  Future<void> reauthorizeSource(int id) async {
    final repo = ref.read(mediaLibraryRepositoryProvider);
    final source = await repo.getSource(id);

    final adapters = ref.read(sourceAdaptersProvider);
    final adapter = adapters[source.kind];
    if (adapter == null) {
      throw MediaSourceException(
        '未找到匹配的媒体源适配器: ${source.kind}',
        code: 'adapter_not_found',
      );
    }

    final selection = await adapter.pickDirectory(
      initialLocator: source.rootLocator,
    );
    if (selection == null) {
      return;
    }

    final isSameRoot = _checkSameRoot(
      source.kind,
      source.rootLocator,
      selection.rootLocator,
    );
    if (!isSameRoot) {
      const errorMsg = '所选目录与原媒体源根目录不一致，如需添加新目录请使用“添加媒体源”';
      _safeSetState(
        (s) => {
          ...s,
          id: (s[id] ?? const ScanProgress()).copyWith(error: errorMsg),
        },
      );
      throw const MediaSourceException(errorMsg, code: 'root_mismatch');
    }

    await refreshSource(id);
  }

  /// 将媒体文件解析为播放器可直接播放的资源
  ///
  /// 查询媒体文件 -> 检查所属启用的媒体源 -> 调用适配器解析播放 URI。
  /// UI 层不直接执行原生调用或数据库查询。保留库中持久化的真实文件名作为显示名。
  Future<PlaybackResource> resolvePlayback(int fileId) async {
    final repo = ref.read(mediaLibraryRepositoryProvider);
    final video = await repo.getVideo(fileId);
    if (video == null) {
      throw const MediaSourceException('未找到指定视频记录', code: 'video_not_found');
    }

    final source = await repo.getSource(video.sourceId);
    if (!source.enabled) {
      throw const MediaSourceException(
        '该媒体源已被停用，无法播放',
        code: 'source_disabled',
      );
    }

    final adapters = ref.read(sourceAdaptersProvider);
    final adapter = adapters[source.kind];
    if (adapter == null) {
      throw MediaSourceException(
        '未找到匹配的媒体源适配器: ${source.kind}',
        code: 'adapter_not_found',
      );
    }

    try {
      final resource = await adapter.resolvePlayback(source, video.externalId);
      final displayName = video.fileName.isNotEmpty
          ? video.fileName
          : resource.displayName;
      return PlaybackResource(
        uri: resource.uri,
        displayName: displayName,
        httpHeaders: resource.httpHeaders,
      );
    } on MediaSourceException {
      rethrow;
    } catch (e, st) {
      AppLogger.instance.error(
        '解析播放资源失败: fileId=$fileId',
        error: e,
        stackTrace: st,
      );
      throw const MediaSourceException(
        '解析播放资源失败，文件可能已移动或源离线',
        code: 'playback_resolution_failed',
      );
    }
  }

  Future<void> _executeScan(int id) async {
    _safeSetState(
      (s) => {
        ...s,
        id: const ScanProgress(
          running: true,
          visited: 0,
          videos: 0,
          cancelled: false,
          error: null,
        ),
      },
    );

    final repo = ref.read(mediaLibraryRepositoryProvider);
    MediaSourceConfig source;
    try {
      source = await repo.getSource(id);
    } catch (e, st) {
      AppLogger.instance.error('获取媒体源配置失败: $id', error: e, stackTrace: st);
      _safeSetState(
        (s) => {
          ...s,
          id: (s[id] ?? const ScanProgress()).copyWith(
            running: false,
            error: '获取媒体源配置失败',
          ),
        },
      );
      return;
    }

    if (!source.enabled) {
      _safeSetState(
        (s) => {...s, id: s[id]!.copyWith(running: false, error: '媒体源已停用')},
      );
      return;
    }

    int scanId;
    try {
      scanId = await repo.beginScan(id);
    } catch (e, st) {
      AppLogger.instance.error('启动扫描事务失败: $id', error: e, stackTrace: st);
      _safeSetState(
        (s) => {...s, id: s[id]!.copyWith(running: false, error: '无法启动扫描')},
      );
      return;
    }

    final adapters = ref.read(sourceAdaptersProvider);
    final adapter = adapters[source.kind];
    if (adapter == null) {
      const msg = '未找到匹配的媒体源适配器';
      await repo.failScan(id, msg);
      _safeSetState(
        (s) => {...s, id: s[id]!.copyWith(running: false, error: msg)},
      );
      return;
    }

    final validExtensions = source.extensions
        .map((e) => e.toLowerCase().replaceFirst('.', ''))
        .toSet();
    final excludedDirs = source.excludedDirectories
        .map((e) => e.toLowerCase())
        .toSet();

    final queue = Queue<String>();
    queue.add(source.rootLocator);
    final visitedDirIds = <String>{source.rootLocator};
    int visitedCount = 0;
    int videoCount = 0;
    final batch = <MediaEntry>[];
    const batchSize = 100;

    try {
      while (queue.isNotEmpty) {
        if (_cancellations[id] == true) {
          break;
        }

        final currentDirId = queue.removeFirst();
        visitedCount++;

        final stream = adapter.listEntries(source, currentDirId);
        await for (final entry in stream) {
          if (_cancellations[id] == true) {
            break;
          }

          // 忽略点开头的隐藏文件与目录
          if (entry.name.startsWith('.')) {
            continue;
          }

          if (entry.isDirectory) {
            if (excludedDirs.contains(entry.name.toLowerCase())) {
              continue;
            }

            if (visitedDirIds.add(entry.externalId)) {
              queue.add(entry.externalId);
              batch.add(entry);
            }
          } else {
            final ext = p
                .extension(entry.name)
                .replaceFirst('.', '')
                .toLowerCase();
            if (validExtensions.contains(ext)) {
              videoCount++;
              batch.add(entry);
            }
          }

          if (batch.length >= batchSize) {
            if (_cancellations[id] == true) {
              break;
            }
            await repo.applyScanBatch(id, scanId, batch);
            batch.clear();
            _safeSetState(
              (s) => {
                ...s,
                id: s[id]!.copyWith(visited: visitedCount, videos: videoCount),
              },
            );
          }
        }
      }

      if (_cancellations[id] == true) {
        _safeSetState(
          (s) => {
            ...s,
            id: s[id]!.copyWith(
              running: false,
              cancelled: true,
              visited: visitedCount,
              videos: videoCount,
            ),
          },
        );
        return;
      }

      if (batch.isNotEmpty) {
        await repo.applyScanBatch(id, scanId, batch);
        batch.clear();
      }

      if (_cancellations[id] == true) {
        _safeSetState(
          (s) => {
            ...s,
            id: s[id]!.copyWith(
              running: false,
              cancelled: true,
              visited: visitedCount,
              videos: videoCount,
            ),
          },
        );
        return;
      }

      await repo.finishScan(id, scanId);
      _safeSetState(
        (s) => {
          ...s,
          id: s[id]!.copyWith(
            running: false,
            cancelled: false,
            visited: visitedCount,
            videos: videoCount,
            clearError: true,
          ),
        },
      );
      // 扫描成功完成且状态更新后，在后台异步触发元数据识别与刷新
      if (ref.mounted) {
        unawaited(ref.read(metadataControllerProvider.notifier).refresh());
      }
    } catch (e, st) {
      AppLogger.instance.error('扫描媒体源失败: $id', error: e, stackTrace: st);
      final safeMessage = e is MediaSourceException
          ? e.message
          : '扫描媒体源失败，请检查网络或目录权限';
      try {
        await repo.failScan(id, safeMessage);
      } catch (err, s) {
        AppLogger.instance.error('更新扫描失败状态出错', error: err, stackTrace: s);
      }
      _safeSetState(
        (s) => {
          ...s,
          id: (s[id] ?? const ScanProgress()).copyWith(
            running: false,
            error: safeMessage,
          ),
        },
      );
    }
  }

  bool _checkSameRoot(String kind, String originalRoot, String newRoot) {
    if (kind == 'local') {
      final normOriginal = p
          .normalize(originalRoot)
          .replaceAll(r'\', '/')
          .toLowerCase();
      final normNew = p.normalize(newRoot).replaceAll(r'\', '/').toLowerCase();
      return normOriginal == normNew;
    }
    return originalRoot.trim() == newRoot.trim();
  }
}
