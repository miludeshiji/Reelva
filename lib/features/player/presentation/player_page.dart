import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:window_manager/window_manager.dart';

import '../../../core/logging/app_logger.dart';
import '../../../shared/widgets/reelva_logo.dart';
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
        overlayContent = Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.video_library_outlined,
              size: 56,
              color: Colors.white54,
            ),
            const SizedBox(height: 12),
            Text(
              '未加载视频',
              style: theme.textTheme.titleMedium?.copyWith(
                color: Colors.white70,
              ),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                FilledButton.icon(
                  key: const Key('idle_open_file_button'),
                  icon: const Icon(Icons.folder_open),
                  label: const Text('选择本地视频'),
                  onPressed: _pickNativeVideo,
                ),
                OutlinedButton.icon(
                  key: const Key('idle_open_url_button'),
                  icon: const Icon(Icons.link),
                  label: const Text('输入网络链接'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Colors.white54),
                  ),
                  onPressed: _openNetworkVideo,
                ),
              ],
            ),
          ],
        );
        break;

      case PlaybackStatus.resolving:
      case PlaybackStatus.opening:
      case PlaybackStatus.buffering:
        overlayContent = Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          decoration: BoxDecoration(
            color: Colors.black54,
            borderRadius: BorderRadius.circular(12),
          ),
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
        overlayContent = Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          decoration: BoxDecoration(
            color: const Color(0x99000000),
            borderRadius: BorderRadius.circular(12),
          ),
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
        overlayContent = Container(
          margin: const EdgeInsets.all(24),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.black87,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: theme.colorScheme.error.withValues(alpha: 0.5),
            ),
          ),
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
      final nextVol = (snapshot.volume + 5.0).clamp(0.0, 100.0);
      engine.setVolume(nextVol);
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.arrowDown) {
      if (snapshot.status == PlaybackStatus.error) {
        return KeyEventResult.handled;
      }
      final nextVol = (snapshot.volume - 5.0).clamp(0.0, 100.0);
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

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(playerSessionProvider);
    _session = session;
    final theme = Theme.of(context);
    final displayName = _currentResource?.displayName ?? '播放器';

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

          void handleReplayOrRetry() async {
            if (snapshot.status == PlaybackStatus.completed) {
              await session.engine.seek(Duration.zero);
              await session.engine.play();
            } else if (_currentResource != null) {
              await session.engine.open(_currentResource!);
            }
          }

          return Focus(
            focusNode: _focusNode,
            autofocus: true,
            onKeyEvent: (node, event) =>
                _handleKeyEvent(node, event, snapshot, session.engine),
            child: Scaffold(
              backgroundColor: Colors.black,
              appBar: _isFullscreen
                  ? null
                  : AppBar(
                      leading: BackButton(
                        key: const Key('player_back_button'),
                        onPressed: _handleExit,
                      ),
                      title: Row(
                        children: [
                          const ReelvaLogo(size: 24),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              displayName,
                              key: const Key('player_title_text'),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      actions: [
                        IconButton(
                          key: const Key('appbar_pick_file_button'),
                          icon: const Icon(Icons.folder_open),
                          tooltip: '选择本地视频',
                          onPressed: _pickNativeVideo,
                        ),
                        IconButton(
                          key: const Key('appbar_open_url_button'),
                          icon: const Icon(Icons.link),
                          tooltip: '输入网络链接',
                          onPressed: _openNetworkVideo,
                        ),
                      ],
                    ),
              body: SafeArea(
                top: !_isFullscreen,
                bottom: !_isFullscreen,
                child: Stack(
                  children: [
                    // 主视频画面（全屏与非全屏使用同一直属 session.videoBuilder）
                    Positioned.fill(
                      child: Container(
                        color: Colors.black,
                        child: Center(child: session.videoBuilder(context)),
                      ),
                    ),

                    // 状态遮罩层（空闲、缓冲加载、播放完成重播、错误提示；内嵌滚动支持小高度视口）
                    Positioned.fill(
                      child: _buildStatusOverlay(
                        context,
                        snapshot,
                        handleReplayOrRetry,
                      ),
                    ),

                    // 全屏模式下的顶部控制浮层（提供退出全屏返回与标题展示）
                    if (_isFullscreen)
                      Positioned(
                        top: 0,
                        left: 0,
                        right: 0,
                        child: Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Colors.black.withValues(alpha: 0.8),
                                Colors.transparent,
                              ],
                            ),
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          child: Row(
                            children: [
                              IconButton(
                                key: const Key('fullscreen_exit_back_button'),
                                icon: const Icon(
                                  Icons.arrow_back,
                                  color: Colors.white,
                                ),
                                tooltip: '退出全屏',
                                onPressed: () => _setFullscreen(false),
                              ),
                              const SizedBox(width: 8),
                              const ReelvaLogo(size: 20),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  displayName,
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    color: Colors.white,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                    // 底部控制面板（进度条、时长缓冲独立行、Wrap响应式控制按钮）
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: PlayerControls(
                        snapshot: snapshot,
                        engine: session.engine,
                        isFullscreen: _isFullscreen,
                        onToggleFullscreen: () =>
                            _setFullscreen(!_isFullscreen),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
