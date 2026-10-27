import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reelva/app/theme/reelva_theme.dart';
import 'package:reelva/features/player/application/player_settings_provider.dart';
import 'package:reelva/features/player/domain/player_settings.dart';
import 'package:reelva/features/player/domain/player_shortcuts.dart';
import 'package:reelva/features/player/infrastructure/player_settings_store.dart';
import 'package:reelva/features/settings/player_shortcuts_page.dart';

class _Store extends PlayerSettingsStore {
  PlayerSettings? saved;
  bool fail = false;

  @override
  Future<void> save(PlayerSettings settings) async {
    if (fail) throw StateError('write failed');
    saved = settings;
  }
}

void main() {
  late _Store store;
  late ProviderContainer container;

  setUp(() {
    store = _Store();
    container = ProviderContainer(
      overrides: [
        playerSettingsStoreProvider.overrideWithValue(store),
        playerSettingsProvider.overrideWith(
          () => PlayerSettingsController(
            initialSettings: const PlayerSettings(maxVolume: 150),
          ),
        ),
      ],
    );
  });
  tearDown(() => container.dispose());

  Widget app({double textScale = 1}) => UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      theme: ReelvaTheme.light,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: const PlayerShortcutsPage(),
    ),
  );

  testWidgets('捕获按键、提示冲突、清除与恢复默认值后自动保存，保留其他播放器偏好', (tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    final edit = find.byKey(const Key('shortcut_bind_togglePause'));
    final labelRect = tester.getRect(find.text('播放 / 暂停'));
    final bindingRect = tester.getRect(edit);
    expect(labelRect.right, lessThan(bindingRect.left));
    expect(labelRect.center.dy, closeTo(bindingRect.center.dy, 1));
    expect(
      tester.getSize(find.byKey(const Key('shortcut_row_togglePause'))).height,
      lessThanOrEqualTo(56),
    );
    await tester.ensureVisible(edit);
    await tester.tap(edit);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(find.byKey(const Key('shortcut_binding_conflict')), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const Key('shortcut_binding_confirm')),
          )
          .onPressed,
      isNull,
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.f2);
    await tester.pump();
    await tester.tap(find.byKey(const Key('shortcut_binding_confirm')));
    await tester.pumpAndSettle();
    expect(find.text('F2'), findsOneWidget);
    final clear = find.byKey(const Key('shortcut_clear_seekBack'));
    await tester.ensureVisible(clear);
    await tester.tap(clear);
    await tester.pump();
    final step = find.byKey(const ValueKey('shortcut_seek_step:2'));
    await tester.ensureVisible(step);
    await tester.tap(step);
    await tester.pumpAndSettle();
    await tester.tap(find.text('5 秒').last);
    await tester.pumpAndSettle();
    expect(
      store.saved!.input.bindingFor(PlayerShortcutAction.togglePause)!.key,
      LogicalKeyboardKey.f2,
    );
    expect(
      store.saved!.input.bindingFor(PlayerShortcutAction.seekBack),
      isNull,
    );
    expect(store.saved!.input.seekSeconds, 5);
    expect(store.saved!.maxVolume, 150);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    expect(find.text('F2'), findsOneWidget);
    final reset = find.byKey(const Key('shortcuts_reset'));
    await tester.ensureVisible(reset);
    await tester.tap(reset);
    await tester.pumpAndSettle();
    expect(store.saved!.input.toJson(), const PlayerInputSettings().toJson());
    expect(store.saved!.maxVolume, 150);
    expect(tester.takeException(), isNull);
  });

  testWidgets('窄屏大字体无溢出，写入失败保留已有配置', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 568);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    store.fail = true;
    final original = container.read(playerSettingsProvider);
    await tester.pumpWidget(app(textScale: 1.5));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byKey(const Key('shortcuts_keyboard')),
        matching: find.byType(Switch),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('保存快捷键设置失败，请重试'), findsOneWidget);
    expect(container.read(playerSettingsProvider), same(original));
    expect(tester.takeException(), isNull);
  });
}
