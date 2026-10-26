import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/logging/app_logger.dart';
import '../../shared/widgets/empty_state_view.dart';
import '../../shared/widgets/glass_widgets.dart';
import '../library/presentation/manual_match_page.dart';
import '../metadata/application/metadata_providers.dart';
import '../metadata/domain/matching_file.dart';
import '../metadata/domain/tmdb_models.dart';
import 'application/source_browser.dart';
import 'application/source_providers.dart';
import 'domain/source_models.dart';

class SourceFilesPage extends ConsumerStatefulWidget {
  const SourceFilesPage({super.key, required this.sourceId});

  final int sourceId;

  @override
  ConsumerState<SourceFilesPage> createState() => _SourceFilesPageState();
}

class _SourceFilesPageState extends ConsumerState<SourceFilesPage> {
  SourceBrowser? _browser;
  final _path = <({String id, String name})>[];
  final _selected = <String, BrowsedMediaFile>{};
  Future<List<MediaEntry>>? _entries;
  String? _error;
  String? _result;
  bool _selecting = false;
  bool _matching = false;
  int _processed = 0;
  int _total = 0;
  int _activeCount = 0;

  @override
  void initState() {
    super.initState();
    _loadSource();
  }

  Future<void> _loadSource() async {
    final repo = ref.read(mediaLibraryRepositoryProvider);
    final adapters = ref.read(sourceAdaptersProvider);
    try {
      final source = await repo.getSource(widget.sourceId);
      if (!source.enabled) throw const MediaSourceException('媒体源已停用');
      final adapter = adapters[source.kind];
      if (adapter == null) throw const MediaSourceException('此媒体源暂时无法浏览');
      if (!mounted) return;
      setState(() {
        _browser = SourceBrowser(source: source, adapter: adapter);
        _path.add((id: source.rootLocator, name: source.name));
        _entries = _browser!.listDirectory(source.rootLocator);
        _error = null;
      });
    } catch (error, stackTrace) {
      AppLogger.instance.error(
        '打开媒体源目录失败',
        error: error,
        stackTrace: stackTrace,
      );
      if (mounted) {
        setState(
          () => _error = error is MediaSourceException
              ? error.message
              : '暂时无法打开媒体源，请检查连接或目录权限',
        );
      }
    }
  }

  void _navigateTo(int index) {
    setState(() {
      _path.removeRange(index + 1, _path.length);
      _entries = _browser!.listDirectory(_path.last.id);
      _error = null;
    });
  }

  void _openFolder(MediaEntry entry) {
    setState(() {
      _path.add((id: entry.externalId, name: entry.name));
      _entries = _browser!.listDirectory(entry.externalId);
      _error = null;
    });
  }

  void _refresh() {
    if (_browser == null) {
      _loadSource();
    } else {
      _browser!.refreshDirectory(_path.last.id);
      setState(() => _entries = _browser!.listDirectory(_path.last.id));
    }
  }

  bool? _selectionState(MediaEntry entry) {
    if (!entry.isDirectory) return _selected.containsKey(entry.externalId);
    final files = _browser!.cachedFileIdsUnder(
      entry.externalId,
      ancestors: _path.map((part) => part.id),
    );
    if (files != null &&
        files.isNotEmpty &&
        files.every(_selected.containsKey)) {
      return true;
    }
    if (_selected.values.any(
      (file) => file.directoryIds.contains(entry.externalId),
    )) {
      return null;
    }
    return false;
  }

  Future<void> _toggle(MediaEntry entry) async {
    if (_selecting || _matching) return;
    if (!entry.isDirectory) {
      setState(() {
        if (_selected.remove(entry.externalId) == null) {
          _selected[entry.externalId] = BrowsedMediaFile(
            entry: entry,
            directoryIds: _path.map((part) => part.id).toList(),
            directoryNames: _path.map((part) => part.name).toList(),
          );
        }
        _result = null;
      });
      return;
    }
    final select = _selectionState(entry) != true;
    final ids = [..._path.map((part) => part.id), entry.externalId];
    final names = [..._path.map((part) => part.name), entry.name];
    setState(() {
      _selecting = true;
      _error = null;
      _result = null;
    });
    try {
      final files = await _browser!.collectFiles(
        directoryIds: ids,
        directoryNames: names,
      );
      if (!mounted) return;
      setState(() {
        for (final file in files) {
          if (select) {
            _selected[file.entry.externalId] = file;
          } else {
            _selected.remove(file.entry.externalId);
          }
        }
        if (files.isEmpty) _result = '此文件夹中没有可匹配的视频';
      });
    } catch (error, stackTrace) {
      AppLogger.instance.error(
        '读取勾选文件夹失败',
        error: error,
        stackTrace: stackTrace,
      );
      if (mounted) {
        setState(
          () => _error = error is MediaSourceException
              ? error.message
              : '读取文件夹失败，原有选择已保留，请重试',
        );
      }
    } finally {
      if (mounted) setState(() => _selecting = false);
    }
  }

