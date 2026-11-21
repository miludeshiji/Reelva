import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/logging/app_logger.dart';
import '../domain/subtitle_adjustment.dart';

class PlayerSubtitleAdjustmentPanel extends StatefulWidget {
  const PlayerSubtitleAdjustmentPanel({
    super.key,
    required this.adjustSubtitle,
  });

  final AdjustSubtitle adjustSubtitle;

  @override
  State<PlayerSubtitleAdjustmentPanel> createState() =>
      _PlayerSubtitleAdjustmentPanelState();
}

class _PlayerSubtitleAdjustmentPanelState
    extends State<PlayerSubtitleAdjustmentPanel> {
  SubtitleAdjustment? _values;
  bool _busy = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    unawaited(_refresh());
  }

  Future<void> _refresh([SubtitleAdjustmentAction? action]) async {
    if (_busy) return;
    setState(() => _busy = true);
    var values = _values;
    var failed = false;
    try {
      values = await widget.adjustSubtitle(
        action: action,
        mediaEpoch: values?.mediaEpoch,
      );
    } catch (error, stackTrace) {
      failed = true;
      AppLogger.instance.error('字幕校准失败', error: error, stackTrace: stackTrace);
    }
    if (!mounted) return;
    setState(() {
      _values = values;
      _busy = false;
      _failed = failed;
    });
  }

  Widget _adjustmentRow({
    required String label,
    required String value,
    required String decreaseLabel,
    required String increaseLabel,
    required SubtitleAdjustmentAction? decrease,
    required SubtitleAdjustmentAction? increase,
    IconData decreaseIcon = Icons.remove_rounded,
    IconData increaseIcon = Icons.add_rounded,
  }) => Row(
    children: [
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label),
            Text(value, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
      IconButton(
        tooltip: decreaseLabel,
        onPressed: _busy || decrease == null ? null : () => _refresh(decrease),
        icon: Icon(decreaseIcon),
      ),
      IconButton(
        tooltip: increaseLabel,
        onPressed: _busy || increase == null ? null : () => _refresh(increase),
        icon: Icon(increaseIcon),
      ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final values = _values;
    final scale = values?.scale;
    final position = values?.position;
    return ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.fromLTRB(20, 0, 12, 12),
      children: [
        if (values == null) ...[
          if (_busy)
            const Center(child: CircularProgressIndicator())
          else if (!_failed)
            const Text('请先选择字幕轨道'),
        ] else ...[
          _adjustmentRow(
            label: '时间偏移',
            value: switch (values.delay) {
              < 0 => '提前 ${values.delay.abs().toStringAsFixed(1)} 秒',
              > 0 => '延后 ${values.delay.toStringAsFixed(1)} 秒',
              _ => '0.0 秒',
            },
            decreaseLabel: '提前 0.1 秒',
            increaseLabel: '延后 0.1 秒',
            decrease: SubtitleAdjustmentAction.earlier,
            increase: SubtitleAdjustmentAction.later,
          ),
          if (scale != null)
            _adjustmentRow(
              label: '大小',
              value: '${(scale * 100).round()}%',
              decreaseLabel: '缩小字幕',
              increaseLabel: '放大字幕',
              decrease: scale > 0 ? SubtitleAdjustmentAction.smaller : null,
              increase: scale < 100 ? SubtitleAdjustmentAction.larger : null,
            ),
          if (position != null)
            _adjustmentRow(
              label: '位置',
              value: '${position.round()}%',
              decreaseLabel: '上移字幕',
              increaseLabel: '下移字幕',
              decrease: position > 0 ? SubtitleAdjustmentAction.up : null,
              increase: position < 150 ? SubtitleAdjustmentAction.down : null,
              decreaseIcon: Icons.arrow_upward_rounded,
              increaseIcon: Icons.arrow_downward_rounded,
            ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: _busy
                  ? null
                  : () => _refresh(SubtitleAdjustmentAction.reset),
              child: const Text('恢复默认'),
            ),
          ),
        ],
        if (_failed)
          Row(
            children: [
              const Expanded(child: Text('字幕校准失败')),
              TextButton(
                onPressed: _busy ? null : () => _refresh(),
                child: const Text('重试'),
              ),
            ],
          ),
      ],
    );
  }
}
