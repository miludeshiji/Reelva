import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reelva/app/theme/reelva_theme.dart';
import 'package:reelva/features/settings/player_shortcuts_page.dart';
import 'package:reelva/shared/widgets/glass_widgets.dart';

const _captureDir = String.fromEnvironment('REELVA_HOVER_CAPTURE_DIR');
typedef _Pixels = ({int width, Uint8List bytes});

Future<_Pixels> _capture(
  WidgetTester tester,
  GlobalKey key, [
  String? name,
]) async {
  final boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  return (await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1);
    try {
      final raw = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
      if (_captureDir.isNotEmpty && name != null) {
        final png = (await image.toByteData(format: ui.ImageByteFormat.png))!;
        await Directory(_captureDir).create(recursive: true);
        await File('$_captureDir/$name.png')
            .writeAsBytes(png.buffer.asUint8List());
      }
      return (width: image.width, bytes: raw.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  }))!;
}

int _pixel(_Pixels image, Offset point) {
  final index = (point.dy.floor() * image.width + point.dx.floor()) * 4;
  return (image.bytes[index] << 24) |
      (image.bytes[index + 1] << 16) |
      (image.bytes[index + 2] << 8) |
      image.bytes[index + 3];
}

Widget _app(GlobalKey boundary, Widget child, {ThemeData? theme}) =>
    MaterialApp(
      theme: theme ?? ReelvaTheme.light,
      home: RepaintBoundary(
        key: boundary,
        child: Scaffold(body: child),
      ),
    );

