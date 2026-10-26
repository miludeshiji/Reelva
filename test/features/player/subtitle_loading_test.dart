import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:reelva/features/player/domain/playback_resource.dart';
import 'package:reelva/features/player/domain/playback_snapshot.dart';
import 'package:reelva/features/player/domain/player_settings.dart';
import 'package:reelva/features/player/domain/subtitle_files.dart';
import 'package:reelva/features/player/infrastructure/media_kit_player_engine.dart';

import 'engine_lifecycle_test.dart' show FakeAndroidMediaDocuments;
import 'test_platform_player.dart';

class _NativeSubtitles extends Fake implements NativePlayer {
  final delegate = TestPlatformPlayer();
  final commands = <List<String>>[];
  final properties = <String, String>{};
  final _tracks = <Map<String, dynamic>>[];
  void Function()? onAdd;

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
  Future<String> getProperty(
    String property, {
    bool waitForInitialization = true,
  }) async => jsonEncode(_tracks);
  @override
  Future<void> command(
    List<String> command, {
    bool waitForInitialization = true,
  }) async {
    commands.add(command);
    if (command[0] != 'sub-add') return;
    onAdd?.call();
    if (command[3].contains('bad')) {
      const message = 'Can not open external file';
      delegate.logController.add(
        const PlayerLog(prefix: 'cplayer', level: 'error', text: message),
      );
      delegate.emitError(message);
      return;
    }
    final id = _tracks.length + 1;
    _tracks.add({'type': 'sub', 'id': id});
    delegate.emitTracks(
      Tracks(
        subtitle: [
          SubtitleTrack.auto(),
          SubtitleTrack.no(),
          ..._tracks.map(
            (track) => SubtitleTrack(track['id'].toString(), null, null),
          ),
        ],
      ),
    );
    if (command[2] == 'select') {
      delegate.emitTrack(
        Track(subtitle: SubtitleTrack('$id', command[3], command[4])),
      );
    }
  }

  @override
  Future<void> setSubtitleTrack(
    SubtitleTrack track, {
    bool synchronized = true,
  }) => delegate.setSubtitleTrack(track);
  @override
  Future<void> open(
    Playable playable, {
    bool play = true,
    bool synchronized = true,
  }) => delegate.open(playable, play: play);
  @override
  Future<void> play({bool synchronized = true}) => delegate.play();
  @override
  Future<void> pause({bool synchronized = true}) => delegate.pause();
  @override
  Future<void> stop({
    bool open = false,
    bool notify = true,
    bool synchronized = true,
  }) async {
    _tracks.clear();
    await delegate.stop();
  }

  @override
  Future<void> dispose({bool synchronized = true}) => delegate.dispose();
}

PlaybackResource _file(String name) =>
    PlaybackResource(uri: Uri.file('C:/media/$name'), displayName: name);
