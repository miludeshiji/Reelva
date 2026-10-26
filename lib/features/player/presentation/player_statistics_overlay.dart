import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/logging/app_logger.dart';
import '../domain/playback_statistics.dart';
import '../domain/player_engine.dart';

class PlayerStatisticsOverlay extends StatefulWidget {
  const PlayerStatisticsOverlay({
    super.key,
    required this.engine,
    required this.onClose,
  });

  final PlayerEngine engine;
  final VoidCallback onClose;

  @override
  State<PlayerStatisticsOverlay> createState() =>
      _PlayerStatisticsOverlayState();
}

class _PlayerStatisticsOverlayState extends State<PlayerStatisticsOverlay> {
  PlaybackStatistics? _statistics;
  Timer? _timer;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    unawaited(_refresh());
  }

  Future<void> _refresh() async {
    try {
      final statistics = await widget.engine.getStatistics();
      if (!mounted) return;
      setState(() {
        _statistics = statistics;
        _failed = false;
      });
    } catch (error, stack) {
      if (!mounted) return;
      if (!_failed) {
        AppLogger.instance.error('读取播放信息失败', error: error, stackTrace: stack);
      }
      setState(() => _failed = true);
    } finally {
      if (mounted) _timer = Timer(const Duration(seconds: 1), _refresh);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String _number(num? value, String unit, {int digits = 2}) =>
      value == null ? '—' : '${value.toStringAsFixed(digits)} $unit';

  String _bitrate(double? value) => value == null
      ? '—'
      : value >= 1000000
      ? _number(value / 1000000, 'Mbps')
      : _number(value / 1000, 'kbps');

  Widget _row(String label, String? value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 5,
          child: Text(label, style: const TextStyle(color: Colors.white70)),
        ),
        const SizedBox(width: 12),
        Expanded(flex: 7, child: Text(value ?? '—')),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final stats = _statistics;
    final color = [
      ?stats?.colorMatrix,
      ?stats?.colorPrimaries,
      ?stats?.colorTransfer,
    ].join(' / ');
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 440),
      child: Material(
        color: Colors.black.withValues(alpha: 0.78),
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(12),
          child: DefaultTextStyle(
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              height: 1.4,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        '播放信息',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: widget.onClose,
                      tooltip: '关闭播放信息',
                      icon: const Icon(Icons.close, size: 18),
                      visualDensity: VisualDensity.compact,
                    ),
                  ],
                ),
                if (_failed)
                  const Text('暂时无法读取播放信息')
                else if (stats == null)
                  const Text('读取播放信息…'),
                if (stats != null) ...[
                  _row('视频编码', stats.videoCodec),
                  _row(
                    '分辨率',
                    stats.width == null || stats.height == null
                        ? null
                        : '${stats.width} × ${stats.height}',
                  ),
                  _row('帧率', _number(stats.frameRate, 'fps', digits: 3)),
                  _row('像素格式', stats.pixelFormat),
                  _row('色彩', color.isEmpty ? null : color),
                  _row('视频码率', _bitrate(stats.videoBitrate)),
                  _row(
                    '硬件解码',
                    stats.hardwareDecoder == 'no'
                        ? '软件解码'
                        : stats.hardwareDecoder,
                  ),
                  _row(
                    '渲染 / 解码丢帧',
                    '${stats.droppedFrames ?? '—'} / ${stats.decoderDroppedFrames ?? '—'}',
                  ),
                  _row('音频编码', stats.audioCodec),
                  _row(
                    '采样率',
                    _number(
                      stats.audioSampleRate == null
                          ? null
                          : stats.audioSampleRate! / 1000,
                      'kHz',
                    ),
                  ),
                  _row('声道', stats.audioChannels),
                  _row('音频码率', _bitrate(stats.audioBitrate)),
                  _row('音画同步差', _number(stats.audioVideoSync, '秒', digits: 3)),
                  _row('缓存时长', _number(stats.cacheSeconds, '秒')),
                  _row(
                    '缓存大小',
                    _number(
                      stats.cacheBytes == null
                          ? null
                          : stats.cacheBytes! / (1024 * 1024),
                      'MiB',
                    ),
                  ),
                  _row(
                    '读取速度',
                    _number(
                      stats.cacheSpeed == null
                          ? null
                          : stats.cacheSpeed! / (1024 * 1024),
                      'MiB/s',
                    ),
                  ),
                  _row('播放速度', '${widget.engine.snapshot.rate}×'),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
