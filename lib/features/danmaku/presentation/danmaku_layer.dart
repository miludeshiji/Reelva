import 'package:canvas_danmaku/canvas_danmaku.dart' as canvas;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../player/domain/playback_resource.dart';
import '../../player/domain/playback_snapshot.dart';
import '../application/danmaku_controller.dart';
import '../application/danmaku_providers.dart';
import '../domain/danmaku.dart';
import '../domain/danmaku_timeline.dart';

class DanmakuLayer extends ConsumerStatefulWidget {
  const DanmakuLayer({
    super.key,
    required this.resource,
    required this.snapshot,
  });
  final PlaybackResource? resource;
  final PlaybackSnapshot snapshot;
  @override
  ConsumerState<DanmakuLayer> createState() => _DanmakuLayerState();
}

class _DanmakuLayerState extends ConsumerState<DanmakuLayer>
    with SingleTickerProviderStateMixin {
  late final DanmakuController _controller;
  late final Ticker _ticker;
  final Stopwatch _clock = Stopwatch()..start();
  canvas.DanmakuController<void>? _canvas;
  List<DanmakuComment> _comments = const [];
  DanmakuSettings? _settings;
  DanmakuSettings? _appliedSettings;
  double? _appliedRate;
  DanmakuTimeline _timeline = DanmakuTimeline(const []);
  int _anchorMs = 0;
  int _positionMs = 0;
  double _offset = 0;

  bool get _playing =>
      _controller.settings.enabled &&
      widget.snapshot.status == PlaybackStatus.playing &&
      _comments.isNotEmpty;
  int get _sourceTime =>
      _positionMs +
      (_playing
          ? ((_clock.elapsedMilliseconds - _anchorMs).clamp(0, 500) *
                    widget.snapshot.rate)
                .round()
          : 0) -
      (_offset * 1000).round();

  @override
  void initState() {
    super.initState();
    _controller = ref.read(danmakuControllerProvider);
    _controller.addListener(_changed);
    _ticker = createTicker(_tick);
    _positionMs = widget.snapshot.position.inMilliseconds;
    _open();
  }

  void _open() {
    final resource = widget.resource;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && widget.resource == resource) _controller.open(resource);
    });
  }

  @override
  void didUpdateWidget(covariant DanmakuLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.resource != oldWidget.resource) _open();
    final next = widget.snapshot;
    final previous = oldWidget.snapshot;
    if (next.position != previous.position ||
        next.status != previous.status ||
        next.rate != previous.rate) {
      final predicted =
          _positionMs +
          (previous.status == PlaybackStatus.playing
              ? ((_clock.elapsedMilliseconds - _anchorMs) * previous.rate)
                    .round()
              : 0);
      final seek =
          (next.position.inMilliseconds - predicted).abs() > 750 ||
          next.position < previous.position;
      _positionMs = next.position.inMilliseconds;
      _anchorMs = _clock.elapsedMilliseconds;
      if (seek || next.rate != previous.rate) _reset();
      _syncAfterFrame();
    }
  }

  void _changed() {
    if (!mounted) return;
    final offset =
        _controller.offsetSeconds + (_controller.selected?.shiftSeconds ?? 0);
    if (!identical(_comments, _controller.comments)) {
      _comments = _controller.comments;
      _timeline = DanmakuTimeline(_comments);
      _offset = offset;
      _reset();
    } else if (_offset != offset ||
        _settings?.enabled != _controller.settings.enabled) {
      _offset = offset;
      _reset();
    }
    _settings = _controller.settings;
    _syncAfterFrame();
    setState(() {});
  }

  void _reset() {
    _timeline.seek(_sourceTime);
    // 控制器在构建期间回调，画布更新统一延后到本帧结束。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _canvas?.clear();
    });
  }

  void _syncAfterFrame() => WidgetsBinding.instance.addPostFrameCallback((_) {
    if (!mounted) return;
    final settings = _controller.settings;
    final rate = widget.snapshot.rate > 0 ? widget.snapshot.rate : 1.0;
    if (!identical(_appliedSettings, settings) || _appliedRate != rate) {
      _canvas?.updateOption(
        canvas.DanmakuOption(
          fontSize: settings.fontSize,
          opacity: settings.opacity,
          area: settings.area,
          duration: settings.duration / rate,
          staticDuration: 4 / rate,
          hideTop: !settings.showTop,
          hideBottom: !settings.showBottom,
          safeArea: true,
        ),
      );
      _appliedSettings = settings;
      _appliedRate = rate;
    }
    if (_playing) {
      if (!(_canvas?.running ?? true)) _canvas?.resume();
      if (!_ticker.isActive && !_timeline.finished) _ticker.start();
    } else {
      if (_canvas?.running ?? false) _canvas?.pause();
      _ticker.stop();
    }
  });

  void _tick(Duration elapsed) {
    if (!_playing || _canvas == null) return;
    for (final comment in _timeline.takeThrough(
      _sourceTime,
      _controller.settings,
    )) {
      _canvas!.addDanmaku(
        canvas.DanmakuContentItem<void>(
          comment.text,
          color: Color(0xff000000 | comment.color),
          type: comment.mode == 4
              ? canvas.DanmakuItemType.bottom
              : comment.mode == 5
              ? canvas.DanmakuItemType.top
              : canvas.DanmakuItemType.scroll,
        ),
      );
    }
    if (_timeline.finished) _ticker.stop();
  }

  @override
  void dispose() {
    _controller.removeListener(_changed);
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(danmakuControllerProvider);
    return IgnorePointer(
      child: RepaintBoundary(
        child: ClipRect(
          child: Visibility(
            visible:
                _controller.settings.enabled &&
                widget.resource != null &&
                const {
                  PlaybackStatus.playing,
                  PlaybackStatus.paused,
                  PlaybackStatus.buffering,
                }.contains(widget.snapshot.status),
            maintainState: true,
            child: canvas.DanmakuScreen<void>(
              option: const canvas.DanmakuOption(),
              createdController: (controller) {
                _canvas = controller;
                _syncAfterFrame();
              },
            ),
          ),
        ),
      ),
    );
  }
}
