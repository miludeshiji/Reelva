import 'package:flutter/material.dart';

/// 播放列表、字幕和音频共用右下角按钮上方的面板位置及外观。
class PlayerSelectionPanel extends StatelessWidget {
  const PlayerSelectionPanel({
    super.key,
    required this.anchorKey,
    required this.panelKey,
    required this.title,
    required this.child,
  });

  final GlobalKey anchorKey;
  final Key panelKey;
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final button = anchorKey.currentContext!.findRenderObject()! as RenderBox;
      final anchor = button.localToGlobal(Offset.zero) & button.size;
      final safePadding = MediaQuery.paddingOf(context);
      final availableHeight = (anchor.top - safePadding.top - 16).clamp(
        0.0,
        constraints.maxHeight * 0.7,
      );
      return Dialog(
        alignment: Alignment.bottomRight,
        insetPadding: EdgeInsets.only(
          left: safePadding.left + 8,
          top: safePadding.top + 8,
          right: constraints.maxWidth - anchor.right,
          bottom: constraints.maxHeight - anchor.top + 8,
        ),
        constraints: const BoxConstraints(minWidth: 0, maxWidth: 280),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: availableHeight),
          child: SizedBox(
            key: panelKey,
            width: 280,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 8, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                      IconButton(
                        tooltip: '关闭$title',
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                ),
                Flexible(child: child),
              ],
            ),
          ),
        ),
      );
    },
  );
}
