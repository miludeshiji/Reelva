import 'package:flutter/material.dart';
import 'package:reelva/shared/widgets/empty_state_view.dart';

class LibraryPage extends StatelessWidget {
  const LibraryPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('影视库')),
      body: const EmptyStateView(
        icon: Icons.video_library_outlined,
        title: '影视库为空',
        message: '配置媒体源并完成扫描后，影视库将呈现海报墙与分类详情。',
      ),
    );
  }
}
