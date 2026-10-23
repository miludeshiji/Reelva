import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:reelva/app/shell_page.dart';
import 'package:reelva/features/home/home_page.dart';
import 'package:reelva/features/library/library_page.dart';
import 'package:reelva/features/settings/settings_page.dart';
import 'package:reelva/features/sources/sources_page.dart';
import 'package:reelva/shared/widgets/empty_state_view.dart';
import 'package:reelva/features/player/presentation/player_page.dart';

GoRouter createRouter({String initialLocation = '/'}) {
  return GoRouter(
    initialLocation: initialLocation,
    routes: [
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) {
          return AppShell(navigationShell: navigationShell);
        },
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(path: '/', builder: (context, state) => const HomePage()),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/library',
                builder: (context, state) => const LibraryPage(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/sources',
                builder: (context, state) => const SourcesPage(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/settings',
                builder: (context, state) => const SettingsPage(),
              ),
            ],
          ),
        ],
      ),
      GoRoute(path: '/player', builder: (context, state) => const PlayerPage()),
    ],
    errorBuilder: (context, state) => Scaffold(
      appBar: AppBar(title: const Text('Reelva')),
      body: EmptyStateView(
        icon: Icons.error_outline,
        title: '页面未找到',
        message: '请求的页面不存在或已被移除。',
        actionLabel: '返回首页',
        onAction: () => context.go('/'),
      ),
    ),
  );
}

final routerProvider = Provider<GoRouter>((ref) {
  final router = createRouter();
  ref.onDispose(() {
    router.dispose();
  });
  return router;
});
