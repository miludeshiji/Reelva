import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:reelva/features/player/application/player_settings_provider.dart';
import 'package:reelva/features/player/domain/playback_resource.dart';
import 'package:reelva/features/player/domain/player_settings.dart';
import 'package:reelva/features/player/infrastructure/media_kit_player_engine.dart';
import 'package:reelva/features/player/infrastructure/mpv_player_configuration.dart';
import 'package:reelva/features/player/infrastructure/player_settings_store.dart';

import 'test_platform_player.dart';

class _FailingStore extends PlayerSettingsStore {
  @override
  Future<void> save(PlayerSettings settings) async =>
      throw StateError('storage unavailable');
}

/// 在原生接口边界记录参数，复用现有播放替身，不加载本机 DLL。
class _NativePlayer extends Fake implements NativePlayer {
  final delegate = TestPlatformPlayer();
  final properties = <String, String>{};

  @override
  PlayerState get state => delegate.state;

  @override
  PlayerStream get stream => delegate.stream;

  @override
  Future<void> setProperty(
    String property,
    String value, {
    bool waitForInitialization = true,
  }) async {
    properties[property] = value;
  }

  @override
  Future<void> open(
    Playable playable, {
    bool play = true,
    bool synchronized = true,
  }) => delegate.open(playable, play: play);

  @override
  Future<void> play({bool synchronized = true}) => delegate.play();

  @override
  Future<void> stop({
    bool open = false,
    bool notify = true,
    bool synchronized = true,
  }) => delegate.stop();

  @override
  Future<void> dispose({bool synchronized = true}) => delegate.dispose();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  test('平台默认值参考个人配置并限制移动端负载', () {
    final windows = PlayerSettings.defaultsFor(TargetPlatform.windows);
    final android = PlayerSettings.defaultsFor(TargetPlatform.android);
    expect(windows.cacheSizeMb, 1024);
    expect(windows.highQualityRendering, isTrue);
    expect(windows.deband, isTrue);
    expect(android.cacheSizeMb, 128);
    expect(android.highQualityRendering, isFalse);
    expect(android.deband, isFalse);
    expect(android.pitchCorrection, isTrue);
    expect(windows.ditherDepth, DitherDepth.auto);
    expect(windows.maxVolume, 200);
  });

  test('保存后重新读取完整配置，缺省字段使用本机默认值', () async {
    const store = PlayerSettingsStore();
    final settings = PlayerSettings.defaultsFor(TargetPlatform.windows)
        .copyWith(
          hardwareDecoding: false,
          cacheEnabled: false,
          cacheSizeMb: 256,
          ditherDepth: DitherDepth.eight,
          pitchCorrection: false,
          maxVolume: 150,
          audioAutoLoad: TrackAutoLoad.disabled,
          subtitleAutoLoad: TrackAutoLoad.exact,
          subtitleLanguages: 'en,zh-hans',
          subtitleFont: 'Source Han Sans Medium',
          subtitleFontSize: 48,
          subtitleBorderSize: 3,
          subtitleBlur: 0,
          subtitleMarginY: 24,
          assStyleOverride: AssStyleOverride.force,
          blendSubtitles: false,
        );
    await store.save(settings);
    expect((await store.read()).toJson(), settings.toJson());

    FlutterSecureStorage.setMockInitialValues({
      PlayerSettingsStore.storageKey: jsonEncode({'cacheSizeMb': 64}),
    });
    final partial = await store.read();
    expect(partial.cacheSizeMb, 64);
    expect(
      partial.subtitleFont,
      PlayerSettings.defaultsFor(defaultTargetPlatform).subtitleFont,
    );
  });

  test('拒绝损坏或超范围设置，避免把无效参数传给播放器', () async {
    const store = PlayerSettingsStore();
    FlutterSecureStorage.setMockInitialValues({
      PlayerSettingsStore.storageKey: '{broken',
    });
    await expectLater(store.read(), throwsFormatException);
    FlutterSecureStorage.setMockInitialValues({
      PlayerSettingsStore.storageKey: jsonEncode({'cacheSizeMb': 4096}),
    });
    await expectLater(store.read(), throwsFormatException);
    await expectLater(
      store.save(const PlayerSettings(maxVolume: 999)),
      throwsFormatException,
    );
  });

  test('存储写入失败时保持当前配置', () async {
    final container = ProviderContainer(
      overrides: [
        playerSettingsStoreProvider.overrideWithValue(_FailingStore()),
      ],
    );
    addTearDown(container.dispose);
    final original = container.read(playerSettingsProvider);
    await expectLater(
      container
          .read(playerSettingsProvider.notifier)
          .save(original.copyWith(maxVolume: 100)),
      throwsStateError,
    );
    expect(container.read(playerSettingsProvider), same(original));
  });

  test('加载媒体之前应用用户配置，保留嵌入式渲染和原生字幕配置', () async {
    const settings = PlayerSettings(
      hardwareDecoding: false,
      cacheSizeMb: 64,
      maxVolume: 150,
      subtitleLanguages: 'en,zh',
      subtitleFontSize: 48,
    );
    final platformPlayer = _NativePlayer();
    final engine = MediaKitPlayerEngine(
      player: Player(platformPlayer: platformPlayer),
      settings: settings,
    );
    addTearDown(engine.dispose);
    var openedWithSettings = false;
    platformPlayer.delegate.onOpen = (_) async {
      expect(
        platformPlayer.properties['demuxer-max-bytes'],
        '${64 * 1024 * 1024}',
      );
      expect(platformPlayer.properties['cache-on-disk'], 'no');
      expect(platformPlayer.properties['volume-max'], '150');
      expect(platformPlayer.properties['slang'], 'en,zh');
      expect(platformPlayer.properties['sub-font-size'], '48');
      expect(platformPlayer.properties.containsKey('vo'), isFalse);
      expect(platformPlayer.properties.containsKey('gpu-context'), isFalse);
      openedWithSettings = true;
    };
    await engine.open(
      PlaybackResource(uri: Uri.file('C:/movie.mkv'), displayName: 'movie'),
    );
    expect(openedWithSettings, isTrue);

    final playerConfiguration = mediaKitPlayerConfiguration(settings);
    expect(playerConfiguration.libass, isTrue);
    expect(playerConfiguration.libassAndroidFont, subtitleFontAsset);
    expect(playerConfiguration.pitch, isFalse);
    final videoConfiguration = mediaKitVideoConfiguration(settings);
    expect(videoConfiguration.hwdec, 'no');
    expect(videoConfiguration.enableHardwareAcceleration, isTrue);
  });

  test('引擎允许放大音量且遵循本次会话的音量上限', () async {
    final platformPlayer = TestPlatformPlayer();
    final engine = MediaKitPlayerEngine(
      player: Player(platformPlayer: platformPlayer),
      settings: const PlayerSettings(maxVolume: 150),
    );
    addTearDown(engine.dispose);
    await engine.setVolume(130);
    expect(platformPlayer.lastVolume, 130);
    await engine.setVolume(200);
    expect(platformPlayer.lastVolume, 150);
    await engine.setVolume(-10);
    expect(platformPlayer.lastVolume, 0);
  });
}
