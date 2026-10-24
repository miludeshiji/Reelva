import 'dart:ui' show ImageFilter;

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

/// 深色视频区的玻璃控制面板；父页面为小高度视口提供滚动空间。
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
  });

  final PlaybackSnapshot snapshot;
  final PlayerEngine engine;
  final bool isFullscreen;
  final VoidCallback onToggleFullscreen;
  final String? title;
  final String? subtitle;
  final bool overlay;

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

  Widget _buildPlaybackAction(PlaybackSnapshot snapshot, PlayerEngine engine) {
    final style = IconButton.styleFrom(
      backgroundColor: Colors.white.withValues(alpha: 0.22),
      foregroundColor: Colors.white,
      disabledForegroundColor: Colors.white38,
      minimumSize: const Size(56, 56),
      iconSize: 28,
      shape: const CircleBorder(side: BorderSide(color: Colors.white54)),
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
          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
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
    // 独立挂载在浅色 MaterialApp 时也与深色控制面板保持一致。
    return Theme(
      data: ReelvaTheme.player,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final controls = _buildControls(context);
          return constraints.hasBoundedHeight
              ? SingleChildScrollView(child: controls)
              : controls;
        },
      ),
    );
  }

  Widget _buildControls(BuildContext context) {
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

    return ClipRRect(
      borderRadius: BorderRadius.circular(ReelvaDesign.radiusLarge),
      child: BackdropFilter(
        filter: ImageFilter.blur(
          sigmaX: isOverlay ? 16 : 0,
          sigmaY: isOverlay ? 16 : 0,
        ),
        child: Container(
          color: const Color(0xFF0E141C)
              .withValues(alpha: isOverlay ? 0.88 : 1),
          padding: EdgeInsets.all(
            isOverlay ? ReelvaDesign.space16 : ReelvaDesign.space24,
          ),
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
                      color: Colors.white,
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
              SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 4,
                  activeTrackColor: Colors.white,
                  inactiveTrackColor: const Color(0xFF536A73),
                  secondaryActiveTrackColor: const Color(0xFF96A8B1),
                  thumbColor: Colors.white,
                  overlayColor: Colors.white12,
                  thumbShape: const RoundSliderThumbShape(
                    enabledThumbRadius: 6,
                  ),
                  overlayShape: const RoundSliderOverlayShape(
                    overlayRadius: 14,
                  ),
                ),
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
                  onChanged: isSeekEnabled
                      ? (value) {
                          setState(() => _dragPositionMs = value);
                        }
                      : null,
                  onChangeEnd: isSeekEnabled
                      ? (value) {
                          setState(() => _dragPositionMs = null);
                          engine.seek(Duration(milliseconds: value.round()));
                        }
                      : null,
                ),
              ),
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                spacing: ReelvaDesign.space12,
                runSpacing: ReelvaDesign.space4,
                children: [
                  Text(
                    '$displayPosText / $totalDurText',
                    key: const Key('player_time_display_text'),
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: Colors.white,
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
              const SizedBox(height: ReelvaDesign.space20),
              GlassCard(
                blur: true,
                color: Colors.white.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(32),
                padding: const EdgeInsets.symmetric(
                  horizontal: ReelvaDesign.space16,
                  vertical: ReelvaDesign.space8,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    IconButton(
                      key: const Key('player_seek_back_button'),
                      icon: const Icon(Icons.replay_10_rounded),
                      tooltip: '后退 10 秒',
                      onPressed: isSeekEnabled
                          ? () {
                              final target =
                                  snapshot.position -
                                  const Duration(seconds: 10);
                              engine.seek(
                                target < Duration.zero ? Duration.zero : target,
                              );
                            }
                          : null,
                    ),
                    _buildPlaybackAction(snapshot, engine),
                    IconButton(
                      key: const Key('player_seek_forward_button'),
                      icon: const Icon(Icons.forward_10_rounded),
                      tooltip: '快进 10 秒',
                      onPressed: isSeekEnabled
                          ? () {
                              final target =
                                  snapshot.position +
                                  const Duration(seconds: 10);
                              engine.seek(
                                target > snapshot.duration
                                    ? snapshot.duration
                                    : target,
                              );
                            }
                          : null,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: ReelvaDesign.space12),
              Wrap(
                spacing: ReelvaDesign.space8,
                runSpacing: ReelvaDesign.space4,
                alignment: WrapAlignment.spaceBetween,
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
                    label: '音频',
                    tooltip: '音频轨道',
                    tracks: snapshot.audioTracks,
                    selectedId: snapshot.audioTrackId,
                    onSelected: engine.setAudioTrack,
                  ),
                  PopupMenuButton<double>(
                    key: const Key('player_rate_button'),
                    tooltip: '播放倍速',
                    initialValue: snapshot.rate,
                    onSelected: engine.setRate,
                    itemBuilder: (context) => PlayerControls.supportedRates
                        .map(
                          (r) => PopupMenuItem<double>(
                            value: r,
                            child: Text('${r}x'),
                          ),
                        )
                        .toList(),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: ReelvaDesign.space8,
                        vertical: ReelvaDesign.space12,
                      ),
                      child: Text(
                        '${snapshot.rate}x',
                        key: const Key('player_rate_text'),
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  IconButton(
                    key: const Key('player_fullscreen_button'),
                    icon: Icon(
                      widget.isFullscreen
                          ? Icons.fullscreen_exit_rounded
                          : Icons.fullscreen_rounded,
                    ),
                    tooltip: widget.isFullscreen ? '退出全屏' : '全屏',
                    onPressed: widget.onToggleFullscreen,
                  ),
                  IconButton(
                    key: const Key('player_stop_button'),
                    icon: const Icon(Icons.stop_rounded),
                    tooltip: '停止',
                    onPressed: snapshot.status == PlaybackStatus.idle
                        ? null
                        : engine.stop,
                  ),
                ],
              ),
              LayoutBuilder(
                builder: (context, constraints) => Align(
                  alignment: Alignment.centerLeft,
                  child: SizedBox(
                    width: constraints.maxWidth.clamp(0, 260).toDouble(),
                    child: Row(
                      children: [
                        IconButton(
                          key: const Key('player_mute_button'),
                          icon: Icon(
                            snapshot.volume == 0
                                ? Icons.volume_off_rounded
                                : Icons.volume_up_rounded,
                          ),
                          tooltip: snapshot.volume == 0 ? '取消静音' : '静音',
                          onPressed: _toggleMute,
                        ),
                        Expanded(
                          child: SliderTheme(
                            data: SliderTheme.of(context).copyWith(
                              trackHeight: 3,
                              activeTrackColor: Colors.white,
                              inactiveTrackColor: Colors.white24,
                              thumbColor: Colors.white,
                              overlayColor: Colors.white12,
                              thumbShape: const RoundSliderThumbShape(
                                enabledThumbRadius: 5,
                              ),
                            ),
                            child: Slider(
                              key: const Key('player_volume_slider'),
                              value: snapshot.volume.clamp(0.0, 100.0),
                              min: 0.0,
                              max: 100.0,
                              onChanged: engine.setVolume,
                            ),
                          ),
                        ),
                        Text(
                          '${snapshot.volume.round()}%',
                          key: const Key('player_volume_text'),
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: Colors.white,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
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
      onSelected: onSelected,
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
          style: Theme.of(context).textTheme.labelMedium
              ?.copyWith(color: tracks.isEmpty ? Colors.white38 : Colors.white),
        ),
      ),
    );
  }
}
