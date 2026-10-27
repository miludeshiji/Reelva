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
  late final TextEditingController _languages;
  late final TextEditingController _font;

  PlayerSettings get _settings => ref.read(playerSettingsProvider);

  @override
  void initState() {
    super.initState();
    _languages = TextEditingController(text: _settings.subtitleLanguages);
    _font = TextEditingController(text: _settings.subtitleFont);
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

  Future<void> _save(PlayerSettings Function(PlayerSettings) update) async {
    try {
      final settings = update(_settings);
      await ref.read(playerSettingsProvider.notifier).save(settings);
    } catch (e, st) {
      AppLogger.instance.error('保存播放器设置失败', error: e, stackTrace: st);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('保存播放器设置失败，请重试'),
          action: SnackBarAction(label: '重试', onPressed: () => _save(update)),
        ),
      );
    }
  }

  void _restoreDefaults() {
    _formKey.currentState!.reset();
    final settings = PlayerSettings.defaultsFor(defaultTargetPlatform);
    _languages.text = settings.subtitleLanguages;
    _font.text = settings.subtitleFont;
    _save((current) => settings.copyWith(input: current.input));
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
  }) => GlassSwitchTile(
    key: Key(key),
    contentPadding: EdgeInsets.zero,
    title: Text(title),
    value: value,
    onChanged: onChanged,
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
              if (next != null) onChanged(next);
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
        onChanged: (next) => onChanged(next.round()),
      ),
    ],
  );

  static const _autoLoadOptions = {
    TrackAutoLoad.disabled: '不自动加载',
    TrackAutoLoad.exact: '与视频文件名完全相同',
    TrackAutoLoad.fuzzy: '文件名包含视频名称',
  };

  @override
  Widget build(BuildContext context) {
    ref.watch(playerSettingsProvider);
    return SettingsSubpage(
      title: '播放器',
      trailing: GlassIconButton(
        key: const Key('player_settings_reset'),
        icon: Icons.restart_alt_rounded,
        size: ReelvaDesign.pageHeaderButtonSize,
        tooltip: '恢复默认值',
        onPressed: _restoreDefaults,
      ),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('修改后自动保存。'),
            const SizedBox(height: 16),
            _section('视频', [
              _toggle(
                key: 'player_setting_hwdec',
                title: '硬件解码',
                value: _settings.hardwareDecoding,
                onChanged: (value) => _save(
                  (settings) => settings.copyWith(hardwareDecoding: value),
                ),
              ),
              _toggle(
                key: 'player_setting_high_quality',
                title: '高质量缩放',
                value: _settings.highQualityRendering,
                onChanged: (value) => _save(
                  (settings) => settings.copyWith(highQualityRendering: value),
                ),
              ),
              _toggle(
                key: 'player_setting_deband',
                title: '去色带',
                value: _settings.deband,
                onChanged: (value) =>
                    _save((settings) => settings.copyWith(deband: value)),
              ),
              _choice(
                key: 'player_setting_dither',
                label: '抖动目标色深',
                value: _settings.ditherDepth,
                options: const {
                  DitherDepth.auto: '自动',
                  DitherDepth.eight: '8 位',
                  DitherDepth.ten: '10 位',
                  DitherDepth.disabled: '关闭抖动',
                },
                onChanged: (value) =>
                    _save((settings) => settings.copyWith(ditherDepth: value)),
              ),
            ]),
            _section('缓存', [
              _toggle(
                key: 'player_setting_cache',
                title: '预读缓存',
                value: _settings.cacheEnabled,
                onChanged: (value) =>
                    _save((settings) => settings.copyWith(cacheEnabled: value)),
              ),
              _choice(
                key: 'player_setting_cache_size',
                label: '前向缓存上限',
                value: _settings.cacheSizeMb,
                enabled: _settings.cacheEnabled,
                options: {
                  for (final size in PlayerSettings.cacheSizesMb)
                    size: '$size MiB',
                },
                onChanged: (value) =>
                    _save((settings) => settings.copyWith(cacheSizeMb: value)),
              ),
            ]),
            _section('音频', [
              _toggle(
                key: 'player_setting_pitch',
                title: '倍速音调修正',
                value: _settings.pitchCorrection,
                onChanged: (value) => _save(
                  (settings) => settings.copyWith(pitchCorrection: value),
                ),
              ),
              _choice(
                key: 'player_setting_max_volume',
                label: '最大音量',
                value: _settings.maxVolume,
                options: {
                  for (final volume in PlayerSettings.volumeLimits)
                    volume: '$volume%',
                },
                onChanged: (value) =>
                    _save((settings) => settings.copyWith(maxVolume: value)),
              ),
              _choice(
                key: 'player_setting_auto_audio',
                label: '自动加载同目录音频',
                value: _settings.audioAutoLoad,
                options: _autoLoadOptions,
                onChanged: (value) => _save(
                  (settings) => settings.copyWith(audioAutoLoad: value),
                ),
              ),
            ]),
            _section('字幕', [
              TextFormField(
                key: const Key('player_setting_sub_languages'),
                controller: _languages,
                autovalidateMode: AutovalidateMode.onUserInteraction,
                decoration: const InputDecoration(
                  labelText: '优先字幕语言',
                  errorMaxLines: 3,
                ),
                validator: (_) =>
                    PlayerSettings.validSubtitleLanguages(_normalizedLanguages)
                    ? null
                    : '请使用英文逗号分隔语言代码，例如 zh,en',
                onChanged: (_) {
                  final languages = _normalizedLanguages;
                  if (PlayerSettings.validSubtitleLanguages(languages)) {
                    _save(
                      (settings) =>
                          settings.copyWith(subtitleLanguages: languages),
                    );
                  }
                },
              ),
              _choice(
                key: 'player_setting_auto_subtitles',
                label: '自动加载同目录字幕',
                value: _settings.subtitleAutoLoad,
                options: _autoLoadOptions,
                onChanged: (value) => _save(
                  (settings) => settings.copyWith(subtitleAutoLoad: value),
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                key: const Key('player_setting_sub_font'),
                controller: _font,
                autovalidateMode: AutovalidateMode.onUserInteraction,
                maxLength: 128,
                decoration: const InputDecoration(labelText: '字幕字体'),
                validator: (value) =>
                    value == null || value.trim().isEmpty ? '请输入字幕字体名称' : null,
                onChanged: (value) {
                  final font = value.trim();
                  if (font.isNotEmpty) {
                    _save((settings) => settings.copyWith(subtitleFont: font));
                  }
                },
              ),
              _slider(
                key: 'player_setting_sub_size',
                title: '字幕字号',
                value: _settings.subtitleFontSize,
                min: 16,
                max: 80,
                onChanged: (value) => _save(
                  (settings) => settings.copyWith(subtitleFontSize: value),
                ),
              ),
              _slider(
                key: 'player_setting_sub_border',
                title: '黑色描边粗细',
                value: _settings.subtitleBorderSize,
                min: 0,
                max: 10,
                onChanged: (value) => _save(
                  (settings) => settings.copyWith(subtitleBorderSize: value),
                ),
              ),
              _slider(
                key: 'player_setting_sub_blur',
                title: '描边柔化',
                value: _settings.subtitleBlur,
                min: 0,
                max: 3,
                onChanged: (value) =>
                    _save((settings) => settings.copyWith(subtitleBlur: value)),
              ),
              _slider(
                key: 'player_setting_sub_margin',
                title: '字幕垂直边距',
                value: _settings.subtitleMarginY,
                min: 0,
                max: 100,
                onChanged: (value) => _save(
                  (settings) => settings.copyWith(subtitleMarginY: value),
                ),
              ),
              _choice(
                key: 'player_setting_ass_override',
                label: 'ASS 字幕样式',
                value: _settings.assStyleOverride,
                options: const {
                  AssStyleOverride.preserve: '遵循字幕原始样式',
                  AssStyleOverride.compatible: '兼容原始样式与边距调整',
                  AssStyleOverride.force: '使用自定义字幕样式',
                },
                onChanged: (value) => _save(
                  (settings) => settings.copyWith(assStyleOverride: value),
                ),
              ),
              _toggle(
                key: 'player_setting_blend_subtitles',
                title: '字幕随视频处理',
                value: _settings.blendSubtitles,
                onChanged: (value) => _save(
                  (settings) => settings.copyWith(blendSubtitles: value),
                ),
              ),
            ]),
          ],
        ),
      ),
    );
  }
}
