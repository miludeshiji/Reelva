import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/logging/app_logger.dart';
import '../../metadata/application/metadata_providers.dart';
import '../../metadata/domain/tmdb_models.dart';

/// 本地元数据编辑对话框
///
/// 允许用户手动修改作品的标题、年份、简介以及海报路径。
/// 保存后将自动锁定（metadataLocked=true），防止后续自动元数据刷新意外覆盖。
class LocalEditDialog extends ConsumerStatefulWidget {
  const LocalEditDialog({
    super.key,
    required this.workId,
    required this.initialTitle,
    this.initialYear,
    this.initialOverview,
    this.initialPosterPath,
  });

  final int workId;
  final String initialTitle;
  final int? initialYear;
  final String? initialOverview;
  final String? initialPosterPath;

  static Future<bool?> show(
    BuildContext context, {
    required int workId,
    required String initialTitle,
    int? initialYear,
    String? initialOverview,
    String? initialPosterPath,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => LocalEditDialog(
        workId: workId,
        initialTitle: initialTitle,
        initialYear: initialYear,
        initialOverview: initialOverview,
        initialPosterPath: initialPosterPath,
      ),
    );
  }

  @override
  ConsumerState<LocalEditDialog> createState() => _LocalEditDialogState();
}

class _LocalEditDialogState extends ConsumerState<LocalEditDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _titleController;
  late final TextEditingController _yearController;
  late final TextEditingController _overviewController;
  late final TextEditingController _posterPathController;

  bool _isSaving = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.initialTitle);
    _yearController = TextEditingController(
      text: widget.initialYear != null ? widget.initialYear.toString() : '',
    );
    _overviewController = TextEditingController(
      text: widget.initialOverview ?? '',
    );
    _posterPathController = TextEditingController(
      text: widget.initialPosterPath ?? '',
    );
  }

  @override
  void dispose() {
    _titleController.dispose();
    _yearController.dispose();
    _overviewController.dispose();
    _posterPathController.dispose();
    super.dispose();
  }

  Future<void> _handleSave() async {
    if (!_formKey.currentState!.validate()) return;

    final title = _titleController.text.trim();
    final yearText = _yearController.text.trim();
    final int? year = yearText.isNotEmpty ? int.tryParse(yearText) : null;
    final overviewText = _overviewController.text.trim();
    final String? overview = overviewText.isNotEmpty ? overviewText : null;
    final posterText = _posterPathController.text.trim();
    final String? posterPath = posterText.isNotEmpty ? posterText : null;

    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    try {
      final service = ref.read(metadataServiceProvider);
      await service.editLocal(
        widget.workId,
        title: title,
        year: year,
        overview: overview,
        posterPath: posterPath,
      );

      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e, st) {
      AppLogger.instance.error('本地修改元数据失败', error: e, stackTrace: st);
      if (!mounted) return;
      final msg = e is MetadataException ? e.message : '保存失败，请检查输入或稍后重试';
      setState(() {
        _errorMessage = msg;
      });
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.edit_note_outlined),
          SizedBox(width: 8),
          Text('编辑本地元数据'),
        ],
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 锁定保护说明卡片
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: colorScheme.secondaryContainer.withValues(
                      alpha: 0.4,
                    ),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: colorScheme.outlineVariant.withValues(alpha: 0.5),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.lock_outline,
                        size: 18,
                        color: colorScheme.primary,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '保存修改后将自动开启元数据锁定，后续扫描或自动匹配绝不会覆盖您的手动设置。',
                          style: TextStyle(
                            fontSize: 12,
                            color: colorScheme.onSecondaryContainer,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
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
                  const SizedBox(height: 12),
                ],
                TextFormField(
                  key: const Key('local_edit_title_input'),
                  controller: _titleController,
                  decoration: const InputDecoration(
                    labelText: '作品标题 *',
                    hintText: '输入作品展示标题',
                    border: OutlineInputBorder(),
                  ),
                  validator: (val) {
                    if (val == null || val.trim().isEmpty) {
                      return '标题不能为空';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  key: const Key('local_edit_year_input'),
                  controller: _yearController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: '上映年份 (可选)',
                    hintText: '如 2024',
                    border: OutlineInputBorder(),
                  ),
                  validator: (val) {
                    if (val != null && val.trim().isNotEmpty) {
                      final n = int.tryParse(val.trim());
                      if (n == null || n < 1888 || n > 2100) {
                        return '请输入合理有效的年份 (1888-2100)';
                      }
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  key: const Key('local_edit_overview_input'),
                  controller: _overviewController,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: '作品简介 (可选)',
                    hintText: '输入剧情梗概或说明...',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  key: const Key('local_edit_poster_input'),
                  controller: _posterPathController,
                  decoration: const InputDecoration(
                    labelText: '海报相对路径或 URL (可选)',
                    hintText: '如 /abc.jpg 或本地文件路径',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSaving ? null : () => Navigator.of(context).pop(false),
          child: const Text('取消'),
        ),
        FilledButton.icon(
          key: const Key('local_edit_save_button'),
          onPressed: _isSaving ? null : _handleSave,
          icon: _isSaving
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.check, size: 18),
          label: const Text('保存并锁定'),
        ),
      ],
    );
  }
}
