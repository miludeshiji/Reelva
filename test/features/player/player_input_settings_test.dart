import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reelva/features/player/domain/player_shortcuts.dart';
import 'package:reelva/features/player/infrastructure/player_settings_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('默认按键无冲突，修饰键精确匹配且兼容小键盘回车', () {
    const input = PlayerInputSettings();
    input.validate();
    expect(input.seekSeconds, 2);
    expect(input.largeSeekSeconds, 60);
    expect(input.volumeStep, 2);
    expect(
      input.actionFor(const PlayerKeyBinding(LogicalKeyboardKey.arrowRight)),
      PlayerShortcutAction.seekForward,
    );
    expect(
      input.actionFor(
        const PlayerKeyBinding(LogicalKeyboardKey.arrowRight, shift: true),
      ),
      PlayerShortcutAction.seekForwardLarge,
    );
    expect(
      input.actionFor(
        const PlayerKeyBinding(LogicalKeyboardKey.arrowRight, control: true),
      ),
      PlayerShortcutAction.subtitlesLater,
    );
    expect(
      input.actionFor(
        const PlayerKeyBinding(LogicalKeyboardKey.arrowRight, alt: true),
      ),
      PlayerShortcutAction.audioLater,
    );
    expect(
      input.actionFor(
        const PlayerKeyBinding(
          LogicalKeyboardKey.arrowRight,
          control: true,
          shift: true,
        ),
      ),
      isNull,
    );
    expect(
      input.actionFor(const PlayerKeyBinding(LogicalKeyboardKey.numpadEnter)),
      PlayerShortcutAction.toggleFullscreen,
    );
  });

  test('旧配置使用默认快捷键，新绑定和禁用项可以持久化且保留画质配置', () async {
    FlutterSecureStorage.setMockInitialValues({
      PlayerSettingsStore.storageKey: jsonEncode({'maxVolume': 150}),
    });
    const store = PlayerSettingsStore();
    final previous = await store.read();
    expect(previous.input.seekSeconds, 2);
    final input = previous.input.copyWith(
      bindings: {
        PlayerShortcutAction.togglePause: const PlayerKeyBinding(
          LogicalKeyboardKey.f2,
        ),
        PlayerShortcutAction.seekBack: null,
      },
      seekSeconds: 5,
      wheelVolume: false,
    );
    await store.save(previous.copyWith(input: input));
    final restored = await store.read();
    expect(restored.maxVolume, 150);
    expect(restored.input.toJson(), input.toJson());
    expect(
      restored.input.actionFor(
        const PlayerKeyBinding(LogicalKeyboardKey.space),
      ),
      isNull,
    );
    expect(
      restored.input.actionFor(const PlayerKeyBinding(LogicalKeyboardKey.f2)),
      PlayerShortcutAction.togglePause,
    );
    expect(restored.input.bindingFor(PlayerShortcutAction.seekBack), isNull);
    expect(
      input
          .copyWith(keyboardEnabled: false)
          .actionFor(const PlayerKeyBinding(LogicalKeyboardKey.f2)),
      isNull,
    );
  });

  test('旧配置保留自定义 Tab，新配置默认用 Tab 切换播放信息', () {
    final defaults = PlayerInputSettings.fromJson(const {});
    expect(
      defaults.actionFor(const PlayerKeyBinding(LogicalKeyboardKey.tab)),
      PlayerShortcutAction.toggleStatistics,
    );
    final previous = PlayerInputSettings.fromJson({
      'bindings': {
        'togglePause': const PlayerKeyBinding(LogicalKeyboardKey.tab).toJson(),
      },
    });
    expect(
      previous.actionFor(const PlayerKeyBinding(LogicalKeyboardKey.tab)),
      PlayerShortcutAction.togglePause,
    );
    expect(previous.bindingFor(PlayerShortcutAction.toggleStatistics), isNull);
  });

  test('重复按键、纯修饰键和无效步长不能保存', () {
    expect(
      () => const PlayerInputSettings(
        bindings: {
          PlayerShortcutAction.togglePause: PlayerKeyBinding(
            LogicalKeyboardKey.enter,
          ),
        },
      ).validate(),
      throwsFormatException,
    );
    expect(
      () => const PlayerInputSettings(
        bindings: {
          PlayerShortcutAction.togglePause: PlayerKeyBinding(
            LogicalKeyboardKey.shiftLeft,
          ),
        },
      ).validate(),
      throwsFormatException,
    );
    expect(
      () => const PlayerInputSettings(seekSeconds: -2).validate(),
      throwsFormatException,
    );
  });
}
