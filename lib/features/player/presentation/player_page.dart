import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:window_manager/window_manager.dart';

import '../../../app/theme/reelva_theme.dart';
import '../../../app/desktop_window_controller.dart';
import '../../../core/logging/app_logger.dart';
import '../../../shared/widgets/glass_widgets.dart';
import '../../sources/application/source_providers.dart';
import '../application/playback_session.dart';
import '../application/player_providers.dart';
import '../application/player_settings_provider.dart';
import '../domain/playback_resource.dart';
import '../domain/playback_playlist_entry.dart';
import '../domain/playback_snapshot.dart';
import '../domain/player_engine.dart';
import '../domain/player_shortcuts.dart';
import '../infrastructure/media_file_picker.dart';
import '../infrastructure/android_screen_brightness.dart';
import '../infrastructure/android_screenshot_store.dart';
import '../infrastructure/windows_player_input.dart';
import 'network_address_dialog.dart';
import 'player_controls.dart';
import 'player_selection_panel.dart';
import 'player_statistics_overlay.dart';
import 'source_subtitle_dialog.dart';

enum _SpeedHoldSource { screen, keyboard }

enum _ScreenAdjustment { brightness, volume }

/// Reelva 核心播放页面
///
/// 独立于主导航索引外壳，拥有受控的独立播放生命周期。
/// 退出时立即捕获进度并启动引擎释放，路由返回不等待原生资源释放；进入后台时自动暂停；
/// 全屏时复用同一直属视频渲染曲面；原生全屏操作成功后才更新 UI 状态，失败弹窗安全提示且不锁死；
/// 返回操作受 PopScope 严格接管，全屏时优先退出全屏，非全屏退出路由（支持返回首页回退）。
class PlayerPage extends ConsumerStatefulWidget {
  const PlayerPage({super.key, this.initialResource});

  final PlaybackResource? initialResource;

  @override
  ConsumerState<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends ConsumerState<PlayerPage>
    with WidgetsBindingObserver, WindowListener {
  PlaybackSession? _session;
  bool _isFullscreen = false;
  bool _isTogglingFullscreen = false;
  bool _isExiting = false;
  bool _canPopAfterExit = false;
  PlaybackResource? _currentResource;
  bool _isOpeningInitialResource = false;
  int _actionCounter = 0;
  final FocusNode _focusNode = FocusNode();
  late final PlayerInputSettings _input;
  double _lastNonZeroVolume = 100;
  bool _isWindowClosing = false;
  final GlobalKey _controlsKey = GlobalKey();
  final GlobalKey _playlistAnchorKey = GlobalKey();
  Timer? _controlsHideTimer;
  PlaybackStatus? _controlsStatus;
  bool _usesOverlayControls = false;
  bool _controlsVisible = true;
  bool _screenLocked = false;
  bool _capturingScreenshot = false;
  bool _pointerOverControls = false;
  bool _controlsHaveFocus = false;
  int _controlsInteractions = 0;
  bool _hasProgressError = false;
  Orientation? _videoOrientation;
  Future<void> _orientationUpdate = Future<void>.value();
  final _speedHolds = <_SpeedHoldSource>{};
  double? _rateBeforeHold;
  Timer? _rightHoldTimer;
  bool _rightKeyPressed = false;
  bool _statisticsVisible = false;
  PlayerShortcutAction? _rightTapAction;
  bool _switchingEpisode = false;
  Size? _windowVideoSize;
  Future<void> _windowSizeUpdate = Future<void>.value();
  Future<void> _windowPreparation = Future<void>.value();
  Future<void>? _windowRestore;
  DesktopWindowController? _desktopWindow;
  final _screenBrightness = const AndroidScreenBrightness();
  bool _brightnessAdjusted = false;
  _ScreenAdjustment? _verticalGesture;
  double? _gestureInitialValue;
  double _gestureDelta = 0;
  int _gestureId = 0;
  ({_ScreenAdjustment type, double value})? _gestureFeedback;
  Timer? _gestureFeedbackTimer;
  final _windowsInput = const WindowsPlayerInput();
  bool? _imeEnabled;

  bool get _editingText {
    final focusContext = FocusManager.instance.primaryFocus?.context;
    return focusContext != null &&
        (focusContext.widget is EditableText ||
            focusContext.findAncestorWidgetOfExactType<EditableText>() != null);
  }

  void _syncWindowsIme() {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.windows) return;
    final enabled = _isExiting || !_focusNode.hasFocus || _editingText;
    if (_imeEnabled == enabled) return;
    _imeEnabled = enabled;
    unawaited(
      _windowsInput.setImeEnabled(enabled).catchError((
        Object error,
        StackTrace stack,
      ) {
        AppLogger.instance.error(
          '切换播放器输入法状态失败',
          error: error,
          stackTrace: stack,
        );
      }),
    );
  }

  bool get _isMobile =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  bool get _canCaptureScreenshot =>
      _isMobile &&
      !_isExiting &&
      !_capturingScreenshot &&
      _canOperateMedia &&
      (_session?.engine.snapshot.videoWidth ?? 0) > 0 &&
      (_session?.engine.snapshot.videoHeight ?? 0) > 0;

  void _toggleScreenLock() {
    if (!_isMobile || _isExiting) return;
    _cancelSpeedHold();
    _gestureId++;
    _endScreenAdjustment(cancel: true);
    _focusNode.requestFocus();
    setState(() {
      _screenLocked = !_screenLocked;
      _statisticsVisible = false;
      _controlsVisible = true;
    });
    _scheduleControlsHide();
  }

