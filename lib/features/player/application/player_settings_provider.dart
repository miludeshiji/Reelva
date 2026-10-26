import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/player_settings.dart';
import '../infrastructure/player_settings_store.dart';

final playerSettingsStoreProvider = Provider<PlayerSettingsStore>((ref) {
  return const PlayerSettingsStore();
});

final playerSettingsProvider =
    NotifierProvider<PlayerSettingsController, PlayerSettings>(
      PlayerSettingsController.new,
    );

class PlayerSettingsController extends Notifier<PlayerSettings> {
  PlayerSettingsController({this.initialSettings});

  final PlayerSettings? initialSettings;

  @override
  PlayerSettings build() =>
      initialSettings ?? PlayerSettings.defaultsFor(defaultTargetPlatform);

  Future<void> save(PlayerSettings settings) async {
    await ref.read(playerSettingsStoreProvider).save(settings);
    state = settings;
  }

  Future<void> reload() async {
    final settings = await ref.read(playerSettingsStoreProvider).read();
    if (ref.mounted) state = settings;
  }
}
