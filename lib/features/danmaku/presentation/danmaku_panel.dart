import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../application/danmaku_controller.dart';
import '../domain/danmaku.dart';
import '../infrastructure/danmaku_api.dart';

class DanmakuPanel extends StatefulWidget {
  const DanmakuPanel({
    super.key,
    required this.controller,
    required this.initialKeyword,
  });
  final DanmakuController controller;
  final String initialKeyword;
  @override
  State<DanmakuPanel> createState() => _DanmakuPanelState();
}

class _DanmakuPanelState extends State<DanmakuPanel> {
  late final _keyword = TextEditingController(text: widget.initialKeyword);
  late DanmakuSource _source = widget.controller.api.dandanConfigured
      ? DanmakuSource.dandanplay
      : DanmakuSource.bilibili;
  List<DanmakuShow> _shows = const [];
  List<DanmakuEpisode>? _episodes;
  String? _showTitle;
  String? _error;
  bool _loading = false;
  bool _applying = false;
  CancelToken? _cancel;
  int _request = 0;

  @override
  void dispose() {
    _cancel?.cancel();
    _keyword.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final keyword = _keyword.text.trim();
    if (keyword.isEmpty) return;
    await _load(() async {
      final shows = await widget.controller.api.search(
        keyword,
        _source,
        cancelToken: _cancel,
      );
      return (shows, null);
    });
  }

