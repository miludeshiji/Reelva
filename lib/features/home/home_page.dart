import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:reelva/shared/widgets/empty_state_view.dart';
import 'package:reelva/shared/widgets/reelva_logo.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [ReelvaLogo(size: 28), SizedBox(width: 8), Text('首页')],
        ),
      ),
      body: EmptyStateView(
        icon: Icons.movie_outlined,
        title: '暂无影视内容',
        message: '添加媒体源后将在此展示推荐与最近播放内容。',
        actionLabel: '前往媒体源',
        onAction: () => context.go('/sources'),
      ),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('home_open_player_fab'),
        onPressed: () => context.go('/player'),
        icon: const Icon(Icons.play_arrow),
        label: const Text('打开播放器'),
      ),
    );
  }
}
