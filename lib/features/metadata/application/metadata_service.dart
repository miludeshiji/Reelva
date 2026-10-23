import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../../../core/logging/app_logger.dart';
import '../../library/infrastructure/media_library_repository.dart';
import '../domain/tmdb_models.dart';
import '../infrastructure/tmdb_client.dart';
import '../infrastructure/tmdb_token_store.dart';

/// 元数据批量刷新执行结果统计
@immutable
class MetadataRefreshResult {
  final int matched;
  final int needsReview;
  final int skipped;
  final List<String> errors;

  const MetadataRefreshResult({
    this.matched = 0,
    this.needsReview = 0,
    this.skipped = 0,
    this.errors = const [],
  });

  @override
  String toString() =>
      'MetadataRefreshResult(matched: $matched, needsReview: $needsReview, skipped: $skipped, errors: ${errors.length})';
}

/// 影视元数据核心应用服务
///
/// 职责：
/// 1. TMDB 搜索与置信度算法排序（标题、原名、别名、年份加权）
/// 2. 保守自动匹配（必须已知年份、置信度高且与第二名有显著胜出裕度；不确定/多集保留人工核对）
/// 3. 手动匹配绑定（抓取详情及所有季集分集，写入数据库并施加元数据锁，返回规范 ID）
/// 4. 批量刷新与并发互斥保护
/// 5. 本地元数据手工编辑与输入校验
class MetadataService {
  final TmdbClient tmdbClient;
  final MediaLibraryRepository mediaLibraryRepository;
  final TmdbTokenStore tokenStore;

  Future<MetadataRefreshResult>? _inFlightRefresh;
  final Set<int> _activeLocks = {};

  MetadataService({
    required this.tmdbClient,
    required this.mediaLibraryRepository,
    required this.tokenStore,
  });

  /// 搜索 TMDB 影视条目，按置信度排序返回候选列表
  Future<List<TmdbWork>> search(
    String query, {
    required String type,
    int? year,
  }) async {
    final cleanQuery = query.trim();
    if (cleanQuery.isEmpty) return const [];

    List<TmdbWork> rawCandidates;
    if (type == 'movie') {
      rawCandidates = await tmdbClient.searchMovie(cleanQuery, year: year);
    } else {
      rawCandidates = await tmdbClient.searchTv(cleanQuery, year: year);
    }

    if (rawCandidates.isEmpty) return const [];

    // 计算置信度得分并降序排序
    final scored = rawCandidates.map((candidate) {
      final score = computeMatchScore(
        query: cleanQuery,
        targetYear: year,
        candidate: candidate,
      );
      return MapEntry(candidate, score);
    }).toList();

    scored.sort((a, b) => b.value.compareTo(a.value));
    return scored.map((e) => e.key).toList();
  }

