import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/logging/app_logger.dart';
import '../../shared/widgets/glass_widgets.dart';
import '../player/application/player_settings_provider.dart';
import '../player/domain/player_settings.dart';
import 'settings_subpages.dart';

class PlayerSettingsPage extends ConsumerStatefulWidget {
  const PlayerSettingsPage({super.key});

  @override
  ConsumerState<PlayerSettingsPage> createState() => _PlayerSettingsPageState();
}

class _PlayerSettingsPageState extends ConsumerState<PlayerSettingsPage> {
  final _formKey = GlobalKey<FormState>();
  late PlayerSettings _draft;
  late final TextEditingController _languages;
  late final TextEditingController _font;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _draft = ref.read(playerSettingsProvider);
    _languages = TextEditingController(text: _draft.subtitleLanguages);
    _font = TextEditingController(text: _draft.subtitleFont);
  }

  @override
  void dispose() {
    _languages.dispose();
    _font.dispose();
    super.dispose();
  }

  String get _normalizedLanguages => _languages.text
      .split(',')
      .map((value) => value.trim().toLowerCase())
      .join(',');

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final settings = _draft.copyWith(
      subtitleLanguages: _normalizedLanguages,
      subtitleFont: _font.text.trim(),
    );
    setState(() => _saving = true);
    try {
      await ref.read(playerSettingsProvider.notifier).save(settings);
      if (!mounted) return;
      _draft = settings;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('播放器设置已保存，下次进入播放器时生效')));
    } catch (e, st) {
      AppLogger.instance.error('保存播放器设置失败', error: e, stackTrace: st);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('保存播放器设置失败，请重试')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _restoreDefaults() {
    _formKey.currentState!.reset();
    setState(() {
      _draft = PlayerSettings.defaultsFor(defaultTargetPlatform)
          .copyWith(input: _draft.input);
      _languages.text = _draft.subtitleLanguages;
      _font.text = _draft.subtitleFont;
    });
  }

  Widget _section(String title, List<Widget> children) => Padding(
    padding: const EdgeInsets.only(bottom: ReelvaDesign.space16),
    child: GlassCard(
      padding: const EdgeInsets.all(ReelvaDesign.space16),
      borderRadius: BorderRadius.circular(22),
      color: Colors.white.withValues(alpha: 0.88),
      child: Material(
        type: MaterialType.transparency,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            ...children,
          ],
        ),
      ),
    ),
  );

  Widget _toggle({
    required String key,
    required String title,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) => SwitchListTile.adaptive(
    key: Key(key),
    contentPadding: EdgeInsets.zero,
    title: Text(title),
    value: value,
    onChanged: (next) => setState(() => onChanged(next)),
  );

  Widget _choice<T>({
    required String key,
    required String label,
    required T value,
    required Map<T, String> options,
    required ValueChanged<T> onChanged,
    bool enabled = true,
  }) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: DropdownButtonFormField<T>(
      key: ValueKey('$key:$value'),
      initialValue: value,
      isExpanded: true,
      borderRadius: BorderRadius.circular(ReelvaDesign.radius),
      decoration: InputDecoration(labelText: label),
      items: [
        for (final entry in options.entries)
          DropdownMenuItem(value: entry.key, child: Text(entry.value)),
      ],
      onChanged: !enabled
          ? null
          : (next) {
              if (next != null) setState(() => onChanged(next));
            },
    ),
  );

  Widget _slider({
    required String key,
    required String title,
    required int value,
    required int min,
    required int max,
    required ValueChanged<int> onChanged,
  }) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const SizedBox(height: 12),
      Text('$title：$value'),
      Slider(
        key: Key(key),
        value: value.toDouble(),
        min: min.toDouble(),
        max: max.toDouble(),
        divisions: max - min,
        label: '$value',
        onChanged: (next) => setState(() => onChanged(next.round())),
      ),
    ],
  );

  static const _autoLoadOptions = {
    TrackAutoLoad.disabled: '不自动加载',
    TrackAutoLoad.exact: '与视频文件名完全相同',
    TrackAutoLoad.fuzzy: '文件名包含视频名称',
  };

  @override
  Widget build(BuildContext context) => SettingsSubpage(
    title: '播放器',
    child: Form(
      key: _formKey,
      child: AbsorbPointer(
        absorbing: _saving,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('设置仅保存在本机，保存后下次进入播放器时生效。'),
            const SizedBox(height: 16),
            _section('视频', [
              _toggle(
                key: 'player_setting_hwdec',
                title: '硬件解码',
                value: _draft.hardwareDecoding,
                onChanged: (value) =>
                    _draft = _draft.copyWith(hardwareDecoding: value),
              ),
              _toggle(
                key: 'player_setting_high_quality',
                title: '高质量缩放',
                value: _draft.highQualityRendering,
                onChanged: (value) =>
                    _draft = _draft.copyWith(highQualityRendering: value),
              ),
              _toggle(
                key: 'player_setting_deband',
                title: '去色带',
                value: _draft.deband,
                onChanged: (value) => _draft = _draft.copyWith(deband: value),
              ),
              _choice(
                key: 'player_setting_dither',
                label: '抖动目标色深',
                value: _draft.ditherDepth,
                options: const {
                  DitherDepth.auto: '自动',
                  DitherDepth.eight: '8 位',
                  DitherDepth.ten: '10 位',
                  DitherDepth.disabled: '关闭抖动',
                },
                onChanged: (value) =>
                    _draft = _draft.copyWith(ditherDepth: value),
              ),
            ]),
            _section('缓存', [
              _toggle(
                key: 'player_setting_cache',
                title: '预读缓存',
                value: _draft.cacheEnabled,
                onChanged: (value) =>
                    _draft = _draft.copyWith(cacheEnabled: value),
              ),
              _choice(
                key: 'player_setting_cache_size',
                label: '前向缓存上限',
                value: _draft.cacheSizeMb,
                enabled: _draft.cacheEnabled,
                options: {
                  for (final size in PlayerSettings.cacheSizesMb)
                    size: '$size MiB',
                },
                onChanged: (value) =>
                    _draft = _draft.copyWith(cacheSizeMb: value),
              ),
            ]),
            _section('音频', [
              _toggle(
                key: 'player_setting_pitch',
                title: '倍速音调修正',
                value: _draft.pitchCorrection,
                onChanged: (value) =>
                    _draft = _draft.copyWith(pitchCorrection: value),
              ),
              _choice(
                key: 'player_setting_max_volume',
                label: '最大音量',
                value: _draft.maxVolume,
                options: {
                  for (final volume in PlayerSettings.volumeLimits)
                    volume: '$volume%',
                },
                onChanged: (value) =>
                    _draft = _draft.copyWith(maxVolume: value),
              ),
              _choice(
                key: 'player_setting_auto_audio',
                label: '自动加载同目录音频',
                value: _draft.audioAutoLoad,
                options: _autoLoadOptions,
                onChanged: (value) =>
                    _draft = _draft.copyWith(audioAutoLoad: value),
              ),
            ]),
            _section('字幕', [
              TextFormField(
                key: const Key('player_setting_sub_languages'),
                controller: _languages,
                decoration: const InputDecoration(
                  labelText: '优先字幕语言',
                  errorMaxLines: 3,
                ),
                validator: (_) =>
                    PlayerSettings.validSubtitleLanguages(_normalizedLanguages)
                    ? null
                    : '请使用英文逗号分隔语言代码，例如 zh,en',
              ),
              _choice(
                key: 'player_setting_auto_subtitles',
                label: '自动加载同目录字幕',
                value: _draft.subtitleAutoLoad,
                options: _autoLoadOptions,
                onChanged: (value) =>
                    _draft = _draft.copyWith(subtitleAutoLoad: value),
              ),
              const SizedBox(height: 16),
              TextFormField(
                key: const Key('player_setting_sub_font'),
                controller: _font,
                maxLength: 128,
                decoration: const InputDecoration(labelText: '字幕字体'),
                validator: (value) =>
                    value == null || value.trim().isEmpty ? '请输入字幕字体名称' : null,
              ),
              _slider(
                key: 'player_setting_sub_size',
                title: '字幕字号',
                value: _draft.subtitleFontSize,
                min: 16,
                max: 80,
                onChanged: (value) =>
                    _draft = _draft.copyWith(subtitleFontSize: value),
              ),
              _slider(
                key: 'player_setting_sub_border',
                title: '黑色描边粗细',
                value: _draft.subtitleBorderSize,
                min: 0,
                max: 10,
                onChanged: (value) =>
                    _draft = _draft.copyWith(subtitleBorderSize: value),
              ),
              _slider(
                key: 'player_setting_sub_blur',
                title: '描边柔化',
                value: _draft.subtitleBlur,
                min: 0,
                max: 3,
                onChanged: (value) =>
                    _draft = _draft.copyWith(subtitleBlur: value),
              ),
              _slider(
                key: 'player_setting_sub_margin',
                title: '字幕垂直边距',
                value: _draft.subtitleMarginY,
                min: 0,
                max: 100,
                onChanged: (value) =>
                    _draft = _draft.copyWith(subtitleMarginY: value),
              ),
              _choice(
                key: 'player_setting_ass_override',
                label: 'ASS 字幕样式',
                value: _draft.assStyleOverride,
                options: const {
                  AssStyleOverride.preserve: '遵循字幕原始样式',
                  AssStyleOverride.compatible: '兼容原始样式与边距调整',
                  AssStyleOverride.force: '使用自定义字幕样式',
                },
                onChanged: (value) =>
                    _draft = _draft.copyWith(assStyleOverride: value),
              ),
              _toggle(
                key: 'player_setting_blend_subtitles',
                title: '字幕随视频处理',
                value: _draft.blendSubtitles,
                onChanged: (value) =>
                    _draft = _draft.copyWith(blendSubtitles: value),
              ),
            ]),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                FilledButton.icon(
                  key: const Key('player_settings_save'),
                  onPressed: _saving ? null : _save,
                  icon: _saving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save_outlined),
                  label: const Text('保存设置'),
                ),
                OutlinedButton(
                  key: const Key('player_settings_reset'),
                  onPressed: _saving ? null : _restoreDefaults,
                  child: const Text('恢复默认值'),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}
