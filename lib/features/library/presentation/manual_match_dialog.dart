import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/logging/app_logger.dart';
import '../../../shared/widgets/poster_image.dart';
import '../../metadata/application/metadata_providers.dart';
import '../../metadata/domain/tmdb_models.dart';

/// 手动在线匹配对话框
///
/// 允许用户为指定作品搜索 TMDB 影视元数据，支持明确的电影与剧集类型切换（防止类型结构错配），
/// 展示带海报、年份与简介的候选条目列表，选定后执行手动匹配并锁定元数据。
/// 若匹配导致多条作品合并，将返回最终规范化的作品 ID（canonicalWorkId）。
class ManualMatchDialog extends ConsumerStatefulWidget {
  const ManualMatchDialog({
    super.key,
    required this.workId,
    required this.currentTitle,
    this.currentType,
    this.currentYear,
  });

  final int workId;
  final String currentTitle;
  final String? currentType;
  final int? currentYear;

  static Future<int?> show(
    BuildContext context, {
    required int workId,
    required String currentTitle,
    String? currentType,
    int? currentYear,
  }) {
    return showDialog<int>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => ManualMatchDialog(
        workId: workId,
        currentTitle: currentTitle,
        currentType: currentType,
        currentYear: currentYear,
      ),
    );
  }

  @override
  ConsumerState<ManualMatchDialog> createState() => _ManualMatchDialogState();
}

class _ManualMatchDialogState extends ConsumerState<ManualMatchDialog> {
  late final TextEditingController _queryController;
  late final TextEditingController _yearController;
  late String _selectedType;

  int _searchGeneration = 0;
  bool _isSearching = false;
  int? _matchingCandidateId;
  String? _errorMessage;
  List<TmdbWork>? _searchResults;

  @override
  void initState() {
    super.initState();
    _queryController = TextEditingController(text: widget.currentTitle);
    _yearController = TextEditingController(
      text: widget.currentYear != null ? widget.currentYear.toString() : '',
    );
    _selectedType = (widget.currentType == 'series') ? 'series' : 'movie';
  }

  @override
  void dispose() {
    _queryController.dispose();
    _yearController.dispose();
    super.dispose();
  }

  Future<void> _handleSearch() async {
    final query = _queryController.text.trim();
    if (query.isEmpty) {
      setState(() {
        _errorMessage = '请输入搜索标题或关键词';
      });
      return;
    }

    final yearText = _yearController.text.trim();
    int? year;
    if (yearText.isNotEmpty) {
      year = int.tryParse(yearText);
      if (year == null || year < 1888 || year > 2100) {
        setState(() {
          _errorMessage = '年份格式无效，请输入 1888-2100 间的有效数字';
        });
        return;
      }
    }

    final currentGen = ++_searchGeneration;

    setState(() {
      _isSearching = true;
      _errorMessage = null;
    });

    try {
      final service = ref.read(metadataServiceProvider);
      final results = await service.search(
        query,
        type: _selectedType,
        year: year,
      );

      if (!mounted || currentGen != _searchGeneration) return;
      setState(() {
        _searchResults = results;
      });
    } catch (e, st) {
      AppLogger.instance.error('手动搜索 TMDB 失败', error: e, stackTrace: st);
      if (!mounted || currentGen != _searchGeneration) return;
      final msg = e is MetadataException
          ? e.message
          : '搜索失败，请检查 TMDB 凭据配置或网络连接';
      setState(() {
        _errorMessage = msg;
      });
    } finally {
      if (mounted && currentGen == _searchGeneration) {
        setState(() {
          _isSearching = false;
        });
      }
    }
  }

