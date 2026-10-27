import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:reelva/app/router.dart';
import 'package:reelva/app/theme/reelva_theme.dart';
import 'package:reelva/features/update/presentation/update_prompt_host.dart';

class ReelvaApp extends ConsumerWidget {
  const ReelvaApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);

    return MaterialApp.router(
      title: 'Reelva',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.light,
      darkTheme: ReelvaTheme.player,
      theme: ReelvaTheme.light,
      routerConfig: router,
      builder: (context, child) => UpdatePromptHost(
        router: router,
        child: child ?? const SizedBox.shrink(),
      ),
    );
  }
}
