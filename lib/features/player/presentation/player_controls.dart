import 'package:flutter/material.dart';

import '../../../app/theme/reelva_theme.dart';
import '../../../shared/widgets/glass_widgets.dart' show GlassPopupMenuItem;
import '../domain/playback_snapshot.dart';
import '../domain/player_engine.dart';

/// 格式化时长为分:秒或时:分:秒。
String formatDuration(Duration d) {
  if (d < Duration.zero) return '00:00';
  final hours = d.inHours;
  final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
  final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  if (hours > 0) return '$hours:$minutes:$seconds';
  return '$minutes:$seconds';
}

/// 透明悬浮播放控件；音量按需展开，窄屏将字幕、音轨和倍速收入设置面板。
class PlayerControls extends StatefulWidget {
  const PlayerControls({
    super.key,
    required this.snapshot,
    required this.engine,
    required this.isFullscreen,
    required this.onToggleFullscreen,
    this.overlay = false,
    this.onInteractionChanged,
    this.maxVolume = 100,
    this.onPickLocalSubtitle,
    this.onPickSourceSubtitle,
  });

  final PlaybackSnapshot snapshot;
  final PlayerEngine engine;
  final bool isFullscreen;
  final VoidCallback onToggleFullscreen;
  final bool overlay;
  final ValueChanged<bool>? onInteractionChanged;
  final double maxVolume;
  final VoidCallback? onPickLocalSubtitle;
  final VoidCallback? onPickSourceSubtitle;

  static const List<double> supportedRates = [0.5, 1.0, 1.25, 1.5, 2.0, 3.0];

  @override
  State<PlayerControls> createState() => _PlayerControlsState();
}

class _PlayerControlsState extends State<PlayerControls> {
  double _lastNonZeroVolume = 100.0;
  double? _dragPositionMs;
  FocusNode? _focusBeforeVolumeMenu;

  @override
  void initState() {
    super.initState();
    if (widget.snapshot.volume > 0) {
      _lastNonZeroVolume = widget.snapshot.volume;
    }
  }

