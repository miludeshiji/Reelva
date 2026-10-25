import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/logging/app_logger.dart';
import '../../../shared/widgets/glass_widgets.dart';
import '../../../shared/widgets/poster_image.dart';
import '../../metadata/application/metadata_providers.dart';
import '../../metadata/domain/matching_file.dart';
import '../../metadata/domain/tmdb_models.dart';

class ManualMatchPage extends ConsumerStatefulWidget {
  const ManualMatchPage({
    super.key,
    required this.files,
    required this.initialTitle,
    this.initialYear,
  });

  final List<MatchingFile> files;
  final String initialTitle;
  final int? initialYear;

  static Future<int?> show(
    BuildContext context, {
    required List<MatchingFile> files,
    required String initialTitle,
    int? initialYear,
  }) => Navigator.of(context).push<int>(
    MaterialPageRoute(
      builder: (_) => ManualMatchPage(
        files: files,
        initialTitle: initialTitle,
        initialYear: initialYear,
      ),
    ),
  );

  @override
  ConsumerState<ManualMatchPage> createState() => _ManualMatchPageState();
}

class _ManualMatchPageState extends ConsumerState<ManualMatchPage> {
  late final _query = TextEditingController(text: widget.initialTitle);
  late final _year = TextEditingController(
    text: widget.initialYear?.toString() ?? '',
  );
  final _batchSeason = TextEditingController();
  final _previewKey = GlobalKey();
  final _numbers = <int, ({int? season, int? episode})>{};
  final _included = <int>{};
  Map<int, String> _fileErrors = {};
  List<TmdbWork>? _results;
  TmdbWork? _candidate;
  String? _error;
  bool _searching = false;
  bool _preparing = false;
  bool _applying = false;
  int _searchGeneration = 0;
  int _seasonInputGeneration = 0;

  @override
  void initState() {
    super.initState();
    for (final file in widget.files) {
      final parsed = file.parsed;
      _included.add(file.fileId);
      _numbers[file.fileId] = (
        season: parsed.seasonNumber ?? file.seasonNumber,
        episode: parsed.episodeNumber ?? file.episodeNumber,
      );
    }
  }

  @override
  void dispose() {
    _query.dispose();
    _year.dispose();
    _batchSeason.dispose();
    super.dispose();
  }

  void _invalidateSearch(String _) {
    setState(() {
      _searchGeneration++;
      _searching = false;
      _results = null;
      _candidate = null;
      _error = null;
    });
  }

  Future<void> _search() async {
    final query = _query.text.trim();
    final year = int.tryParse(_year.text.trim());
    if (query.isEmpty ||
        (_year.text.trim().isNotEmpty &&
            (year == null || year < 1888 || year > 2100))) {
      setState(
        () => _error = query.isEmpty ? '请输入搜索标题或关键词' : '请输入有效年份（1888–2100）',
      );
      return;
    }
    final service = ref.read(metadataServiceProvider);
    final generation = ++_searchGeneration;
    FocusScope.of(context).unfocus();
    setState(() {
      _searching = true;
      _error = null;
      _candidate = null;
      _results = null;
    });
    try {
      final results = await service.search(query, year: year);
      if (mounted && generation == _searchGeneration) {
        setState(() => _results = results);
      }
    } catch (error, stackTrace) {
      AppLogger.instance.error(
        '手动搜索 TMDB 失败',
        error: error,
        stackTrace: stackTrace,
      );
      if (mounted && generation == _searchGeneration) {
        setState(
          () => _error = error is MetadataException
              ? error.message
              : '搜索失败，请检查网络或 TMDB 凭据',
        );
      }
    } finally {
      if (mounted && generation == _searchGeneration) {
        setState(() => _searching = false);
      }
    }
  }