  /// 手动绑定元数据
  ///
  /// 1. 获取目标影视完整详情（含别名）
  /// 2. 若为电视剧，并发查询本地现存季号的完整分集列表
  /// 3. 事务应用元数据并打上手工锁，返回合并后的规范 ID
  Future<int> matchManually(
    int workId,
    TmdbWork candidate, {
    TmdbEpisode? episode,
  }) async {
    if (_activeLocks.contains(workId)) {
      throw const MetadataException(
        '当前影视正在处理中，请勿重复操作',
        code: 'concurrent_lock',
      );
    }
    _activeLocks.add(workId);

    try {
      final localWork = await mediaLibraryRepository.getWorkDetails(workId);
      if (localWork == null) {
        throw const MetadataException('未找到对应作品', code: 'work_not_found');
      }

      final isMovie = candidate.type == 'movie';
      final TmdbWork details;
      final List<TmdbEpisode> episodes = [];

      if (isMovie) {
        if (localWork.work.type == 'series' ||
            localWork.versions.any((v) => v.seasonNumber != null)) {
          throw const MetadataException(
            '无法将剧集作品变更为电影',
            code: 'incompatible_type',
          );
        }
        details = await tmdbClient.getMovieDetails(candidate.id);

        final canonicalId = await mediaLibraryRepository.applyMetadata(
          workId,
          details,
          manual: true,
        );
        return canonicalId;
      } else {
        if (localWork.work.type != 'series' && episode == null) {
          throw const MetadataException('未指定分集信息', code: 'episode_required');
        }

        if (await mediaLibraryRepository.hasMultiEpisodeFiles(workId)) {
          throw const MetadataException(
            '当前文件包含多集内容，暂不支持单集手动绑定',
            code: 'multi_episode_unsupported',
          );
        }

        details = await tmdbClient.getTvDetails(candidate.id);

        TmdbEpisode? targetEpisode;
        if (episode != null) {
          // 明确 episode 后只请求其实际 seasonNumber，检查 episodeNumber 确在 TMDB 返回列表
          final seasonEps = await tmdbClient.getTvSeasonEpisodes(
            candidate.id,
            episode.seasonNumber,
          );
          for (final ep in seasonEps) {
            if (ep.episodeNumber == episode.episodeNumber) {
              targetEpisode = ep;
              break;
            }
          }
          if (targetEpisode == null) {
            throw const MetadataException(
              '未在 TMDB 找到指定的季集',
              code: 'episode_not_found',
            );
          }
          episodes.addAll(seasonEps);
        } else {
          // 原有已确定 series 按已有季号获取，勿改为全量抓季
          final seasons = localWork.versions
              .map((v) => v.seasonNumber)
              .whereType<int>()
              .where((s) => s >= 0)
              .toSet();

          if (seasons.isEmpty) {
            seasons.add(1);
          }

          // 按季获取分集信息；若获取失败显式抛出异常，绝不静默吞掉伪装成完全成功
          for (final seasonNum in seasons) {
            final eps = await tmdbClient.getTvSeasonEpisodes(
              candidate.id,
              seasonNum,
            );
            episodes.addAll(eps);
          }
        }

        // 写入仓储并上锁
        final canonicalId = await mediaLibraryRepository.applyMetadata(
          workId,
          details,
          manual: true,
          episode: targetEpisode,
        );

        if (episodes.isNotEmpty) {
          await mediaLibraryRepository.applyEpisodeMetadata(
            canonicalId,
            episodes,
            manual: true,
          );
        }

        return canonicalId;
      }
    } finally {
      _activeLocks.remove(workId);
    }
  }

  /// 批量刷新未匹配影视元数据
  ///
  /// 先执行未识别待定文件提取，再对未锁定本地作品按高置信度保守自动匹配。
  /// 缺少密钥或离线不擦除已有数据与缓存。
  Future<MetadataRefreshResult> refresh() {
    if (_inFlightRefresh != null) {
      return _inFlightRefresh!;
    }
    _inFlightRefresh = _doRefresh().whenComplete(() {
      _inFlightRefresh = null;
    });
    return _inFlightRefresh!;
  }

