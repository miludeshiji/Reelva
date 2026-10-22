import 'package:flutter/material.dart';
import 'package:reelva/shared/widgets/empty_state_view.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: const EmptyStateView(
        icon: Icons.settings_outlined,
        title: '设置',
        message: '应用基础设置与播放选项将在后续版本中提供。',
      ),
    );
  }
}