PlaybackResource _sourceVideo() => PlaybackResource(
  uri: Uri.parse('https://source.test/movie'),
  displayName: 'movie.mkv',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('字幕匹配保留精确和模糊规则，防止相近集号误挂', () {
    expect(
      matchesSubtitle('Episode01.MKV', 'episode01.ASS', TrackAutoLoad.exact),
      isTrue,
    );
    expect(
      matchesSubtitle('Episode01.mkv', 'Episode01.zh.srt', TrackAutoLoad.exact),
      isFalse,
    );
    expect(
      matchesSubtitle(
        'Episode01.mkv',
        'Episode01.zh-Hans.srt',
        TrackAutoLoad.fuzzy,
      ),
      isTrue,
    );
    expect(
      matchesSubtitle(
        'Episode01.mkv',
        'Episode010.zh.srt',
        TrackAutoLoad.fuzzy,
      ),
      isFalse,
    );
    expect(
      matchesSubtitle('Episode01.mkv', 'Episode01.ass', TrackAutoLoad.disabled),
      isFalse,
    );
    expect(
      matchesSubtitle('movie.mkv', 'movie.idx', TrackAutoLoad.fuzzy),
      isFalse,
    );
  });

  test('字幕枚举不阻塞起播，按语言优先级选择并加载多个匹配文件', () async {
    final native = _NativeSubtitles();
    final engine = MediaKitPlayerEngine(player: Player(platformPlayer: native));
    addTearDown(engine.dispose);
    final discover = Completer<List<PlaybackResource>>();
    await engine.open(
      _sourceVideo().copyWith(discoverSubtitles: () => discover.future),
    );
    expect(engine.snapshot.status, PlaybackStatus.playing);
    expect(native.properties['sub-auto'], 'no');
    discover.complete([
      _file('movie.en.srt'),
      _file('other.ass'),
      _file('movie.zh.ass'),
    ]);
    await pumpEventQueue();
    expect(native.commands.map((command) => command[3]), [
      'movie.zh.ass',
      'movie.en.srt',
    ]);
    expect(native.commands.map((command) => command[2]), ['select', 'auto']);
    expect(native.commands.map((command) => command[4]), ['zh', 'en']);
    expect(
      engine.snapshot.subtitleTracks.where(
        (track) => track.id != 'auto' && track.id != 'no',
      ),
      hasLength(2),
    );
  });

  test('本地目录保留 libmpv 原有自动字幕发现，避免重复加载', () async {
    final native = _NativeSubtitles();
    final engine = MediaKitPlayerEngine(player: Player(platformPlayer: native));
    addTearDown(engine.dispose);
    var enumerated = false;
    await engine.open(
      _file('movie.mkv').copyWith(
        discoverSubtitles: () async {
          enumerated = true;
          return [_file('movie.ass')];
        },
      ),
    );
    await pumpEventQueue();
    expect(enumerated, isFalse);
    expect(native.commands, isEmpty);
    expect(native.properties['sub-auto'], 'fuzzy');
  });

  test('字幕加载期间的视频解码错误仍作为播放异常处理', () async {
    final native = _NativeSubtitles();
    final engine = MediaKitPlayerEngine(player: Player(platformPlayer: native));
    addTearDown(engine.dispose);
    await engine.open(_file('movie.mkv'));
    native.onAdd = () {
      native.delegate.emitLog(
        const PlayerLog(prefix: 'vd', level: 'error', text: 'decoder failed'),
      );
      native.delegate.emitError('decoder failed');
    };
    await engine.loadSubtitle(_file('movie.ass'));
    expect(engine.snapshot.status, PlaybackStatus.error);
  });

  test('关闭自动加载不枚举源目录，精确模式只加载同名字幕', () async {
    for (final mode in [TrackAutoLoad.disabled, TrackAutoLoad.exact]) {
      final native = _NativeSubtitles();
      final engine = MediaKitPlayerEngine(
        player: Player(platformPlayer: native),
        settings: PlayerSettings(subtitleAutoLoad: mode),
      );
      var enumerated = false;
      await engine.open(
        _sourceVideo().copyWith(
          discoverSubtitles: () async {
            enumerated = true;
            return [_file('movie.ass'), _file('movie.zh.srt')];
          },
        ),
      );
      await pumpEventQueue();
      expect(enumerated, mode != TrackAutoLoad.disabled);
      expect(native.commands.length, mode == TrackAutoLoad.disabled ? 0 : 1);
      await engine.dispose();
    }
  });

  test('自动发现完成前用户关闭字幕，后到的字幕保留为可选轨道', () async {
    final native = _NativeSubtitles();
    final engine = MediaKitPlayerEngine(player: Player(platformPlayer: native));
    addTearDown(engine.dispose);
    final discover = Completer<List<PlaybackResource>>();
    await engine.open(
      _sourceVideo().copyWith(discoverSubtitles: () => discover.future),
    );
    await engine.setSubtitleTrack('no');
    discover.complete([_file('movie.zh.srt')]);
    await pumpEventQueue();
    expect(native.commands.single[2], 'auto');
    expect(native.delegate.lastSubtitleTrack?.id, 'no');
  });

  test('切换视频后丢弃旧视频的字幕目录结果', () async {
    final native = _NativeSubtitles();
    final engine = MediaKitPlayerEngine(player: Player(platformPlayer: native));
    addTearDown(engine.dispose);
    final discover = Completer<List<PlaybackResource>>();
    await engine.open(
      _sourceVideo().copyWith(discoverSubtitles: () => discover.future),
    );
    await engine.open(_file('next.mkv'));
    discover.complete([_file('movie.ass')]);
    await pumpEventQueue();
    expect(native.commands, isEmpty);
  });

  test('字幕读取失败不打断视频，后续自动字幕继续加载', () async {
    final native = _NativeSubtitles();
    final engine = MediaKitPlayerEngine(player: Player(platformPlayer: native));
    addTearDown(engine.dispose);
    await engine.open(
      _sourceVideo().copyWith(
        discoverSubtitles: () async => [
          _file('movie.bad.zh.ass'),
          _file('movie.en.srt'),
        ],
      ),
    );
    await pumpEventQueue();
    expect(engine.snapshot.status, PlaybackStatus.playing);
    expect(native.commands.map((command) => command[2]), ['select', 'select']);
    await expectLater(
      engine.loadSubtitle(_file('bad.ass')),
      throwsA(isA<PlaybackResourceException>()),
    );
    expect(engine.snapshot.status, PlaybackStatus.playing);
  });

  for (final finish in ['stop', 'switch', 'dispose']) {
    test('外挂字幕的 SAF 句柄和远程租约在 $finish 后释放', () async {
      final platform = TestPlatformPlayer();
      final documents = FakeAndroidMediaDocuments();
      final engine = MediaKitPlayerEngine(
        player: Player(platformPlayer: platform),
        documents: documents,
      );
      var releases = 0;
      await engine.open(_file('movie.mkv'));
      await engine.loadSubtitle(
        PlaybackResource(
          uri: Uri.parse('content://provider/subtitle'),
          displayName: '字幕.ass',
          release: () async {
            releases++;
          },
        ),
      );
      expect(platform.lastSubtitleTrack?.id, 'fd://100');
      expect(documents.closedFds, isEmpty);
      switch (finish) {
        case 'stop':
          await engine.stop();
        case 'switch':
          await engine.open(_file('next.mkv'));
        case 'dispose':
          await engine.dispose();
      }
      expect(documents.closedFds, [100]);
      expect(releases, 1);
      await engine.dispose();
      expect(releases, 1);
    });
  }

  test('字幕连接准备期间仍能暂停，停止后释放迟到的租约', () async {
    final platform = TestPlatformPlayer();
    final engine = MediaKitPlayerEngine(
      player: Player(platformPlayer: platform),
    );
    addTearDown(engine.dispose);
    final lease = Completer<PlaybackResource>();
    var releases = 0;
    await engine.open(_file('movie.mkv'));
    final loading = engine.loadSubtitle(
      _file('movie.ass').copyWith(prepare: () => lease.future),
    );
    await engine.pause();
    expect(engine.snapshot.status, PlaybackStatus.paused);
    await engine.stop();
    lease.complete(
      _file('movie.ass').copyWith(
        release: () async {
          releases++;
        },
      ),
    );
    await loading;
    expect(platform.lastSubtitleTrack, isNull);
    expect(releases, 1);
  });

  test('重复选择已加载的字幕复用轨道，租约只在停止时释放', () async {
    final native = _NativeSubtitles();
    final engine = MediaKitPlayerEngine(player: Player(platformPlayer: native));
    addTearDown(engine.dispose);
    var releases = 0;
    final subtitle = _file('movie.ass').copyWith(
      release: () async {
        releases++;
      },
    );
    await engine.open(_file('movie.mkv'));
    await engine.loadSubtitle(subtitle);
    await engine.loadSubtitle(subtitle);
    expect(native.commands, hasLength(1));
    expect(native.delegate.lastSubtitleTrack?.id, '1');
    expect(releases, 0);
    await engine.stop();
    expect(releases, 1);
  });

  test('手动字幕准备或底层添加失败时释放资源且保留视频状态', () async {
    final platform = TestPlatformPlayer();
    final documents = FakeAndroidMediaDocuments();
    final engine = MediaKitPlayerEngine(
      player: Player(platformPlayer: platform),
      documents: documents,
    );
    addTearDown(engine.dispose);
    await engine.open(_file('movie.mkv'));
    await expectLater(
      engine.loadSubtitle(
        _file('movie.ass')
            .copyWith(prepare: () async => throw StateError('offline')),
      ),
      throwsA(isA<PlaybackResourceException>()),
    );
    platform.onSetSubtitleTrack = (_) async => throw StateError('bad subtitle');
    var releases = 0;
    await expectLater(
      engine.loadSubtitle(
        PlaybackResource(
          uri: Uri.parse('content://provider/subtitle'),
          displayName: 'movie.ass',
          release: () async {
            releases++;
          },
        ),
      ),
      throwsA(isA<PlaybackResourceException>()),
    );
    expect(documents.closedFds, [100]);
    expect(releases, 1);
    expect(engine.snapshot.status, PlaybackStatus.playing);
  });
}
