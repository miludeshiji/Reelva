import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class UpdatePreferences {
  const UpdatePreferences({this.automatic = true, this.lastCheckedAt});

  final bool automatic;
  final DateTime? lastCheckedAt;

  bool shouldCheck(DateTime now) =>
      automatic &&
      (lastCheckedAt == null ||
          now.difference(lastCheckedAt!) >= const Duration(hours: 24));
}

class UpdatePreferencesStore {
  const UpdatePreferencesStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  static const automaticKey = 'reelva_update_automatic';
  static const lastCheckedKey = 'reelva_update_last_checked';
  final FlutterSecureStorage _storage;

  Future<UpdatePreferences> read() async => UpdatePreferences(
    automatic: await _storage.read(key: automaticKey) != 'false',
    lastCheckedAt: DateTime.tryParse(
      await _storage.read(key: lastCheckedKey) ?? '',
    ),
  );

  Future<void> saveAutomatic(bool value) =>
      _storage.write(key: automaticKey, value: '$value');

  Future<void> saveLastChecked(DateTime value) => _storage.write(
    key: lastCheckedKey,
    value: value.toUtc().toIso8601String(),
  );
}
