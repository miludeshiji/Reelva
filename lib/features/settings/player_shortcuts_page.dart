import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/logging/app_logger.dart';
import '../../shared/widgets/glass_widgets.dart';
import '../player/application/player_settings_provider.dart';
import '../player/domain/player_shortcuts.dart';
import 'settings_subpages.dart';

class PlayerShortcutsPage extends ConsumerStatefulWidget {
  const PlayerShortcutsPage({super.key});

  @override
  ConsumerState<PlayerShortcutsPage> createState() =>
      _PlayerShortcutsPageState();
}

class _PlayerShortcutsPageState extends ConsumerState<PlayerShortcutsPage> {
  late PlayerInputSettings _draft;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _draft = ref.read(playerSettingsProvider).input;
  }

  Future<void> _editBinding(PlayerShortcutAction action) async {
    final binding = await showDialog<PlayerKeyBinding>(
      context: context,
      builder: (_) => _BindingDialog(action: action, settings: _draft),
    );
    if (!mounted || binding == null) return;
    setState(
      () => _draft = _draft.copyWith(
        bindings: {..._draft.bindings, action: binding},
      ),
    );
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final settings = ref.read(playerSettingsProvider).copyWith(input: _draft);
      await ref.read(playerSettingsProvider.notifier).save(settings);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('快捷键设置已保存，下次进入播放器时生效')));
    } catch (error, stack) {
      AppLogger.instance.error('保存快捷键设置失败', error: error, stackTrace: stack);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('保存快捷键设置失败，请重试')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _card(Widget child) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: GlassCard(
      padding: const EdgeInsets.all(16),
      borderRadius: BorderRadius.circular(22),
      child: Material(type: MaterialType.transparency, child: child),
    ),
  );

  Widget _toggle(
    String key,
    String label,
    bool value,
    ValueChanged<bool> change, {
    String? subtitle,
  }) => SwitchListTile.adaptive(
    key: Key(key),
    contentPadding: EdgeInsets.zero,
    title: Text(label),
    subtitle: subtitle == null ? null : Text(subtitle),
    value: value,
    onChanged: (value) => setState(() => change(value)),
  );

  Widget _step(
    String key,
    String label,
    int value,
    List<int> values,
    String unit,
    ValueChanged<int> change,
  ) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: DropdownButtonFormField<int>(
      key: ValueKey('$key:$value'),
      initialValue: value,
      isExpanded: true,
      borderRadius: BorderRadius.circular(ReelvaDesign.radius),
      decoration: InputDecoration(labelText: label),
      items: [
        for (final option in values)
          DropdownMenuItem(value: option, child: Text('$option$unit')),
      ],
      onChanged: (value) {
        if (value != null) setState(() => change(value));
      },
    ),
  );

  Widget _bindingRow(PlayerShortcutAction action) {
    final binding = _draft.bindingFor(action);
    return Padding(
      key: Key('shortcut_row_${action.name}'),
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: LayoutBuilder(
        builder: (context, constraints) => Row(
          children: [
            Expanded(child: Text(action.label)),
            const SizedBox(width: 12),
            ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: constraints.maxWidth * 0.55,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Tooltip(
                      message: binding == null
                          ? '设置快捷键'
                          : '修改快捷键：${binding.label}',
                      child: OutlinedButton(
                        key: Key('shortcut_bind_${action.name}'),
                        onPressed: () => _editBinding(action),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                        ),
                        child: binding == null
                            ? const Icon(Icons.add_rounded, size: 20)
                            : Text(
                                binding.label,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                      ),
                    ),
                  ),
                  if (binding != null) ...[
                    const SizedBox(width: 4),
                    IconButton(
                      key: Key('shortcut_clear_${action.name}'),
                      tooltip: '清除按键',
                      onPressed: () => setState(
                        () => _draft = _draft.copyWith(
                          bindings: {..._draft.bindings, action: null},
                        ),
                      ),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => SettingsSubpage(
    title: '快捷键',
    child: AbsorbPointer(
      absorbing: _saving,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('保存后下次进入播放器生效，仅保存在本机。点击右侧按键或＋可设置，×可清除绑定。'),
          const SizedBox(height: 16),
          _card(
            Column(
              children: [
                _toggle(
                  'shortcuts_keyboard',
                  '启用键盘快捷键',
                  _draft.keyboardEnabled,
                  (value) => _draft = _draft.copyWith(keyboardEnabled: value),
                  subtitle: '仅在播放页生效，输入框和弹窗保留原有按键操作；Android 可使用外接键盘。',
                ),
              ],
            ),
          ),
          for (final group in ShortcutGroup.values)
            GlassExpansionCard(
              margin: const EdgeInsets.only(bottom: 16),
              borderRadius: BorderRadius.circular(22),
              tileKey: Key('shortcut_group_${group.name}'),
              title: Text(group.label),
              initiallyExpanded: group == ShortcutGroup.playback,
              children: [
                for (final action in PlayerShortcutAction.values.where(
                  (action) => action.group == group,
                ))
                  _bindingRow(action),
              ],
            ),
          _card(
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('定位与音量步长', style: Theme.of(context).textTheme.titleMedium),
                _step(
                  'shortcut_seek_step',
                  '普通定位',
                  _draft.seekSeconds,
                  PlayerInputSettings.seekSteps,
                  ' 秒',
                  (value) => _draft = _draft.copyWith(seekSeconds: value),
                ),
                _step(
                  'shortcut_large_seek_step',
                  '大幅定位',
                  _draft.largeSeekSeconds,
                  PlayerInputSettings.largeSeekSteps,
                  ' 秒',
                  (value) => _draft = _draft.copyWith(largeSeekSeconds: value),
                ),
                _step(
                  'shortcut_volume_step',
                  '普通音量调节',
                  _draft.volumeStep,
                  PlayerInputSettings.volumeSteps,
                  '%',
                  (value) => _draft = _draft.copyWith(volumeStep: value),
                ),
                _step(
                  'shortcut_large_volume_step',
                  '大幅音量调节',
                  _draft.largeVolumeStep,
                  PlayerInputSettings.volumeSteps,
                  '%',
                  (value) => _draft = _draft.copyWith(largeVolumeStep: value),
                ),
              ],
            ),
          ),
          _card(
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('鼠标', style: Theme.of(context).textTheme.titleMedium),
                _toggle(
                  'shortcut_mouse_click',
                  '左键单击播放 / 暂停',
                  _draft.clickToPause,
                  (value) => _draft = _draft.copyWith(clickToPause: value),
                  subtitle: '关闭后单击显示或隐藏控件，触屏点按始终保留此行为。',
                ),
                _toggle(
                  'shortcut_mouse_double_click',
                  '左键双击切换全屏',
                  _draft.doubleClickFullscreen,
                  (value) =>
                      _draft = _draft.copyWith(doubleClickFullscreen: value),
                ),
                _toggle(
                  'shortcut_mouse_context_menu',
                  '右键打开播放菜单',
                  _draft.rightClickMenu,
                  (value) => _draft = _draft.copyWith(rightClickMenu: value),
                ),
                _toggle(
                  'shortcut_mouse_wheel_volume',
                  '纵向滚轮调节音量',
                  _draft.wheelVolume,
                  (value) => _draft = _draft.copyWith(wheelVolume: value),
                ),
                _step(
                  'shortcut_wheel_volume_step',
                  '滚轮音量步长',
                  _draft.wheelVolumeStep,
                  PlayerInputSettings.volumeSteps,
                  '%',
                  (value) => _draft = _draft.copyWith(wheelVolumeStep: value),
                ),
                _toggle(
                  'shortcut_mouse_wheel_seek',
                  '横向滚轮调节进度',
                  _draft.horizontalWheelSeek,
                  (value) =>
                      _draft = _draft.copyWith(horizontalWheelSeek: value),
                  subtitle: '向左前进，向右后退。',
                ),
                _step(
                  'shortcut_wheel_seek_step',
                  '横向定位步长',
                  _draft.wheelSeekSeconds,
                  PlayerInputSettings.seekSteps,
                  ' 秒',
                  (value) => _draft = _draft.copyWith(wheelSeekSeconds: value),
                ),
              ],
            ),
          ),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              FilledButton(
                key: const Key('shortcuts_save'),
                onPressed: _saving ? null : _save,
                child: Text(_saving ? '正在保存' : '保存设置'),
              ),
              OutlinedButton(
                key: const Key('shortcuts_reset'),
                onPressed: _saving
                    ? null
                    : () =>
                          setState(() => _draft = const PlayerInputSettings()),
                child: const Text('恢复默认值'),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}

class _BindingDialog extends StatefulWidget {
  const _BindingDialog({required this.action, required this.settings});
  final PlayerShortcutAction action;
  final PlayerInputSettings settings;

  @override
  State<_BindingDialog> createState() => _BindingDialogState();
}

class _BindingDialogState extends State<_BindingDialog> {
  PlayerKeyBinding? _binding;
  PlayerShortcutAction? _conflict;

  KeyEventResult _capture(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.handled;
    final binding = PlayerKeyBinding.fromEvent(event);
    if (binding == null) return KeyEventResult.handled;
    PlayerShortcutAction? conflict;
    for (final action in PlayerShortcutAction.values) {
      if (action != widget.action &&
          widget.settings.bindingFor(action) == binding) {
        conflict = action;
        break;
      }
    }
    setState(() {
      _binding = binding;
      _conflict = conflict;
    });
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) => Focus(
    autofocus: true,
    onKeyEvent: _capture,
    child: AlertDialog(
      title: Text('设置：${widget.action.label}'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('请按下一个按键或组合键（支持 Ctrl、Shift、Alt、Meta）。'),
          const SizedBox(height: 16),
          Text(
            _binding?.label ?? '等待按键…',
            key: const Key('shortcut_captured_key'),
            style: Theme.of(context).textTheme.titleLarge,
          ),
          if (_conflict != null)
            Text(
              '与“${_conflict!.label}”冲突，请换一个按键。',
              key: const Key('shortcut_binding_conflict'),
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          key: const Key('shortcut_binding_confirm'),
          onPressed: _binding == null || _conflict != null
              ? null
              : () => Navigator.pop(context, _binding),
          child: const Text('使用此按键'),
        ),
      ],
    ),
  );
}
