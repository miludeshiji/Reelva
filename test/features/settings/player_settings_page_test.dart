import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reelva/app/theme/reelva_theme.dart';
import 'package:reelva/features/player/application/player_settings_provider.dart';
import 'package:reelva/features/player/domain/player_settings.dart';
import 'package:reelva/features/player/infrastructure/player_settings_store.dart';
import 'package:reelva/features/settings/player_settings_page.dart';

class _Store extends PlayerSettingsStore {
  PlayerSettings? saved;
  bool fail = false;

  @override
  Future<void> save(PlayerSettings settings) async {
    if (fail) throw StateError('storage unavailable');
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
            initialSettings: const PlayerSettings(
              subtitleLanguages: 'en',
              subtitleFont: 'Test Font',
            ),
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
      home: const PlayerSettingsPage(),
    ),
  );

  testWidgets('编辑后保存，重新打开回显，恢复默认值也需保存', (tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('player_setting_hwdec')));
    expect(store.saved, isNull);

    final languages = find.byKey(const Key('player_setting_sub_languages'));
    await tester.ensureVisible(languages);
    await tester.enterText(languages, 'ZH, en');
    final font = find.byKey(const Key('player_setting_sub_font'));
    await tester.ensureVisible(font);
    await tester.enterText(font, 'My Subtitle Font');
    final save = find.byKey(const Key('player_settings_save'));
    await tester.ensureVisible(save);
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(store.saved!.hardwareDecoding, isFalse);
    expect(store.saved!.subtitleLanguages, 'zh,en');
    expect(store.saved!.subtitleFont, 'My Subtitle Font');

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    expect(tester.widget<TextFormField>(languages).controller!.text, 'zh,en');
    expect(
      tester.widget<TextFormField>(font).controller!.text,
      'My Subtitle Font',
    );
    final reset = find.byKey(const Key('player_settings_reset'));
    await tester.ensureVisible(reset);
    await tester.tap(reset);
    await tester.pumpAndSettle();
    expect(store.saved!.subtitleLanguages, 'zh,en');
    expect(
      tester.widget<TextFormField>(languages).controller!.text,
      contains('zh,chi'),
    );
    expect(
      tester.widget<TextFormField>(font).controller!.text,
      isNot('My Subtitle Font'),
    );
    await tester.ensureVisible(save);
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(store.saved!.hardwareDecoding, isTrue);
    expect(store.saved!.subtitleLanguages, contains('zh,chi'));
    expect(tester.takeException(), isNull);
  });

  testWidgets('保存失败显示提示且保留原配置', (tester) async {
    store.fail = true;
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    final original = container.read(playerSettingsProvider);
    await tester.tap(find.byKey(const Key('player_setting_hwdec')));
    final save = find.byKey(const Key('player_settings_save'));
    await tester.ensureVisible(save);
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(find.text('保存播放器设置失败，请重试'), findsOneWidget);
    expect(container.read(playerSettingsProvider), same(original));
    expect(store.saved, isNull);
  });

  testWidgets('窄屏放大字体仍可滚动并保存，非法语言格式不会写入', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 568);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(app(textScale: 1.5));
    await tester.pumpAndSettle();
    final languages = find.byKey(const Key('player_setting_sub_languages'));
    await tester.ensureVisible(languages);
    await tester.enterText(languages, '中文，英文');
    final save = find.byKey(const Key('player_settings_save'));
    await tester.ensureVisible(save);
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(store.saved, isNull);
    expect(find.text('请使用英文逗号分隔语言代码，例如 zh,en'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