  Future<void> _handleSelectCandidate(TmdbWork candidate) async {
    setState(() {
      _matchingCandidateId = candidate.id;
      _errorMessage = null;
    });

    try {
      final service = ref.read(metadataServiceProvider);
      final canonicalWorkId = await service.matchManually(
        widget.workId,
        candidate,
      );

      if (!mounted) return;
      Navigator.of(context).pop(canonicalWorkId);
    } catch (e, st) {
      AppLogger.instance.error('应用手动匹配元数据失败', error: e, stackTrace: st);
      if (!mounted) return;
      final msg = e is MetadataException ? e.message : '应用元数据匹配失败，请重试';
      setState(() {
        _errorMessage = msg;
      });
    } finally {
      if (mounted) {
        setState(() {
          _matchingCandidateId = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final viewHeight = MediaQuery.sizeOf(context).height;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 580,
          maxHeight: (viewHeight * 0.8).clamp(320.0, 640.0),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Icon(Icons.search),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '手动匹配 TMDB 元数据',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              // 1. 类型明确选择（电影 / 剧集），防止错配结构，换行适配 320px
              Wrap(
                spacing: 8,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  const Text(
                    '作品类型：',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(
                        value: 'movie',
                        label: Text('电影'),
                        icon: Icon(Icons.movie_outlined, size: 16),
                      ),
                      ButtonSegment(
                        value: 'series',
                        label: Text('剧集'),
                        icon: Icon(Icons.tv_outlined, size: 16),
                      ),
                    ],
                    selected: {_selectedType},
                    onSelectionChanged: (set) {
                      setState(() {
                        _selectedType = set.first;
                        _searchResults = null;
                        _errorMessage = null;
                      });
                    },
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // 2. 搜索标题与年份输入区（宽屏并排，窄屏换行）
              LayoutBuilder(
                builder: (context, constraints) {
                  final isNarrow = constraints.maxWidth < 420;

                  final queryField = TextField(
                    key: const Key('manual_match_query_input'),
                    controller: _queryController,
                    decoration: const InputDecoration(
                      labelText: '影视标题',
                      hintText: '输入搜索关键词',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (_) {
                      if (_searchResults != null) {
                        setState(() {
                          _searchResults = null;
                        });
                      }
                    },
                    onSubmitted: (_) => _handleSearch(),
                  );

                  final yearField = TextField(
                    key: const Key('manual_match_year_input'),
                    controller: _yearController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: '年份',
                      hintText: '如 2024',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                    onSubmitted: (_) => _handleSearch(),
                  );

                  final searchBtn = FilledButton.icon(
                    key: const Key('manual_match_search_button'),
                    onPressed: _isSearching ? null : _handleSearch,
                    icon: _isSearching
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.search, size: 18),
                    label: const Text('搜索'),
                  );

                  if (isNarrow) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        queryField,
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(child: yearField),
                            const SizedBox(width: 8),
                            searchBtn,
                          ],
                        ),
                      ],
                    );
                  }

                  return Row(
                    children: [
                      Expanded(flex: 3, child: queryField),
                      const SizedBox(width: 8),
                      Expanded(flex: 1, child: yearField),
                      const SizedBox(width: 8),
                      searchBtn,
                    ],
                  );
                },
              ),
              const SizedBox(height: 10),

              if (_errorMessage != null) ...[
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: colorScheme.errorContainer,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.error_outline,
                        size: 16,
                        color: colorScheme.error,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _errorMessage!,
                          style: TextStyle(
                            fontSize: 12,
                            color: colorScheme.onErrorContainer,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
              ],

              // 3. 搜索候选结果列表
              Expanded(child: _buildCandidatesList(context)),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: _matchingCandidateId != null
                      ? null
                      : () => Navigator.of(context).pop(null),
                  child: const Text('取消'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCandidatesList(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    if (_isSearching) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 12),
            Text('正在查询 TMDB 数据库...'),
          ],
        ),
      );
    }

    if (_searchResults == null) {
      return Center(
        child: Text(
          '输入标题并点击搜索查找 TMDB 影视元数据',
          style: TextStyle(color: colorScheme.onSurfaceVariant),
        ),
      );
    }

    if (_searchResults!.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.search_off,
              size: 40,
              color: colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 8),
            Text(
              '未找到匹配的 ${_selectedType == 'movie' ? '电影' : '剧集'}',
              style: TextStyle(color: colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 4),
            Text(
              '可尝试更换关键词或移除年份筛选',
              style: TextStyle(
                fontSize: 12,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      key: const Key('manual_match_results_list'),
      itemCount: _searchResults!.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final candidate = _searchResults![index];
        final isMatching = _matchingCandidateId == candidate.id;

        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              PosterImage(
                posterPath: candidate.posterPath,
                title: candidate.title,
                width: 50,
                height: 75,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      candidate.title,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (candidate.originalTitle != null &&
                        candidate.originalTitle != candidate.title)
                      Text(
                        candidate.originalTitle!,
                        style: TextStyle(
                          fontSize: 12,
                          color: colorScheme.onSurfaceVariant,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    Row(
                      children: [
                        if (candidate.year != null) ...[
                          Text(
                            '${candidate.year} 年',
                            style: TextStyle(
                              fontSize: 12,
                              color: colorScheme.primary,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(width: 8),
                        ],
                        Text(
                          candidate.type == 'movie' ? '电影' : '剧集',
                          style: TextStyle(
                            fontSize: 11,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                    if (candidate.overview != null &&
                        candidate.overview!.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          candidate.overview!,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              FilledButton.tonal(
                key: Key('manual_match_select_button_${candidate.id}'),
                onPressed: _matchingCandidateId != null
                    ? null
                    : () => _handleSelectCandidate(candidate),
                child: isMatching
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('选定匹配'),
              ),
            ],
          ),
        );
      },
    );
  }
}
