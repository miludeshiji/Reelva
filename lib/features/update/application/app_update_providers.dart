import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/logging/app_logger.dart';
import '../domain/app_release.dart';
import '../infrastructure/android_update_installer.dart';
import '../infrastructure/apk_downloader.dart';
import '../infrastructure/github_release_client.dart';
import '../infrastructure/update_preferences_store.dart';

final packageInfoProvider = FutureProvider<PackageInfo>(
  (ref) => PackageInfo.fromPlatform(),
);

final githubReleaseClientProvider = Provider<GithubReleaseClient>((ref) {
  final client = GithubReleaseClient();
  ref.onDispose(client.close);
  return client;
});

final apkDownloaderProvider = Provider<ApkDownloader>((ref) {
  final downloader = ApkDownloader();
  ref.onDispose(downloader.close);
  return downloader;
});

final androidUpdateInstallerProvider = Provider<AndroidUpdateInstaller>(
  (ref) => const AndroidUpdateInstaller(),
);

final updateAbisProvider = FutureProvider<List<String>>(
  (ref) => ref.watch(androidUpdateInstallerProvider).supportedAbis(),
);

final openUpdateUrlProvider = Provider<Future<void> Function(Uri)>(
  (ref) => (uri) async {
    if (!const ['https', 'http'].contains(uri.scheme) ||
        !await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      throw StateError('无法打开链接');
    }
  },
);

final updatePreferencesStoreProvider = Provider<UpdatePreferencesStore>(
  (ref) => const UpdatePreferencesStore(),
);

final updatePreferencesProvider =
    AsyncNotifierProvider<UpdatePreferencesController, UpdatePreferences>(
      UpdatePreferencesController.new,
    );

class UpdatePreferencesController extends AsyncNotifier<UpdatePreferences> {
  @override
  Future<UpdatePreferences> build() =>
      ref.watch(updatePreferencesStoreProvider).read();

  Future<void> setAutomatic(bool automatic) async {
    await ref.read(updatePreferencesStoreProvider).saveAutomatic(automatic);
    final current = await future;
    state = AsyncData(
      UpdatePreferences(
        automatic: automatic,
        lastCheckedAt: current.lastCheckedAt,
      ),
    );
  }

  Future<void> markChecked(DateTime now) async {
    await ref.read(updatePreferencesStoreProvider).saveLastChecked(now);
    final current = await future;
    state = AsyncData(
      UpdatePreferences(automatic: current.automatic, lastCheckedAt: now),
    );
  }
}

final updateCheckProvider =
    NotifierProvider<AppUpdateController, AsyncValue<AppRelease?>>(
      AppUpdateController.new,
    );

class AppUpdateController extends Notifier<AsyncValue<AppRelease?>> {
  Future<AppRelease?>? _pending;

  @override
  AsyncValue<AppRelease?> build() => const AsyncData(null);

  Future<AppRelease?> check() => _pending ??= _check();

  Future<AppRelease?> _check() async {
    state = const AsyncLoading();
    try {
      final info = await ref.read(packageInfoProvider.future);
      try {
        await ref
            .read(updatePreferencesProvider.notifier)
            .markChecked(DateTime.now());
      } catch (e, st) {
        AppLogger.instance.error('保存更新检查时间失败', error: e, stackTrace: st);
      }
      final release = await ref
          .read(githubReleaseClientProvider)
          .findUpdate(info.version);
      if (ref.mounted) state = AsyncData(release);
      return release;
    } catch (e, st) {
      if (ref.mounted) state = AsyncError(e, st);
      rethrow;
    } finally {
      _pending = null;
    }
  }
}
