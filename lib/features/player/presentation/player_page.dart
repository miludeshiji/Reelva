import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:window_manager/window_manager.dart';

import '../../../app/theme/reelva_theme.dart';
import '../../../core/logging/app_logger.dart';
import '../../../shared/widgets/glass_widgets.dart';
import '../application/playback_session.dart';
import '../application/player_providers.dart';
import '../domain/playback_resource.dart';
import '../domain/playback_snapshot.dart';
import '../domain/player_engine.dart';
import 'network_address_dialog.dart';
import 'player_controls.dart';

/// Reelva 核心播放页面
///
/// 独立于主导航索引外壳，拥有受控的独立播放生命周期。
/// 退出页面时先 await engine.dispose() 彻底释放底层播放器；进入后台时自动暂停；
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
  PlaybackResource? _currentResource;
  int _actionCounter = 0;
  final FocusNode _focusNode = FocusNode();
  bool _isWindowClosing = false;
  final GlobalKey _controlsKey = GlobalKey();
  Timer? _controlsHideTimer;
  PlaybackStatus? _controlsStatus;
  bool _usesOverlayControls = false;
  bool _controlsVisible = true;
  bool _pointerOverControls = false;
  bool _controlsHaveFocus = false;
  int _controlsInteractions = 0;
  bool _hasProgressError = false;
  Orientation? _videoOrientation;
  Future<void> _orientationUpdate = Future<void>.value();

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
    if (!_usesOverlayControls ||
        _controlsStatus != PlaybackStatus.playing ||
        _pointerOverControls ||
        _controlsHaveFocus ||
        _controlsInteractions > 0 ||
        _hasProgressError) {
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
    _controlsVisible = true;
    _scheduleControlsHide();
  }

  Widget _buildControlsVisibility(Widget child) {
    return IgnorePointer(
      ignoring: !_controlsVisible,
      child: ExcludeFocus(
        excluding: !_controlsVisible,
        child: ExcludeSemantics(
          excluding: !_controlsVisible,
          child: AnimatedOpacity(
            opacity: _controlsVisible ? 1 : 0,
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
    WidgetsBinding.instance.addObserver(this);
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.windows) {
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
  void didUpdateWidget(covariant PlayerPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialResource != oldWidget.initialResource) {
      _currentResource = widget.initialResource;
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
    }
  }

  @override
  void dispose() {
    _isExiting = true;
    _actionCounter++;
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.windows) {
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
    if (_isFullscreen) {
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.windows) {
        windowManager.setFullScreen(false).catchError((
          Object e,
          StackTrace st,
        ) {
          AppLogger.instance.error(
            '销毁还原 Windows 全屏模式异常',
            error: e,
            stackTrace: st,
          );
        });
      } else if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge)
            .catchError((Object e, StackTrace st) {
              AppLogger.instance.error(
                '销毁还原 Android 沉浸模式异常',
                error: e,
                stackTrace: st,
              );
            });
      }
    }
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden) {
      _session?.engine.pause().catchError((Object e, StackTrace st) {
        AppLogger.instance.error('进入后台自动暂停失败', error: e, stackTrace: st);
      });
    }
  }

  Future<void> _handleExit() async {
    if (_isExiting) return;
    _isExiting = true;

    await _setVideoOrientation(null);

    if (_isFullscreen) {
      await _setFullscreen(false);
    }

    final engine = _session?.engine;
    if (engine != null) {
      try {
        await engine.dispose();
      } catch (e, st) {
        AppLogger.instance.error('退出页面释放播放引擎异常', error: e, stackTrace: st);
      }
    }

    if (!mounted) return;

    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/');
    }
  }

  Future<void> _setFullscreen(bool targetFullscreen) async {
    if (_isTogglingFullscreen || _isFullscreen == targetFullscreen) return;
    _isTogglingFullscreen = true;

    var nativeSuccess = true;
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.windows) {
      try {
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
        setState(() {
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
        setState(() {
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
    final route = ModalRoute.of(context);
    if (route != null && !route.isCurrent) {
      return false;
    }
    final focus = FocusManager.instance.primaryFocus;
    if (focus != null) {
      final ctx = focus.context;
      if (ctx != null) {
        if (ctx.widget is EditableText ||
            ctx.findAncestorWidgetOfExactType<EditableText>() != null) {
          return false;
        }
      }
    }
    return true;
  }

  KeyEventResult _handleKeyEvent(
    FocusNode node,
    KeyEvent event,
    PlaybackSnapshot snapshot,
    PlayerEngine engine,
  ) {
    if (event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }

    if (!_canHandleShortcuts(context)) {
      return KeyEventResult.ignored;
    }

    _showControls();
    final key = event.logicalKey;

    if (key == LogicalKeyboardKey.space) {
      if (snapshot.status == PlaybackStatus.idle ||
          snapshot.status == PlaybackStatus.resolving ||
          snapshot.status == PlaybackStatus.opening ||
          snapshot.status == PlaybackStatus.error) {
        return KeyEventResult.handled;
      }
      if (snapshot.status == PlaybackStatus.completed) {
        engine.seek(Duration.zero);
        engine.play();
        return KeyEventResult.handled;
      }
      if (snapshot.isPlaying) {
        engine.pause();
      } else {
        engine.play();
      }
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.arrowLeft) {
      if (snapshot.duration <= Duration.zero ||
          snapshot.status == PlaybackStatus.idle ||
          snapshot.status == PlaybackStatus.resolving ||
          snapshot.status == PlaybackStatus.opening ||
          snapshot.status == PlaybackStatus.error) {
        return KeyEventResult.handled;
      }
      final target = snapshot.position - const Duration(seconds: 10);
      engine.seek(target < Duration.zero ? Duration.zero : target);
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.arrowRight) {
      if (snapshot.duration <= Duration.zero ||
          snapshot.status == PlaybackStatus.idle ||
          snapshot.status == PlaybackStatus.resolving ||
          snapshot.status == PlaybackStatus.opening ||
          snapshot.status == PlaybackStatus.error) {
        return KeyEventResult.handled;
      }
      final target = snapshot.position + const Duration(seconds: 10);
      engine.seek(target > snapshot.duration ? snapshot.duration : target);
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.arrowUp) {
      if (snapshot.status == PlaybackStatus.error) {
        return KeyEventResult.handled;
      }
      final nextVol = (snapshot.volume + 5.0).clamp(0.0, _session!.maxVolume);
      engine.setVolume(nextVol);
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.arrowDown) {
      if (snapshot.status == PlaybackStatus.error) {
        return KeyEventResult.handled;
      }
      final nextVol = (snapshot.volume - 5.0).clamp(0.0, _session!.maxVolume);
      engine.setVolume(nextVol);
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.escape) {
      if (_isFullscreen && !_isTogglingFullscreen) {
        _setFullscreen(false);
        return KeyEventResult.handled;
      }
    }

    return KeyEventResult.ignored;
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
              key: const Key('player_source_menu_button'),
              icon: const Icon(Icons.more_vert_rounded),
              tooltip: '打开视频',
              onOpened: () {
                _controlsInteractions++;
                _showControls();
              },
              onCanceled: () {
                _controlsInteractions--;
                _scheduleControlsHide();
              },
              onSelected: (value) async {
                try {
                  if (value == 'file') {
                    await _pickNativeVideo();
                  } else {
                    await _openNetworkVideo();
                  }
                } finally {
                  if (mounted) {
                    _controlsInteractions--;
                    _showControls();
                  }
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem(
                  key: Key('appbar_pick_file_button'),
                  value: 'file',
                  child: Text('选择本地视频'),
                ),
                PopupMenuItem(
                  key: Key('appbar_open_url_button'),
                  value: 'url',
                  child: Text('输入网络链接'),
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
          onPointerMove: (_) => _showControls(),
          child: MouseRegion(
            onHover: (_) => _showControls(),
            cursor: !idle && !_controlsVisible
                ? SystemMouseCursors.none
                : MouseCursor.defer,
            child: Stack(
              fit: StackFit.expand,
              children: [
                // 始终保留同一曲面；全屏、缩放和停止只改变约束与可见性。
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    _focusNode.requestFocus();
                    if (_controlsVisible &&
                        snapshot.status == PlaybackStatus.playing) {
                      _controlsHideTimer?.cancel();
                      setState(() => _controlsVisible = false);
                    } else {
                      _showControls();
                    }
                  },
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
                if (idle)
                  _buildEmptySurface(context)
                else
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
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
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
          final snapshot = snapshotAsync.data ?? const PlaybackSnapshot();
          final idle = snapshot.status == PlaybackStatus.idle;
          _syncVideoOrientation(snapshot);
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
                onKeyEvent: (node, event) =>
                    _handleKeyEvent(node, event, snapshot, session.engine),
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
