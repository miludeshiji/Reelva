import 'package:flutter_test/flutter_test.dart';
import 'package:reelva/features/danmaku/domain/danmaku.dart';
import 'package:reelva/features/danmaku/domain/danmaku_timeline.dart';
import 'package:reelva/features/danmaku/infrastructure/danmaku_api.dart';

import 'danmaku_fakes.dart';

void main() {
  const show = DanmakuShow(
    source: DanmakuSource.dandanplay,
    id: '1',
    title: 'Example',
  );
  test('只挂载唯一的正确分集，编号来自接口', () {
    expect(
      matchDanmakuEpisode(testDanmakuQuery, show, [testDanmakuEpisode])?.id,
      '10001',
    );
    expect(
      matchDanmakuEpisode(testDanmakuQuery, show, [
        testDanmakuEpisode,
        testDanmakuEpisode,
      ]),
      isNull,
    );
    expect(
      matchDanmakuEpisode(
        testDanmakuQuery,
        const DanmakuShow(
          source: DanmakuSource.dandanplay,
          id: '2',
          title: 'Other',
        ),
        [testDanmakuEpisode],
      ),
      isNull,
    );
  });
  test('TMDB 关联仍需区分季度，特别篇与多集文件不自动猜测', () {
    const query = DanmakuQuery(
      title: 'Example',
      fileName: '',
      contentKey: 'x',
      versionKey: 'x',
      season: 2,
      episode: 1,
    );
    expect(matchDanmakuEpisode(query, show, [testDanmakuEpisode]), isNull);
    for (final title in [
      'Example 第二季',
      'Example Season 2',
      'Example 2nd Season',
      'Example 第2期',
    ]) {
      final season = DanmakuShow(
        source: DanmakuSource.dandanplay,
        id: '2',
        title: title,
      );
      expect(
        matchDanmakuEpisode(query, season, [testDanmakuEpisode]),
        testDanmakuEpisode,
        reason: title,
      );
    }
    const special = DanmakuQuery(
      title: 'Example',
      fileName: '',
      contentKey: 'x',
      versionKey: 'x',
      season: 0,
      episode: 1,
    );
    expect(matchDanmakuEpisode(special, show, [testDanmakuEpisode]), isNull);
    const ambiguous = DanmakuQuery(
      title: 'Example',
      fileName: '',
      contentKey: 'x',
      versionKey: 'x',
      season: 1,
      episode: 1,
      ambiguous: true,
    );
    expect(matchDanmakuEpisode(ambiguous, show, [testDanmakuEpisode]), isNull);
  });
  test('分集解析保留整数与特别篇边界', () {
    expect(danmakuEpisodeNumber('第12话 标题'), 12);
    expect(danmakuEpisodeNumber('12 标题'), 12);
    expect(danmakuEpisodeNumber('12.5'), isNull);
    expect(danmakuEpisodeNumber('SP1'), isNull);
  });
  test('解析聚合来源、毫秒和颜色，忽略无效或不支持的弹幕', () {
    final comments = parseDanmakuBody((
      DanmakuSource.dandanplay,
      '{"comments":[{"p":"2.75,5,16711680,[BiliBili]123","m":"hello"},{"p":"1,1,255,42","m":"first"},{"p":"NaN,1,1,1","m":"bad"},{"p":"-1,1,1,1","m":"bad"},{"p":"3,7,1,1","m":"advanced"}]}',
    ));
    expect(comments.map((comment) => comment.timeMs), [1000, 2750]);
    expect(comments.last.color, 0xff0000);
    expect(comments.last.bilibili, isTrue);
    expect(comments.first.bilibili, isFalse);
    final bili = parseDanmakuBody((
      DanmakuSource.bilibili,
      '<i><d p="1.125,4,25,65280,0,0,user,1">a &amp; b</d></i>',
    ));
    expect(bili.single.timeMs, 1125);
    expect(bili.single.text, 'a & b');
    expect(bili.single.color, 0x00ff00);
  });
  test('时间轴覆盖倍速跨过的区间，定位不倾倒跳过的弹幕', () {
    final timeline = DanmakuTimeline([
      for (var i = 0; i < 10; i++) DanmakuComment(timeMs: i * 100, text: '$i'),
    ]);
    const settings = DanmakuSettings();
    expect(timeline.takeThrough(300, settings).map((comment) => comment.text), [
      '0',
      '1',
      '2',
      '3',
    ]);
    expect(timeline.takeThrough(600, settings).map((comment) => comment.text), [
      '4',
      '5',
      '6',
    ]);
    expect(timeline.takeThrough(600, settings), isEmpty);
    timeline.seek(850);
    expect(timeline.takeThrough(900, settings).map((comment) => comment.text), [
      '9',
    ]);
    timeline.seek(200);
    expect(timeline.takeThrough(200, settings).single.text, '2');
  });
  test('密度、重复内容与来源筛选不积压到下一秒', () {
    final timeline = DanmakuTimeline([
      const DanmakuComment(timeMs: 0, text: 'same'),
      const DanmakuComment(timeMs: 1, text: 'same', bilibili: true),
      const DanmakuComment(timeMs: 2, text: 'bili', bilibili: true),
      const DanmakuComment(timeMs: 3, text: 'top', mode: 5),
      const DanmakuComment(timeMs: 4, text: 'other'),
      const DanmakuComment(timeMs: 1000, text: 'next'),
    ]);
    const settings = DanmakuSettings(
      density: 1,
      showBilibili: false,
      showTop: false,
    );
    expect(
      timeline.takeThrough(2000, settings).map((comment) => comment.text),
      ['same', 'next'],
    );
  });
}
