import 'package:flutter/material.dart';

import '../domain/playback_snapshot.dart';
import '../domain/player_engine.dart';

/// 格式化时长为分:秒或时:分:秒
String formatDuration(Duration d) {
  if (d < Duration.zero) return '00:00';
  final hours = d.inHours;
  final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
  final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  if (hours > 0) {
    return '$hours:$minutes:$seconds';
  }
  return '$minutes:$seconds';
}

/// 播放器底部控制面板
///
/// 包含播放/暂停/重播/停止、进度预览跳转、时长与缓冲行分离、倍速选择（.5/1/1.25/1.5/2/3）、
/// 音量调节与静音记忆恢复、全屏切换。
/// 采用 Wrap 响应式多行折行并保证全屏及核心按钮均可见，彻底防止大字体及窄屏溢出。
class PlayerControls extends StatefulWidget {
  const PlayerControls({
    super.key,
    required this.snapshot,
    required this.engine,
    required this.isFullscreen,
    required this.onToggleFullscreen,
  });

  final PlaybackSnapshot snapshot;
  final PlayerEngine engine;
  final bool isFullscreen;
  final VoidCallback onToggleFullscreen;

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
    PlaybackSnapshot snapshot,
    PlayerEngine engine,
    bool isFullscreen,
  ) {
    final color = isFullscreen ? Colors.white : null;

    if (snapshot.status == PlaybackStatus.completed) {
      return IconButton(
        key: const Key('player_replay_button'),
        icon: const Icon(Icons.replay),
        tooltip: '重新播放',
        color: color,
        onPressed: () async {
          await engine.seek(Duration.zero);
          await engine.play();
        },
      );
    }

    if (snapshot.status == PlaybackStatus.resolving ||
        snapshot.status == PlaybackStatus.opening) {
      return const IconButton(
        key: Key('player_play_button'),
        icon: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        tooltip: '正在准备',
        onPressed: null,
      );
    }

    if (snapshot.status == PlaybackStatus.error ||
        snapshot.status == PlaybackStatus.idle) {
      return IconButton(
        key: const Key('player_play_button'),
        icon: const Icon(Icons.play_arrow),
        tooltip: '不可播放',
        color: color?.withValues(alpha: 0.4),
        onPressed: null,
      );
    }

    if (snapshot.isPlaying) {
      return IconButton(
        key: const Key('player_pause_button'),
        icon: const Icon(Icons.pause),
        tooltip: '暂停',
        color: color,
        onPressed: engine.pause,
      );
    }

    return IconButton(
      key: const Key('player_play_button'),
      icon: const Icon(Icons.play_arrow),
      tooltip: '播放',
      color: color,
      onPressed: engine.play,
    );
  }

  @override
  Widget build(BuildContext context) {
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
    final bufferText = '缓冲: ${formatDuration(snapshot.buffered)}';

    return Container(
      decoration: BoxDecoration(
        color: widget.isFullscreen
            ? Colors.black.withValues(alpha: 0.85)
            : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.95),
        borderRadius: widget.isFullscreen
            ? null
            : const BorderRadius.vertical(top: Radius.circular(12)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 0. 非致命保存错误提示栏
          if (snapshot.progressErrorMessage != null &&
              snapshot.progressErrorMessage!.isNotEmpty)
            Container(
              key: const Key('player_progress_error_banner'),
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: theme.colorScheme.errorContainer.withValues(alpha: 0.85),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.warning_amber_rounded,
                    size: 16,
                    color: theme.colorScheme.onErrorContainer,
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      snapshot.progressErrorMessage!,
                      key: const Key('player_progress_error_text'),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onErrorContainer,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          // 1. 时长与缓冲时间独立行（防止大字体下与 SeekSlider 挤压溢出）
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '$displayPosText / $totalDurText',
                key: const Key('player_time_display_text'),
                style: theme.textTheme.labelMedium?.copyWith(
                  color: widget.isFullscreen ? Colors.white : null,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              Text(
                bufferText,
                key: const Key('player_buffer_text'),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: widget.isFullscreen
                      ? Colors.white70
                      : theme.colorScheme.outline,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),

          // 2. 独立完整宽度的 SeekSlider，支持拖动预览与释放触发单个 Seek 操作
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 4,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
            ),
            child: Slider(
              key: const Key('player_seek_slider'),
              value: displayPosMs.clamp(0.0, totalDurationMs),
              min: 0.0,
              max: totalDurationMs,
              // secondaryTrackValue 与 min/max 同为毫秒单位
              secondaryTrackValue: hasKnownDuration
                  ? snapshot.buffered.inMilliseconds
                        .clamp(0, totalDurationMs.toInt())
                        .toDouble()
                  : null,
              onChanged: isSeekEnabled
                  ? (value) {
                      setState(() {
                        _dragPositionMs = value;
                      });
                    }
                  : null,
              onChangeEnd: isSeekEnabled
                  ? (value) {
                      final targetMs = value.round();
                      setState(() {
                        _dragPositionMs = null;
                      });
                      engine.seek(Duration(milliseconds: targetMs));
                    }
                  : null,
            ),
          ),

          const SizedBox(height: 2),

          // 3. 底部控制按钮组：采用 Wrap 响应式多行折行，杜绝把全屏按钮推出屏幕外
          Wrap(
            spacing: 12,
            runSpacing: 4,
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              // 播放/暂停/重播与停止按钮组
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildPlaybackAction(snapshot, engine, widget.isFullscreen),
                  IconButton(
                    key: const Key('player_stop_button'),
                    icon: const Icon(Icons.stop),
                    tooltip: '停止',
                    color: widget.isFullscreen ? Colors.white : null,
                    onPressed: snapshot.status == PlaybackStatus.idle
                        ? null
                        : engine.stop,
                  ),
                ],
              ),

              // 静音与音量调节滑动条组
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    key: const Key('player_mute_button'),
                    icon: Icon(
                      snapshot.volume == 0 ? Icons.volume_off : Icons.volume_up,
                    ),
                    tooltip: snapshot.volume == 0 ? '取消静音' : '静音',
                    color: widget.isFullscreen ? Colors.white : null,
                    onPressed: _toggleMute,
                  ),
                  SizedBox(
                    width: 80,
                    child: SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        trackHeight: 3,
                        thumbShape: const RoundSliderThumbShape(
                          enabledThumbRadius: 5,
                        ),
                      ),
                      child: Slider(
                        key: const Key('player_volume_slider'),
                        value: snapshot.volume.clamp(0.0, 100.0),
                        min: 0.0,
                        max: 100.0,
                        onChanged: (val) => engine.setVolume(val),
                      ),
                    ),
                  ),
                  Text(
                    '${snapshot.volume.round()}%',
                    key: const Key('player_volume_text'),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: widget.isFullscreen ? Colors.white : null,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),

              // 音频与字幕轨道选择组
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  PopupMenuButton<String>(
                    key: const Key('player_audio_track_button'),
                    tooltip: '音频轨道',
                    initialValue: snapshot.audioTrackId,
                    enabled: snapshot.audioTracks.isNotEmpty,
                    onSelected: (id) => engine.setAudioTrack(id),
                    itemBuilder: (context) => snapshot.audioTracks
                        .map(
                          (t) => PopupMenuItem<String>(
                            value: t.id,
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    t.label,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                if (t.id == snapshot.audioTrackId) ...[
                                  const SizedBox(width: 8),
                                  const Icon(Icons.check, size: 16),
                                ],
                              ],
                            ),
                          ),
                        )
                        .toList(),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 4,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.audiotrack,
                            size: 18,
                            color: widget.isFullscreen ? Colors.white : null,
                          ),
                          const SizedBox(width: 2),
                          Text(
                            '音频',
                            key: const Key('player_audio_track_text'),
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: widget.isFullscreen ? Colors.white : null,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  PopupMenuButton<String>(
                    key: const Key('player_subtitle_track_button'),
                    tooltip: '字幕轨道',
                    initialValue: snapshot.subtitleTrackId,
                    enabled: snapshot.subtitleTracks.isNotEmpty,
                    onSelected: (id) => engine.setSubtitleTrack(id),
                    itemBuilder: (context) => snapshot.subtitleTracks
                        .map(
                          (t) => PopupMenuItem<String>(
                            value: t.id,
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    t.label,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                if (t.id == snapshot.subtitleTrackId) ...[
                                  const SizedBox(width: 8),
                                  const Icon(Icons.check, size: 16),
                                ],
                              ],
                            ),
                          ),
                        )
                        .toList(),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 4,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.subtitles,
                            size: 18,
                            color: widget.isFullscreen ? Colors.white : null,
                          ),
                          const SizedBox(width: 2),
                          Text(
                            '字幕',
                            key: const Key('player_subtitle_track_text'),
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: widget.isFullscreen ? Colors.white : null,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),

              // 倍速与全屏控制组
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  PopupMenuButton<double>(
                    key: const Key('player_rate_button'),
                    tooltip: '播放倍速',
                    initialValue: snapshot.rate,
                    onSelected: (rate) => engine.setRate(rate),
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
                        horizontal: 6,
                        vertical: 4,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.speed,
                            size: 18,
                            color: widget.isFullscreen ? Colors.white : null,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '${snapshot.rate}x',
                            key: const Key('player_rate_text'),
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: widget.isFullscreen ? Colors.white : null,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    key: const Key('player_fullscreen_button'),
                    icon: Icon(
                      widget.isFullscreen
                          ? Icons.fullscreen_exit
                          : Icons.fullscreen,
                    ),
                    tooltip: widget.isFullscreen ? '退出全屏' : '全屏',
                    color: widget.isFullscreen ? Colors.white : null,
                    onPressed: widget.onToggleFullscreen,
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}
