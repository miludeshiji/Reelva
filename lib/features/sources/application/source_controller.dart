import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../../core/logging/app_logger.dart';
import '../../library/domain/library_work.dart';
import '../../player/domain/playback_playlist_entry.dart';
import '../../player/domain/playback_resource.dart';
import '../domain/source_models.dart';
import '../infrastructure/remote_credentials_store.dart';
import 'source_providers.dart';
import 'source_subtitles.dart';
import '../../metadata/application/nfo_providers.dart';
import '../../metadata/application/nfo_service.dart';

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
  /// 用户取消选择则返回 null；选择成功后持久化源、触发初次扫描并返回媒体源。
  Future<MediaSourceConfig?> addDirectory({
    String? name,
    List<String> extensions = defaultVideoExtensions,
    List<String> excludedDirectories = defaultExcludedDirectories,
    bool scanAfterAdd = true,
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
      return null;
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

    if (scanAfterAdd) unawaited(refreshSource(source.id));
    return source;
  }

  /// 添加或更新远程媒体源（WebDAV / SMB）
  ///
  /// - 校验并清洗根目录定位符（移除嵌入的凭据与 query 参数）；
  /// - 重复添加相同类型的相同根目录时，更新凭据与配置，不产生孤儿凭据；
  /// - 若当前媒体源正在扫描，先取消并等待其优雅退出，再更新凭据；
  /// - 添加或更新完成后触发初次扫描。
  Future<MediaSourceConfig> addRemoteSource({
    required String kind,
    required String rootUrl,
    String? name,
    RemoteCredentials credentials = const RemoteCredentials(),
    List<String> extensions = defaultVideoExtensions,
    List<String> excludedDirectories = defaultExcludedDirectories,
  }) async {
    final sanitizedRoot = sanitizeAndValidateRootLocator(
      kind: kind,
      rawInput: rootUrl,
    );

    final displayName = name != null && name.trim().isNotEmpty
        ? name.trim()
        : _defaultNameForLocator(kind, sanitizedRoot);

    final repo = ref.read(mediaLibraryRepositoryProvider);
    final credStore = ref.read(remoteCredentialsStoreProvider);

    final existing = await repo.findSourceByRoot(kind, sanitizedRoot);
    if (existing != null) {
      cancelScan(existing.id);
      final inFlight = _activeScans[existing.id];
      if (inFlight != null) {
        try {
          await inFlight;
        } catch (_) {}
      }

      String? credRef = existing.credentialRef;
      if (!credentials.isAnonymous) {
        credRef ??= RemoteCredentialsStore.generateReference(kind);
        await credStore.write(credRef, credentials);
      } else if (credRef != null) {
        await credStore.delete(credRef);
        credRef = null;
      }

      final updated = await repo.upsertSource(
        kind: kind,
        rootLocator: sanitizedRoot,
        name: displayName,
        credentialRef: credRef,
        clearCredentialRef: credRef == null,
        extensions: extensions,
        excludedDirectories: excludedDirectories,
      );

      unawaited(refreshSource(updated.id));
      return updated;
    } else {
      String? credRef;
      bool createdInStore = false;
      if (!credentials.isAnonymous) {
        credRef = RemoteCredentialsStore.generateReference(kind);
        await credStore.write(credRef, credentials);
        createdInStore = true;
      }

      try {
        final created = await repo.upsertSource(
          kind: kind,
          rootLocator: sanitizedRoot,
          name: displayName,
          credentialRef: credRef,
          extensions: extensions,
          excludedDirectories: excludedDirectories,
        );

        unawaited(refreshSource(created.id));
        return created;
      } catch (e) {
        if (createdInStore && credRef != null) {
          try {
            await credStore.delete(credRef);
          } catch (_) {}
        }
        rethrow;
      }
    }
  }

  /// 更新已有媒体源的安全凭据
  ///
  /// - 保持原有根目录不变；
  /// - 若当前正在扫描，先取消并等待其优雅退出；
  /// - 密码与 Token 等机密更新至安全存储，失败时抛出安全异常；
  /// - 匿名凭据将清理已有的安全存储项，避免孤儿引用。
  Future<void> updateCredentials(int id, RemoteCredentials credentials) async {
    cancelScan(id);
    final inFlight = _activeScans[id];
    if (inFlight != null) {
      try {
        await inFlight;
      } catch (_) {}
    }

    final repo = ref.read(mediaLibraryRepositoryProvider);
    final credStore = ref.read(remoteCredentialsStoreProvider);
    final source = await repo.getSource(id);

    if (credentials.isAnonymous) {
      if (source.credentialRef != null) {
        await credStore.delete(source.credentialRef!);
        await repo.updateSourceCredentials(id, null);
      }
    } else {
      final credRef =
          source.credentialRef ??
          RemoteCredentialsStore.generateReference(source.kind);
      await credStore.write(credRef, credentials);
      if (source.credentialRef != credRef) {
        await repo.updateSourceCredentials(id, credRef);
      }
    }
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
    final credStore = ref.read(remoteCredentialsStoreProvider);
    final source = await repo.getSource(id);

    // 先删除安全存储中的凭据；若存储删除失败直接抛出异常，绝不声明删除成功导致机密残留
    if (source.credentialRef != null) {
      await credStore.delete(source.credentialRef!);
      await repo.updateSourceCredentials(id, null);
    }

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
  /// UI 层不直接执行原生调用或数据库查询。已匹配剧集携带集名与按季集排序的播放列表。
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
      final fileName = video.fileName.isNotEmpty
          ? video.fileName
          : resource.fileName;
      var displayName = fileName;
      final details = await repo.getWorkDetailsForFile(fileId);
      final playlist = <PlaybackPlaylistEntry>[];
      if (details != null) {
        final episodes = <(int, int), LibraryVersion>{};
        for (final version in details.versions) {
          if (version.episodeNumber == null) continue;
          final key = (version.seasonNumber ?? 1, version.episodeNumber!);
          final previous = episodes[key];
          if (previous == null ||
              version.fileId == fileId ||
              (previous.fileId != fileId &&
                  version.available &&
                  (!previous.available ||
                      (version.sourceName == video.sourceName &&
                          previous.sourceName != video.sourceName)))) {
            episodes[key] = version;
          }
        }
        for (final version in episodes.values) {
          final title = version.episodeTitle?.trim();
          playlist.add(
            PlaybackPlaylistEntry(
              fileId: version.fileId,
              title: title == null || title.isEmpty
                  ? '第 ${version.episodeNumber} 集'
                  : title,
              available: version.available,
              seasonNumber: version.seasonNumber,
              episodeNumber: version.episodeNumber,
            ),
          );
        }
        if (playlist.isEmpty) {
          if (details.work.metadataSource != 'local' ||
              details.work.metadataLocked) {
            displayName = details.work.title;
          }
          playlist.add(
            PlaybackPlaylistEntry(
              fileId: fileId,
              title: displayName,
              available: video.available,
            ),
          );
        } else {
          final current = playlist.where((entry) => entry.fileId == fileId);
          if (current.isNotEmpty) displayName = current.first.displayTitle;
        }
      }
      return resource.copyWith(
        displayName: displayName,
        fileName: fileName,
        playlist: List.unmodifiable(playlist),
        libraryFileId: () => fileId,
        sourceId: source.id,
        discoverSubtitles: () => discoverSourceSubtitles(
          source: source,
          adapter: adapter,
          videoId: video.externalId,
        ),
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

    final nfoContexts = <String, NfoDirectoryContext?>{};
    final nfoService = ref.read(nfoServiceProvider);
    final queue = Queue<String>();
    queue.add(source.rootLocator);
    final directoryPaths = <String, List<String>>{source.rootLocator: []};
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
        _safeSetState(
          (s) => {
            ...s,
            id: s[id]!.copyWith(visited: visitedCount, videos: videoCount),
          },
        );

        final directoryEntries = <MediaEntry>[];
        final childDirectories = <String>[];
        final stream = adapter.listEntries(source, currentDirId);
        await for (var entry in stream) {
          if (_cancellations[id] == true) {
            break;
          }

          // 忽略点开头的隐藏文件与目录
          if (entry.name.startsWith('.')) {
            continue;
          }

          if (source.kind == 'androidSaf') {
            final path = [...directoryPaths[currentDirId]!, entry.name];
            if (entry.isDirectory) directoryPaths[entry.externalId] = path;
            entry = MediaEntry(
              externalId: entry.externalId,
              locator: Uri(
                scheme: 'reelva-index',
                pathSegments: path,
              ).toString(),
              name: entry.name,
              isDirectory: entry.isDirectory,
              size: entry.size,
              modifiedAt: entry.modifiedAt,
              etag: entry.etag,
            );
          }
          directoryEntries.add(entry);
          if (entry.isDirectory) {
            if (excludedDirs.contains(entry.name.toLowerCase())) {
              continue;
            }

            if (visitedDirIds.add(entry.externalId)) {
              queue.add(entry.externalId);
              childDirectories.add(entry.externalId);
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
        if (_cancellations[id] != true) {
          if (batch.isNotEmpty) {
            await repo.applyScanBatch(id, scanId, batch);
            batch.clear();
          }
          final context = await nfoService.importDirectory(
            source,
            currentDirId,
            directoryEntries,
            inherited: nfoContexts[currentDirId],
            onError: (message) =>
                ref.read(nfoControllerProvider.notifier).reportError(message),
          );
          for (final child in childDirectories) {
            nfoContexts[child] = context;
          }
        }
        _safeSetState(
          (s) => {
            ...s,
            id: s[id]!.copyWith(visited: visitedCount, videos: videoCount),
          },
        );
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
    try {
      final origSanitized = sanitizeAndValidateRootLocator(
        kind: kind,
        rawInput: originalRoot,
      );
      final newSanitized = sanitizeAndValidateRootLocator(
        kind: kind,
        rawInput: newRoot,
      );
      return origSanitized == newSanitized;
    } catch (_) {
      return originalRoot.trim() == newRoot.trim();
    }
  }

  String _defaultNameForLocator(String kind, String locator) {
    switch (kind) {
      case 'webdav':
        final uri = Uri.tryParse(locator);
        if (uri != null && uri.host.isNotEmpty) {
          final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
          if (segments.isNotEmpty) {
            return '${uri.host}/${segments.last}';
          }
          return uri.host;
        }
        return 'WebDAV 源';
      case 'smb':
        final uri = Uri.tryParse(locator);
        if (uri != null && uri.host.isNotEmpty) {
          return '${uri.host}${uri.path}';
        }
        return 'SMB 源';
      default:
        return '远程媒体源';
    }
  }
}
