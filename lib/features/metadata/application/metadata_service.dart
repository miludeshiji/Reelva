import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../../../core/logging/app_logger.dart';
import '../../library/infrastructure/media_library_repository.dart';
import '../domain/matching_file.dart';
import '../domain/match_decision.dart';
import '../domain/media_filename_parser.dart';
import '../domain/tmdb_models.dart';
import '../infrastructure/tmdb_client.dart';
import '../infrastructure/tmdb_token_store.dart';

enum MetadataPhase { recognizing, matching }

/// 元数据批量刷新执行结果统计
@immutable
class MetadataRefreshResult {
  final int matched;
  final int needsReview;
  final int skipped;
  final List<String> errors;
  final bool localOnly;
  final Map<MatchReason, int> reviewReasons;

  const MetadataRefreshResult({
    this.matched = 0,
    this.needsReview = 0,
    this.skipped = 0,
    this.errors = const [],
    this.localOnly = false,
    this.reviewReasons = const {},
  });

  @override
  String toString() =>
      'MetadataRefreshResult(matched: $matched, needsReview: $needsReview, skipped: $skipped, errors: ${errors.length})';
}

/// 影视元数据核心应用服务
///
/// 职责：
/// 1. TMDB 搜索与置信度算法排序（标题、原名、别名、年份加权）
/// 2. 多标题召回与详情身份核验；年份缺失仍可检索，不确定季集保留人工核对
/// 3. 手动匹配绑定（抓取详情及所有季集分集，写入数据库并施加元数据锁，返回规范 ID）
/// 4. 批量刷新与并发互斥保护
/// 5. 本地元数据手工编辑与输入校验
class MetadataService {
  final TmdbClient tmdbClient;
  final MediaLibraryRepository mediaLibraryRepository;
  final TmdbTokenStore tokenStore;
  final Future<void> Function({
    int? workId,
    List<int>? fileIds,
    bool replaceIdentity,
  })?
  saveMetadataFiles;

  Future<MetadataRefreshResult>? _inFlightRefresh;
  final Set<int> _activeLocks = {};
  static const int _automaticConcurrency = 4;
  Future<void> _automaticWrites = Future.value();

  MetadataService({
    required this.tmdbClient,
    required this.mediaLibraryRepository,
    required this.tokenStore,
    this.saveMetadataFiles,
  });

