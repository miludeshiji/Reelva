import 'tmdb_models.dart';

enum MatchReason {
  noTitleEvidence('缺少可用的作品标题'),
  noCandidates('未找到 TMDB 候选，可尝试其他标题'),
  candidateAmbiguous('候选相近或标题证据不足，需要确认作品'),
  yearConflict('候选首播或上映年份与本地信息不一致'),
  typeConflict('候选类型与文件中的电影或剧集信息不一致'),
  episodeMappingUnverified('季集编号尚未核实，请确认所属季和集号'),
  specialUnverified('特别篇或多集内容需要手动确认对应关系'),
  extraMedia('附属视频已跳过自动匹配，可在媒体源中查看和播放');

  const MatchReason(this.message);
  final String message;
}

class MatchDecision {
  const MatchDecision({
    this.automatic,
    this.reason,
    this.candidates = const [],
  });

  final TmdbWork? automatic;
  final MatchReason? reason;
  final List<TmdbWork> candidates;
}