  Future<void> _load(
    Future<(List<DanmakuShow>?, List<DanmakuEpisode>?)> Function() operation,
  ) async {
    final request = ++_request;
    _cancel?.cancel();
    _cancel = CancelToken();
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await operation();
      if (!mounted || request != _request) return;
      setState(() {
        if (result.$1 != null) {
          _shows = result.$1!;
          _episodes = null;
          _showTitle = null;
        }
        if (result.$2 != null) _episodes = result.$2;
        if ((_episodes?.length ?? _shows.length) == 0) {
          _error = '未找到结果，请修改关键词或切换来源';
        }
      });
    } catch (error) {
      if (mounted && request == _request) {
        setState(
          () =>
              _error = error is DanmakuException ? error.message : '搜索失败，请稍后重试',
        );
      }
    } finally {
      if (mounted && request == _request) setState(() => _loading = false);
    }
  }

  Future<void> _select(DanmakuEpisode episode) async {
    setState(() => _applying = true);
    await widget.controller.select(episode);
    if (!mounted) return;
    if (widget.controller.selected?.cacheKey == episode.cacheKey) {
      Navigator.pop(context);
    } else {
      setState(() => _applying = false);
    }
  }

  Widget _slider(
    String label,
    double value,
    double min,
    double max,
    int divisions,
    ValueChanged<double> change,
    String display,
  ) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text('$label · $display'),
      Slider(
        value: value,
        min: min,
        max: max,
        divisions: divisions,
        onChanged: change,
      ),
    ],
  );

  Widget _settings(DanmakuController controller) {
    final settings = controller.settings;
    void update(DanmakuSettings next) =>
        unawaited(controller.updateSettings(next));
    return ExpansionTile(
      title: const Text('显示与时间设置'),
      tilePadding: EdgeInsets.zero,
      children: [
        _slider(
          '字号',
          settings.fontSize,
          12,
          48,
          18,
          (value) => update(settings.copyWith(fontSize: value)),
          '${settings.fontSize.round()}',
        ),
        _slider(
          '不透明度',
          settings.opacity,
          0.1,
          1,
          18,
          (value) => update(settings.copyWith(opacity: value)),
          '${(settings.opacity * 100).round()}%',
        ),
        _slider(
          '显示区域',
          settings.area,
          0.25,
          1,
          3,
          (value) => update(settings.copyWith(area: value)),
          '${(settings.area * 100).round()}%',
        ),
        _slider(
          '滚动时长',
          settings.duration,
          4,
          16,
          12,
          (value) => update(settings.copyWith(duration: value)),
          '${settings.duration.round()} 秒',
        ),
        _slider(
          '每秒最多',
          settings.density.toDouble(),
          5,
          60,
          11,
          (value) => update(settings.copyWith(density: value.round())),
          '${settings.density} 条',
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('顶部弹幕'),
          value: settings.showTop,
          onChanged: (value) => update(settings.copyWith(showTop: value)),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('底部弹幕'),
          value: settings.showBottom,
          onChanged: (value) => update(settings.copyWith(showBottom: value)),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('B站弹幕'),
          value: settings.showBilibili,
          onChanged: (value) => update(settings.copyWith(showBilibili: value)),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('其他来源弹幕'),
          value: settings.showOther,
          onChanged: (value) => update(settings.copyWith(showOther: value)),
        ),
        Row(
          children: [
            const Expanded(child: Text('时间偏移\n正值延后，负值提前')),
            IconButton(
              tooltip: '提前 0.5 秒',
              onPressed: controller.query == null
                  ? null
                  : () =>
                        controller.updateOffset(controller.offsetSeconds - 0.5),
              icon: const Icon(Icons.remove),
            ),
            TextButton(
              onPressed: controller.query == null
                  ? null
                  : () async {
                      var input = controller.offsetSeconds.toStringAsFixed(1);
                      final value = await showDialog<double>(
                        context: context,
                        builder: (context) => AlertDialog(
                          title: const Text('弹幕时间偏移'),
                          content: TextFormField(
                            initialValue: input,
                            onChanged: (value) => input = value,
                            autofocus: true,
                            decoration: const InputDecoration(
                              suffixText: '秒',
                              helperText: '范围 -600 至 600 秒',
                            ),
                            keyboardType: const TextInputType.numberWithOptions(
                              signed: true,
                              decimal: true,
                            ),
                            onFieldSubmitted: (value) {
                              final parsed = double.tryParse(value);
                              if (parsed != null && parsed.isFinite) {
                                Navigator.pop(context, parsed);
                              }
                            },
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(context),
                              child: const Text('取消'),
                            ),
                            FilledButton(
                              onPressed: () {
                                final parsed = double.tryParse(input);
                                if (parsed != null && parsed.isFinite) {
                                  Navigator.pop(context, parsed);
                                }
                              },
                              child: const Text('确定'),
                            ),
                          ],
                        ),
                      );
                      if (value != null) await controller.updateOffset(value);
                    },
              child: Text('${controller.offsetSeconds.toStringAsFixed(1)} 秒'),
            ),
            IconButton(
              tooltip: '延后 0.5 秒',
              onPressed: controller.query == null
                  ? null
                  : () =>
                        controller.updateOffset(controller.offsetSeconds + 0.5),
              icon: const Icon(Icons.add),
            ),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) => Dialog(
    insetPadding: const EdgeInsets.all(16),
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 620),
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.82,
        child: AnimatedBuilder(
          animation: widget.controller,
          builder: (context, _) {
            final controller = widget.controller;
            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 8, 0),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          '弹幕',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                      ),
                      IconButton(
                        tooltip: '关闭弹幕面板',
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: CustomScrollView(
                    slivers: [
                      SliverPadding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        sliver: SliverToBoxAdapter(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              SwitchListTile(
                                key: const Key('danmaku_enabled'),
                                contentPadding: EdgeInsets.zero,
                                title: const Text('显示弹幕'),
                                subtitle: const Text('开启后优先加载同目录弹幕，否则在线匹配'),
                                value: controller.settings.enabled,
                                onChanged: (value) => controller.updateSettings(
                                  controller.settings.copyWith(enabled: value),
                                ),
                              ),
                              if (controller.loading)
                                const LinearProgressIndicator(),
                              Text(
                                controller.message,
                                key: const Key('danmaku_status'),
                              ),
                              if (controller.localFileName != null)
                                Padding(
                                  padding: const EdgeInsets.only(top: 8),
                                  child: Text(
                                    '本地弹幕 · ${controller.localFileName}',
                                    key: const Key('danmaku_local_file'),
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall,
                                  ),
                                ),
                              if (controller.selected != null)
                                Padding(
                                  padding: const EdgeInsets.only(top: 8),
                                  child: Text(
                                    '${controller.selected!.source.label} · ${controller.selected!.label}',
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall,
                                  ),
                                ),
                              Align(
                                alignment: Alignment.centerLeft,
                                child: TextButton.icon(
                                  key: const Key('danmaku_pick_local'),
                                  onPressed:
                                      controller.localPicker == null ||
                                          controller.pickingLocal
                                      ? null
                                      : controller.pickLocal,
                                  icon: const Icon(Icons.file_open_outlined),
                                  label: const Text('选择本地弹幕'),
                                ),
                              ),
                              Align(
                                alignment: Alignment.centerRight,
                                child: TextButton.icon(
                                  onPressed:
                                      controller.settings.enabled &&
                                          !controller.loading
                                      ? controller.retryAutomatic
                                      : null,
                                  icon: const Icon(Icons.refresh),
                                  label: const Text('重新自动匹配'),
                                ),
                              ),
                              _settings(controller),
                              const Divider(),
                              SegmentedButton<DanmakuSource>(
                                segments: [
                                  for (final source in DanmakuSource.values)
                                    ButtonSegment(
                                      value: source,
                                      label: Text(source.label),
                                    ),
                                ],
                                selected: {_source},
                                onSelectionChanged: (value) {
                                  ++_request;
                                  _cancel?.cancel();
                                  setState(() {
                                    _source = value.single;
                                    _shows = const [];
                                    _episodes = null;
                                    _error = null;
                                    _loading = false;
                                  });
                                },
                              ),
                              const SizedBox(height: 12),
                              TextField(
                                key: const Key('danmaku_search'),
                                controller: _keyword,
                                textInputAction: TextInputAction.search,
                                decoration: InputDecoration(
                                  labelText: '搜索作品',
                                  hintText: _source == DanmakuSource.bilibili
                                      ? '也可输入 BV 号或 B站视频链接'
                                      : '作品名称',
                                  suffixIcon: IconButton(
                                    tooltip: '搜索弹幕',
                                    onPressed: _search,
                                    icon: const Icon(Icons.search),
                                  ),
                                ),
                                onSubmitted: (_) => _search(),
                              ),
                              if (_episodes != null)
                                TextButton.icon(
                                  onPressed: () =>
                                      setState(() => _episodes = null),
                                  icon: const Icon(Icons.arrow_back),
                                  label: Text(_showTitle ?? '返回搜索结果'),
                                ),
                              if (_loading)
                                const Padding(
                                  padding: EdgeInsets.all(16),
                                  child: Center(
                                    child: CircularProgressIndicator(),
                                  ),
                                ),
                              if (_error != null)
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 12,
                                  ),
                                  child: Text(_error!),
                                ),
                            ],
                          ),
                        ),
                      ),
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(8, 8, 8, 16),
                        sliver: SliverList.builder(
                          itemCount: _episodes?.length ?? _shows.length,
                          itemBuilder: (context, index) {
                            final episodes = _episodes;
                            if (episodes != null) {
                              final episode = episodes[index];
                              return ListTile(
                                title: Text(episode.episodeTitle),
                                subtitle: Text(episode.title),
                                selected:
                                    controller.selected?.cacheKey ==
                                    episode.cacheKey,
                                onTap: _applying
                                    ? null
                                    : () => _select(episode),
                              );
                            }
                            final show = _shows[index];
                            return ListTile(
                              title: Text(show.title),
                              subtitle: Text(
                                '${show.source.label}${show.year == null ? '' : ' · ${show.year}'}',
                              ),
                              trailing: const Icon(Icons.chevron_right),
                              onTap: () {
                                _showTitle = show.title;
                                _load(
                                  () async => (
                                    null,
                                    await controller.api.episodes(
                                      show,
                                      cancelToken: _cancel,
                                    ),
                                  ),
                                );
                              },
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    ),
  );
}