  @override
  void didUpdateWidget(covariant PlayerControls oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.snapshot.volume > 0) {
      _lastNonZeroVolume = widget.snapshot.volume;
    }
  }

  void _toggleMute(PlaybackSnapshot snapshot) {
    if (snapshot.volume > 0) {
      _lastNonZeroVolume = snapshot.volume;
      widget.engine.setVolume(0);
    } else {
      widget.engine.setVolume(
        _lastNonZeroVolume > 0 ? _lastNonZeroVolume : 100.0,
      );
    }
  }

  Widget _buildPlaybackAction(
    BuildContext context,
    PlaybackSnapshot snapshot,
    PlayerEngine engine,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final style = IconButton.styleFrom(
      backgroundColor: Colors.transparent,
      foregroundColor: scheme.onSurface,
      disabledForegroundColor: scheme.onSurface.withValues(alpha: 0.38),
      fixedSize: const Size(48, 44),
      iconSize: 26,
      padding: const EdgeInsets.all(8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(ReelvaDesign.radiusSmall),
      ),
    );

    if (snapshot.status == PlaybackStatus.completed) {
      return IconButton(
        key: const Key('player_replay_button'),
        icon: const Icon(Icons.replay_rounded),
        tooltip: '重新播放',
        style: style,
        onPressed: () async {
          await engine.seek(Duration.zero);
          await engine.play();
        },
      );
    }

    if (snapshot.status == PlaybackStatus.resolving ||
        snapshot.status == PlaybackStatus.opening) {
      return IconButton(
        key: const Key('player_play_button'),
        icon: const SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        tooltip: '正在准备',
        style: style,
        onPressed: null,
      );
    }

    if (snapshot.status == PlaybackStatus.error ||
        snapshot.status == PlaybackStatus.idle) {
      return IconButton(
        key: const Key('player_play_button'),
        icon: const Icon(Icons.play_arrow_rounded),
        tooltip: '不可播放',
        style: style,
        onPressed: null,
      );
    }

    if (snapshot.isPlaying) {
      return IconButton(
        key: const Key('player_pause_button'),
        icon: const Icon(Icons.pause_rounded),
        tooltip: '暂停',
        style: style,
        onPressed: engine.pause,
      );
    }

    return IconButton(
      key: const Key('player_play_button'),
      icon: const Icon(Icons.play_arrow_rounded),
      tooltip: '播放',
      style: style,
      onPressed: engine.play,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isOverlay = widget.overlay || widget.isFullscreen;
    return Theme(
      data: isOverlay ? ReelvaTheme.player : ReelvaTheme.light,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final controls = _buildControls(
            context,
            constraints.maxWidth <
                700 * MediaQuery.textScalerOf(context).scale(1),
          );
          return constraints.hasBoundedHeight
              ? SingleChildScrollView(child: controls)
              : controls;
        },
      ),
    );
  }

  Widget _buildControls(BuildContext context, bool compact) {
    final theme = Theme.of(context);
    final snapshot = widget.snapshot;
    final engine = widget.engine;
    final hasKnownDuration = snapshot.duration > Duration.zero;
    final totalDurationMs = hasKnownDuration
        ? snapshot.duration.inMilliseconds.toDouble()
        : 1.0;
    final currentPosMs = hasKnownDuration
        ? snapshot.position.inMilliseconds
              .clamp(0, snapshot.duration.inMilliseconds)
              .toDouble()
        : 0.0;
    final isSeekEnabled =
        hasKnownDuration &&
        snapshot.status != PlaybackStatus.idle &&
        snapshot.status != PlaybackStatus.error &&
        snapshot.status != PlaybackStatus.resolving &&
        snapshot.status != PlaybackStatus.opening;
    final displayPosMs = _dragPositionMs ?? currentPosMs;
    final displayPosText = formatDuration(
      Duration(milliseconds: displayPosMs.round()),
    );
    final totalDurText = hasKnownDuration
        ? formatDuration(snapshot.duration)
        : '--:--';

    final seekSlider = Slider(
      key: const Key('player_seek_slider'),
      value: displayPosMs.clamp(0.0, totalDurationMs),
      min: 0.0,
      max: totalDurationMs,
      secondaryTrackValue: hasKnownDuration
          ? snapshot.buffered.inMilliseconds
                .clamp(0, totalDurationMs.toInt())
                .toDouble()
          : null,
      onChangeStart: isSeekEnabled
          ? (_) => widget.onInteractionChanged?.call(true)
          : null,
      onChanged: isSeekEnabled
          ? (value) => setState(() => _dragPositionMs = value)
          : null,
      onChangeEnd: isSeekEnabled
          ? (value) {
              setState(() => _dragPositionMs = null);
              engine.seek(Duration(milliseconds: value.round()));
              widget.onInteractionChanged?.call(false);
            }
          : null,
    );
    final timeDisplay = Text(
      '$displayPosText / $totalDurText',
      key: const Key('player_time_display_text'),
      style: theme.textTheme.labelMedium?.copyWith(
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    );
    final bufferDisplay = Text(
      '缓冲: ${formatDuration(snapshot.buffered)}',
      key: const Key('player_buffer_text'),
      style: theme.textTheme.labelSmall?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    );

    final transport = Row(
      mainAxisSize: MainAxisSize.min,
      spacing: ReelvaDesign.space4,
      children: [
        IconButton(
          key: const Key('player_seek_back_button'),
          icon: const Icon(Icons.replay_10_rounded),
          tooltip: '后退 10 秒',
          onPressed: isSeekEnabled
              ? () {
                  final target =
                      snapshot.position - const Duration(seconds: 10);
                  engine.seek(target < Duration.zero ? Duration.zero : target);
                }
              : null,
        ),
        _buildPlaybackAction(context, snapshot, engine),
        IconButton(
          key: const Key('player_seek_forward_button'),
          icon: const Icon(Icons.forward_10_rounded),
          tooltip: '快进 10 秒',
          onPressed: isSeekEnabled
              ? () {
                  final target =
                      snapshot.position + const Duration(seconds: 10);
                  engine.seek(
                    target > snapshot.duration ? snapshot.duration : target,
                  );
                }
              : null,
        ),
      ],
    );
    final volume = _buildVolumeMenu(context, snapshot);
    final fullscreen = IconButton(
      key: const Key('player_fullscreen_button'),
      icon: Icon(
        widget.isFullscreen
            ? Icons.fullscreen_exit_rounded
            : Icons.fullscreen_rounded,
      ),
      tooltip: widget.isFullscreen ? '退出全屏' : '全屏',
      onPressed: widget.onToggleFullscreen,
    );
    final more = IconButton(
      key: const Key('player_more_button'),
      icon: const Icon(Icons.more_horiz_rounded),
      tooltip: '播放设置',
      onPressed: () async {
        final onInteractionChanged = widget.onInteractionChanged;
        onInteractionChanged?.call(true);
        try {
          await showModalBottomSheet<void>(
            context: context,
            backgroundColor: theme.colorScheme.surface,
            showDragHandle: true,
            builder: (context) => Theme(
              data: theme,
              child: SafeArea(
                top: false,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                  child: StreamBuilder<PlaybackSnapshot>(
                    stream: engine.snapshots,
                    initialData: engine.snapshot,
                    builder: (context, state) =>
                        _buildSettings(context, state.data ?? snapshot),
                  ),
                ),
              ),
            ),
          );
        } finally {
          onInteractionChanged?.call(false);
        }
      },
    );

    return IconButtonTheme(
      data: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: theme.colorScheme.onSurface,
          minimumSize: const Size(40, 40),
          padding: const EdgeInsets.all(8),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          iconSize: 22,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(ReelvaDesign.radiusSmall),
          ),
        ),
      ),
      child: SliderTheme(
        data: SliderTheme.of(context).copyWith(
          trackHeight: 3,
          activeTrackColor: theme.colorScheme.primary,
          inactiveTrackColor: theme.colorScheme.onSurface.withValues(
            alpha: 0.16,
          ),
          secondaryActiveTrackColor: theme.colorScheme.primary.withValues(
            alpha: 0.32,
          ),
          thumbColor: theme.colorScheme.primary,
          thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
          overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (snapshot.progressErrorMessage?.isNotEmpty ?? false)
                Padding(
                  key: const Key('player_progress_error_banner'),
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    snapshot.progressErrorMessage!,
                    key: const Key('player_progress_error_text'),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                  ),
                ),
              if (compact) ...[
                seekSlider,
                timeDisplay,
              ] else
                Row(
                  children: [
                    Expanded(child: seekSlider),
                    timeDisplay,
                    const SizedBox(width: 16),
                    bufferDisplay,
                  ],
                ),
              Row(
                children: [
                  transport,
                  const Spacer(),
                  if (compact) more else _buildSettings(context, snapshot),
                  volume,
                  fullscreen,
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildVolumeMenu(BuildContext context, PlaybackSnapshot snapshot) {
    const panelWidth = 240.0;
    final theme = Theme.of(context);
    final engine = widget.engine;
    return MenuAnchor(
      alignmentOffset: const Offset(-panelWidth, 8),
      style: const MenuStyle(
        alignment: Alignment.bottomRight,
        padding: WidgetStatePropertyAll(EdgeInsets.all(8)),
      ),
      consumeOutsideTap: true,
      onOpen: () {
        _focusBeforeVolumeMenu = FocusManager.instance.primaryFocus;
        widget.onInteractionChanged?.call(true);
      },
      onClose: () {
        _focusBeforeVolumeMenu?.requestFocus();
        _focusBeforeVolumeMenu = null;
        widget.onInteractionChanged?.call(false);
      },
      menuChildren: [
        StreamBuilder<PlaybackSnapshot>(
          stream: engine.snapshots,
          initialData: snapshot,
          builder: (context, state) {
            final current = state.data ?? snapshot;
            final isMuted = current.volume == 0;
            return SizedBox(
              key: const Key('player_volume_panel'),
              width: panelWidth - 16,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text('音量', style: theme.textTheme.labelLarge),
                        ),
                        Text(
                          '${current.volume.round()}%',
                          key: const Key('player_volume_text'),
                          style: theme.textTheme.labelSmall?.copyWith(
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ],
                    ),
                  ),
                  Slider(
                    key: const Key('player_volume_slider'),
                    autofocus: true,
                    value: current.volume.clamp(0.0, widget.maxVolume),
                    max: widget.maxVolume,
                    onChanged: (volume) {
                      if (volume > 0) _lastNonZeroVolume = volume;
                      engine.setVolume(volume);
                    },
                  ),
                  MenuItemButton(
                    key: const Key('player_mute_button'),
                    closeOnActivate: false,
                    leadingIcon: Icon(
                      isMuted
                          ? Icons.volume_up_rounded
                          : Icons.volume_off_rounded,
                    ),
                    onPressed: () => _toggleMute(current),
                    child: Text(isMuted ? '取消静音' : '静音'),
                  ),
                ],
              ),
            );
          },
        ),
      ],
      builder: (context, controller, child) => IconButton(
        key: const Key('player_volume_button'),
        icon: Icon(
          snapshot.volume == 0
              ? Icons.volume_off_rounded
              : Icons.volume_up_rounded,
        ),
        tooltip: '音量',
        onPressed: () {
          if (controller.isOpen) {
            controller.close();
          } else {
            controller.open();
          }
        },
      ),
    );
  }

  Widget _buildSettings(BuildContext context, PlaybackSnapshot snapshot) {
    final theme = Theme.of(context);
    final engine = widget.engine;
    return Wrap(
      spacing: ReelvaDesign.space4,
      runSpacing: ReelvaDesign.space4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        _buildTrackMenu(
          context,
          menuKey: const Key('player_subtitle_track_button'),
          textKey: const Key('player_subtitle_track_text'),
          label: '字幕',
          tooltip: '字幕轨道',
          tracks: snapshot.subtitleTracks,
          selectedId: snapshot.subtitleTrackId,
          onSelected: engine.setSubtitleTrack,
          extraActions: {
            if (widget.onPickLocalSubtitle != null)
              '__local_subtitle': ('选择本地字幕', widget.onPickLocalSubtitle!),
            if (widget.onPickSourceSubtitle != null)
              '__source_subtitle': ('选择媒体源字幕', widget.onPickSourceSubtitle!),
          },
        ),
        _buildTrackMenu(
          context,
          menuKey: const Key('player_audio_track_button'),
          textKey: const Key('player_audio_track_text'),
          label: '音轨',
          tooltip: '音频轨道',
          tracks: snapshot.audioTracks,
          selectedId: snapshot.audioTrackId,
          onSelected: engine.setAudioTrack,
        ),
        PopupMenuButton<double>(
          key: const Key('player_rate_button'),
          tooltip: '播放倍速',
          initialValue: snapshot.rate,
          onOpened: () => widget.onInteractionChanged?.call(true),
          onCanceled: () => widget.onInteractionChanged?.call(false),
          onSelected: (rate) {
            widget.onInteractionChanged?.call(false);
            engine.setRate(rate);
          },
          itemBuilder: (context) => PlayerControls.supportedRates
              .map(
                (rate) => GlassPopupMenuItem<double>(
                  value: rate,
                  child: Text('${rate}x'),
                ),
              )
              .toList(),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
            child: Text(
              '${snapshot.rate}x',
              key: const Key('player_rate_text'),
              style: theme.textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTrackMenu(
    BuildContext context, {
    required Key menuKey,
    required Key textKey,
    required String label,
    required String tooltip,
    required List<PlaybackTrack> tracks,
    required String? selectedId,
    required ValueChanged<String> onSelected,
    Map<String, (String, VoidCallback)> extraActions = const {},
  }) {
    return PopupMenuButton<String>(
      key: menuKey,
      tooltip: tooltip,
      initialValue: selectedId,
      enabled: tracks.isNotEmpty || extraActions.isNotEmpty,
      onOpened: () => widget.onInteractionChanged?.call(true),
      onCanceled: () => widget.onInteractionChanged?.call(false),
      onSelected: (track) {
        widget.onInteractionChanged?.call(false);
        final action = extraActions[track];
        if (action != null) {
          action.$2();
        } else {
          onSelected(track);
        }
      },
      itemBuilder: (context) => [
        ...tracks.map(
          (track) => GlassPopupMenuItem<String>(
            value: track.id,
            child: Row(
              children: [
                Expanded(
                  child: Text(track.label, overflow: TextOverflow.ellipsis),
                ),
                if (track.id == selectedId) ...[
                  const SizedBox(width: ReelvaDesign.space8),
                  const Icon(Icons.check, size: 16),
                ],
              ],
            ),
          ),
        ),
        if (tracks.isNotEmpty && extraActions.isNotEmpty)
          const PopupMenuDivider(),
        ...extraActions.entries.map(
          (entry) => GlassPopupMenuItem<String>(
            value: entry.key,
            child: Text(entry.value.$1),
          ),
        ),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: ReelvaDesign.space8,
          vertical: ReelvaDesign.space12,
        ),
        child: Text(
          label,
          key: textKey,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
            color: tracks.isEmpty && extraActions.isEmpty
                ? Theme.of(context).disabledColor
                : Theme.of(context).colorScheme.onSurface,
          ),
        ),
      ),
    );
  }
}
