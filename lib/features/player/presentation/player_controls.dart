import 'package:flutter/material.dart';

import '../../../app/theme/reelva_theme.dart';
import '../../../shared/widgets/glass_widgets.dart';
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

/// 视频内使用深色玻璃浮层，视频下方使用与首页一致的浅色玻璃卡片。
class PlayerControls extends StatefulWidget {
  const PlayerControls({
    super.key,
    required this.snapshot,
    required this.engine,
    required this.isFullscreen,
    required this.onToggleFullscreen,
    this.title,
    this.subtitle,
    this.overlay = false,
    this.onInteractionChanged,
  });

  final PlaybackSnapshot snapshot;
  final PlayerEngine engine;
  final bool isFullscreen;
  final VoidCallback onToggleFullscreen;
  final String? title;
  final String? subtitle;
  final bool overlay;
  final ValueChanged<bool>? onInteractionChanged;

  static const List<double> supportedRates = [0.5, 1.0, 1.25, 1.5, 2.0, 3.0];

  @override
  State<PlayerControls> createState() => _PlayerControlsState();
}

class _PlayerControlsState extends State<PlayerControls> {
  double _lastNonZeroVolume = 100.0;
  double? _dragPositionMs;

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

  void _toggleMute() {
    if (widget.snapshot.volume > 0) {
      _lastNonZeroVolume = widget.snapshot.volume;
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
      backgroundColor: scheme.primary,
      foregroundColor: scheme.onPrimary,
      disabledBackgroundColor: scheme.primary.withValues(alpha: 0.12),
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
          final controls = _buildControls(context, constraints.maxWidth < 640);
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
    final isOverlay = widget.overlay || widget.isFullscreen;
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
    final mute = IconButton(
      key: const Key('player_mute_button'),
      icon: Icon(
        snapshot.volume == 0
            ? Icons.volume_off_rounded
            : Icons.volume_up_rounded,
      ),
      tooltip: snapshot.volume == 0 ? '取消静音' : '静音',
      onPressed: _toggleMute,
    );
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
    final volume = SizedBox(
      width: compact ? 136 : 144,
      child: Row(
        children: [
          Expanded(
            child: Slider(
              key: const Key('player_volume_slider'),
              value: snapshot.volume.clamp(0.0, 100.0),
              max: 100.0,
              onChangeStart: (_) => widget.onInteractionChanged?.call(true),
              onChanged: engine.setVolume,
              onChangeEnd: (_) => widget.onInteractionChanged?.call(false),
            ),
          ),
          Text(
            '${snapshot.volume.round()}%',
            key: const Key('player_volume_text'),
            style: theme.textTheme.labelSmall?.copyWith(
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
    final tools = Wrap(
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
                (rate) =>
                    PopupMenuItem<double>(value: rate, child: Text('${rate}x')),
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
        if (!compact) mute,
        IconButton(
          key: const Key('player_stop_button'),
          icon: const Icon(Icons.stop_rounded),
          tooltip: '停止',
          onPressed: snapshot.status == PlaybackStatus.idle
              ? null
              : engine.stop,
        ),
        volume,
        if (!compact) fullscreen,
      ],
    );

    return IconButtonTheme(
      data: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: theme.colorScheme.onSurface,
          minimumSize: const Size(40, 40),
          padding: const EdgeInsets.all(8),
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
        child: GlassCard(
          blur: true,
          color: isOverlay
              ? ReelvaDesign.playerBackground.withValues(alpha: 0.64)
              : Colors.white.withValues(alpha: 0.84),
          borderRadius: BorderRadius.circular(22),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (snapshot.progressErrorMessage != null &&
                  snapshot.progressErrorMessage!.isNotEmpty)
                Container(
                  key: const Key('player_progress_error_banner'),
                  margin: const EdgeInsets.only(bottom: ReelvaDesign.space12),
                  padding: const EdgeInsets.all(ReelvaDesign.space12),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.errorContainer,
                    borderRadius: BorderRadius.circular(
                      ReelvaDesign.radiusSmall,
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.warning_amber_rounded,
                        size: 20,
                        color: theme.colorScheme.onErrorContainer,
                      ),
                      const SizedBox(width: ReelvaDesign.space8),
                      Expanded(
                        child: Text(
                          snapshot.progressErrorMessage!,
                          key: const Key('player_progress_error_text'),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onErrorContainer,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              if (widget.title != null) ...[
                Text(
                  '当前播放',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: ReelvaDesign.space8),
                RichText(
                  key: const Key('player_now_playing_title'),
                  textScaler: MediaQuery.textScalerOf(context),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  text: TextSpan(
                    text: widget.title,
                    style: theme.textTheme.titleLarge?.copyWith(
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                ),
                if (widget.subtitle != null) ...[
                  const SizedBox(height: ReelvaDesign.space4),
                  Text(
                    widget.subtitle!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
                const SizedBox(height: ReelvaDesign.space16),
              ],
              Row(
                children: [
                  Expanded(
                    child: Slider(
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
                          ? (value) {
                              setState(() => _dragPositionMs = value);
                            }
                          : null,
                      onChangeEnd: isSeekEnabled
                          ? (value) {
                              setState(() => _dragPositionMs = null);
                              engine.seek(
                                Duration(milliseconds: value.round()),
                              );
                              widget.onInteractionChanged?.call(false);
                            }
                          : null,
                    ),
                  ),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '$displayPosText / $totalDurText',
                        key: const Key('player_time_display_text'),
                        style: theme.textTheme.labelMedium?.copyWith(
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                      Text(
                        '缓冲: ${formatDuration(snapshot.buffered)}',
                        key: const Key('player_buffer_text'),
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: ReelvaDesign.space4),
              if (compact) ...[
                Row(children: [transport, const Spacer(), mute, fullscreen]),
                const SizedBox(height: ReelvaDesign.space4),
                tools,
              ] else
                Row(children: [transport, const Spacer(), tools]),
            ],
          ),
        ),
      ),
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
  }) {
    return PopupMenuButton<String>(
      key: menuKey,
      tooltip: tooltip,
      initialValue: selectedId,
      enabled: tracks.isNotEmpty,
      onOpened: () => widget.onInteractionChanged?.call(true),
      onCanceled: () => widget.onInteractionChanged?.call(false),
      onSelected: (track) {
        widget.onInteractionChanged?.call(false);
        onSelected(track);
      },
      itemBuilder: (context) => tracks
          .map(
            (track) => PopupMenuItem<String>(
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
          )
          .toList(),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: ReelvaDesign.space8,
          vertical: ReelvaDesign.space12,
        ),
        child: Text(
          label,
          key: textKey,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
            color: tracks.isEmpty
                ? Theme.of(context).disabledColor
                : Theme.of(context).colorScheme.onSurface,
          ),
        ),
      ),
    );
  }
}