  Future<MetadataRefreshResult> _doRefresh() async {
    int matched = 0;
    int needsReview = 0;
    int skipped = 0;
    final List<String> errors = [];

    // 1. 率先迁移未解析文件生成候选条目（失败显式传播）
    try {
      await mediaLibraryRepository.recognizePendingFiles();
    } catch (e, st) {
      AppLogger.instance.error('识别待处理文件失败', error: e, stackTrace: st);
      final msg = e is MetadataException ? e.message : '媒体库待处理文件识别失败';
      throw MetadataException(msg, code: 'recognition_error');
    }

    // 2. 检查凭据配置（isConfigured 会向上抛出 storage_error，由 controller/UI 捕获）
    final isConfigured = await tokenStore.isConfigured();
    if (!isConfigured) {
      return MetadataRefreshResult(
        skipped: skipped,
        needsReview: needsReview,
        errors: const ['未配置 TMDB API 密钥，仅完成本地识别'],
      );
    }

    // 3. 获取待匹配作品列表
    final pendingWorks = await mediaLibraryRepository.unmatchedWorks();
    if (pendingWorks.isEmpty) {
      return const MetadataRefreshResult();
    }

    for (final work in pendingWorks) {
      if (work.metadataLocked) {
        skipped++;
        continue;
      }

      // 年份未知或类型未知时保守不自动匹配，留作人工审核
      if (work.year == null || work.type == null) {
        needsReview++;
        continue;
      }

      try {
        final candidates = await search(
          work.title,
          type: work.type!,
          year: work.year,
        );

        if (candidates.isEmpty) {
          needsReview++;
          continue;
        }

        final top = candidates.first;
        final topScore = computeMatchScore(
          query: work.title,
          targetYear: work.year,
          candidate: top,
        );

        final runnerUpScore = candidates.length > 1
            ? computeMatchScore(
                query: work.title,
                targetYear: work.year,
                candidate: candidates[1],
              )
            : 0.0;

        // 严格高置信度判定：
        // 1. 年份必须相差 <= 1 年
        // 2. 综合得分 >= 0.85
        // 3. 必须有显著胜出优势（领先第二名 >= 0.15）
        final isYearMatched =
            top.year != null && (top.year! - work.year!).abs() <= 1;
        final isWinner =
            (topScore - runnerUpScore) >= 0.15 || candidates.length == 1;
        final isHighConfidence = isYearMatched && topScore >= 0.85 && isWinner;

        if (isHighConfidence) {
          // 抓取详情与分集
          final isMovie = work.type == 'movie';
          final TmdbWork details;
          final List<TmdbEpisode> episodes = [];

          if (isMovie) {
            details = await tmdbClient.getMovieDetails(top.id);
          } else {
            details = await tmdbClient.getTvDetails(top.id);
            final localWork = await mediaLibraryRepository.getWorkDetails(
              work.id,
            );
            final seasons =
                localWork?.versions
                    .map((v) => v.seasonNumber)
                    .whereType<int>()
                    .where((s) => s >= 0)
                    .toSet() ??
                {1};

            for (final seasonNum in seasons) {
              final eps = await tmdbClient.getTvSeasonEpisodes(
                top.id,
                seasonNum,
              );
              episodes.addAll(eps);
            }
          }

          // 自动应用元数据（不锁）
          final canonicalId = await mediaLibraryRepository.applyMetadata(
            work.id,
            details,
            manual: false,
          );

          if (episodes.isNotEmpty) {
            await mediaLibraryRepository.applyEpisodeMetadata(
              canonicalId,
              episodes,
              manual: false,
            );
          }

          matched++;
        } else {
          // 低置信度保守保留在待审核中，不污染数据
          needsReview++;
        }
      } on MetadataException catch (metaErr) {
        if (metaErr.code == 'unauthorized') {
          errors.add(metaErr.message);
          // 凭据无效直接中止后续请求
          break;
        } else if (metaErr.code == 'rate_limit') {
          errors.add(metaErr.message);
          break;
        } else {
          errors.add('${work.title}: ${metaErr.message}');
        }
      } catch (e) {
        errors.add('${work.title}: 匹配异常');
      }
    }
    return MetadataRefreshResult(
      matched: matched,
      needsReview: needsReview,
      skipped: skipped,
      errors: errors,
    );
  }

  static final RegExp _validPosterPathRegex = RegExp(
    r'^/[a-zA-Z0-9_\-]+\.(jpg|jpeg|png|webp)$',
    caseSensitive: false,
  );

  /// 本地手工编辑作品元数据（标题、年份、简介、海报相对路径），施加本地锁
  Future<void> editLocal(
    int workId, {
    required String title,
    int? year,
    String? overview,
    String? posterPath,
  }) async {
    final cleanTitle = title.trim();
    if (cleanTitle.isEmpty) {
      throw const MetadataException('标题不能为空', code: 'invalid_title');
    }

    if (year != null && (year < 1888 || year > 2100)) {
      throw const MetadataException('年份不合法 (1888-2100)', code: 'invalid_year');
    }

    String? cleanPosterPath;
    if (posterPath != null && posterPath.trim().isNotEmpty) {
      final trimmed = posterPath.trim();
      if (trimmed.contains('://') ||
          trimmed.startsWith('//') ||
          trimmed.contains('?') ||
          trimmed.contains('#') ||
          trimmed.contains('\\') ||
          trimmed.contains('..')) {
        throw const MetadataException(
          '海报路径无效：必须为 TMDB 单文件相对路径（如 /name.jpg），不支持完整 URL、查询参数或路径跳转',
          code: 'invalid_poster_path',
        );
      }

      final normalized = trimmed.startsWith('/') ? trimmed : '/$trimmed';
      if (!_validPosterPathRegex.hasMatch(normalized)) {
        throw const MetadataException(
          '海报路径格式无效：必须为 TMDB 单文件相对路径（如 /name.jpg、/name.png、/name.webp）',
          code: 'invalid_poster_path',
        );
      }
      cleanPosterPath = normalized;
    }

    await mediaLibraryRepository.editMetadata(
      workId,
      title: cleanTitle,
      year: year,
      overview: overview?.trim(),
      posterPath: cleanPosterPath,
    );
  }

