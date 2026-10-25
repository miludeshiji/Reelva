import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:reelva/app/theme/reelva_theme.dart';
import 'package:reelva/shared/widgets/glass_navigation.dart';

class AnimatedBranchContainer extends StatelessWidget {
  const AnimatedBranchContainer({
    super.key,
    required this.currentIndex,
    required this.children,
  });

  final int currentIndex;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 300);

    return Stack(
      fit: StackFit.expand,
      children: [
        for (var index = 0; index < children.length; index++)
          TweenAnimationBuilder<double>(
            tween: Tween(
              begin: index == currentIndex ? 1 : 0,
              end: index == currentIndex ? 1 : 0,
            ),
            duration: duration,
            curve: Curves.easeInOutCubic,
            builder: (context, opacity, child) => Offstage(
              offstage: opacity == 0,
              child: Opacity(opacity: opacity, child: child),
            ),
            child: IgnorePointer(
              ignoring: index != currentIndex,
              child: ExcludeFocus(
                excluding: index != currentIndex,
                child: ExcludeSemantics(
                  excluding: index != currentIndex,
                  child: TickerMode(
                    enabled: index == currentIndex,
                    child: children[index],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  void _onDestinationSelected(int index) {
    navigationShell.goBranch(
      index,
      initialLocation: index == navigationShell.currentIndex,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isWide =
        MediaQuery.sizeOf(context).width >= ReelvaDesign.desktopBreakpoint;

    if (isWide) {
      return Scaffold(
        backgroundColor: ReelvaDesign.background,
        body: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            GlassSidebar(
              selectedIndex: navigationShell.currentIndex,
              onDestinationSelected: _onDestinationSelected,
            ),
            Expanded(child: navigationShell),
          ],
        ),
      );
    }

    return Scaffold(
      backgroundColor: ReelvaDesign.background,
      body: navigationShell,
      bottomNavigationBar: GlassBottomNavigationBar(
        selectedIndex: navigationShell.currentIndex,
        onDestinationSelected: _onDestinationSelected,
      ),
    );
  }
}
