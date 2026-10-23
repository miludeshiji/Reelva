import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:reelva/app/app.dart';
import 'package:reelva/core/errors/error_handling.dart';
import 'package:reelva/features/player/infrastructure/media_kit_player_engine.dart';
import 'package:window_manager/window_manager.dart';

void _registerLicenses() {
  LicenseRegistry.addLicense(() async* {
    final license = await rootBundle.loadString('assets/licenses/libsmb2.txt');
    yield LicenseEntryWithLineBreaks(['libsmb2'], license);
  });
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  _registerLicenses();
  installErrorHandling();
  initializeMediaKit();

  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.windows) {
    await windowManager.ensureInitialized();
  }

  runApp(const ProviderScope(child: ReelvaApp()));
}