  Future<void> _match({required bool manual}) async {
    final repo = ref.read(mediaLibraryRepositoryProvider);
    final service = ref.read(metadataServiceProvider);
    final selected = _selected.values.toList();
    setState(() {
      _matching = true;
      _error = null;
      _result = null;
      _processed = 0;
      _total = selected.length;
      _activeCount = 0;
    });
    try {
      final ids = await repo.indexSourceFiles(
        widget.sourceId,
        selected.map((file) => file.entry).toList(),
      );
      final files = [
        for (final file in selected)
          MatchingFile(
            fileId: ids[file.entry.externalId]!,
            name: file.entry.name,
            directoryNames: file.directoryNames,
          ),
      ];
      if (!mounted) return;
      if (manual) {
        final first = files.first.parsed;
        final workId = await ManualMatchPage.show(
          context,
          files: files,
          initialTitle: first.title,
          initialYear: first.year,
        );
        if (mounted && workId != null) {
          setState(() {
            _selected.clear();
            _result = '手动匹配完成，影视库已更新';
          });
        }
      } else {
        final result = await service.matchFilesAutomatically(
          files,
          isCancelled: () => !mounted,
          onActiveChanged: (active) {
            if (mounted) setState(() => _activeCount = active);
          },
          onProgress: (processed, total) {
            if (mounted) {
              setState(() {
                _processed = processed;
                _total = total;
              });
            }
          },
        );
        if (!mounted) return;
        setState(() {
          _result =
              '已匹配 ${result.matched} 个视频 · ${result.needsReview} 个待确认 · ${result.skipped} 个已跳过'
              '${result.reviewReasons.isEmpty ? '' : '\n${result.reviewReasons.entries.map((entry) => '${entry.key.message}（${entry.value}）').join('\n')}'}';
          if (result.errors.isNotEmpty) _error = result.errors.join('\n');
          if (result.needsReview == 0 && result.errors.isEmpty) {
            _selected.clear();
          }
        });
      }
    } catch (error, stackTrace) {
      AppLogger.instance.error(
        '匹配所选媒体文件失败',
        error: error,
        stackTrace: stackTrace,
      );
      if (mounted) {
        setState(
          () => _error = error is MediaSourceException
              ? error.message
              : error is MetadataException
              ? error.message
              : '匹配失败，请稍后重试',
        );
      }
    } finally {
      if (mounted) setState(() => _matching = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final busy = _selecting || _matching;
    final actionStyle = OutlinedButton.styleFrom(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      minimumSize: const Size(0, 44),
    );
    return PopScope(
      canPop: _path.length <= 1,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && _path.length > 1) _navigateTo(_path.length - 2);
      },
      child: Scaffold(
        backgroundColor: ReelvaDesign.background,
        body: GlassBackground(
          child: SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: ReelvaDesign.contentMaxWidth,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: GlassPageHeader(
                            title: '源文件',
                            leading: GlassIconButton(
                              key: const Key('source_files_back_button'),
                              icon: Icons.arrow_back,
                              tooltip: '返回',
                              size: ReelvaDesign.pageHeaderButtonSize,
                              onPressed: () {
                                if (_path.length > 1) {
                                  _navigateTo(_path.length - 2);
                                } else {
                                  context.pop();
                                }
                              },
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.only(right: 24),
                          child: GlassIconButton(
                            icon: Icons.refresh,
                            tooltip: '刷新目录',
                            size: ReelvaDesign.pageHeaderButtonSize,
                            onPressed: busy ? null : _refresh,
                          ),
                        ),
                      ],
                    ),
                    if (_path.isNotEmpty)
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: Row(
                          children: [
                            for (
                              var index = 0;
                              index < _path.length;
                              index++
                            ) ...[
                              if (index > 0)
                                const Icon(
                                  Icons.chevron_right,
                                  size: 16,
                                  color: ReelvaDesign.muted,
                                ),
                              TextButton(
                                onPressed: () => _navigateTo(index),
                                child: Text(_path[index].name),
                              ),
                            ],
                          ],
                        ),
                      ),
                    if (_error != null || _result != null || _matching)
                      ConstrainedBox(
                        constraints: BoxConstraints(
                          maxHeight: MediaQuery.sizeOf(context).height * 0.25,
                        ),
                        child: SingleChildScrollView(
                          child: GlassCard(
                            margin: const EdgeInsets.fromLTRB(24, 8, 24, 12),
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                if (_matching) ...[
                                  LinearProgressIndicator(
                                    value: _total > 0
                                        ? _processed / _total
                                        : null,
                                  ),
                                  const SizedBox(height: 8),
                                  Text('正在匹配：已处理 $_processed / $_total 个视频'),
                                  if (_activeCount > 0)
                                    Text('正在同时处理 $_activeCount 项'),
                                ],
                                if (_result != null) Text(_result!),
                                if (_error != null)
                                  Text(
                                    _error!,
                                    style: TextStyle(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .error,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    Expanded(
                      child: _entries == null
                          ? Center(
                              child: _error == null
                                  ? const CircularProgressIndicator()
                                  : GlassButton(
                                      onPressed: _refresh,
                                      child: const Text('重试'),
                                    ),
                            )
                          : FutureBuilder<List<MediaEntry>>(
                              future: _entries,
                              builder: (context, snapshot) {
                                if (snapshot.connectionState !=
                                    ConnectionState.done) {
                                  return const Center(
                                    child: SingleChildScrollView(
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          CircularProgressIndicator(),
                                          SizedBox(height: 12),
                                          Text('正在读取目录…'),
                                        ],
                                      ),
                                    ),
                                  );
                                }
                                if (snapshot.hasError) {
                                  return EmptyStateView(
                                    icon: Icons.folder_off_outlined,
                                    title: '暂时无法读取目录',
                                    message:
                                        snapshot.error is MediaSourceException
                                        ? (snapshot.error!
                                                  as MediaSourceException)
                                              .message
                                        : '请检查连接或目录权限后重试。',
                                    actionLabel: '重试',
                                    onAction: _refresh,
                                  );
                                }
                                final entries = snapshot.data!;
                                if (entries.isEmpty) {
                                  return const EmptyStateView(
                                    icon: Icons.folder_open,
                                    title: '此目录没有视频',
                                    message: '可返回上级目录查看其他文件夹。',
                                  );
                                }
                                return ListView.separated(
                                  key: const Key('source_files_list'),
                                  padding: const EdgeInsets.fromLTRB(
                                    24,
                                    8,
                                    24,
                                    24,
                                  ),
                                  itemCount: entries.length,
                                  separatorBuilder: (_, index) =>
                                      const SizedBox(height: 12),
                                  itemBuilder: (context, index) =>
                                      _entryCard(entries[index], busy),
                                );
                              },
                            ),
                    ),
                    if (_selected.isNotEmpty || _selecting)
                      GlassCard(
                        key: const Key('source_files_selection_bar'),
                        margin: const EdgeInsets.fromLTRB(24, 8, 24, 12),
                        padding: const EdgeInsets.all(12),
                        child: Wrap(
                          spacing: 12,
                          runSpacing: 8,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(
                              _selecting
                                  ? '正在读取文件夹…'
                                  : '已选 ${_selected.length} 个视频',
                            ),
                            GlassButton(
                              key: const Key('source_files_auto_match_button'),
                              primary: true,
                              style: actionStyle,
                              icon: Icons.auto_awesome_outlined,
                              onPressed: busy
                                  ? null
                                  : () => _match(manual: false),
                              child: const Text('自动匹配'),
                            ),
                            GlassButton(
                              key: const Key(
                                'source_files_manual_match_button',
                              ),
                              icon: Icons.search,
                              style: actionStyle,
                              onPressed: busy
                                  ? null
                                  : () => _match(manual: true),
                              child: const Text('手动匹配'),
                            ),
                            GlassIconButton(
                              icon: Icons.clear_all,
                              tooltip: '清空选择',
                              size: 40,
                              onPressed: busy
                                  ? null
                                  : () => setState(_selected.clear),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _entryCard(MediaEntry entry, bool busy) => GlassCard(
    padding: const EdgeInsets.all(12),
    onTap: entry.isDirectory
        ? () => _openFolder(entry)
        : busy
        ? null
        : () => _toggle(entry),
    child: Row(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: ReelvaDesign.accent.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
            entry.isDirectory
                ? Icons.folder_outlined
                : Icons.video_file_outlined,
            color: ReelvaDesign.accent,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                entry.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              Text(
                entry.isDirectory ? '文件夹' : '视频文件',
                style: const TextStyle(color: ReelvaDesign.muted, fontSize: 12),
              ),
            ],
          ),
        ),
        Checkbox(
          key: Key('source_file_checkbox_${entry.externalId}'),
          tristate: entry.isDirectory,
          value: _selectionState(entry),
          onChanged: busy ? null : (_) => _toggle(entry),
        ),
      ],
    ),
  );
}
