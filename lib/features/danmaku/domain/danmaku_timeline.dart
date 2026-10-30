import 'danmaku.dart';

/// 按真实时间戳推进游标；定位使用二分查找，不回放跳过的弹幕。
class DanmakuTimeline {
  DanmakuTimeline(this.comments);
  final List<DanmakuComment> comments;
  int _index = 0;
  final Map<String, int> _recent = {};
  int _densitySecond = -1;
  int _densityCount = 0;
  bool get finished => _index >= comments.length;

  void seek(int timeMs) {
    var low = 0;
    var high = comments.length;
    while (low < high) {
      final mid = (low + high) ~/ 2;
      if (comments[mid].timeMs < timeMs) {
        low = mid + 1;
      } else {
        high = mid;
      }
    }
    _index = low;
    _recent.clear();
    _densitySecond = -1;
    _densityCount = 0;
  }

  Iterable<DanmakuComment> takeThrough(
    int timeMs,
    DanmakuSettings settings,
  ) sync* {
    while (_index < comments.length && comments[_index].timeMs <= timeMs) {
      final comment = comments[_index++];
      if ((!settings.showTop && comment.mode == 5) ||
          (!settings.showBottom && comment.mode == 4) ||
          (!settings.showBilibili && comment.bilibili) ||
          (!settings.showOther && !comment.bilibili)) {
        continue;
      }
      final second = comment.timeMs ~/ 1000;
      if (_densitySecond != second) {
        _densitySecond = second;
        _densityCount = 0;
        _recent.removeWhere((text, time) => comment.timeMs - time > 1500);
      }
      if (_densityCount >= settings.density) continue;
      final text = comment.text.trim();
      final previous = _recent[text];
      if (previous != null && comment.timeMs - previous < 1500) continue;
      _recent[text] = comment.timeMs;
      _densityCount++;
      yield comment;
    }
  }
}