  /// 搜索 TMDB 影视条目，按置信度排序返回候选列表
  Future<List<TmdbWork>> search(String query, {String? type, int? year}) async {
    final cleanQuery = query.trim();
    if (cleanQuery.isEmpty) return const [];

    List<TmdbWork> rawCandidates;
    if (type == 'movie') {
      rawCandidates = await tmdbClient.searchMovie(cleanQuery, year: year);
    } else if (type == 'series') {
      rawCandidates = await tmdbClient.searchTv(cleanQuery, year: year);
    } else {
      final groups = await Future.wait([
        tmdbClient.searchMovie(cleanQuery, year: year),
        tmdbClient.searchTv(cleanQuery, year: year),
      ]);
      rawCandidates = groups.expand((group) => group).toSet().toList();
    }

    if (rawCandidates.isEmpty && year != null) {
      rawCandidates = await search(cleanQuery, type: type);
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

  Future<List<PreparedFileMatch>> prepareFileMatches(
    List<MatchingFile> files,
    TmdbWork candidate, {
    Map<int, ({int? season, int? episode})> overrides = const {},
  }) async {
    final seasons = <int, List<TmdbEpisode>>{};
    final prepared = <PreparedFileMatch>[];
    for (final file in files) {
      if (candidate.type == 'movie') {
        prepared.add(PreparedFileMatch(file: file));
        continue;
      }
      final parsed = file.parsed;
      final numbers = overrides[file.fileId] ?? file.seriesNumbers;
      final season = numbers.season;
      var number = numbers.episode;
      String? error;
      TmdbEpisode? episode;
      if (parsed.isMultiEpisode) {
        error = '此文件包含多集，请取消勾选后单独处理';
      } else if (season == null || season < 0) {
        error = '请选择所属季';
      } else if (parsed.isSpecialOrOva &&
          season == 0 &&
          !overrides.containsKey(file.fileId)) {
        final episodes = seasons[0] ??= await tmdbClient.getTvSeasonEpisodes(
          candidate.id,
          0,
        );
        episode = _specialEpisode(parsed, episodes);
        number = episode?.episodeNumber;
        if (episode == null) error = '请确认第 0 季中特别篇的集号';
      } else if (number == null || number < 1) {
        error = '请填写集号';
      } else {
        final episodes = seasons[season] ??= await tmdbClient
            .getTvSeasonEpisodes(candidate.id, season);
        episode = episodes.where((e) => e.episodeNumber == number).firstOrNull;
        if (episode == null) error = 'TMDB 中没有第 $season 季第 $number 集';
      }
      prepared.add(
        PreparedFileMatch(
          file: file,
          seasonNumber: season,
          episodeNumber: number,
          episode: episode,
          error: error,
        ),
      );
    }
    return prepared;
  }

  Future<int> matchFilesManually(
    List<PreparedFileMatch> files,
    TmdbWork candidate,
  ) async {
    if (files.isEmpty || files.any((file) => file.error != null)) {
      throw const MetadataException('请先确认所选文件的匹配信息');
    }
    final metadata = candidate.type == 'movie'
        ? await tmdbClient.getMovieDetails(candidate.id)
        : await tmdbClient.getTvDetails(candidate.id);
    final workId = await mediaLibraryRepository.applyMetadataToFiles({
      for (final file in files) file.file.fileId: file.episode,
    }, metadata);
    if (workId == null) throw const MetadataException('没有可匹配的文件');
    unawaited(
      Future<void>.sync(
        () => saveMetadataFiles?.call(
          fileIds: files.map((file) => file.file.fileId).toList(),
          replaceIdentity: true,
        ),
      ).catchError((Object error, StackTrace stackTrace) {
        AppLogger.instance.error(
          '手动匹配后后台保存目录元数据失败',
          error: error,
          stackTrace: stackTrace,
        );
      }),
    );
    return workId;
  }

  Future<MetadataRefreshResult> matchFilesAutomatically(
    List<MatchingFile> files, {
    void Function(int processed, int total)? onProgress,
    void Function(int active)? onActiveChanged,
    bool Function()? isCancelled,
  }) {
    final groups = <(String?, int?, String), List<MatchingFile>>{};
    for (final file in files) {
      (groups[_groupKey(file.parsed)] ??= []).add(file);
    }
    final tasks = groups.values.toList();
    var completed = 0;
    onProgress?.call(0, files.length);
    return _runMatchingTasks(
      tasks.length,
      (index, session) => _matchFiles(
        tasks[index],
        session,
        isCancelled: isCancelled,
        onFileCompleted: () {
          completed++;
          onProgress?.call(completed, files.length);
        },
      ),
      onActiveChanged: onActiveChanged,
      isCancelled: isCancelled,
    );
  }

  Future<MetadataRefreshResult> _runMatchingTasks(
    int total,
    Future<MetadataRefreshResult> Function(int index, _MatchSession session)
    run, {
    void Function(int processed, int total)? onProgress,
    void Function(int active)? onActiveChanged,
    bool Function()? isCancelled,
  }) async {
    final session = _MatchSession();
    var next = 0;
    var completed = 0;
    var active = 0;
    var matched = 0;
    var needsReview = 0;
    var skipped = 0;
    final errors = <String>{};
    final reasons = <MatchReason, int>{};
    onProgress?.call(0, total);
    onActiveChanged?.call(0);
    Future<void> worker() async {
      while (!session.stopped &&
          !(isCancelled?.call() ?? false) &&
          next < total) {
        final index = next++;
        active++;
        onActiveChanged?.call(active);
        try {
          final result = await run(index, session);
          matched += result.matched;
          needsReview += result.needsReview;
          skipped += result.skipped;
          errors.addAll(result.errors);
          for (final entry in result.reviewReasons.entries) {
            reasons.update(
              entry.key,
              (count) => count + entry.value,
              ifAbsent: () => entry.value,
            );
          }
        } catch (_) {
          session.stopped = true;
          rethrow;
        } finally {
          completed++;
          onProgress?.call(completed, total);
          active--;
          onActiveChanged?.call(active);
        }
      }
    }

    await Future.wait([
      for (var i = 0; i < math.min(_automaticConcurrency, total); i++) worker(),
    ]);
    return MetadataRefreshResult(
      matched: matched,
      needsReview: needsReview,
      skipped: skipped,
      errors: errors.toList(),
      reviewReasons: reasons,
    );
  }

  Future<T> _writeAutomatically<T>(Future<T> Function() write) {
    final result = _automaticWrites.then((_) => write());
    _automaticWrites = result.then<void>(
      (_) {},
      onError: (Object error, StackTrace stackTrace) {},
    );
    return result;
  }

  static List<String> _queries(ParsedMediaFilename parsed) => {
    ...parsed.titleCandidates,
    parsed.title,
    ?parsed.secondaryTitle,
  }.where((title) => _normalize(title).isNotEmpty).take(3).toList();

  static (String?, int?, String) _groupKey(ParsedMediaFilename parsed) => (
    parsed.type,
    (parsed.seasonNumber ?? 1) > 1 ? null : parsed.year,
    _queries(parsed).map(_normalize).join('|'),
  );

  Future<MetadataRefreshResult> _matchFiles(
    List<MatchingFile> files,
    _MatchSession session, {
    void Function()? onFileCompleted,
    bool Function()? isCancelled,
  }) async {
    var matched = 0;
    final matchedFileIds = <int>[];
    var needsReview = 0;
    var skipped = 0;
    final errors = <String>[];
    final reasons = <MatchReason, int>{};
    bool cancelled() => session.stopped || (isCancelled?.call() ?? false);
    for (final file in files) {
      if (cancelled()) break;
      try {
        if (await mediaLibraryRepository.isFileMetadataProtected(file.fileId)) {
          skipped++;
          continue;
        }
        final parsed = file.parsed;
        final decision = await _decide(parsed, session, isCancelled: cancelled);
        var reason = decision.reason;
        final metadata = decision.automatic;
        TmdbEpisode? episode;
        if (metadata != null && metadata.type == 'series') {
          final mapping = await _automaticEpisode(
            parsed,
            metadata,
            session,
            isCancelled: cancelled,
          );
          reason = mapping.reason;
          episode = mapping.episode;
        }
        if (reason != null || metadata == null) {
          final actualReason = reason ?? MatchReason.candidateAmbiguous;
          reasons.update(actualReason, (count) => count + 1, ifAbsent: () => 1);
          if (actualReason == MatchReason.extraMedia) {
            skipped++;
          } else {
            needsReview++;
          }
          await _writeAutomatically(() async {
            if (cancelled()) return;
            await mediaLibraryRepository.recordMatchingReview(
              [file.fileId],
              MatchDecision(
                reason: actualReason,
                candidates: decision.candidates,
              ),
            );
          });
          continue;
        }
        if (cancelled()) break;
        final workId = await _writeAutomatically(() async {
          if (cancelled()) return null;
          return mediaLibraryRepository.applyMetadataToFiles(
            {file.fileId: episode},
            metadata,
            manual: false,
          );
        });
        if (workId == null) {
          skipped++;
        } else {
          matched++;
          matchedFileIds.add(file.fileId);
        }
      } on MetadataException catch (error) {
        if (error.code == 'cancelled') break;
        errors.add(error.message);
        if (error.code == 'unauthorized' || error.code == 'rate_limit') {
          session.stopped = true;
          break;
        }
      } catch (error, stackTrace) {
        AppLogger.instance.error(
          '自动匹配失败',
          error: error,
          stackTrace: stackTrace,
        );
        errors.add('匹配请求失败，请检查网络后重试');
      } finally {
        onFileCompleted?.call();
      }
    }
    if (matchedFileIds.isNotEmpty) {
      await saveMetadataFiles?.call(
        fileIds: matchedFileIds,
        replaceIdentity: false,
      );
    }
    return MetadataRefreshResult(
      matched: matched,
      needsReview: needsReview,
      skipped: skipped,
      errors: errors.toSet().toList(),
      reviewReasons: reasons,
    );
  }

  Future<MatchDecision> _decide(
    ParsedMediaFilename parsed,
    _MatchSession session, {
    bool Function()? isCancelled,
  }) async {
    if (parsed.isExtra) {
      return const MatchDecision(reason: MatchReason.extraMedia);
    }
    if (parsed.isMultiEpisode) {
      return const MatchDecision(reason: MatchReason.specialUnverified);
    }
    final queries = _queries(parsed);
    if (queries.isEmpty) {
      return const MatchDecision(reason: MatchReason.noTitleEvidence);
    }
    // 后续季目录中的年份可能是该季播出年，不能用它筛选全剧首播年。
    final year = (parsed.seasonNumber ?? 1) > 1 ? null : parsed.year;
    final key = _groupKey(parsed);
    final decision = await (session.decisions[key] ??= _retrieveAndDecide(
      queries,
      parsed.type,
      year,
      session,
      isCancelled: isCancelled,
    ));
    final filenameTitle = parsed.filenameTitle;
    if (decision.automatic != null &&
        filenameTitle != null &&
        _normalize(filenameTitle).length >= 4 &&
        !_exactTitle(filenameTitle, decision.automatic!)) {
      return MatchDecision(
        reason: MatchReason.candidateAmbiguous,
        candidates: decision.candidates,
      );
    }
    return decision;
  }

  Future<MatchDecision> _retrieveAndDecide(
    List<String> queries,
    String? type,
    int? year,
    _MatchSession session, {
    bool Function()? isCancelled,
  }) async {
    final found = <TmdbWork, TmdbWork>{};
    var requests = 0;
    final types = type == null ? ['movie', 'series'] : [type];
    for (final query in queries) {
      for (final searchType in types) {
        for (final filter in [year, if (year != null) null]) {
          if (requests >= 6) break;
          if (isCancelled?.call() ?? false) {
            throw const MetadataException('已取消匹配', code: 'cancelled');
          }
          requests++;
          final searchKey = (searchType, _normalize(query), filter);
          final results = await (session.searches[searchKey] ??=
              searchType == 'movie'
              ? tmdbClient.searchMovie(query, year: filter)
              : tmdbClient.searchTv(query, year: filter));
          for (final candidate in results) {
            found[candidate] = candidate;
          }
          // 年份筛选已得到精确标题时仍继续其他有来源的标题，聚合后统一判定。
          if (filter != null &&
              results.any((candidate) => _exactTitle(query, candidate))) {
            break;
          }
        }
      }
    }
    if (found.isEmpty) {
      return const MatchDecision(reason: MatchReason.noCandidates);
    }
    double score(TmdbWork work) {
      final scores = queries.map(
        (query) =>
            computeMatchScore(query: query, targetYear: year, candidate: work),
      );
      final exact = queries.where((query) => _exactTitle(query, work)).length;
      return scores.reduce(math.max) +
          math.min(2, math.max(0, exact - 1)) * 0.05;
    }

    var ranked = found.values.toList()
      ..sort((a, b) => score(b).compareTo(score(a)));
    for (final candidate in ranked.take(3).toList()) {
      if (type != null && candidate.type != type) continue;
      if (isCancelled?.call() ?? false) {
        throw const MetadataException('已取消匹配', code: 'cancelled');
      }
      final detail = await (session.details[candidate] ??=
          candidate.type == 'movie'
          ? tmdbClient.getMovieDetails(candidate.id)
          : tmdbClient.getTvDetails(candidate.id));
      if (detail.id != candidate.id || detail.type != candidate.type) {
        throw const MetadataException(
          'TMDB 返回的作品身份不一致',
          code: 'invalid_response',
        );
      }
      found[candidate] = detail;
    }
    ranked = found.values.toList()
      ..sort((a, b) => score(b).compareTo(score(a)));
    final top = ranked.first;
    MatchDecision review(MatchReason reason) =>
        MatchDecision(reason: reason, candidates: ranked.take(3).toList());
    if (type != null && top.type != type) {
      return review(MatchReason.typeConflict);
    }
    if (!session.details.containsKey(top)) {
      return review(MatchReason.candidateAmbiguous);
    }
    if (year != null && (top.year == null || (year - top.year!).abs() > 1)) {
      return review(MatchReason.yearConflict);
    }
    final exact = queries.where((query) => _exactTitle(query, top)).toList();
    if (queries.any(
      (query) =>
          !_exactTitle(query, top) &&
          exact.any(
            (matched) =>
                _normalize(query).startsWith(_normalize(matched)) &&
                !(year != null &&
                    _normalize(query) == _normalize('$matched $year')) &&
                _normalize(query).length > _normalize(matched).length + 1,
          ),
    )) {
      return review(MatchReason.candidateAmbiguous);
    }
    if (exact.isEmpty ||
        (year == null &&
            exact.every((query) => _normalize(query).length <= 3) &&
            exact.map(_normalize).toSet().length < 2)) {
      return review(MatchReason.candidateAmbiguous);
    }
    if (ranked.length > 1 && score(top) - score(ranked[1]) < 0.12) {
      return review(MatchReason.candidateAmbiguous);
    }
    return MatchDecision(automatic: top, candidates: ranked.take(3).toList());
  }

  static bool _exactTitle(String query, TmdbWork candidate) =>
      [
        candidate.title,
        if (candidate.originalTitle != null) candidate.originalTitle!,
        ...candidate.aliases,
      ].any(
        (title) =>
            _normalize(query) == _normalize(title) ||
            (candidate.type == 'movie' &&
                _movieTitleKey(query) == _movieTitleKey(title)),
      );

  static String _movieTitleKey(String title) {
    final releaseTitle = title.replaceFirst(
      RegExp(r'\s+-\s+movie\s*$', caseSensitive: false),
      '',
    );
    final theatrical = RegExp(r'剧场版|劇場版');
    return '${_normalize(releaseTitle.replaceAll(theatrical, ''))}'
        '${theatrical.hasMatch(releaseTitle) ? '剧场版' : ''}';
  }

  Future<({TmdbEpisode? episode, MatchReason? reason})> _automaticEpisode(
    ParsedMediaFilename parsed,
    TmdbWork work,
    _MatchSession session, {
    bool Function()? isCancelled,
  }) async {
    final season = parsed.seasonNumber;
    final number = parsed.episodeNumber;
    const review = (
      episode: null,
      reason: MatchReason.episodeMappingUnverified,
    );
    Future<List<TmdbEpisode>> episodes(int season) {
      if (isCancelled?.call() ?? false) {
        throw const MetadataException('已取消匹配', code: 'cancelled');
      }
      return session.seasons[(work.id, season)] ??= tmdbClient
          .getTvSeasonEpisodes(work.id, season);
    }

    if (parsed.isSpecialOrOva) {
      final specials = await episodes(0);
      if (RegExp(
        r'S00[ ._-]*E\d+',
        caseSensitive: false,
      ).hasMatch(parsed.rawName)) {
        final episode = specials
            .where((episode) => episode.episodeNumber == number)
            .firstOrNull;
        return episode == null ? review : (episode: episode, reason: null);
      }
      final episode = _specialEpisode(parsed, specials);
      return episode == null
          ? (episode: null, reason: MatchReason.specialUnverified)
          : (episode: episode, reason: null);
    }
    if (season == null || number == null || parsed.hasSeasonConflict) {
      return review;
    }
    if (work.seasonNumbers.isNotEmpty && !work.seasonNumbers.contains(season)) {
      return review;
    }
    if (parsed.isSeasonInferred) {
      final seasons = work.seasonNumbers.where((season) => season > 0).toSet();
      final numericName = RegExp(r'^\d{1,3}\.[^./\\]+$')
          .hasMatch(parsed.rawName);
      if (numericName || seasons.length != 1 || !seasons.contains(1)) {
        return review;
      }
    }
    final current = await episodes(season);
    final direct = current
        .where((episode) => episode.episodeNumber == number)
        .firstOrNull;
    if (parsed.absoluteEpisodeNumber != null &&
        season > 1 &&
        !RegExp(
          r'\d(?:st|nd|rd|th)',
          caseSensitive: false,
        ).hasMatch(parsed.rawEpisodeToken ?? '')) {
      if (season > 10) return review;
      var offset = 0;
      for (var previous = 1; previous < season; previous++) {
        final list = await episodes(previous);
        final numbers = list.map((episode) => episode.episodeNumber).toSet();
        if (numbers.isEmpty ||
            numbers.length != numbers.reduce(math.max) ||
            numbers.reduce(math.min) != 1) {
          return review;
        }
        offset += numbers.length;
      }
      final mapped = current
          .where(
            (episode) =>
                episode.episodeNumber == parsed.absoluteEpisodeNumber! - offset,
          )
          .firstOrNull;
      if (mapped != null &&
          direct != null &&
          mapped.episodeNumber != direct.episodeNumber) {
        return review;
      }
      if (mapped != null) return (episode: mapped, reason: null);
    }
    return direct == null ? review : (episode: direct, reason: null);
  }

  static TmdbEpisode? _specialEpisode(
    ParsedMediaFilename parsed,
    List<TmdbEpisode> episodes,
  ) {
    if (episodes.length == 1) return episodes.single;
    final raw = _normalize(parsed.rawName);
    final matches = episodes.where((episode) {
      final title = _normalize(episode.title ?? '');
      return title.length >= 4 && raw.contains(title);
    }).toList();
    return matches.length == 1 ? matches.single : null;
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
        await saveMetadataFiles?.call(
          workId: canonicalId,
          replaceIdentity: true,
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

        await saveMetadataFiles?.call(
          workId: canonicalId,
          replaceIdentity: true,
        );
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
  Future<MetadataRefreshResult> refresh({
    void Function(MetadataPhase phase, int processed, int? total)? onProgress,
    void Function(int active)? onActiveChanged,
  }) {
    if (_inFlightRefresh != null) {
      return _inFlightRefresh!;
    }
    _inFlightRefresh =
        _doRefresh(
          onProgress: onProgress,
          onActiveChanged: onActiveChanged,
        ).whenComplete(() {
          _inFlightRefresh = null;
        });
    return _inFlightRefresh!;
  }

  Future<MetadataRefreshResult> _doRefresh({
    void Function(MetadataPhase phase, int processed, int? total)? onProgress,
    void Function(int active)? onActiveChanged,
  }) async {
    onProgress?.call(MetadataPhase.recognizing, 0, null);
    try {
      await mediaLibraryRepository.recognizePendingFiles();
    } catch (error, stackTrace) {
      AppLogger.instance.error(
        '识别待处理文件失败',
        error: error,
        stackTrace: stackTrace,
      );
      throw const MetadataException('媒体库待处理文件识别失败', code: 'recognition_error');
    }
    if (!await tokenStore.isConfigured()) {
      return const MetadataRefreshResult(localOnly: true);
    }
    final works = await mediaLibraryRepository.unmatchedWorks();
    return _runMatchingTasks(
      works.length,
      (index, session) async {
        final work = works[index];
        if (work.metadataLocked || work.metadataSource != 'local') {
          return const MetadataRefreshResult(skipped: 1);
        }
        final files = await mediaLibraryRepository.matchingFilesForWork(
          work.id,
        );
        if (files.isEmpty) return const MetadataRefreshResult(skipped: 1);
        final result = await _matchFiles(files, session);
        if (result.errors.isNotEmpty) session.stopped = true;
        return MetadataRefreshResult(
          matched: result.needsReview == 0 && result.matched > 0 ? 1 : 0,
          needsReview: result.needsReview > 0 ? 1 : 0,
          skipped:
              result.needsReview == 0 &&
                  result.matched == 0 &&
                  result.errors.isEmpty
              ? 1
              : 0,
          errors: result.errors,
          reviewReasons: {
            for (final reason in result.reviewReasons.keys) reason: 1,
          },
        );
      },
      onProgress: (completed, total) =>
          onProgress?.call(MetadataPhase.matching, completed, total),
      onActiveChanged: onActiveChanged,
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
    await saveMetadataFiles?.call(workId: workId, replaceIdentity: true);
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
      RegExp(r'''[\s\-_\.:/\\,()\[\]{}：，。！？!?「」『』“”‘’"'・·]+'''),
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

/// 单次任务内复用请求，跨任务仍沿用 TmdbClient 的持久缓存与限流。
class _MatchSession {
  bool stopped = false;
  final searches = <(String, String, int?), Future<List<TmdbWork>>>{};
  final details = <TmdbWork, Future<TmdbWork>>{};
  final seasons = <(int, int), Future<List<TmdbEpisode>>>{};
  final decisions = <(String?, int?, String), Future<MatchDecision>>{};
}
