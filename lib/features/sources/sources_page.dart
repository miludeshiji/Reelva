import 'package:flutter/material.dart';
import 'package:reelva/shared/widgets/empty_state_view.dart';

class SourcesPage extends StatelessWidget {
  const SourcesPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('媒体源')),
      body: const EmptyStateView(
        icon: Icons.folder_outlined,
        title: '暂无媒体源',
        message: '后续可在设置或管理中添加本地目录或 WebDAV 等远程源。',
      ),
    );
  }
}
