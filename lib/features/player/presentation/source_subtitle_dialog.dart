import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/logging/app_logger.dart';
import '../../sources/application/source_browser.dart';
import '../../sources/application/source_providers.dart';
import '../../sources/domain/source_models.dart';
import '../domain/subtitle_files.dart';

class SourceSubtitleDialog extends ConsumerStatefulWidget {
  const SourceSubtitleDialog({super.key, this.currentSourceId});

  final int? currentSourceId;

  @override
  ConsumerState<SourceSubtitleDialog> createState() =>
      _SourceSubtitleDialogState();
}

class _SourceSubtitleDialogState extends ConsumerState<SourceSubtitleDialog> {
  SourceBrowser? _browser;
  final _path = <({String id, String name})>[];
  Future<List<MediaEntry>>? _entries;
  bool _selecting = false;
  String? _error;

  void _openSource(MediaSourceConfig source) {
    final adapter = ref.read(sourceAdaptersProvider)[source.kind];
    if (adapter == null) {
      setState(() => _error = '此媒体源暂时无法浏览');
      return;
    }
    setState(() {
      _browser = SourceBrowser(
        source: source.copyWith(extensions: subtitleExtensions),
        adapter: adapter,
      );
      _path.add((id: source.rootLocator, name: source.name));
      _entries = _browser!.listDirectory(source.rootLocator);
      _error = null;
    });
  }

  void _back() {
    setState(() {
      _path.removeLast();
      _error = null;
      if (_path.isEmpty) {
        _browser = null;
        _entries = null;
      } else {
        _entries = _browser!.listDirectory(_path.last.id);
      }
    });
  }

  Future<void> _select(MediaEntry entry) async {
    if (entry.isDirectory) {
      setState(() {
        _path.add((id: entry.externalId, name: entry.name));
        _entries = _browser!.listDirectory(entry.externalId);
        _error = null;
      });
      return;
    }
    setState(() {
      _selecting = true;
      _error = null;
    });
    try {
      final browser = _browser!;
      final resource = await browser.adapter.resolvePlayback(
        browser.source,
        entry.externalId,
      );
      if (mounted) {
        Navigator.of(context).pop(
          resource.copyWith(
            displayName: entry.name,
            sourceId: browser.source.id,
          ),
        );
      }
    } catch (error, stackTrace) {
      AppLogger.instance.error(
        '选择媒体源字幕失败',
        error: error,
        stackTrace: stackTrace,
      );
      if (mounted) setState(() => _error = '无法读取字幕，请检查媒体源连接或访问权限');
    } finally {
      if (mounted) setState(() => _selecting = false);
    }
  }

  Widget _sourceList() {
    final sources = ref.watch(mediaSourcesProvider);
    return sources.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stackTrace) => Center(
        child: TextButton(
          onPressed: () => ref.invalidate(mediaSourcesProvider),
          child: const Text('无法读取媒体源，点击重试'),
        ),
      ),
      data: (all) {
        final enabled = all.where((source) => source.enabled).toList();
        enabled.sort(
          (a, b) => (a.id == widget.currentSourceId ? 0 : 1).compareTo(
            b.id == widget.currentSourceId ? 0 : 1,
          ),
        );
        if (enabled.isEmpty) {
          return const Center(child: Text('暂无可用媒体源，请先添加媒体源'));
        }
        return ListView.builder(
          itemCount: enabled.length,
          itemBuilder: (context, index) {
            final source = enabled[index];
            return ListTile(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              leading: const Icon(Icons.source_outlined),
              title: Text(source.name),
              subtitle: source.id == widget.currentSourceId
                  ? const Text('当前播放源')
                  : null,
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => _openSource(source),
            );
          },
        );
      },
    );
  }

  Widget _directoryList() => FutureBuilder<List<MediaEntry>>(
    future: _entries,
    builder: (context, snapshot) {
      if (snapshot.connectionState != ConnectionState.done) {
        return const Center(child: CircularProgressIndicator());
      }
      if (snapshot.hasError) {
        return Center(
          child: TextButton(
            onPressed: () => setState(() {
              _browser!.refreshDirectory(_path.last.id);
              _entries = _browser!.listDirectory(_path.last.id);
            }),
            child: const Text('目录读取失败，点击重试'),
          ),
        );
      }
      final entries = snapshot.data ?? [];
      if (entries.isEmpty) return const Center(child: Text('此目录没有字幕文件或子目录'));
      return ListView.builder(
        itemCount: entries.length,
        itemBuilder: (context, index) {
          final entry = entries[index];
          return ListTile(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            leading: Icon(
              entry.isDirectory
                  ? Icons.folder_outlined
                  : Icons.subtitles_outlined,
            ),
            title: Text(entry.name),
            trailing: entry.isDirectory
                ? const Icon(Icons.chevron_right_rounded)
                : null,
            onTap: _selecting ? null : () => _select(entry),
          );
        },
      );
    },
  );

  @override
  Widget build(BuildContext context) => AlertDialog(
    scrollable: true,
    title: const Text('选择媒体源字幕'),
    content: SizedBox(
      width: 560,
      height: MediaQuery.sizeOf(context).height * 0.55,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_browser != null)
            TextButton.icon(
              onPressed: _selecting ? null : _back,
              icon: const Icon(Icons.arrow_back_rounded),
              label: Text(
                _path.map((part) => part.name).join(' / '),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          if (_selecting) const LinearProgressIndicator(),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(8),
              child: Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          Expanded(child: _browser == null ? _sourceList() : _directoryList()),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('取消'),
      ),
    ],
  );
}