  Future<void> _choose(TmdbWork candidate) async {
    FocusScope.of(context).unfocus();
    final service = ref.read(metadataServiceProvider);
    setState(() {
      _candidate = candidate;
      _preparing = true;
      _error = null;
      _fileErrors = {};
    });
    try {
      final plans = await service.prepareFileMatches(
        widget.files,
        candidate,
        overrides: _numbers,
      );
      if (mounted) {
        setState(() {
          _fileErrors = {
            for (final plan in plans)
              if (plan.error != null) plan.file.fileId: plan.error!,
          };
        });
      }
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error is MetadataException
              ? error.message
              : '读取季集失败，请检查网络后重试',
        );
      }
    } finally {
      if (mounted) {
        setState(() => _preparing = false);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || _error != null) return;
          final preview = _previewKey.currentContext;
          if (preview != null) {
            Scrollable.ensureVisible(
              preview,
              duration: const Duration(milliseconds: 250),
            );
          }
        });
      }
    }
  }

  void _fillSeason() {
    final season = int.tryParse(_batchSeason.text.trim());
    if (season == null || season < 0) {
      setState(() => _error = '季号应为 0 或正整数');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _seasonInputGeneration++;
      for (final fileId in _included) {
        final numbers = _numbers[fileId]!;
        if (numbers.season == null) {
          _numbers[fileId] = (season: season, episode: numbers.episode);
          _fileErrors.remove(fileId);
        }
      }
      _error = null;
    });
  }

  Future<void> _apply() async {
    final candidate = _candidate!;
    final service = ref.read(metadataServiceProvider);
    final files = widget.files
        .where((file) => _included.contains(file.fileId))
        .toList();
    setState(() {
      _applying = true;
      _error = null;
    });
    try {
      final plans = await service.prepareFileMatches(
        files,
        candidate,
        overrides: _numbers,
      );
      final errors = {
        for (final plan in plans)
          if (plan.error != null) plan.file.fileId: plan.error!,
      };
      if (!mounted) return;
      if (errors.isNotEmpty) {
        setState(() {
          _fileErrors = errors;
          _error = '还有 ${errors.length} 个文件需要确认，请修正季集或取消勾选';
        });
        return;
      }
      final workId = await service.matchFilesManually(plans, candidate);
      if (mounted) Navigator.of(context).pop(workId);
    } catch (error, stackTrace) {
      AppLogger.instance.error(
        '应用所选文件匹配失败',
        error: error,
        stackTrace: stackTrace,
      );
      if (mounted) {
        setState(
          () => _error = error is MetadataException
              ? error.message
              : '匹配失败，请稍后重试',
        );
      }
    } finally {
      if (mounted) setState(() => _applying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final busy = _preparing || _applying;
    return PopScope(
      canPop: !_applying,
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
                    GlassPageHeader(
                      title: '手动匹配',
                      leading: GlassIconButton(
                        icon: Icons.arrow_back,
                        tooltip: '返回',
                        size: ReelvaDesign.pageHeaderButtonSize,
                        onPressed: _applying
                            ? null
                            : () => Navigator.of(context).pop(),
                      ),
                    ),
                    Expanded(
                      child: CustomScrollView(
                        slivers: [
                          SliverPadding(
                            padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
                            sliver: SliverToBoxAdapter(
                              child: GlassCard(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    TextField(
                                      key: const Key(
                                        'manual_match_query_input',
                                      ),
                                      controller: _query,
                                      enabled: !busy,
                                      onChanged: _invalidateSearch,
                                      onSubmitted: (_) => _search(),
                                      decoration: const InputDecoration(
                                        labelText: '影视标题',
                                        hintText: '同时搜索电影与剧集',
                                      ),
                                    ),
                                    const SizedBox(height: 12),
                                    Row(
                                      children: [
                                        Expanded(
                                          child: TextField(
                                            key: const Key(
                                              'manual_match_year_input',
                                            ),
                                            controller: _year,
                                            enabled: !busy,
                                            onChanged: _invalidateSearch,
                                            keyboardType: TextInputType.number,
                                            decoration: const InputDecoration(
                                              labelText: '年份（可选）',
                                            ),
                                            onSubmitted: (_) => _search(),
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        GlassButton(
                                          key: const Key(
                                            'manual_match_search_button',
                                          ),
                                          primary: true,
                                          icon: Icons.search,
                                          onPressed: _searching || busy
                                              ? null
                                              : _search,
                                          child: const Text('搜索'),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          if (_searching || busy)
                            const SliverToBoxAdapter(
                              child: Padding(
                                padding: EdgeInsets.symmetric(
                                  horizontal: 24,
                                  vertical: 8,
                                ),
                                child: LinearProgressIndicator(),
                              ),
                            ),
                          if (_error != null)
                            SliverToBoxAdapter(
                              child: GlassCard(
                                margin: const EdgeInsets.fromLTRB(
                                  24,
                                  0,
                                  24,
                                  16,
                                ),
                                child: Text(
                                  _error!,
                                  style: TextStyle(
                                    color: Theme.of(context).colorScheme.error,
                                  ),
                                ),
                              ),
                            ),
                          if (_candidate == null) ...[
                            if (_results == null && !_searching)
                              const SliverToBoxAdapter(
                                child: Padding(
                                  padding: EdgeInsets.all(24),
                                  child: Text('搜索 TMDB 并选择作品，随后确认所选文件的对应关系。'),
                                ),
                              ),
                            if (_results?.isEmpty ?? false)
                              const SliverToBoxAdapter(
                                child: Padding(
                                  padding: EdgeInsets.all(24),
                                  child: Text('未找到匹配作品，请尝试其他关键词或年份。'),
                                ),
                              ),
                            if (_results != null)
                              SliverPadding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 24,
                                ),
                                sliver: SliverList.builder(
                                  key: const Key('manual_match_results_list'),
                                  itemCount: _results?.length ?? 0,
                                  itemBuilder: (context, index) =>
                                      _candidateCard(_results![index]),
                                ),
                              ),
                          ] else ...[
                            SliverToBoxAdapter(
                              child: Padding(
                                key: _previewKey,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 24,
                                ),
                                child: _candidateCard(
                                  _candidate!,
                                  selected: true,
                                ),
                              ),
                            ),
                            SliverToBoxAdapter(
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  24,
                                  4,
                                  24,
                                  16,
                                ),
                                child: _candidate!.type == 'series'
                                    ? GlassCard(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.stretch,
                                          children: [
                                            const Text(
                                              '文件名中的季集号优先，缺失时可从目录识别或手动补全。',
                                            ),
                                            const SizedBox(height: 12),
                                            Wrap(
                                              spacing: 12,
                                              runSpacing: 8,
                                              crossAxisAlignment:
                                                  WrapCrossAlignment.center,
                                              children: [
                                                SizedBox(
                                                  width: 120,
                                                  child: TextField(
                                                    key: const Key(
                                                      'manual_match_batch_season_input',
                                                    ),
                                                    controller: _batchSeason,
                                                    enabled: !busy,
                                                    keyboardType:
                                                        TextInputType.number,
                                                    decoration:
                                                        const InputDecoration(
                                                          labelText: '所属季',
                                                        ),
                                                  ),
                                                ),
                                                GlassButton(
                                                  onPressed: busy
                                                      ? null
                                                      : _fillSeason,
                                                  child: const Text('补全缺失季号'),
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                      )
                                    : const Text('所选文件将作为这部电影的不同版本，其他电影请分别匹配。'),
                              ),
                            ),
                            SliverPadding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 24,
                              ),
                              sliver: SliverList.builder(
                                itemCount: widget.files.length,
                                itemBuilder: (context, index) =>
                                    _fileCard(widget.files[index], busy),
                              ),
                            ),
                          ],
                          const SliverToBoxAdapter(child: SizedBox(height: 24)),
                        ],
                      ),
                    ),
                    if (_candidate != null)
                      GlassCard(
                        margin: const EdgeInsets.fromLTRB(24, 8, 24, 12),
                        padding: const EdgeInsets.all(12),
                        child: Wrap(
                          spacing: 16,
                          runSpacing: 8,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text('已选 ${_included.length} 个视频'),
                            GlassButton(
                              key: const Key('manual_match_apply_button'),
                              primary: true,
                              icon: Icons.check,
                              onPressed: busy || _included.isEmpty
                                  ? null
                                  : _apply,
                              child: Text(_applying ? '正在匹配…' : '确认匹配'),
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

  Widget _candidateCard(
    TmdbWork candidate, {
    bool selected = false,
  }) => GlassCard(
    margin: const EdgeInsets.only(bottom: 12),
    padding: const EdgeInsets.all(12),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        PosterImage(
          posterPath: candidate.posterPath,
          title: candidate.title,
          width: 48,
          height: 72,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                candidate.title,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              Text(
                '${candidate.type == 'movie' ? '电影' : '剧集'}${candidate.year == null ? '' : ' · ${candidate.year}'}',
              ),
              if (candidate.overview?.isNotEmpty ?? false)
                Text(
                  candidate.overview!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        GlassIconButton(
          key: Key(
            'manual_match_select_button_${candidate.type}_${candidate.id}',
          ),
          icon: selected ? Icons.check_circle_outline : Icons.chevron_right,
          tooltip: selected ? '已选择' : '选择作品',
          onPressed: selected || _preparing || _applying
              ? null
              : () => _choose(candidate),
        ),
      ],
    ),
  );

  Widget _fileCard(MatchingFile file, bool busy) {
    final included = _included.contains(file.fileId);
    final numbers = _numbers[file.fileId]!;
    return GlassCard(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: Text(file.name)),
              Checkbox(
                key: Key('manual_match_file_checkbox_${file.fileId}'),
                value: included,
                onChanged: busy
                    ? null
                    : (value) => setState(() {
                        if (value ?? false) {
                          _included.add(file.fileId);
                        } else {
                          _included.remove(file.fileId);
                        }
                      }),
              ),
            ],
          ),
          if (_candidate!.type == 'series') ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    key: ValueKey(
                      'manual_match_season_${file.fileId}_$_seasonInputGeneration',
                    ),
                    initialValue: numbers.season?.toString() ?? '',
                    enabled: included && !busy,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: '季'),
                    onChanged: (value) {
                      _numbers[file.fileId] = (
                        season: int.tryParse(value),
                        episode: _numbers[file.fileId]!.episode,
                      );
                      if (_fileErrors.containsKey(file.fileId)) {
                        setState(() => _fileErrors.remove(file.fileId));
                      }
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    key: ValueKey('manual_match_episode_${file.fileId}'),
                    initialValue: numbers.episode?.toString() ?? '',
                    enabled: included && !busy,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: '集'),
                    onChanged: (value) {
                      _numbers[file.fileId] = (
                        season: _numbers[file.fileId]!.season,
                        episode: int.tryParse(value),
                      );
                      if (_fileErrors.containsKey(file.fileId)) {
                        setState(() => _fileErrors.remove(file.fileId));
                      }
                    },
                  ),
                ),
              ],
            ),
            if (included && _fileErrors[file.fileId] != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  _fileErrors[file.fileId]!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
          ],
        ],
      ),
    );
  }
}