  Future<void> _captureScreenshot() async {
    final session = _session;
    if (session == null || !_canCaptureScreenshot) return;
    final snapshot = session.engine.snapshot;
    final title = String.fromCharCodes(
      (_currentResource?.displayName ?? '视频')
          .replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1F]'), '_')
          .trim()
          .runes
          .take(48),
    );
    final position = formatDuration(snapshot.position).replaceAll(':', '-');
    final name =
        '${title.isEmpty ? '视频' : title}_${position}_${DateTime.now().millisecondsSinceEpoch}.png';
    setState(() => _capturingScreenshot = true);
    _showControls();
    try {
      final image = await session.engine.captureFrame();
      if (image == null || image.isEmpty) {
        throw StateError('当前视频没有可截图的画面');
      }
      await const AndroidScreenshotStore().save(image, name: name);
      if (mounted && !_isExiting) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('截图已保存到相册 · Reelva')));
      }
    } catch (error, stack) {
      AppLogger.instance.error('保存视频截图失败', error: error, stackTrace: stack);
      if (mounted && !_isExiting) {
        final denied =
            error is PlatformException && error.code == 'PERMISSION_DENIED';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(denied ? '未获得存储权限，无法保存截图' : '截图失败，请重试')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _capturingScreenshot = false);
        _scheduleControlsHide();
      }
    }
  }

  Future<void> _startScreenAdjustment(
    DragStartDetails details,
    double width,
  ) async {
    if (_screenLocked || !_canOperateMedia || _speedHolds.isNotEmpty) return;
    final type = details.localPosition.dx < width / 2
        ? _ScreenAdjustment.brightness
        : _ScreenAdjustment.volume;
    final id = ++_gestureId;
    _gestureFeedbackTimer?.cancel();
    _verticalGesture = type;
    _gestureDelta = 0;
    _gestureInitialValue = null;
    _controlsInteractions++;
    _showControls();
    try {
      final value = type == _ScreenAdjustment.brightness
          ? await _screenBrightness.read()
          : _session!.engine.snapshot.volume;
      if (!mounted ||
          _isExiting ||
          _gestureId != id ||
          _verticalGesture != type) {
        return;
      }
      _gestureInitialValue = value;
      _applyScreenAdjustment();
    } catch (error, stack) {
      _screenAdjustmentFailed(id, type, error, stack);
    }
  }

  void _updateScreenAdjustment(DragUpdateDetails details, double height) {
    if (_verticalGesture == null) return;
    _gestureDelta -= details.delta.dy / (height * 0.65);
    _applyScreenAdjustment();
  }

  void _applyScreenAdjustment() {
    final type = _verticalGesture;
    final initial = _gestureInitialValue;
    if (type == null || initial == null) return;
    final max = type == _ScreenAdjustment.brightness
        ? 1.0
        : _session!.maxVolume;
    final value = (initial + _gestureDelta * max).clamp(0.0, max);
    final id = _gestureId;
    setState(() => _gestureFeedback = (type: type, value: value));
    final Future<void> operation;
    if (type == _ScreenAdjustment.brightness) {
      _brightnessAdjusted = true;
      operation = _screenBrightness.set(value);
    } else {
      operation = _session!.engine.setVolume(value);
    }
    unawaited(
      operation.catchError((Object error, StackTrace stack) {
        _screenAdjustmentFailed(id, type, error, stack);
      }),
    );
  }

  void _endScreenAdjustment({bool cancel = false}) {
    if (_verticalGesture != null) {
      _verticalGesture = null;
      _controlsInteractions--;
    }
    _gestureInitialValue = null;
    _gestureFeedbackTimer?.cancel();
    if (cancel) {
      if (mounted && !_isExiting) {
        setState(() => _gestureFeedback = null);
      } else {
        _gestureFeedback = null;
      }
    } else if (_gestureFeedback != null) {
      _gestureFeedbackTimer = Timer(const Duration(milliseconds: 800), () {
        if (mounted) setState(() => _gestureFeedback = null);
      });
    }
    _scheduleControlsHide();
  }

  void _screenAdjustmentFailed(
    int id,
    _ScreenAdjustment type,
    Object error,
    StackTrace stack,
  ) {
    if (_gestureId != id) return;
    _gestureId++;
    final label = type == _ScreenAdjustment.brightness ? '亮度' : '音量';
    AppLogger.instance.error('滑动调节$label失败', error: error, stackTrace: stack);
    _endScreenAdjustment(cancel: true);
    if (mounted && !_isExiting) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('无法调节$label，请重试')));
    }
  }

  Future<void> _restoreScreenBrightness() async {
    if (!_brightnessAdjusted) return;
    _brightnessAdjusted = false;
    try {
      await _screenBrightness.reset();
    } catch (error, stack) {
      AppLogger.instance.error('还原播放器屏幕亮度失败', error: error, stackTrace: stack);
    }
  }

  void _syncWindowVideoSize(PlaybackSnapshot snapshot) {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.windows) return;
    if (snapshot.status == PlaybackStatus.idle) {
      _windowVideoSize = null;
      return;
    }
    if (_isFullscreen ||
        _isTogglingFullscreen ||
        snapshot.videoWidth <= 0 ||
        snapshot.videoHeight <= 0) {
      return;
    }
    final size = Size(
      snapshot.videoWidth.toDouble(),
      snapshot.videoHeight.toDouble(),
    );
    if (_windowVideoSize == size) return;
    _windowVideoSize = size;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _windowSizeUpdate = _windowSizeUpdate
          .then((_) async {
            await _windowPreparation;
            if (!mounted ||
                _isExiting ||
                _isFullscreen ||
                _windowVideoSize != size) {
              return;
            }
            if (await windowManager.isFullScreen()) return;
            if (await windowManager.isMaximized()) {
              await windowManager.unmaximize();
              await WidgetsBinding.instance.endOfFrame;
            }
            if (!mounted ||
                _isExiting ||
                _isFullscreen ||
                _windowVideoSize != size) {
              return;
            }
            final bounds = await windowManager.getBounds();
            if (!mounted ||
                _isExiting ||
                _isFullscreen ||
                _windowVideoSize != size) {
              return;
            }
            final view = View.of(context);
            final clientSize = view.physicalSize / view.devicePixelRatio;
            // window_manager 使用外框尺寸，Flutter View 是视频所在的客户区。
            final frameWidth = (bounds.width - clientSize.width).clamp(
              0.0,
              double.infinity,
            );
            final frameHeight = (bounds.height - clientSize.height).clamp(
              0.0,
              double.infinity,
            );
            final fitted = applyBoxFit(
              BoxFit.contain,
              size,
              clientSize,
            ).destination;
            await windowManager.setBounds(
              Rect.fromCenter(
                center: bounds.center,
                width: fitted.width + frameWidth,
                height: fitted.height + frameHeight,
              ),
            );
          })
          .catchError((Object error, StackTrace stack) {
            AppLogger.instance.error(
              '按视频比例调整窗口失败',
              error: error,
              stackTrace: stack,
            );
          });
    });
  }

  int get _playlistIndex =>
      _currentResource?.playlist.indexWhere(
        (entry) => entry.fileId == _currentResource?.libraryFileId,
      ) ??
      -1;

  Future<void> _playEpisode(int index) async {
    if (_switchingEpisode || _isExiting) return;
    final playlist = _currentResource?.playlist;
    if (playlist == null ||
        index < 0 ||
        index >= playlist.length ||
        index == _playlistIndex ||
        !playlist[index].available) {
      return;
    }
    final actionId = ++_actionCounter;
    setState(() => _switchingEpisode = true);
    try {
      final resource = await ref
          .read(sourceControllerProvider.notifier)
          .resolvePlayback(playlist[index].fileId);
      if (!mounted || _isExiting || actionId != _actionCounter) return;
      _cancelSpeedHold();
      final next = resource.copyWith(playlist: playlist);
      setState(() {
        _currentResource = next;
        _statisticsVisible = false;
        _windowVideoSize = null;
      });
      await _session!.engine.open(next);
    } catch (error, stack) {
      if (!mounted || _isExiting || actionId != _actionCounter) return;
      AppLogger.instance.error('切换剧集失败', error: error, stackTrace: stack);
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('无法播放该集，请检查媒体源后重试')));
    } finally {
      if (mounted) {
        setState(() => _switchingEpisode = false);
        _showControls();
      }
    }
  }

  Future<void> _showPlaylist() async {
    final resource = _currentResource;
    if (resource == null) return;
    final entries = resource.playlist;
    final current = _playlistIndex;
    final rowHeight = 72 * MediaQuery.textScalerOf(context).scale(1);
    final scroll = ScrollController(
      initialScrollOffset: current < 0 ? 0 : current * rowHeight,
    );
    _controlsInteractions++;
    _showControls();
    try {
      final selected = await showDialog<int>(
        context: _playlistAnchorKey.currentContext!,
        useSafeArea: false,
        builder: (context) => PlayerSelectionPanel(
          anchorKey: _playlistAnchorKey,
          panelKey: const Key('player_playlist_panel'),
          title: '播放列表',
          child: entries.isEmpty
              ? ListTile(
                  leading: const Icon(Icons.graphic_eq_rounded),
                  title: Text(resource.displayName),
                  subtitle: const Text('正在播放'),
                  selected: true,
                )
              : ListView.builder(
                  shrinkWrap: true,
                  key: const Key('player_playlist'),
                  controller: scroll,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  itemExtent: rowHeight,
                  itemCount: entries.length,
                  itemBuilder: (context, index) {
                    final entry = entries[index];
                    return ListTile(
                      key: ValueKey('player_playlist_entry_${entry.fileId}'),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(
                          ReelvaDesign.radiusSmall,
                        ),
                      ),
                      selected: index == current,
                      enabled: entry.available && !_switchingEpisode,
                      leading: Icon(
                        index == current
                            ? Icons.graphic_eq_rounded
                            : Icons.play_arrow_rounded,
                      ),
                      title: Text(
                        entry.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        entry.available
                            ? entry.episodeLabel ?? '当前视频'
                            : '${entry.episodeLabel ?? ''} · 暂不可播放',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      onTap: () => Navigator.pop(context, index),
                    );
                  },
                ),
        ),
      );
      if (mounted &&
          !_isExiting &&
          _currentResource == resource &&
          selected != null) {
        await _playEpisode(selected);
      }
    } finally {
      scroll.dispose();
      if (mounted) {
        _controlsInteractions--;
        _showControls();
        _focusNode.requestFocus();
      }
    }
  }

  void _setSpeedHold(_SpeedHoldSource source, bool held) {
    final engine = _session?.engine;
    if (engine == null) return;
    final double? rate;
    if (held) {
      if (!mounted ||
          _isExiting ||
          _screenLocked ||
          !_canOperateMedia ||
          !_speedHolds.add(source)) {
        return;
      }
      if (_speedHolds.length > 1) return;
      _rateBeforeHold = engine.snapshot.rate;
      rate = 3;
    } else {
      if (!_speedHolds.remove(source) || _speedHolds.isNotEmpty) return;
      rate = _rateBeforeHold;
      _rateBeforeHold = null;
    }
    if (rate == null) return;
    if (mounted && !_isExiting) setState(() {});
    unawaited(
      engine.setRate(rate).catchError((Object error, StackTrace stack) {
        AppLogger.instance.error('切换长按倍速失败', error: error, stackTrace: stack);
      }),
    );
  }

  void _cancelSpeedHold() {
    _rightHoldTimer?.cancel();
    _rightHoldTimer = null;
    _rightKeyPressed = false;
    _rightTapAction = null;
    for (final source in _SpeedHoldSource.values) {
      _setSpeedHold(source, false);
    }
  }

  Future<void> _setVideoOrientation(Orientation? orientation) {
    if (kIsWeb ||
        defaultTargetPlatform != TargetPlatform.android ||
        _videoOrientation == orientation) {
      return _orientationUpdate;
    }
    _videoOrientation = orientation;
    _orientationUpdate = _orientationUpdate
        .then((_) async {
          if (orientation != null &&
              (!mounted || _isExiting || _videoOrientation != orientation)) {
            return;
          }
          await SystemChrome.setPreferredOrientations(switch (orientation) {
            Orientation.landscape => [
              DeviceOrientation.landscapeLeft,
              DeviceOrientation.landscapeRight,
            ],
            Orientation.portrait => [DeviceOrientation.portraitUp],
            null => [],
          });
          await SystemChrome.setEnabledSystemUIMode(
            orientation == null
                ? SystemUiMode.edgeToEdge
                : SystemUiMode.immersiveSticky,
          );
        })
        .catchError((Object e, StackTrace st) {
          AppLogger.instance.error('设置视频屏幕方向失败', error: e, stackTrace: st);
        });
    return _orientationUpdate;
  }

  void _syncVideoOrientation(PlaybackSnapshot snapshot) {
    if (_isExiting) return;
    if (snapshot.status == PlaybackStatus.idle) {
      unawaited(_setVideoOrientation(null));
    } else if (snapshot.videoWidth > 0 && snapshot.videoHeight > 0) {
      unawaited(
        _setVideoOrientation(
          snapshot.videoWidth > snapshot.videoHeight
              ? Orientation.landscape
              : Orientation.portrait,
        ),
      );
    }
  }

  void _scheduleControlsHide() {
    _controlsHideTimer?.cancel();
    if (_isExiting ||
        !_usesOverlayControls ||
        (!_screenLocked &&
            (_controlsStatus != PlaybackStatus.playing ||
                _pointerOverControls ||
                _controlsHaveFocus ||
                _controlsInteractions > 0 ||
                _hasProgressError))) {
      return;
    }
    _controlsHideTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _controlsVisible = false);
    });
  }

  void _showControls() {
    if (!_controlsVisible) setState(() => _controlsVisible = true);
    _scheduleControlsHide();
  }

  void _hideControls() {
    _controlsHideTimer?.cancel();
    if (_controlsVisible) setState(() => _controlsVisible = false);
  }

  void _updateControlsVisibility(PlaybackSnapshot snapshot, bool overlay) {
    final hasProgressError = snapshot.progressErrorMessage?.isNotEmpty ?? false;
    if (_controlsStatus == snapshot.status &&
        _usesOverlayControls == overlay &&
        _hasProgressError == hasProgressError) {
      return;
    }
    _controlsStatus = snapshot.status;
    _usesOverlayControls = overlay;
    _hasProgressError = hasProgressError;
    if (snapshot.status == PlaybackStatus.idle) _screenLocked = false;
    if (!_screenLocked) _controlsVisible = true;
    _scheduleControlsHide();
  }

  Widget _buildControlsVisibility(
    Widget child, {
    bool allowWhenLocked = false,
  }) {
    final visible = _controlsVisible && (!_screenLocked || allowWhenLocked);
    return IgnorePointer(
      ignoring: !visible,
      child: ExcludeFocus(
        excluding: !visible,
        child: ExcludeSemantics(
          excluding: !visible,
          child: AnimatedOpacity(
            opacity: visible ? 1 : 0,
            duration: const Duration(milliseconds: 200),
            child: child,
          ),
        ),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _input = ref.read(playerSettingsProvider).input;
    WidgetsBinding.instance.addObserver(this);
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.windows) {
      _desktopWindow = ref.read(desktopWindowControllerProvider);
      _windowPreparation = _desktopWindow!.beginPlayback();
      FocusManager.instance.addListener(_syncWindowsIme);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _syncWindowsIme();
      });
      windowManager.addListener(this);
      windowManager.setPreventClose(true).catchError((Object e, StackTrace st) {
        AppLogger.instance.error(
          '设置 Windows 窗口阻止关闭失败',
          error: e,
          stackTrace: st,
        );
      });
    }
    if (widget.initialResource != null) {
      _currentResource = widget.initialResource;
      _isOpeningInitialResource = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _openInitialResource();
      });
    }
  }

  @override
  void onWindowClose() async {
    if (_isWindowClosing || _isExiting) return;
    _isWindowClosing = true;
    _isExiting = true;
    _actionCounter++;
    _cancelSpeedHold();

    bool isPreventClose = false;
    try {
      isPreventClose = await windowManager.isPreventClose();
    } catch (e, st) {
      AppLogger.instance.error('查询窗口阻止关闭状态异常', error: e, stackTrace: st);
    }
    if (isPreventClose) {
      final engine = _session?.engine;
      if (engine != null) {
        try {
          await engine.dispose();
        } catch (e, st) {
          AppLogger.instance.error('窗口关闭前释放播放引擎异常', error: e, stackTrace: st);
        }
      }
      try {
        await windowManager.destroy();
      } catch (e, st) {
        AppLogger.instance.error('销毁窗口异常', error: e, stackTrace: st);
      }
    }
  }

  @override
  void onWindowBlur() => _cancelSpeedHold();

  @override
  void didUpdateWidget(covariant PlayerPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialResource != oldWidget.initialResource) {
      _cancelSpeedHold();
      _endScreenAdjustment(cancel: true);
      _statisticsVisible = false;
      _currentResource = widget.initialResource;
      _isOpeningInitialResource = widget.initialResource != null;
      if (widget.initialResource != null) {
        _openInitialResource();
      } else {
        _session?.engine.stop().catchError((Object e, StackTrace st) {
          AppLogger.instance.error('停止播放引擎异常', error: e, stackTrace: st);
        });
      }
    }
  }

  Future<void> _openInitialResource() async {
    final resource = widget.initialResource;
    if (resource == null) return;
    final actionId = ++_actionCounter;
    try {
      if (!mounted || _isExiting || actionId != _actionCounter) return;
      await ref.read(playerSessionProvider).engine.open(resource);
    } catch (e, st) {
      if (!mounted || _isExiting || actionId != _actionCounter) return;
      AppLogger.instance.error('打开初始视频资源异常', error: e, stackTrace: st);
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('无法播放视频，请重试')));
    } finally {
      if (mounted && !_isExiting && widget.initialResource == resource) {
        setState(() {
          _isOpeningInitialResource = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _isExiting = true;
    _actionCounter++;
    _cancelSpeedHold();
    _endScreenAdjustment(cancel: true);
    unawaited(_restoreScreenBrightness());
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.windows) {
      if (!_isWindowClosing) unawaited(_restoreAppWindow());
      FocusManager.instance.removeListener(_syncWindowsIme);
      _syncWindowsIme();
      windowManager.removeListener(this);
      windowManager.setPreventClose(false).catchError((
        Object e,
        StackTrace st,
      ) {
        AppLogger.instance.error(
          '还原 Windows 窗口阻止关闭失败',
          error: e,
          stackTrace: st,
        );
      });
    }
    WidgetsBinding.instance.removeObserver(this);
    _controlsHideTimer?.cancel();
    unawaited(_setVideoOrientation(null));
    _focusNode.dispose();
    _session?.engine.stop().catchError((Object e, StackTrace st) {
      AppLogger.instance.error('卸载页面停止播放引擎异常', error: e, stackTrace: st);
    });
    if (_isFullscreen &&
        !kIsWeb &&
        defaultTargetPlatform == TargetPlatform.android) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge)
          .catchError((Object e, StackTrace st) {
            AppLogger.instance.error(
              '销毁还原 Android 沉浸模式异常',
              error: e,
              stackTrace: st,
            );
          });
    }
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden) {
      _cancelSpeedHold();
      _endScreenAdjustment(cancel: true);
      _session?.engine.pause().catchError((Object e, StackTrace st) {
        AppLogger.instance.error('进入后台自动暂停失败', error: e, stackTrace: st);
      });
    }
  }

  Future<void> _handleExit() async {
    if (_isExiting) return;
    _isExiting = true;
    _cancelSpeedHold();
    _endScreenAdjustment(cancel: true);
    _syncWindowsIme();

    // 先捕获进度并启动释放；路由退出不等待原生播放器和远程租约释放。
    final disposal = _session?.engine.dispose().catchError((
      Object error,
      StackTrace stack,
    ) {
      AppLogger.instance.error('退出页面释放播放引擎异常', error: error, stackTrace: stack);
    });

    if (_isFullscreen) {
      await _setFullscreen(false);
    }
    await _restoreAppWindow();

    if (!mounted) return;
    setState(() => _canPopAfterExit = true);
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;

    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/');
    }
    await _restoreScreenBrightness();
    await _setVideoOrientation(null);
    await disposal;
  }

  Future<void> _restoreAppWindow() =>
      _windowRestore ??= _windowSizeUpdate.then((_) async {
        await _windowPreparation;
        await _desktopWindow?.endPlayback();
      });

  Future<void> _setFullscreen(bool targetFullscreen) async {
    if (_isTogglingFullscreen || _isFullscreen == targetFullscreen) return;
    _isTogglingFullscreen = true;

    var nativeSuccess = true;
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.windows) {
      try {
        await _windowPreparation;
        await windowManager.setFullScreen(targetFullscreen);
      } catch (e, st) {
        nativeSuccess = false;
        AppLogger.instance.error('切换 Windows 全屏模式失败', error: e, stackTrace: st);
      }
    } else if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      try {
        if (targetFullscreen) {
          await SystemChrome.setEnabledSystemUIMode(
            SystemUiMode.immersiveSticky,
          );
        } else {
          await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
        }
      } catch (e, st) {
        nativeSuccess = false;
        AppLogger.instance.error(
          '切换 Android 沉浸式全屏失败',
          error: e,
          stackTrace: st,
        );
      }
    }

    if (nativeSuccess) {
      if (mounted) {
        setState(() {
          _isFullscreen = targetFullscreen;
          if (!targetFullscreen) _windowVideoSize = null;
        });
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('全屏模式切换失败')));
      }
    }
    _isTogglingFullscreen = false;
  }

  Future<void> _pickNativeVideo() async {
    final actionId = ++_actionCounter;
    try {
      final picker = ref.read(mediaFilePickerProvider);
      final resource = await picker.pick();

      // 防止异步操作返回时页面已卸载，正在退出，或被后续并发选择取代
      if (!mounted || _isExiting || actionId != _actionCounter) return;

      if (resource != null) {
        _cancelSpeedHold();
        setState(() {
          _statisticsVisible = false;
          _currentResource = resource;
        });
        await ref.read(playerSessionProvider).engine.open(resource);
      }
    } catch (e, st) {
      if (!mounted || _isExiting || actionId != _actionCounter) return;
      AppLogger.instance.error('选择本地视频异常', error: e, stackTrace: st);
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('选择媒体文件失败，请重试')));
    }
  }

  Future<void> _openNetworkVideo() async {
    final actionId = ++_actionCounter;
    try {
      final resource = await showDialog<PlaybackResource>(
        context: context,
        builder: (context) => const NetworkAddressDialog(),
      );

      if (!mounted || _isExiting || actionId != _actionCounter) return;

      if (resource != null) {
        _cancelSpeedHold();
        setState(() {
          _statisticsVisible = false;
          _currentResource = resource;
        });
        await ref.read(playerSessionProvider).engine.open(resource);
      }
    } catch (e, st) {
      if (!mounted || _isExiting || actionId != _actionCounter) return;
      AppLogger.instance.error('打开网络视频异常', error: e, stackTrace: st);
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('无法播放网络视频，请检查地址或格式')));
    }
  }

  bool _pickingSubtitle = false;

  Future<void> _pickSubtitle({required bool fromSource}) async {
    if (_pickingSubtitle || !_canOperateMedia) return;
    _pickingSubtitle = true;
    final video = _currentResource;
    final actionId = _actionCounter;
    _controlsInteractions++;
    _showControls();
    try {
      final subtitle = fromSource
          ? await showDialog<PlaybackResource>(
              context: context,
              builder: (context) =>
                  SourceSubtitleDialog(currentSourceId: video?.sourceId),
            )
          : await ref.read(mediaFilePickerProvider).pickSubtitle();
      if (!mounted ||
          _isExiting ||
          actionId != _actionCounter ||
          !identical(video, _currentResource) ||
          subtitle == null) {
        return;
      }
      await _session!.engine.loadSubtitle(subtitle);
    } catch (error, stackTrace) {
      AppLogger.instance.error(
        '选择或加载字幕失败',
        error: error,
        stackTrace: stackTrace,
      );
      if (mounted && !_isExiting && actionId == _actionCounter) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(switch (error) {
              PlaybackResourceException() => error.message,
              MediaPickerException() => error.message,
              _ => '无法加载字幕，请检查文件或访问权限',
            }),
          ),
        );
      }
    } finally {
      _pickingSubtitle = false;
      if (_controlsInteractions > 0) _controlsInteractions--;
      if (mounted && !_isExiting) _showControls();
    }
  }

  Widget _buildStatusOverlay(
    BuildContext context,
    PlaybackSnapshot snapshot,
    VoidCallback onRetry,
  ) {
    final theme = Theme.of(context);
    Widget? overlayContent;

    switch (snapshot.status) {
      case PlaybackStatus.idle:
        return const SizedBox.shrink();

      case PlaybackStatus.resolving:
      case PlaybackStatus.opening:
      case PlaybackStatus.buffering:
        overlayContent = GlassCard(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          color: const Color(0xC2263543),
          blur: true,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(color: Colors.white),
              const SizedBox(height: 12),
              Text(
                snapshot.status == PlaybackStatus.buffering
                    ? '正在缓冲...'
                    : '正在准备播放...',
                key: const Key('player_loading_text'),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: Colors.white,
                ),
              ),
            ],
          ),
        );
        break;

      case PlaybackStatus.completed:
        overlayContent = GlassCard(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          color: const Color(0xC2263543),
          blur: true,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton.filled(
                key: const Key('center_replay_button'),
                iconSize: 40,
                icon: const Icon(Icons.replay),
                tooltip: '重新播放',
                onPressed: onRetry,
              ),
              const SizedBox(height: 8),
              Text(
                '播放已完成',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: Colors.white,
                ),
              ),
            ],
          ),
        );
        break;

      case PlaybackStatus.error:
        overlayContent = GlassCard(
          margin: const EdgeInsets.all(24),
          padding: const EdgeInsets.all(20),
          color: const Color(0xE61B2634),
          blur: true,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.error_outline,
                size: 48,
                color: theme.colorScheme.error,
              ),
              const SizedBox(height: 12),
              Text(
                snapshot.errorMessage ?? '播放发生错误',
                key: const Key('player_error_text'),
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium?.copyWith(
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '建议检查网络连接、视频文件完整性或选择其他媒体重试',
                key: const Key('player_error_suggestion_text'),
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: Colors.white70,
                ),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 12,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: [
                  if (_currentResource != null)
                    FilledButton.icon(
                      key: const Key('player_retry_button'),
                      icon: const Icon(Icons.refresh),
                      label: const Text('重试'),
                      onPressed: onRetry,
                    ),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.folder_open),
                    label: const Text('选择其他视频'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                    ),
                    onPressed: _pickNativeVideo,
                  ),
                ],
              ),
            ],
          ),
        );
        break;

      case PlaybackStatus.playing:
      case PlaybackStatus.paused:
        return const SizedBox.shrink();
    }

    return Center(child: SingleChildScrollView(child: overlayContent));
  }

  bool _canHandleShortcuts(BuildContext context) {
    if (_screenLocked) return false;
    final route = ModalRoute.of(context);
    if (route != null && !route.isCurrent) {
      return false;
    }
    return !_editingText;
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event.logicalKey == LogicalKeyboardKey.arrowRight && _rightKeyPressed) {
      if (event is KeyUpEvent) {
        final action = _rightTapAction;
        _rightHoldTimer?.cancel();
        _rightHoldTimer = null;
        _rightKeyPressed = false;
        _rightTapAction = null;
        _setSpeedHold(_SpeedHoldSource.keyboard, false);
        if (action != null && _canHandleShortcuts(context)) {
          unawaited(_runShortcut(action));
        }
      }
      return KeyEventResult.handled;
    }
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }

    if (!_canHandleShortcuts(context)) {
      return KeyEventResult.ignored;
    }

    final binding = PlayerKeyBinding.fromEvent(event);
    final action = binding == null ? null : _input.actionFor(binding);
    if (event is KeyDownEvent &&
        binding == const PlayerKeyBinding(LogicalKeyboardKey.arrowRight) &&
        _input.keyboardEnabled &&
        _canOperateMedia) {
      _rightKeyPressed = true;
      _rightTapAction = action;
      _rightHoldTimer = Timer(kLongPressTimeout, () {
        _rightHoldTimer = null;
        _rightTapAction = null;
        if (mounted && _canHandleShortcuts(context)) {
          _setSpeedHold(_SpeedHoldSource.keyboard, true);
        }
      });
      return KeyEventResult.handled;
    }
    if (action == null) return KeyEventResult.ignored;
    if (event is KeyRepeatEvent && !action.repeatable) {
      return KeyEventResult.handled;
    }
    unawaited(_runShortcut(action));
    return KeyEventResult.handled;
  }

  bool get _canOperateMedia => switch (_session?.engine.snapshot.status) {
    PlaybackStatus.playing ||
    PlaybackStatus.paused ||
    PlaybackStatus.buffering ||
    PlaybackStatus.completed => true,
    _ => false,
  };

  Future<void> _seekBy(int seconds) async {
    final engine = _session!.engine;
    final snapshot = engine.snapshot;
    if (snapshot.duration <= Duration.zero) return;
    final target = (snapshot.position.inMilliseconds + seconds * 1000).clamp(
      0,
      snapshot.duration.inMilliseconds,
    );
    await engine.seek(Duration(milliseconds: target));
  }

  Future<void> _volumeBy(int step) => _session!.engine.setVolume(
    (_session!.engine.snapshot.volume + step).clamp(0.0, _session!.maxVolume),
  );

  Future<void> _runShortcut(PlayerShortcutAction action) async {
    if (!mounted || _isExiting || _screenLocked) return;
    _showControls();
    try {
      if (action == PlayerShortcutAction.toggleFullscreen) {
        await _setFullscreen(!_isFullscreen);
        return;
      }
      if (action == PlayerShortcutAction.exitFullscreen) {
        if (_isFullscreen) await _setFullscreen(false);
        return;
      }
      if (action == PlayerShortcutAction.toggleStatistics) {
        if (_statisticsVisible || _canOperateMedia) {
          setState(() => _statisticsVisible = !_statisticsVisible);
        }
        return;
      }
      if (!_canOperateMedia) return;
      final engine = _session!.engine;
      final snapshot = engine.snapshot;
      switch (action) {
        case PlayerShortcutAction.togglePause:
          if (snapshot.status == PlaybackStatus.completed) {
            await engine.seek(Duration.zero);
            await engine.play();
          } else if (snapshot.isPlaying) {
            await engine.pause();
          } else {
            await engine.play();
          }
        case PlayerShortcutAction.seekBack:
          await _seekBy(-_input.seekSeconds);
        case PlayerShortcutAction.seekForward:
          await _seekBy(_input.seekSeconds);
        case PlayerShortcutAction.seekBackLarge:
          await _seekBy(-_input.largeSeekSeconds);
        case PlayerShortcutAction.seekForwardLarge:
          await _seekBy(_input.largeSeekSeconds);
        case PlayerShortcutAction.volumeUp:
          await _volumeBy(_input.volumeStep);
        case PlayerShortcutAction.volumeDown:
          await _volumeBy(-_input.volumeStep);
        case PlayerShortcutAction.volumeUpLarge:
          await _volumeBy(_input.largeVolumeStep);
        case PlayerShortcutAction.volumeDownLarge:
          await _volumeBy(-_input.largeVolumeStep);
        case PlayerShortcutAction.toggleMute:
          if (snapshot.volume > 0) _lastNonZeroVolume = snapshot.volume;
          await engine.setVolume(
            snapshot.volume > 0
                ? 0
                : _lastNonZeroVolume.clamp(0.0, _session!.maxVolume),
          );
        case PlayerShortcutAction.resetRate:
        case PlayerShortcutAction.slower:
        case PlayerShortcutAction.faster:
        case PlayerShortcutAction.halveRate:
        case PlayerShortcutAction.doubleRate:
          final rate = switch (action) {
            PlayerShortcutAction.resetRate => 1.0,
            PlayerShortcutAction.slower => snapshot.rate - 0.1,
            PlayerShortcutAction.faster => snapshot.rate + 0.1,
            PlayerShortcutAction.halveRate => snapshot.rate * 0.5,
            _ => snapshot.rate * 2,
          };
          await engine.setRate(
            double.parse(rate.clamp(0.1, 16.0).toStringAsFixed(2)),
          );
        case PlayerShortcutAction.cycleAudio:
        case PlayerShortcutAction.cycleSubtitles:
          final audio = action == PlayerShortcutAction.cycleAudio;
          final tracks =
              (audio ? snapshot.audioTracks : snapshot.subtitleTracks)
                  .where((track) => track.id != 'auto')
                  .toList();
          if (tracks.isEmpty) return;
          final index = tracks.indexWhere(
            (track) =>
                track.id ==
                (audio ? snapshot.audioTrackId : snapshot.subtitleTrackId),
          );
          final next = tracks[(index + 1) % tracks.length].id;
          if (audio) {
            await engine.setAudioTrack(next);
          } else {
            await engine.setSubtitleTrack(next);
          }
        case PlayerShortcutAction.showProgress:
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '${formatDuration(snapshot.position)} / ${formatDuration(snapshot.duration)}',
              ),
            ),
          );
        case PlayerShortcutAction.showTracks:
          _controlsInteractions++;
          try {
            await showDialog<void>(
              context: context,
              builder: (context) => AlertDialog(
                title: const Text('音轨与字幕'),
                content: SingleChildScrollView(
                  child: Text(
                    [
                      '音轨',
                      ...snapshot.audioTracks.map(
                        (track) =>
                            '${track.id == snapshot.audioTrackId ? '✓ ' : ''}${track.label}',
                      ),
                      '',
                      '字幕',
                      ...snapshot.subtitleTracks.map(
                        (track) =>
                            '${track.id == snapshot.subtitleTrackId ? '✓ ' : ''}${track.label}',
                      ),
                    ].join('\n'),
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('关闭'),
                  ),
                ],
              ),
            );
          } finally {
            _controlsInteractions--;
            if (mounted) _scheduleControlsHide();
          }
        default:
          await engine.executeShortcut(action);
      }
    } catch (error, stack) {
      AppLogger.instance.error(
        '执行播放操作失败：${action.name}',
        error: error,
        stackTrace: stack,
      );
      if (mounted && !_isExiting) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('当前视频无法执行“${action.label}”')));
      }
    }
  }

  void _toggleSurfaceControls() {
    _focusNode.requestFocus();
    if (_controlsVisible) {
      _hideControls();
    } else {
      _showControls();
    }
  }

  void _handleScroll(PointerSignalEvent event) {
    if (_screenLocked || event is! PointerScrollEvent || !_canOperateMedia) {
      return;
    }
    final vertical = event.scrollDelta.dy.abs() >= event.scrollDelta.dx.abs();
    if ((vertical && !_input.wheelVolume) ||
        (!vertical && !_input.horizontalWheelSeek)) {
      return;
    }
    if (event.scrollDelta == Offset.zero) return;
    GestureBinding.instance.pointerSignalResolver.register(event, (_) {
      _showControls();
      final operation = vertical
          ? _volumeBy(
              event.scrollDelta.dy < 0
                  ? _input.wheelVolumeStep
                  : -_input.wheelVolumeStep,
            )
          : _seekBy(
              event.scrollDelta.dx < 0
                  ? _input.wheelSeekSeconds
                  : -_input.wheelSeekSeconds,
            );
      unawaited(
        operation.catchError((Object error, StackTrace stack) {
          AppLogger.instance.error('滚轮播放操作失败', error: error, stackTrace: stack);
        }),
      );
    });
  }

  Future<void> _showContextMenu(Offset position) async {
    if (_screenLocked || !_canOperateMedia) return;
    _focusNode.requestFocus();
    _showControls();
    _controlsInteractions++;
    try {
      final overlay =
          Overlay.of(context).context.findRenderObject()! as RenderBox;
      final selected = await showMenu<PlayerShortcutAction>(
        context: context,
        position: RelativeRect.fromRect(
          Rect.fromLTWH(position.dx, position.dy, 0, 0),
          Offset.zero & overlay.size,
        ),
        items: [
          for (final action in [
            PlayerShortcutAction.togglePause,
            PlayerShortcutAction.toggleFullscreen,
            PlayerShortcutAction.toggleMute,
            PlayerShortcutAction.cycleAudio,
            PlayerShortcutAction.cycleSubtitles,
            PlayerShortcutAction.showTracks,
            PlayerShortcutAction.loopFile,
          ])
            GlassPopupMenuItem(value: action, child: Text(action.label)),
        ],
      );
      if (selected != null && mounted) await _runShortcut(selected);
    } finally {
      _controlsInteractions--;
      if (mounted) _scheduleControlsHide();
    }
  }

  Widget _buildHeader(
    BuildContext context, {
    required String title,
    required bool fullscreen,
    bool overlay = false,
  }) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: ReelvaDesign.space16,
        vertical: overlay ? ReelvaDesign.space8 : ReelvaDesign.space20,
      ),
      child: Row(
        children: [
          IconButton(
            key: Key(
              fullscreen ? 'fullscreen_exit_back_button' : 'player_back_button',
            ),
            icon: const Icon(Icons.arrow_back_rounded),
            tooltip: fullscreen ? '退出全屏' : '返回',
            style: IconButton.styleFrom(
              minimumSize: const Size(40, 40),
              padding: const EdgeInsets.all(8),
              backgroundColor: overlay
                  ? Colors.transparent
                  : theme.colorScheme.surface,
              side: overlay
                  ? BorderSide.none
                  : BorderSide(color: theme.colorScheme.outlineVariant),
            ),
            onPressed: fullscreen ? () => _setFullscreen(false) : _handleExit,
          ),
          const SizedBox(width: ReelvaDesign.space12),
          Expanded(
            child: Text(
              title,
              key: const Key('player_title_text'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleMedium,
            ),
          ),
          if (overlay)
            PopupMenuButton<String>(
              key: const Key('player_options_menu_button'),
              icon: const Icon(Icons.more_vert_rounded),
              tooltip: '播放选项',
              onOpened: () {
                _controlsInteractions++;
                _showControls();
              },
              onCanceled: () {
                _controlsInteractions--;
                _scheduleControlsHide();
              },
              onSelected: (_) {
                _controlsInteractions--;
                setState(() => _statisticsVisible = true);
                _showControls();
                _focusNode.requestFocus();
              },
              itemBuilder: (_) => const [
                GlassPopupMenuItem<String>(
                  key: Key('player_video_info_button'),
                  value: 'statistics',
                  child: Text('视频信息'),
                ),
              ],
            )
          else ...[
            const SizedBox(width: ReelvaDesign.space8),
            IconButton(
              key: const Key('appbar_pick_file_button'),
              icon: const Icon(Icons.folder_open_rounded),
              tooltip: '选择本地视频',
              style: IconButton.styleFrom(
                minimumSize: const Size(40, 40),
                padding: const EdgeInsets.all(8),
              ),
              onPressed: _pickNativeVideo,
            ),
            IconButton(
              key: const Key('appbar_open_url_button'),
              icon: const Icon(Icons.link_rounded),
              tooltip: '输入网络链接',
              style: IconButton.styleFrom(
                minimumSize: const Size(40, 40),
                padding: const EdgeInsets.all(8),
              ),
              onPressed: _openNetworkVideo,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildEmptySurface(BuildContext context) {
    final theme = Theme.of(context);
    return GlassCard(
      key: const Key('player_empty_surface'),
      color: theme.colorScheme.surface.withValues(alpha: 0.7),
      borderRadius: BorderRadius.circular(ReelvaDesign.radiusLarge),
      padding: const EdgeInsets.all(ReelvaDesign.space24),
      child: Center(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              GlassCard(
                color: theme.colorScheme.primaryContainer,
                padding: const EdgeInsets.all(ReelvaDesign.space16),
                child: Icon(
                  Icons.video_library_outlined,
                  size: 32,
                  color: theme.colorScheme.primary,
                ),
              ),
              const SizedBox(height: ReelvaDesign.space20),
              Text(
                '让好故事开始播放',
                textAlign: TextAlign.center,
                style: theme.textTheme.titleLarge,
              ),
              const SizedBox(height: ReelvaDesign.space8),
              Text(
                '从本地选择影片，或粘贴视频链接。',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: ReelvaDesign.space24),
              Wrap(
                spacing: ReelvaDesign.space8,
                runSpacing: ReelvaDesign.space8,
                alignment: WrapAlignment.center,
                children: [
                  FilledButton.icon(
                    key: const Key('idle_open_file_button'),
                    icon: const Icon(Icons.folder_open_rounded),
                    label: const Text('选择本地视频'),
                    onPressed: _pickNativeVideo,
                  ),
                  OutlinedButton.icon(
                    key: const Key('idle_open_url_button'),
                    icon: const Icon(Icons.link_rounded),
                    label: const Text('网络链接'),
                    onPressed: _openNetworkVideo,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildControls(
    PlaybackSnapshot snapshot,
    PlayerEngine engine, {
    required bool overlay,
  }) {
    final entries =
        _currentResource?.playlist ?? const <PlaybackPlaylistEntry>[];
    final index = _playlistIndex;
    return MouseRegion(
      onEnter: (_) {
        _pointerOverControls = true;
        _showControls();
      },
      onExit: (_) {
        _pointerOverControls = false;
        _scheduleControlsHide();
      },
      child: Focus(
        onFocusChange: (focused) {
          _controlsHaveFocus = focused;
          if (focused) {
            _showControls();
          } else {
            _scheduleControlsHide();
          }
        },
        child: PlayerControls(
          key: _controlsKey,
          snapshot: snapshot,
          engine: engine,
          maxVolume: _session!.maxVolume,
          overlay: overlay,
          isFullscreen: _isFullscreen,
          onToggleFullscreen: () => _setFullscreen(!_isFullscreen),
          onPickLocalSubtitle: () => _pickSubtitle(fromSource: false),
          onPickSourceSubtitle: () => _pickSubtitle(fromSource: true),
          onPreviousEpisode:
              !_switchingEpisode && index > 0 && entries[index - 1].available
              ? () => _playEpisode(index - 1)
              : null,
          onNextEpisode:
              !_switchingEpisode &&
                  index >= 0 &&
                  index + 1 < entries.length &&
                  entries[index + 1].available
              ? () => _playEpisode(index + 1)
              : null,
          onShowPlaylist: _currentResource == null ? null : _showPlaylist,
          playlistAnchorKey: _playlistAnchorKey,
          onInteractionChanged: (interacting) {
            if (!mounted) return;
            if (interacting) {
              _controlsInteractions++;
            } else if (_controlsInteractions > 0) {
              _controlsInteractions--;
            }
            _showControls();
          },
        ),
      ),
    );
  }

  Widget _buildMobileActions() {
    final style = IconButton.styleFrom(
      backgroundColor: Colors.black.withValues(alpha: 0.35),
      foregroundColor: Colors.white,
      disabledForegroundColor: Colors.white38,
      fixedSize: const Size(48, 48),
      iconSize: 26,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    );
    return _buildControlsVisibility(
      SafeArea(
        key: const Key('player_mobile_actions'),
        minimum: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            IconButton(
              key: const Key('player_screen_lock_button'),
              tooltip: _screenLocked ? '解锁屏幕' : '锁定屏幕',
              style: style,
              onPressed: _toggleScreenLock,
              icon: Icon(
                _screenLocked ? Icons.lock_rounded : Icons.lock_open_rounded,
              ),
            ),
            IconButton(
              key: const Key('player_screenshot_button'),
              tooltip: _capturingScreenshot ? '正在保存截图' : '视频截图',
              style: style,
              onPressed: _canCaptureScreenshot ? _captureScreenshot : null,
              icon: _capturingScreenshot
                  ? const SizedBox.square(
                      dimension: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.photo_camera_rounded),
            ),
          ],
        ),
      ),
      allowWhenLocked: true,
    );
  }

  Widget _buildVideoRegion(
    BuildContext context, {
    required PlaybackSession session,
    required PlaybackSnapshot snapshot,
    required double height,
    required String title,
    required VoidCallback onRetry,
    required Widget? controls,
  }) {
    final idle = snapshot.status == PlaybackStatus.idle;
    return SizedBox(
      key: const Key('player_video_region'),
      height: height,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(
          idle ? ReelvaDesign.radiusLarge : 0,
        ),
        child: Listener(
          onPointerMove: (event) {
            if (event.kind == PointerDeviceKind.mouse && _speedHolds.isEmpty) {
              _showControls();
            }
          },
          child: MouseRegion(
            onExit: (_) {
              if (!kIsWeb &&
                  defaultTargetPlatform == TargetPlatform.windows &&
                  !idle &&
                  _controlsInteractions == 0) {
                _hideControls();
              }
            },
            onHover: (_) {
              if (_speedHolds.isEmpty) _showControls();
            },
            cursor: !idle && !_controlsVisible
                ? SystemMouseCursors.none
                : MouseCursor.defer,
            child: Stack(
              fit: StackFit.expand,
              children: [
                // 始终保留同一曲面；全屏、缩放和停止只改变约束与可见性。
                GestureDetector(
                  supportedDevices: const {
                    PointerDeviceKind.touch,
                    PointerDeviceKind.stylus,
                    PointerDeviceKind.invertedStylus,
                    PointerDeviceKind.unknown,
                  },
                  behavior: HitTestBehavior.opaque,
                  onTap: _toggleSurfaceControls,
                  onDoubleTap: _isMobile && !_screenLocked
                      ? () => unawaited(
                          _runShortcut(PlayerShortcutAction.togglePause),
                        )
                      : null,
                  onVerticalDragStart: _isMobile && !_screenLocked
                      ? (details) => unawaited(
                          _startScreenAdjustment(
                            details,
                            MediaQuery.sizeOf(context).width,
                          ),
                        )
                      : null,
                  onVerticalDragUpdate: _isMobile && !_screenLocked
                      ? (details) => _updateScreenAdjustment(details, height)
                      : null,
                  onVerticalDragEnd: _isMobile && !_screenLocked
                      ? (_) => _endScreenAdjustment()
                      : null,
                  onVerticalDragCancel: _isMobile && !_screenLocked
                      ? () => _endScreenAdjustment(cancel: true)
                      : null,
                  onLongPressStart: _screenLocked
                      ? null
                      : (_) {
                          _focusNode.requestFocus();
                          _setSpeedHold(_SpeedHoldSource.screen, true);
                        },
                  onLongPressEnd: _screenLocked
                      ? null
                      : (_) => _setSpeedHold(_SpeedHoldSource.screen, false),
                  child: Listener(
                    onPointerSignal: _handleScroll,
                    onPointerCancel: (_) =>
                        _setSpeedHold(_SpeedHoldSource.screen, false),
                    child: GestureDetector(
                      supportedDevices: const {PointerDeviceKind.mouse},
                      behavior: HitTestBehavior.opaque,
                      onTap: () {
                        _focusNode.requestFocus();
                        if (_input.clickToPause && !_screenLocked) {
                          unawaited(
                            _runShortcut(PlayerShortcutAction.togglePause),
                          );
                        } else {
                          _toggleSurfaceControls();
                        }
                      },
                      onDoubleTap:
                          _input.doubleClickFullscreen && !_screenLocked
                          ? () => unawaited(
                              _runShortcut(
                                PlayerShortcutAction.toggleFullscreen,
                              ),
                            )
                          : null,
                      onSecondaryTapUp: _input.rightClickMenu && !_screenLocked
                          ? (details) => unawaited(
                              _showContextMenu(details.globalPosition),
                            )
                          : null,
                      child: ColoredBox(
                        color: idle
                            ? Colors.transparent
                            : ReelvaDesign.playerBackground,
                        child: Offstage(
                          offstage: idle,
                          child: Center(child: session.videoBuilder(context)),
                        ),
                      ),
                    ),
                  ),
                ),
                if (idle)
                  _buildEmptySurface(context)
                else if (!_screenLocked)
                  Positioned.fill(
                    top: (height * 0.25).clamp(0.0, 80.0),
                    bottom: (height * 0.4).clamp(0.0, 156.0),
                    child: Theme(
                      data: ReelvaTheme.player,
                      child: Builder(
                        builder: (context) =>
                            _buildStatusOverlay(context, snapshot, onRetry),
                      ),
                    ),
                  ),
                if (!idle)
                  Positioned(
                    key: const Key('player_overlay_header'),
                    top: 0,
                    left: 0,
                    right: 0,
                    child: _buildControlsVisibility(
                      DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              ReelvaDesign.playerBackground.withValues(
                                alpha: 0.35,
                              ),
                              Colors.transparent,
                            ],
                          ),
                        ),
                        child: SafeArea(
                          bottom: false,
                          child: _buildHeader(
                            context,
                            title: title,
                            fullscreen: _isFullscreen,
                            overlay: true,
                          ),
                        ),
                      ),
                    ),
                  ),
                if (controls != null)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: _buildControlsVisibility(
                      DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.transparent,
                              ReelvaDesign.playerBackground.withValues(
                                alpha: 0.35,
                              ),
                            ],
                          ),
                        ),
                        child: SafeArea(
                          top: false,
                          minimum: const EdgeInsets.fromLTRB(8, 16, 8, 4),
                          child: ConstrainedBox(
                            constraints: BoxConstraints(
                              maxHeight: height * 0.48,
                            ),
                            child: KeyedSubtree(
                              key: const Key('player_controls_panel'),
                              child: controls,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                if (!idle && _isMobile)
                  Positioned.fill(child: _buildMobileActions()),
                if (!idle && _speedHolds.isNotEmpty && snapshot.rate == 3)
                  Positioned(
                    left: 0,
                    right: 0,
                    top:
                        MediaQuery.paddingOf(context).top +
                        (height * 0.12).clamp(24.0, 64.0),
                    child: IgnorePointer(
                      child: Center(
                        child: Material(
                          key: const Key('player_speed_hold_indicator'),
                          color: Colors.black.withValues(alpha: 0.65),
                          borderRadius: BorderRadius.circular(28),
                          child: const Padding(
                            padding: EdgeInsets.symmetric(
                              horizontal: 18,
                              vertical: 10,
                            ),
                            child: Text(
                              '3倍速中',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                if (!idle && _gestureFeedback != null)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: Center(
                        child: Material(
                          key: const Key('player_gesture_indicator'),
                          color: Colors.black.withValues(alpha: 0.7),
                          borderRadius: BorderRadius.circular(16),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 16,
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  _gestureFeedback!.type ==
                                          _ScreenAdjustment.brightness
                                      ? Icons.brightness_6_rounded
                                      : _gestureFeedback!.value == 0
                                      ? Icons.volume_off_rounded
                                      : Icons.volume_up_rounded,
                                  color: Colors.white,
                                  size: 28,
                                ),
                                const SizedBox(width: 12),
                                Text(
                                  _gestureFeedback!.type ==
                                          _ScreenAdjustment.brightness
                                      ? '亮度 ${(_gestureFeedback!.value * 100).round()}%'
                                      : '音量 ${_gestureFeedback!.value.round()}%',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 18,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                if (_statisticsVisible && !idle)
                  Positioned.fill(
                    child: SafeArea(
                      minimum: const EdgeInsets.fromLTRB(12, 64, 12, 88),
                      child: Align(
                        alignment: Alignment.topLeft,
                        child: PlayerStatisticsOverlay(
                          key: const Key('player_statistics_overlay'),
                          engine: session.engine,
                          onClose: () {
                            setState(() => _statisticsVisible = false);
                            _focusNode.requestFocus();
                          },
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildViewport(
    BuildContext context, {
    required PlaybackSession session,
    required PlaybackSnapshot snapshot,
    required String displayName,
    required VoidCallback onRetry,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final idle = snapshot.status == PlaybackStatus.idle;
        _updateControlsVisibility(snapshot, !idle);
        final padding = idle ? ReelvaDesign.space16 : 0.0;
        final videoHeight = (constraints.maxHeight - padding * 2).clamp(
          0.0,
          double.infinity,
        );
        final controls = idle
            ? null
            : _buildControls(snapshot, session.engine, overlay: true);
        return Padding(
          padding: EdgeInsets.all(padding),
          child: _buildVideoRegion(
            context,
            session: session,
            snapshot: snapshot,
            height: videoHeight,
            title: displayName,
            onRetry: onRetry,
            controls: controls,
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(playerSessionProvider);
    _session = session;
    final resource = _currentResource;
    final displayName = resource?.displayName ?? '播放器';

    return PopScope(
      canPop: _canPopAfterExit,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        if (_screenLocked) {
          _toggleScreenLock();
          return;
        }
        if (_isFullscreen) {
          await _setFullscreen(false);
          return;
        }
        await _handleExit();
      },
      child: StreamBuilder<PlaybackSnapshot>(
        stream: session.engine.snapshots,
        initialData: session.engine.snapshot,
        builder: (context, snapshotAsync) {
          final engineSnapshot = snapshotAsync.data ?? const PlaybackSnapshot();
          // 读取续播进度前引擎仍为空闲；已有视频时直接显示播放布局与加载状态。
          final snapshot =
              _isOpeningInitialResource &&
                  engineSnapshot.status == PlaybackStatus.idle
              ? engineSnapshot.copyWith(status: PlaybackStatus.opening)
              : engineSnapshot;
          if (snapshot.volume > 0) _lastNonZeroVolume = snapshot.volume;
          final idle = snapshot.status == PlaybackStatus.idle;
          _syncVideoOrientation(snapshot);
          _syncWindowVideoSize(snapshot);
          final immersive = !idle || _isFullscreen;

          void handleReplayOrRetry() async {
            if (snapshot.status == PlaybackStatus.completed) {
              await session.engine.seek(Duration.zero);
              await session.engine.play();
            } else if (_currentResource != null) {
              await session.engine.open(_currentResource!);
            }
          }

          return Theme(
            data: immersive ? ReelvaTheme.player : ReelvaTheme.light,
            child: Builder(
              builder: (context) => Focus(
                focusNode: _focusNode,
                autofocus: true,
                onKeyEvent: _handleKeyEvent,
                onFocusChange: (focused) {
                  if (!focused) _cancelSpeedHold();
                },
                child: Scaffold(
                  backgroundColor: immersive
                      ? ReelvaDesign.playerBackground
                      : ReelvaDesign.background,
                  body: GlassBackground(
                    child: SafeArea(
                      top: !immersive,
                      bottom: !immersive,
                      left: !immersive,
                      right: !immersive,
                      child: Column(
                        children: [
                          if (!immersive)
                            DecoratedBox(
                              decoration: BoxDecoration(
                                color: Colors.white,
                                border: Border(
                                  bottom: BorderSide(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .outlineVariant
                                        .withValues(alpha: 0.4),
                                  ),
                                ),
                              ),
                              child: _buildHeader(
                                context,
                                title: '播放器',
                                fullscreen: false,
                              ),
                            ),
                          Expanded(
                            key: const Key('player_viewport'),
                            child: _buildViewport(
                              context,
                              session: session,
                              snapshot: snapshot,
                              displayName: displayName,
                              onRetry: handleReplayOrRetry,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
