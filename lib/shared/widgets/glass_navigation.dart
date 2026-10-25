import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:reelva/shared/widgets/glass_widgets.dart';

const _destinations = [
  (id: 'home', label: '首页', icon: Icons.home_outlined),
  (id: 'library', label: '影视库', icon: Icons.grid_view_outlined),
  (id: 'sources', label: '媒体源', icon: Icons.folder_outlined),
  (id: 'settings', label: '设置', icon: Icons.light_mode_outlined),
];

class GlassBottomNavigationBar extends StatelessWidget {
  const GlassBottomNavigationBar({
    super.key,
    required this.selectedIndex,
    required this.onDestinationSelected,
  });

  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      key: const ValueKey('glass_bottom_navigation'),
      top: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: ReelvaDesign.space16,
          vertical: ReelvaDesign.space12,
        ),
        child: _GlassSurface(
          borderRadius: BorderRadius.circular(32),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 7),
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var index = 0; index < _destinations.length; index++)
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: ReelvaDesign.space4,
                        ),
                        child: _NavigationButton(
                          index: index,
                          selected: index == selectedIndex,
                          onTap: () => onDestinationSelected(index),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class GlassSidebar extends StatefulWidget {
  const GlassSidebar({
    super.key,
    required this.selectedIndex,
    required this.onDestinationSelected,
  });

  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;

  @override
  State<GlassSidebar> createState() => _GlassSidebarState();
}

class _GlassSidebarState extends State<GlassSidebar> {
  bool _isCollapsed = false;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      key: const ValueKey('glass_sidebar'),
      width: _isCollapsed ? 128 : 248,
      child: Padding(
        padding: const EdgeInsets.all(ReelvaDesign.space16),
        child: _GlassSurface(
          borderRadius: BorderRadius.circular(ReelvaDesign.radiusLarge),
          child: SafeArea(
            child: SingleChildScrollView(
              padding: EdgeInsets.symmetric(
                horizontal: _isCollapsed
                    ? ReelvaDesign.space8
                    : ReelvaDesign.space16,
                vertical: ReelvaDesign.space16,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    mainAxisAlignment: _isCollapsed
                        ? MainAxisAlignment.center
                        : MainAxisAlignment.start,
                    children: [
                      IconButton(
                        key: const ValueKey('sidebar_toggle'),
                        tooltip: _isCollapsed ? '展开侧栏' : '收起侧栏',
                        icon: Icon(
                          _isCollapsed
                              ? Icons.menu_rounded
                              : Icons.menu_open_rounded,
                          color: ReelvaDesign.ink,
                        ),
                        onPressed: () => setState(() {
                          _isCollapsed = !_isCollapsed;
                        }),
                      ),
                      if (!_isCollapsed) ...[
                        const SizedBox(width: ReelvaDesign.space12),
                        const Expanded(
                          child: Text(
                            'Reelva',
                            style: TextStyle(
                              color: ReelvaDesign.ink,
                              fontSize: 22,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: ReelvaDesign.space32),
                  for (
                    var index = 0;
                    index < _destinations.length;
                    index++
                  ) ...[
                    if (index > 0) const SizedBox(height: ReelvaDesign.space8),
                    _NavigationButton(
                      index: index,
                      selected: index == widget.selectedIndex,
                      isSidebar: true,
                      textOnly: _isCollapsed,
                      onTap: () => widget.onDestinationSelected(index),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _GlassSurface extends StatelessWidget {
  const _GlassSurface({required this.borderRadius, required this.child});

  final BorderRadius borderRadius;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        boxShadow: const [
          BoxShadow(
            color: Color(0x10283D66),
            blurRadius: 24,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: borderRadius,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.81),
              border: Border.all(color: Colors.white, width: 1.5),
              borderRadius: borderRadius,
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

class _NavigationButton extends StatelessWidget {
  const _NavigationButton({
    required this.index,
    required this.selected,
    required this.onTap,
    this.isSidebar = false,
    this.textOnly = false,
  });

  final int index;
  final bool selected;
  final VoidCallback onTap;
  final bool isSidebar;
  final bool textOnly;

  @override
  Widget build(BuildContext context) {
    final destination = _destinations[index];
    final color = selected ? ReelvaDesign.accent : ReelvaDesign.muted;
    final borderRadius = BorderRadius.circular(27);
    final icon = Icon(destination.icon, size: 20, color: color);
    final label = Text(
      destination.label,
      textAlign: isSidebar && !textOnly ? TextAlign.start : TextAlign.center,
      style: TextStyle(
        color: color,
        fontSize: isSidebar ? 14 : 11,
        fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
        height: 1.2,
      ),
    );

    return Semantics(
      key: ValueKey('navigation_destination_${destination.id}'),
      label: destination.label,
      selected: selected,
      button: true,
      onTap: onTap,
      excludeSemantics: true,
      child: Material(
        color: selected
            ? const Color(0xFFE7EFFC).withValues(alpha: 0.95)
            : Colors.transparent,
        borderRadius: borderRadius,
        child: InkWell(
          borderRadius: borderRadius,
          onTap: onTap,
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: isSidebar ? 54 : 62),
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: isSidebar && !textOnly
                    ? ReelvaDesign.space16
                    : ReelvaDesign.space4,
                vertical: isSidebar
                    ? ReelvaDesign.space12
                    : ReelvaDesign.space8,
              ),
              child: textOnly
                  ? Center(child: label)
                  : isSidebar
                  ? Row(
                      children: [
                        icon,
                        const SizedBox(width: ReelvaDesign.space12),
                        Expanded(child: label),
                      ],
                    )
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [icon, const SizedBox(height: 6), label],
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