  /// 综合置信度得分算法
  static double computeMatchScore({
    required String query,
    required int? targetYear,
    required TmdbWork candidate,
  }) {
    final cleanQuery = _normalize(query);
    if (cleanQuery.isEmpty) return 0.0;

    // 1. 标题相似度计算（兼顾中文名、原名及别名）
    double bestTitleSimilarity = _titleSimilarity(
      cleanQuery,
      _normalize(candidate.title),
    );

    if (candidate.originalTitle != null) {
      final origSim = _titleSimilarity(
        cleanQuery,
        _normalize(candidate.originalTitle!),
      );
      if (origSim > bestTitleSimilarity) {
        bestTitleSimilarity = origSim;
      }
    }

    for (final alias in candidate.aliases) {
      final aliasSim = _titleSimilarity(cleanQuery, _normalize(alias));
      if (aliasSim > bestTitleSimilarity) {
        bestTitleSimilarity = aliasSim;
      }
    }

    // 2. 年份匹配权重
    double yearScore = 0.5;
    if (targetYear != null && candidate.year != null) {
      final diff = (candidate.year! - targetYear).abs();
      if (diff == 0) {
        yearScore = 1.0;
      } else if (diff == 1) {
        yearScore = 0.75;
      } else if (diff == 2) {
        yearScore = 0.4;
      } else {
        yearScore = 0.0;
      }
    } else if (targetYear == null && candidate.year == null) {
      yearScore = 0.5;
    } else {
      yearScore = 0.3;
    }

    // 若年份完全不相符（跨度 > 2 年），标题得分大幅惩罚
    if (targetYear != null &&
        candidate.year != null &&
        (candidate.year! - targetYear).abs() > 2) {
      return (bestTitleSimilarity * 0.3).clamp(0.0, 1.0);
    }

    return (bestTitleSimilarity * 0.7 + yearScore * 0.3).clamp(0.0, 1.0);
  }

  static String _normalize(String s) {
    return s.toLowerCase().replaceAll(
      RegExp(r'[\s\-_\.:/\\,\(\)\[\]\{\}]+'),
      '',
    );
  }

  static double _titleSimilarity(String s1, String s2) {
    if (s1 == s2) return 1.0;
    if (s1.isEmpty || s2.isEmpty) return 0.0;

    if (s1.contains(s2) || s2.contains(s1)) {
      final minLen = math.min(s1.length, s2.length);
      final maxLen = math.max(s1.length, s2.length);
      return minLen / maxLen;
    }

    final dist = _levenshteinDistance(s1, s2);
    final maxLen = math.max(s1.length, s2.length);
    return (1.0 - (dist / maxLen)).clamp(0.0, 1.0);
  }

  static int _levenshteinDistance(String s1, String s2) {
    if (s1 == s2) return 0;
    if (s1.isEmpty) return s2.length;
    if (s2.isEmpty) return s1.length;

    List<int> v0 = List<int>.generate(s2.length + 1, (i) => i);
    List<int> v1 = List<int>.filled(s2.length + 1, 0);

    for (int i = 0; i < s1.length; i++) {
      v1[0] = i + 1;
      for (int j = 0; j < s2.length; j++) {
        final cost = (s1.codeUnitAt(i) == s2.codeUnitAt(j)) ? 0 : 1;
        v1[j + 1] = math.min(v1[j] + 1, math.min(v0[j + 1] + 1, v0[j] + cost));
      }
      for (int j = 0; j <= s2.length; j++) {
        v0[j] = v1[j];
      }
    }

    return v1[s2.length];
  }
}
