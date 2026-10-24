import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:reelva/app/theme/reelva_theme.dart';
import 'package:reelva/shared/widgets/glass_navigation.dart';

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
              onOpenPlayer: () {
                final router = GoRouter.of(context);
                if (router.routeInformationProvider.value.uri.path !=
                    '/player') {
                  router.push<void>('/player');
                }
              },
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
