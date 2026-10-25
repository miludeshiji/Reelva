import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../domain/playback_progress.dart';

/// 播放进度仓储实现
///
/// 负责持久化与查询媒体播放进度、观看历史及首页 Continue Watching 展架聚合。
/// 保存时在事务内基于真实 `fileId` 实时解析所属目标，防止后台元数据刷新合并导致旧 ID 失效。
class PlaybackProgressRepository {
  PlaybackProgressRepository({required this.db, DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final AppDatabase db;
  final DateTime Function() _clock;

  /// 根据真实 [fileId] 保存或更新播放进度
  ///
  /// 进度 >= 90% 时自动判定为已完播（若未显式指定 [completed]）。
  /// 仅当 [fileId] 存在有效作品/剧集关联时才持久化，无关联资源不产生虚假历史。
  Future<void> saveProgress({
    required int fileId,
    required Duration position,
    required Duration duration,
    bool? completed,
  }) async {
    if (fileId <= 0) return;

    await db.transaction(() async {
      // 在事务内基于真实 fileId 实时查询当前关联关系，防止后台元数据合并导致外键失效
      final assignment = await (db.select(
        db.mediaAssignments,
      )..where((tbl) => tbl.fileId.equals(fileId))).getSingleOrNull();

      if (assignment == null) {
        // 未分配任何作品或剧集，不记录虚假进度
        return;
      }

      final String targetType;
      final int targetId;
      final int? workId;
      final int? episodeId;

      if (assignment.workId != null) {
        targetType = 'work';
        targetId = assignment.workId!;
        workId = assignment.workId;
        episodeId = null;
      } else if (assignment.episodeId != null) {
        targetType = 'episode';
        targetId = assignment.episodeId!;
        workId = null;
        episodeId = assignment.episodeId;
      } else {
        return;
      }

      final posMs = position.inMilliseconds < 0 ? 0 : position.inMilliseconds;
      final durMs = duration.inMilliseconds < 0 ? 0 : duration.inMilliseconds;

      final isCompleted =
          completed ?? (durMs > 0 && posMs >= (durMs * 0.90).round());

      final now = _clock();

      final existing =
          await (db.select(db.playbackProgresses)..where(
                (tbl) =>
                    tbl.targetType.equals(targetType) &
                    tbl.targetId.equals(targetId),
              ))
              .getSingleOrNull();

      if (existing != null) {
        await (db.update(
          db.playbackProgresses,
        )..where((tbl) => tbl.id.equals(existing.id))).write(
          PlaybackProgressesCompanion(
            workId: Value(workId),
            episodeId: Value(episodeId),
            lastFileId: Value(fileId),
            positionMs: Value(posMs),
            durationMs: Value(durMs),
            completed: Value(isCompleted),
            updatedAt: Value(now),
          ),
        );
      } else {
        await db
            .into(db.playbackProgresses)
            .insert(
              PlaybackProgressesCompanion.insert(
                targetType: targetType,
                targetId: targetId,
                workId: Value(workId),
                episodeId: Value(episodeId),
                lastFileId: Value(fileId),
                positionMs: Value(posMs),
                durationMs: Value(durMs),
                completed: Value(isCompleted),
                updatedAt: Value(now),
              ),
            );
      }
    });
  }

  /// 根据 [fileId] 查询当前所属目标的播放进度
  Future<PlaybackProgress?> getProgress(int fileId) async {
    if (fileId <= 0) return null;

    final assignment = await (db.select(
      db.mediaAssignments,
    )..where((tbl) => tbl.fileId.equals(fileId))).getSingleOrNull();

    if (assignment == null) return null;

    final String targetType;
    final int targetId;
    if (assignment.workId != null) {
      targetType = 'work';
      targetId = assignment.workId!;
    } else if (assignment.episodeId != null) {
      targetType = 'episode';
      targetId = assignment.episodeId!;
    } else {
      return null;
    }

    final row =
        await (db.select(db.playbackProgresses)..where(
              (tbl) =>
                  tbl.targetType.equals(targetType) &
                  tbl.targetId.equals(targetId),
            ))
            .getSingleOrNull();

    if (row == null) return null;
    return _toPlaybackProgress(row);
  }

  /// 获取首页 Continue Watching 展架列表
  ///
  /// 条件：未完播（completed = 0）且已播时长 >= 5s。
  /// 排序：按 updatedAt DESC, id DESC 稳定排序，最多返回 [limit] 条。
  /// 多版本/分集回退：优先推荐 lastFile，若 lastFile 不可用则退至同目标其他可用备选，全不可用时保留标记。
  /// 展架去重：每个作品（Work）仅保留一条最新播放记录。
  Future<List<ContinueWatchingEntry>> getContinueWatching({
    int limit = 20,
  }) async {
    return (await _progressEntriesQuery(
      limit: limit,
    ).get()).map(_continueEntry).toList();
  }

  Stream<List<ContinueWatchingEntry>> watchContinueWatching({int limit = 20}) =>
      _progressEntriesQuery(limit: limit)
          .watch()
          .map((rows) => rows.map(_continueEntry).toList());

  /// 按最近观看时间返回全部电影与分集记录，包含已完播及当前不可用的媒体。
  Stream<List<WatchHistoryEntry>> watchHistory() =>
      _progressEntriesQuery(continueWatchingOnly: false).watch().map(
        (rows) => rows
            .map(
              (row) => WatchHistoryEntry(
                id: row.read<int>('id'),
                entry: _continueEntry(row),
                completed: row.read<int>('completed') == 1,
                updatedAt: row.read<DateTime>('updated_at'),
              ),
            )
            .toList(),
      );

  Selectable<QueryRow> _progressEntriesQuery({
    int? limit,
    bool continueWatchingOnly = true,
  }) => db.customSelect(
    '''
    WITH ranked_progress AS (
      SELECT p.*, w.id AS library_work_id, w.title, w.poster_path,
        s.season_number, e.episode_number,
        ROW_NUMBER() OVER (
          PARTITION BY w.id ORDER BY p.updated_at DESC, p.id DESC
        ) AS work_rank
      FROM playback_progress p
      LEFT JOIN episodes e ON e.id = p.episode_id
      LEFT JOIN seasons s ON s.id = e.season_id
      JOIN works w ON w.id = p.work_id OR w.id = s.series_id
      ${continueWatchingOnly ? '''
      WHERE p.completed = 0 AND p.position_ms >= 5000
        AND (p.duration_ms <= 0 OR p.position_ms < p.duration_ms * 0.9)
      ''' : ''}
    ), recent AS (
      SELECT * FROM ranked_progress
      ${continueWatchingOnly ? 'WHERE work_rank = 1' : ''}
      ORDER BY updated_at DESC, id DESC ${limit == null ? '' : 'LIMIT ?'}
    ), ranked_files AS (
      SELECT r.id AS progress_id, mf.id AS file_id,
        (me.available = 1 AND ms.enabled = 1 AND me.is_directory = 0) AS is_available,
        ROW_NUMBER() OVER (
          PARTITION BY r.id ORDER BY
            (me.available = 1 AND ms.enabled = 1 AND me.is_directory = 0) DESC,
            (mf.id = r.last_file_id) DESC, ma.preferred DESC, ma.id ASC
        ) AS file_rank
      FROM recent r
      JOIN media_assignments ma ON ma.work_id = r.work_id OR ma.episode_id = r.episode_id
      JOIN media_files mf ON mf.id = ma.file_id
      JOIN media_entries me ON me.id = mf.entry_id
      JOIN media_sources ms ON ms.id = me.source_id
    )
    SELECT r.*, COALESCE(f.file_id, r.last_file_id) AS chosen_file_id,
      COALESCE(f.is_available, 0) AS is_available
    FROM recent r
    LEFT JOIN ranked_files f ON f.progress_id = r.id AND f.file_rank = 1
    ORDER BY r.updated_at DESC, r.id DESC
    ''',
    variables: [if (limit != null) Variable.withInt(limit)],
    readsFrom: {
      db.playbackProgresses,
      db.works,
      db.seasons,
      db.episodes,
      db.mediaAssignments,
      db.mediaFiles,
      db.mediaEntries,
      db.mediaSources,
    },
  );

  static ContinueWatchingEntry _continueEntry(QueryRow row) =>
      ContinueWatchingEntry(
        workId: row.read<int>('library_work_id'),
        title: row.read<String>('title'),
        posterPath: row.readNullable<String>('poster_path'),
        fileId: row.readNullable<int>('chosen_file_id'),
        position: Duration(milliseconds: row.read<int>('position_ms')),
        duration: Duration(milliseconds: row.read<int>('duration_ms')),
        seasonNumber: row.readNullable<int>('season_number'),
        episodeNumber: row.readNullable<int>('episode_number'),
        available: row.read<int>('is_available') == 1,
      );

  PlaybackProgress _toPlaybackProgress(PlaybackProgressData row) {
    return PlaybackProgress(
      id: row.id,
      targetType: ProgressTargetType.parse(row.targetType),
      targetId: row.targetId,
      workId: row.workId,
      episodeId: row.episodeId,
      lastFileId: row.lastFileId,
      position: Duration(milliseconds: row.positionMs),
      duration: Duration(milliseconds: row.durationMs),
      completed: row.completed,
      updatedAt: row.updatedAt,
    );
  }
}
