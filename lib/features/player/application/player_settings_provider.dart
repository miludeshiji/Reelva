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
  late PlayerSettings _savedSettings;
  Future<void> _pendingSave = Future<void>.value();

  @override
  PlayerSettings build() => _savedSettings =
      initialSettings ?? PlayerSettings.defaultsFor(defaultTargetPlatform);

  Future<void> save(PlayerSettings settings) {
    settings.validate();
    final store = ref.read(playerSettingsStoreProvider);
    state = settings;
    // 连续修改按顺序写入，页面离开后仍完成保存。
    final operation = _pendingSave.then((_) async {
      try {
        await store.save(settings);
        _savedSettings = settings;
      } catch (_) {
        if (ref.mounted && identical(state, settings)) state = _savedSettings;
        rethrow;
      }
    });
    // 单次失败交给调用方提示，后续修改仍可继续保存。
    _pendingSave = operation.then<void>((_) {}, onError: (Object error) {});
    return operation;
  }

  Future<void> reload() async {
    await _pendingSave;
    final previous = state;
    final settings = await ref.read(playerSettingsStoreProvider).read();
    if (ref.mounted && identical(state, previous)) {
      _savedSettings = settings;
      state = settings;
    }
  }
}