void main() {
  setUpAll(() async {
    if (_captureDir.isNotEmpty) {
      for (final family in ['Roboto', 'Microsoft YaHei', 'Noto Sans CJK SC']) {
        final font = FontLoader(family)
          ..addFont(rootBundle.load('assets/fonts/NotoSansCJKsc-Regular.otf'));
        await font.load();
      }
      final icons = FontLoader('MaterialIcons')
        ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
      await icons.load();
    }
  });

  testWidgets('快捷键分组收起时整块圆角变色，展开后悬停不染色内容区', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1000, 760);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final boundary = GlobalKey();
    await tester.pumpWidget(
      _app(boundary, const ProviderScope(child: PlayerShortcutsPage())),
    );
    await tester.pumpAndSettle();
    if (_captureDir.isNotEmpty) {
      await _capture(tester, boundary, 'shortcut-rows');
    }
    final playback = find.byKey(const Key('shortcut_group_playback'));
    await tester.tap(
      find.descendant(of: playback, matching: find.byType(ListTile)).first,
    );
    await tester.pumpAndSettle();
    FocusManager.instance.primaryFocus?.unfocus();
    final audio = find.byKey(const Key('shortcut_group_audio'));
    final header = find
        .descendant(of: audio, matching: find.byType(ListTile))
        .first;
    await tester.ensureVisible(header);
    await tester.pumpAndSettle();
    final card = find
        .ancestor(of: audio, matching: find.byType(GlassCard))
        .first;
    final rect = tester.getRect(card);
    final edge = Offset(rect.left + 6, rect.center.dy);
    final corner = rect.topLeft + const Offset(2, 2);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: const Offset(999, 759));
    await tester.pumpAndSettle();
    final normal = await _capture(tester, boundary);
    await mouse.moveTo(tester.getCenter(header));
    await tester.pumpAndSettle();
    final hovered = await _capture(tester, boundary, 'collapsed-hover');
    expect(
      _pixel(hovered, edge),
      isNot(_pixel(normal, edge)),
      reason: '标题悬停需覆盖外层卡片内边缘',
    );
    expect(
      _pixel(hovered, corner),
      _pixel(normal, corner),
      reason: '悬停填充不得越出圆角',
    );

    await tester.tap(header);
    await tester.pumpAndSettle();
    FocusManager.instance.primaryFocus?.unfocus();
    await mouse.moveTo(const Offset(999, 759));
    await tester.pumpAndSettle();
    final expandedNormal = await _capture(tester, boundary);
    final headerRect = tester.getRect(header);
    final headerEdge = Offset(headerRect.left + 6, headerRect.center.dy);
    final bodyEdge = Offset(headerRect.left + 6, headerRect.bottom + 24);
    await mouse.moveTo(headerRect.center);
    await tester.pumpAndSettle();
    final expandedHover = await _capture(
      tester,
      boundary,
      'expanded-header-hover',
    );
    expect(
      _pixel(expandedHover, headerEdge),
      isNot(_pixel(expandedNormal, headerEdge)),
    );
    expect(_pixel(expandedHover, bodyEdge), _pixel(expandedNormal, bodyEdge));
    await mouse.moveTo(
      tester.getCenter(find.byKey(const Key('shortcut_bind_volumeUp'))),
    );
    await tester.pumpAndSettle();
    final childHover = await _capture(
      tester,
      boundary,
      'expanded-button-hover',
    );
    expect(
      _pixel(childHover, headerEdge),
      _pixel(expandedNormal, headerEdge),
      reason: '内容按钮悬停不连带高亮分组标题',
    );
    await mouse.removePointer();
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final dark in [false, true]) {
    testWidgets('按钮、图标和菜单在${dark ? '深色' : '浅色'}主题下覆盖完整圆角点击区域', (tester) async {
      final boundary = GlobalKey();
      final widgets = <Widget>[
        SizedBox(
          width: 160,
          child: FilledButton(onPressed: () {}, child: const Text('Filled')),
        ),
        SizedBox(
          width: 160,
          child: OutlinedButton(
            onPressed: () {},
            child: const Text('Outlined'),
          ),
        ),
        SizedBox(
          width: 160,
          child: TextButton(onPressed: () {}, child: const Text('Text')),
        ),
        SizedBox(
          width: 160,
          child: ElevatedButton(
            onPressed: () {},
            child: const Text('Elevated'),
          ),
        ),
        IconButton(onPressed: () {}, icon: const Icon(Icons.add)),
        GlassIconButton(icon: Icons.add, onPressed: () {}, tooltip: 'Add'),
        SizedBox(
          width: 160,
          child: MenuItemButton(onPressed: () {}, child: const Text('Menu')),
        ),
        const SizedBox(
          width: 160,
          child: GlassPopupMenuItem<int>(value: 1, child: Text('Popup')),
        ),
      ];
      for (final (index, widget) in widgets.indexed) {
        final target = Key('hover_target_$index');
        final content = KeyedSubtree(key: target, child: widget);
        await tester.pumpWidget(
          _app(
            boundary,
            Center(
              child: index >= 6
                  ? Semantics(
                      container: true,
                      explicitChildNodes: true,
                      role: ui.SemanticsRole.menu,
                      child: content,
                    )
                  : content,
            ),
            theme: dark ? ReelvaTheme.player : ReelvaTheme.light,
          ),
        );
        await tester.pumpAndSettle();
        final rect = tester.getRect(find.byKey(target));
        final edge = Offset(rect.left + 6, rect.center.dy);
        final corner = rect.topLeft + const Offset(1, 1);
        final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
        await mouse.addPointer(location: Offset.zero);
        await tester.pumpAndSettle();
        final normal = await _capture(tester, boundary);
        await mouse.moveTo(rect.center);
        await tester.pumpAndSettle();
        final hover = await _capture(tester, boundary);
        expect(
          _pixel(hover, edge),
          isNot(_pixel(normal, edge)),
          reason: '$index 的完整点击区域应有悬停反馈',
        );
        expect(
          _pixel(hover, corner),
          _pixel(normal, corner),
          reason: '$index 的圆角外侧应保持原色',
        );
        await mouse.removePointer();
        await tester.pumpWidget(const SizedBox.shrink());
      }
    });
  }

  testWidgets('禁用按钮不着色，键盘焦点与按下状态保留独立反馈', (tester) async {
    final boundary = GlobalKey();
    const target = Key('state_button');
    await tester.pumpWidget(
      _app(
        boundary,
        const Center(
          child: SizedBox(
            width: 160,
            child: FilledButton(
              key: target,
              onPressed: null,
              child: Text('Disabled'),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    var rect = tester.getRect(find.byKey(target));
    var edge = Offset(rect.left + 6, rect.center.dy);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    await tester.pumpAndSettle();
    final disabled = await _capture(tester, boundary);
    await mouse.moveTo(rect.center);
    await tester.pumpAndSettle();
    expect(
      _pixel(await _capture(tester, boundary), edge),
      _pixel(disabled, edge),
    );
    await mouse.moveTo(Offset.zero);
    final focus = FocusNode();
    final originalStrategy = FocusManager.instance.highlightStrategy;
    FocusManager.instance.highlightStrategy =
        FocusHighlightStrategy.alwaysTraditional;
    addTearDown(
      () => FocusManager.instance.highlightStrategy = originalStrategy,
    );
    await tester.pumpWidget(
      _app(
        boundary,
        Center(
          child: SizedBox(
            width: 160,
            child: OutlinedButton(
              key: target,
              focusNode: focus,
              onPressed: () {},
              child: const Text('Active'),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    rect = tester.getRect(find.byKey(target));
    edge = Offset(rect.left + 6, rect.center.dy);
    final normal = await _capture(tester, boundary);
    focus.requestFocus();
    await tester.pumpAndSettle();
    final focused = await _capture(tester, boundary);
    expect(_pixel(focused, edge), isNot(_pixel(normal, edge)));
    await mouse.moveTo(rect.center);
    await mouse.down(rect.center);
    await tester.pumpAndSettle();
    final pressed = await _capture(tester, boundary);
    expect(_pixel(pressed, edge), isNot(_pixel(focused, edge)));
    await mouse.up();
    await mouse.removePointer();
    await tester.pumpWidget(const SizedBox.shrink());
    focus.dispose();
  });
}
