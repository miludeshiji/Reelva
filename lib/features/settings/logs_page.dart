import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../core/logging/app_log_entry.dart';
import '../../core/logging/app_log_store.dart';
import '../../core/logging/app_logger.dart';
import '../../core/logging/log_exporter.dart';
import '../../shared/widgets/glass_widgets.dart';

class LogsPage extends StatefulWidget {
  const LogsPage({super.key, this.store, this.exporter = const LogExporter()});

  final AppLogStore? store;
  final LogExporter exporter;

  @override
  State<LogsPage> createState() => _LogsPageState();
}

class _LogsPageState extends State<LogsPage> {
  late final AppLogStore _store = widget.store ?? AppLogStore.instance;
  final _search = TextEditingController();
  AppLogLevel? _level;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _store.addListener(_refresh);
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _store.removeListener(_refresh);
    _search.dispose();
    super.dispose();
  }

  void _message(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _export() async {
    setState(() => _busy = true);
    try {
      if (await widget.exporter.export(_store)) _message('日志已导出');
    } catch (error, stack) {
      AppLogger.instance.error(
        '导出日志失败',
        module: '日志',
        error: error,
        stackTrace: stack,
      );
      _message('导出日志失败，请重试');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _clear() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('清空日志'),
        content: const Text('清空本机保留的全部日志？已导出的文件不受影响。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('清空'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    await _store.clear();
    if (!mounted) return;
    setState(() => _busy = false);
    _message(_store.storageError == null ? '日志已清空' : '未能清空日志文件，请重试');
  }

  static String _label(AppLogLevel level) => switch (level) {
    AppLogLevel.info => '信息',
    AppLogLevel.warning => '警告',
    AppLogLevel.error => '错误',
  };

  @override
  Widget build(BuildContext context) {
    final query = _search.text.trim().toLowerCase();
    final entries = _store.entries.reversed
        .where(
          (entry) =>
              (_level == null || entry.level == _level) &&
              (query.isEmpty || entry.text.toLowerCase().contains(query)),
        )
        .toList();
    return Scaffold(
      backgroundColor: ReelvaDesign.background,
      body: GlassBackground(
        child: SafeArea(
          bottom: false,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: ReelvaDesign.contentMaxWidth,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  GlassPageHeader(
                    title: '日志',
                    leading: GlassIconButton(
                      key: const Key('settings_subpage_back_button'),
                      icon: Icons.arrow_back,
                      size: ReelvaDesign.pageHeaderButtonSize,
                      tooltip: '返回设置',
                      onPressed: () => context.pop(),
                    ),
                    trailing: PopupMenuButton<String>(
                      key: const Key('logs_menu'),
                      tooltip: '日志操作',
                      enabled: !_busy,
                      icon: const Icon(Icons.more_horiz),
                      onSelected: (value) {
                        if (value == 'export') _export();
                        if (value == 'clear') _clear();
                      },
                      itemBuilder: (_) => const [
                        GlassPopupMenuItem(
                          value: 'export',
                          child: Text('导出全部日志'),
                        ),
                        GlassPopupMenuItem(
                          value: 'clear',
                          child: Text('清空全部日志'),
                        ),
                      ],
                    ),
                  ),
                  if (_busy) const LinearProgressIndicator(minHeight: 2),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        TextField(
                          key: const Key('logs_search'),
                          controller: _search,
                          onChanged: (_) => setState(() {}),
                          decoration: const InputDecoration(
                            hintText: '搜索日志或模块',
                            prefixIcon: Icon(Icons.search),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 4,
                          children: [
                            ChoiceChip(
                              label: const Text('全部'),
                              selected: _level == null,
                              onSelected: (_) => setState(() => _level = null),
                            ),
                            for (final level in AppLogLevel.values)
                              ChoiceChip(
                                label: Text(_label(level)),
                                selected: _level == level,
                                onSelected: (_) =>
                                    setState(() => _level = level),
                              ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '显示最近 ${_store.entries.length} 条中的 ${entries.length} 条 · 导出包含全部保留日志',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        if (_store.storageError != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(
                              _store.storageError!,
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.error,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: entries.isEmpty
                        ? Center(
                            child: Text(
                              query.isEmpty && _level == null
                                  ? '暂无日志'
                                  : '没有符合条件的日志',
                            ),
                          )
                        : ListView.builder(
                            key: const Key('logs_list'),
                            keyboardDismissBehavior:
                                ScrollViewKeyboardDismissBehavior.onDrag,
                            padding: EdgeInsets.fromLTRB(
                              24,
                              0,
                              24,
                              24 + MediaQuery.paddingOf(context).bottom,
                            ),
                            itemCount: entries.length,
                            itemBuilder: (context, index) {
                              final entry = entries[index];
                              return GlassExpansionCard(
                                key: ObjectKey(entry),
                                margin: const EdgeInsets.only(bottom: 12),
                                title: Text(
                                  entry.message,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                subtitle: Wrap(
                                  spacing: 12,
                                  children: [
                                    Text(
                                      entry.time
                                          .toLocal()
                                          .toIso8601String()
                                          .replaceFirst('T', ' ')
                                          .substring(0, 19),
                                    ),
                                    Text(
                                      '${_label(entry.level)} · ${entry.module}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: entry.level == AppLogLevel.error
                                            ? Theme.of(context)
                                                  .colorScheme
                                                  .error
                                            : null,
                                      ),
                                    ),
                                  ],
                                ),
                                children: [
                                  Align(
                                    alignment: Alignment.centerRight,
                                    child: TextButton.icon(
                                      icon: const Icon(Icons.copy, size: 18),
                                      label: const Text('复制'),
                                      onPressed: () async {
                                        await Clipboard.setData(
                                          ClipboardData(text: entry.text),
                                        );
                                        _message('日志已复制');
                                      },
                                    ),
                                  ),
                                  Align(
                                    alignment: Alignment.centerLeft,
                                    child: SelectionArea(
                                      child: Text(entry.text),
                                    ),
                                  ),
                                ],
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
