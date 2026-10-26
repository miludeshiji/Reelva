import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:reelva/app/shell_page.dart';
import 'package:reelva/features/home/home_page.dart';
import 'package:reelva/features/library/library_page.dart';
import 'package:reelva/features/library/presentation/work_details_page.dart';
import 'package:reelva/features/player/domain/playback_resource.dart';
import 'package:reelva/features/player/presentation/player_page.dart';
import 'package:reelva/features/progress/presentation/watch_history_page.dart';
import 'package:reelva/features/settings/about_page.dart';
import 'package:reelva/features/settings/player_settings_page.dart';
import 'package:reelva/features/settings/player_shortcuts_page.dart';
import 'package:reelva/features/settings/settings_page.dart';
import 'package:reelva/features/settings/settings_subpages.dart';
import 'package:reelva/features/sources/add_source_page.dart';
import 'package:reelva/features/sources/source_setup_page.dart';
import 'package:reelva/features/sources/sources_page.dart';
import 'package:reelva/features/sources/source_files_page.dart';
import 'package:reelva/shared/widgets/empty_state_view.dart';

GoRouter createRouter({String initialLocation = '/'}) {
  return GoRouter(
    initialLocation: initialLocation,
    routes: [
      StatefulShellRoute(
        pageBuilder: (context, state, navigationShell) => _buildMaterialPage(
          state,
          AppShell(navigationShell: navigationShell),
        ),
        navigatorContainerBuilder: (context, navigationShell, children) =>
            AnimatedBranchContainer(
              currentIndex: navigationShell.currentIndex,
              children: children,
            ),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/',
                pageBuilder: (context, state) =>
                    _buildMaterialPage(state, const HomePage()),
                routes: [
                  GoRoute(
                    path: 'history',
                    pageBuilder: (context, state) =>
                        _buildMaterialPage(state, const WatchHistoryPage()),
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/library',
                pageBuilder: (context, state) =>
                    _buildMaterialPage(state, const LibraryPage()),
                routes: [
                  GoRoute(
                    path: 'unmatched',
                    pageBuilder: (context, state) => _buildMaterialPage(
                      state,
                      const LibraryPage(unmatchedOnly: true),
                    ),
                  ),
                  GoRoute(
                    path: 'work/:id',
                    pageBuilder: (context, state) {
                      final id =
                          int.tryParse(state.pathParameters['id'] ?? '') ?? 0;
                      return _buildMaterialPage(
                        state,
                        WorkDetailsPage(workId: id),
                      );
                    },
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/sources',
                pageBuilder: (context, state) =>
                    _buildMaterialPage(state, const SourcesPage()),
                routes: [
                  GoRoute(
                    path: 'add',
                    pageBuilder: (context, state) =>
                        _buildMaterialPage(state, const AddSourcePage()),
                    routes: [
                      GoRoute(
                        path: ':kind',
                        redirect: (context, state) =>
                            SourceSetupKind.values.any(
                              (kind) =>
                                  kind.name == state.pathParameters['kind'],
                            )
                            ? null
                            : '/sources/add',
                        pageBuilder: (context, state) => _buildMaterialPage(
                          state,
                          SourceSetupPage(
                            kind: SourceSetupKind.values.byName(
                              state.pathParameters['kind']!,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  GoRoute(
                    path: ':id/files',
                    pageBuilder: (context, state) => _buildMaterialPage(
                      state,
                      SourceFilesPage(
                        sourceId:
                            int.tryParse(state.pathParameters['id'] ?? '') ?? 0,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/settings',
                pageBuilder: (context, state) =>
                    _buildMaterialPage(state, const SettingsPage()),
                routes: [
                  GoRoute(
                    path: 'player',
                    pageBuilder: (context, state) =>
                        _buildMaterialPage(state, const PlayerSettingsPage()),
                  ),
                  GoRoute(
                    path: 'shortcuts',
                    pageBuilder: (context, state) =>
                        _buildMaterialPage(state, const PlayerShortcutsPage()),
                  ),
                  GoRoute(
                    path: 'tmdb',
                    pageBuilder: (context, state) =>
                        _buildMaterialPage(state, const TmdbSettingsPage()),
                  ),
                  GoRoute(
                    path: 'sync',
                    pageBuilder: (context, state) =>
                        _buildMaterialPage(state, const SyncSettingsPage()),
                  ),
                  GoRoute(
                    path: 'cache',
                    pageBuilder: (context, state) => _buildMaterialPage(
                      state,
                      const PosterCacheSettingsPage(),
                    ),
                  ),
                  GoRoute(
                    path: 'about',
                    pageBuilder: (context, state) =>
                        _buildMaterialPage(state, const AboutPage()),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
      GoRoute(
        path: '/player',
        pageBuilder: (context, state) {
          final extra = state.extra;
          final initialResource = extra is PlaybackResource ? extra : null;
          return _buildMaterialPage(
            state,
            PlayerPage(initialResource: initialResource),
          );
        },
      ),
    ],
    errorPageBuilder: (context, state) => _buildMaterialPage(
      state,
      Scaffold(
        appBar: AppBar(title: const Text('Reelva')),
        body: EmptyStateView(
          icon: Icons.error_outline,
          title: '页面未找到',
          message: '请求的页面不存在或已被移除。',
          actionLabel: '返回首页',
          onAction: () => context.go('/'),
        ),
      ),
    ),
  );
}

// 显式使用 Flutter Material 页面，避免自动识别失败时回退为无动画页面。
MaterialPage<void> _buildMaterialPage(GoRouterState state, Widget child) {
  return MaterialPage<void>(
    key: state.pageKey,
    name: state.name ?? state.path,
    arguments: {...state.pathParameters, ...state.uri.queryParameters},
    restorationId: state.pageKey.value,
    child: child,
  );
}

final routerProvider = Provider<GoRouter>((ref) {
  final router = createRouter();
  ref.onDispose(() {
    router.dispose();
  });
  return router;
});
