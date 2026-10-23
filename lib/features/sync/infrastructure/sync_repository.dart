import 'dart:convert';
import 'dart:math';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';

import '../../../core/database/app_database.dart';
import '../domain/sync_models.dart';

class _LocalTargetRef {
  final int? workId;
  final int? episodeId;
  const _LocalTargetRef({this.workId, this.episodeId});
}

/// 同步数据仓储实现
///
/// 负责本地变更捕获（Local Projection）、确定性版本与冲突合并（Last-Writer-Wins）、
/// 持久化发件箱（Outbox）与进度/元数据应用，以及游标（Cursors）与挂起未决记录（Pending）。
class SyncRepository {
  SyncRepository(
    this.db, {
    DateTime Function()? clock,
    String Function()? createDeviceId,
  }) : _clock = clock ?? DateTime.now,
       _createDeviceId = createDeviceId ?? _defaultGenerateDeviceId;

  final AppDatabase db;
  final DateTime Function() _clock;
  final String Function() _createDeviceId;

  static final RegExp _hex32Regex = RegExp(r'^[0-9a-f]{32}$');

  static String _defaultGenerateDeviceId() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  Future<String> _ensureDeviceId() async {
    final row = await db
        .customSelect(
          'SELECT "value" FROM sync_state WHERE "key" = ?',
          variables: [Variable.withString('device_id')],
        )
        .getSingleOrNull();

    if (row != null) {
      final id = row.read<String>('value');
      if (_hex32Regex.hasMatch(id)) {
        return id;
      }
    }

    final newId = _createDeviceId();
    if (!_hex32Regex.hasMatch(newId)) {
      throw const SyncException('设备标识格式不合法');
    }

    await db.customStatement(
      'INSERT INTO sync_state ("key", "value") VALUES (?, ?) ON CONFLICT("key") DO UPDATE SET "value" = excluded."value"',
      ['device_id', newId],
    );
    return newId;
  }

  Future<int> _getNextOutboxSequence() async {
    final row = await db
        .customSelect(
          'SELECT "value" FROM sync_state WHERE "key" = ?',
          variables: [Variable.withString('outbox_sequence')],
        )
        .getSingleOrNull();

    final current = row != null
        ? (int.tryParse(row.read<String>('value')) ?? 0)
        : 0;
    final next = current + 1;
    await db.customStatement(
      'INSERT INTO sync_state ("key", "value") VALUES (?, ?) ON CONFLICT("key") DO UPDATE SET "value" = excluded."value"',
      ['outbox_sequence', next.toString()],
    );
    return next;
  }

  /// 捕获本地数据变更至 sync_local_registers
  ///
  /// 直接按寄存器维护版本戳（无全局时钟污染）：
  /// - 首次捕获记录：stamp = 原始数据行 updatedAt 毫秒数；
  /// - 已有寄存器发生修改：stamp = max(原始数据行 updatedAt 毫秒数, 同寄存器前次版本 stamp + 1)。
  /// 仅匹配有效 TMDB 身份的实体。已导入记录若本地无变更绝不重复标记 dirty。
  Future<void> captureLocalChanges() async {
    await db.transaction(() async {
      final thisDeviceId = await _ensureDeviceId();
      final nowMs = _clock().millisecondsSinceEpoch;

      // 1. 扫描播放进度
      final progressRows = await db.customSelect('''
        SELECT
          pp.id AS progress_id,
          pp.target_type,
          pp.target_id,
          pp.work_id,
          pp.episode_id,
          pp.position_ms,
          pp.duration_ms,
          pp.completed,
          pp.updated_at,
          w.type AS work_type,
          ext.provider_entity_id AS tmdb_entity_id,
          s.season_number,
          ep.episode_number
        FROM playback_progress pp
        LEFT JOIN episodes ep ON pp.target_type = 'episode' AND pp.target_id = ep.id
        LEFT JOIN seasons s ON ep.season_id = s.id
        LEFT JOIN works w ON w.id = COALESCE(pp.work_id, s.series_id)
        LEFT JOIN external_ids ext ON ext.provider = 'tmdb' AND ext.work_id = w.id
      ''').get();

      for (final row in progressRows) {
        final tmdbEntityId = row.readNullable<String>('tmdb_entity_id');
        if (tmdbEntityId == null) {
          // 无 TMDB 身份，保持纯本地
          continue;
        }

        final targetType = row.read<String>('target_type');
        final workType = row.readNullable<String>('work_type');

        final SyncTarget target;
        if (targetType == 'work') {
          if (workType != 'movie' || !tmdbEntityId.startsWith('movie:')) {
            continue;
          }
          final tmdbId = int.tryParse(tmdbEntityId.substring(6));
          if (tmdbId == null || tmdbId <= 0) continue;
          target = SyncTarget(workType: 'movie', tmdbId: tmdbId);
        } else if (targetType == 'episode') {
          if (workType != 'series' || !tmdbEntityId.startsWith('series:')) {
            continue;
          }
          final tmdbId = int.tryParse(tmdbEntityId.substring(7));
          if (tmdbId == null || tmdbId <= 0) continue;
          final seasonNum = row.readNullable<int>('season_number');
          final episodeNum = row.readNullable<int>('episode_number');
          if (seasonNum == null || episodeNum == null) continue;
          target = SyncTarget(
            workType: 'series',
            tmdbId: tmdbId,
            seasonNumber: seasonNum,
            episodeNumber: episodeNum,
          );
        } else {
          continue;
        }

        final posMs = row.read<int>('position_ms');
        final durMs = row.read<int>('duration_ms');
        final comp = row.read<bool>('completed');
        final currentVal = {
          'positionMs': posMs,
          'durationMs': durMs,
          'completed': comp,
        };

        final recordKey = 'progress:${target.id}';
        final existingReg = await db
            .customSelect(
              'SELECT version_stamp, version_device_id, value_json, dirty FROM sync_local_registers WHERE record_key = ?',
              variables: [Variable.withString(recordKey)],
            )
            .getSingleOrNull();

        final rowUpdatedAt = row
            .read<DateTime>('updated_at')
            .millisecondsSinceEpoch;

        if (existingReg == null) {
          // 初次登记：真实原始更新时间戳
          final stamp = rowUpdatedAt;
          await db.customStatement(
            '''
            INSERT INTO sync_local_registers (
              record_key, kind, target_id, target_json, version_stamp, version_device_id, value_json, dirty, updated_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, 1, ?)
          ''',
            [
              recordKey,
              SyncRecordKind.progress.name,
              target.id,
              jsonEncode(target.toJson()),
              stamp,
              thisDeviceId,
              jsonEncode(currentVal),
              nowMs,
            ],
          );
        } else {
          final storedVal = jsonDecode(
            existingReg.read<String>('value_json'),
          ) as Map<String, dynamic>;
          final isDifferent =
              storedVal['positionMs'] != posMs ||
              storedVal['durationMs'] != durMs ||
              storedVal['completed'] != comp;

          if (isDifferent) {
            final storedStamp = existingReg.read<int>('version_stamp');
            // 已有记录变更：同寄存器因果单调递增，避免与未同步记录产生跨目标时钟膨胀
            final stamp = max(rowUpdatedAt, storedStamp + 1);

            await db.customStatement(
              '''
              UPDATE sync_local_registers
              SET version_stamp = ?,
                  version_device_id = ?,
                  value_json = ?,
                  dirty = 1,
                  updated_at = ?
              WHERE record_key = ?
            ''',
              [stamp, thisDeviceId, jsonEncode(currentVal), nowMs, recordKey],
            );
          }
        }
      }

      // 2. 扫描手动锁定的元数据修正
      final metadataRows = await db.customSelect('''
        SELECT
          w.id,
          w.type,
          w.title,
          w.year,
          w.overview,
          w.poster_path,
          w.updated_at,
          ext.provider_entity_id AS tmdb_entity_id
        FROM works w
        JOIN external_ids ext ON ext.provider = 'tmdb' AND ext.work_id = w.id
        WHERE w.metadata_locked = 1
      ''').get();

      for (final row in metadataRows) {
        final tmdbEntityId = row.read<String>('tmdb_entity_id');
        final workType = row.readNullable<String>('type');
        if (workType == null || (workType != 'movie' && workType != 'series')) {
          continue;
        }

        final expectedPrefix = '$workType:';
        if (!tmdbEntityId.startsWith(expectedPrefix)) continue;
        final tmdbId = int.tryParse(
          tmdbEntityId.substring(expectedPrefix.length),
        );
        if (tmdbId == null || tmdbId <= 0) continue;

        final target = SyncTarget(workType: workType, tmdbId: tmdbId);

        final title = row.read<String>('title');
        final year = row.readNullable<int>('year');
        final overview = row.readNullable<String>('overview');
        final posterPath = row.readNullable<String>('poster_path');

        // 规范化元数据字典格式（显式 4 键），确保与解析器与远程格式完全对齐
        final currentVal = <String, dynamic>{
          'title': title.trim(),
          'year': year,
          'overview': overview,
          'posterPath': posterPath,
        };

        final recordKey = 'metadata:${target.id}';
        final existingReg = await db
            .customSelect(
              'SELECT version_stamp, version_device_id, value_json, dirty FROM sync_local_registers WHERE record_key = ?',
              variables: [Variable.withString(recordKey)],
            )
            .getSingleOrNull();

        final rowUpdatedAt = row
            .read<DateTime>('updated_at')
            .millisecondsSinceEpoch;

        if (existingReg == null) {
          final stamp = rowUpdatedAt;
          await db.customStatement(
            '''
            INSERT INTO sync_local_registers (
              record_key, kind, target_id, target_json, version_stamp, version_device_id, value_json, dirty, updated_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, 1, ?)
          ''',
            [
              recordKey,
              SyncRecordKind.metadata.name,
              target.id,
              jsonEncode(target.toJson()),
              stamp,
              thisDeviceId,
              jsonEncode(currentVal),
              nowMs,
            ],
          );
        } else {
          final storedVal = jsonDecode(
            existingReg.read<String>('value_json'),
          ) as Map<String, dynamic>;
          final isDifferent = !mapEquals(storedVal, currentVal);

          if (isDifferent) {
            final storedStamp = existingReg.read<int>('version_stamp');
            final stamp = max(rowUpdatedAt, storedStamp + 1);

            await db.customStatement(
              '''
              UPDATE sync_local_registers
              SET version_stamp = ?,
                  version_device_id = ?,
                  value_json = ?,
                  dirty = 1,
                  updated_at = ?
              WHERE record_key = ?
            ''',
              [stamp, thisDeviceId, jsonEncode(currentVal), nowMs, recordKey],
            );
          }
        }
      }
    });
  }

  /// 准备待上传的持久化批次（使用冻结的发件箱，若无则从 dirty 记录冻结创建；不隐式调用 capture）
  Future<SyncBatch?> prepareUpload() async {
    return await db.transaction(() async {
      final thisDeviceId = await _ensureDeviceId();

      // 1. 优先读取已冻结但未确认的发件箱批次（保证重试语义不变与崩溃安全）
      final outboxRows = await db
          .customSelect(
            'SELECT sequence, record_key, kind, target_json, version_stamp, version_device_id, value_json FROM sync_outbox ORDER BY sequence ASC, record_key ASC',
          )
          .get();

      if (outboxRows.isNotEmpty) {
        final seq = outboxRows.first.read<int>('sequence');
        final records = outboxRows
            .where((r) => r.read<int>('sequence') == seq)
            .map((r) {
              final target = SyncTarget.fromJson(
                jsonDecode(r.read<String>('target_json'))
                    as Map<String, dynamic>,
              );
              final kind = SyncRecordKind.values.byName(r.read<String>('kind'));
              final version = SyncVersion(
                stamp: r.read<int>('version_stamp'),
                deviceId: r.read<String>('version_device_id'),
              );
              final value = jsonDecode(
                r.read<String>('value_json'),
              ) as Map<String, dynamic>;
              return SyncRecord(
                target: target,
                kind: kind,
                version: version,
                value: value,
              );
            })
            .toList();

        return SyncBatch(
          deviceId: thisDeviceId,
          sequence: seq,
          records: records,
        );
      }

      // 2. 若发件箱为空，从 dirty 记录冻结创建新批次
      final dirtyRows = await db
          .customSelect(
            'SELECT record_key, kind, target_json, version_stamp, version_device_id, value_json FROM sync_local_registers WHERE dirty = 1 ORDER BY record_key ASC',
          )
          .get();

      if (dirtyRows.isEmpty) {
        return null;
      }

      final seq = await _getNextOutboxSequence();
      final List<SyncRecord> records = [];

      for (final r in dirtyRows) {
        final target = SyncTarget.fromJson(
          jsonDecode(r.read<String>('target_json')) as Map<String, dynamic>,
        );
        final kind = SyncRecordKind.values.byName(r.read<String>('kind'));
        final version = SyncVersion(
          stamp: r.read<int>('version_stamp'),
          deviceId: r.read<String>('version_device_id'),
        );
        final value =
            jsonDecode(r.read<String>('value_json')) as Map<String, dynamic>;
        final record = SyncRecord(
          target: target,
          kind: kind,
          version: version,
          value: value,
        );
        records.add(record);

        await db.customStatement(
          '''
          INSERT INTO sync_outbox (
            sequence, record_key, kind, target_json, version_stamp, version_device_id, value_json, created_at
          ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        ''',
          [
            seq,
            record.key,
            kind.name,
            jsonEncode(target.toJson()),
            version.stamp,
            version.deviceId,
            jsonEncode(value),
            _clock().millisecondsSinceEpoch,
          ],
        );
      }

      return SyncBatch(deviceId: thisDeviceId, sequence: seq, records: records);
    });
  }

  /// 确认批次已成功上传：仅清除匹配版本的 dirty 标记，保留更新的本地编辑；同时记录本设备游标避免重取
  Future<void> acknowledgeUpload(SyncBatch batch) async {
    await db.transaction(() async {
      for (final record in batch.records) {
        final row = await db
            .customSelect(
              'SELECT version_stamp, version_device_id FROM sync_local_registers WHERE record_key = ?',
              variables: [Variable.withString(record.key)],
            )
            .getSingleOrNull();

        if (row != null) {
          final stamp = row.read<int>('version_stamp');
          final deviceId = row.read<String>('version_device_id');
          // 仅当寄存器当前版本与上传批次严格匹配时才清除 dirty；若上传期间发生了更新的本地编辑，保留 dirty
          if (stamp == record.version.stamp &&
              deviceId == record.version.deviceId) {
            await db.customStatement(
              'UPDATE sync_local_registers SET dirty = 0 WHERE record_key = ?',
              [record.key],
            );
          }
        }
      }

      // 清除已确认的发件箱批次
      await db.customStatement('DELETE FROM sync_outbox WHERE sequence = ?', [
        batch.sequence,
      ]);

      // 持久化本设备已成功上传游标，避免重新下载自身刚刚上传的批次
      await db.customStatement(
        '''
        INSERT INTO sync_cursors (device_id, last_sequence, updated_at)
        VALUES (?, ?, ?)
        ON CONFLICT(device_id) DO UPDATE SET
          last_sequence = MAX(last_sequence, excluded.last_sequence),
          updated_at = excluded.updated_at
      ''',
        [batch.deviceId, batch.sequence, _clock().millisecondsSinceEpoch],
      );
    });
  }

  /// 读取已接收并持久化的各设备游标映射表
  Future<Map<String, int>> readCursors() async {
    final rows = await db
        .customSelect('SELECT device_id, last_sequence FROM sync_cursors')
        .get();
    final Map<String, int> result = {};
    for (final row in rows) {
      result[row.read<String>('device_id')] = row.read<int>('last_sequence');
    }
    return result;
  }

  /// 严格查找本地实体引用（必须确保 works.type 与 external_ids 严格一致）
  Future<_LocalTargetRef?> _findLocalTarget(
    SyncTarget target,
    SyncRecordKind kind,
  ) async {
    if (target.workType == 'movie') {
      final row = await db
          .customSelect(
            '''
        SELECT w.id AS work_id
        FROM works w
        JOIN external_ids ext ON ext.work_id = w.id AND ext.provider = 'tmdb'
        WHERE w.type = 'movie' AND ext.provider_entity_id = ?
        LIMIT 1
        ''',
            variables: [Variable.withString('movie:${target.tmdbId}')],
          )
          .getSingleOrNull();

      if (row == null) return null;
      return _LocalTargetRef(workId: row.read<int>('work_id'));
    } else if (target.workType == 'series') {
      final workRow = await db
          .customSelect(
            '''
        SELECT w.id AS work_id
        FROM works w
        JOIN external_ids ext ON ext.work_id = w.id AND ext.provider = 'tmdb'
        WHERE w.type = 'series' AND ext.provider_entity_id = ?
        LIMIT 1
        ''',
            variables: [Variable.withString('series:${target.tmdbId}')],
          )
          .getSingleOrNull();

      if (workRow == null) return null;
      final seriesWorkId = workRow.read<int>('work_id');

      if (kind == SyncRecordKind.metadata) {
        return _LocalTargetRef(workId: seriesWorkId);
      } else if (kind == SyncRecordKind.progress) {
        if (target.seasonNumber == null || target.episodeNumber == null) {
          return null;
        }
        final epRow = await db
            .customSelect(
              '''
          SELECT e.id
          FROM episodes e
          JOIN seasons s ON e.season_id = s.id
          WHERE s.series_id = ? AND s.season_number = ? AND e.episode_number = ?
          LIMIT 1
          ''',
              variables: [
                Variable.withInt(seriesWorkId),
                Variable.withInt(target.seasonNumber!),
                Variable.withInt(target.episodeNumber!),
              ],
            )
            .getSingleOrNull();

        if (epRow == null) return null;
        return _LocalTargetRef(episodeId: epRow.read<int>('id'));
      }
    }
    return null;
  }

  /// 校验 last_file_id 是否仍属于该目标
  Future<bool> _isLastFileIdValidForTarget(
    int fileId,
    _LocalTargetRef target,
  ) async {
    final row = await db
        .customSelect(
          '''
      SELECT COUNT(*) AS cnt FROM media_assignments
      WHERE file_id = ? AND (
        (? IS NOT NULL AND work_id = ?) OR
        (? IS NOT NULL AND episode_id = ?)
      )
      ''',
          variables: [
            Variable.withInt(fileId),
            Variable.withInt(target.workId ?? -1),
            Variable.withInt(target.workId ?? -1),
            Variable.withInt(target.episodeId ?? -1),
            Variable.withInt(target.episodeId ?? -1),
          ],
        )
        .getSingle();
    return row.read<int>('cnt') > 0;
  }

  /// 为目标选择最佳关联文件（保留偏好并优先可用媒体源）
  Future<int?> _findBestFileForTarget(_LocalTargetRef target) async {
    final rows = await db
        .customSelect(
          '''
      SELECT ma.file_id
      FROM media_assignments ma
      LEFT JOIN media_files mf ON mf.id = ma.file_id
      LEFT JOIN media_entries me ON me.id = mf.entry_id
      LEFT JOIN media_sources ms ON ms.id = me.source_id
      WHERE (
        (? IS NOT NULL AND ma.work_id = ?) OR
        (? IS NOT NULL AND ma.episode_id = ?)
      )
      ORDER BY (COALESCE(me.available, 1) = 1 AND COALESCE(ms.enabled, 1) = 1 AND COALESCE(me.is_directory, 0) = 0) DESC,
               ma.preferred DESC,
               ma.id ASC
      LIMIT 1
      ''',
          variables: [
            Variable.withInt(target.workId ?? -1),
            Variable.withInt(target.workId ?? -1),
            Variable.withInt(target.episodeId ?? -1),
            Variable.withInt(target.episodeId ?? -1),
          ],
        )
        .get();

    if (rows.isEmpty) return null;
    return rows.first.read<int>('file_id');
  }

  /// 合并整个已验证批次；游标与记录在同一事务中提交。
  Future<int> acceptBatch(SyncBatch batch) async {
    final validated = SyncBatch.fromJson(batch.toJson());
    return db.transaction(() async {
      await captureLocalChanges();
      var applied = 0;
      for (final incoming in validated.records) {
        final pending = await (db.select(
          db.syncPending,
        )..where((r) => r.recordKey.equals(incoming.key))).getSingleOrNull();
        var record = incoming;
        if (pending != null &&
            SyncVersion(
                  stamp: pending.versionStamp,
                  deviceId: pending.versionDeviceId,
                ).compareTo(incoming.version) >
                0) {
          record = _pendingRecord(pending);
        }
        final target = await _findLocalTarget(record.target, record.kind);
        if (target == null) {
          await db
              .into(db.syncPending)
              .insertOnConflictUpdate(
                SyncPendingCompanion.insert(
                  recordKey: record.key,
                  kind: record.kind.name,
                  targetId: record.target.id,
                  targetJson: jsonEncode(record.target.toJson()),
                  versionStamp: record.version.stamp,
                  versionDeviceId: record.version.deviceId,
                  valueJson: jsonEncode(record.value),
                  updatedAt: _clock().millisecondsSinceEpoch,
                ),
              );
          continue;
        }
        if (await _applyRecord(record, target)) applied++;
        await (db.delete(
          db.syncPending,
        )..where((r) => r.recordKey.equals(record.key))).go();
      }
      await _saveCursor(validated.deviceId, validated.sequence);
      return applied;
    });
  }

  /// 目标后来完成扫描与匹配时，应用先前收到的记录。
  Future<int> applyPending() => db.transaction(() async {
    await captureLocalChanges();
    final pending = await db.select(db.syncPending).get();
    var applied = 0;
    for (final row in pending) {
      final record = _pendingRecord(row);
      final target = await _findLocalTarget(record.target, record.kind);
      if (target == null) continue;
      if (await _applyRecord(record, target)) applied++;
      await (db.delete(
        db.syncPending,
      )..where((r) => r.recordKey.equals(record.key))).go();
    }
    return applied;
  });

  static SyncRecord _pendingRecord(SyncPendingData row) => SyncRecord.fromJson({
    'kind': row.kind,
    'target': jsonDecode(row.targetJson),
    'version': {'stamp': row.versionStamp, 'deviceId': row.versionDeviceId},
    'value': jsonDecode(row.valueJson),
  });

  Future<bool> _applyRecord(SyncRecord record, _LocalTargetRef target) async {
    final previous = await (db.select(
      db.syncLocalRegisters,
    )..where((r) => r.recordKey.equals(record.key))).getSingleOrNull();
    if (previous != null &&
        record.version.compareTo(
              SyncVersion(
                stamp: previous.versionStamp,
                deviceId: previous.versionDeviceId,
              ),
            ) <=
            0) {
      return false;
    }
    final updatedAt = DateTime.fromMillisecondsSinceEpoch(record.version.stamp);
    if (record.kind == SyncRecordKind.progress) {
      final targetType = target.workId != null ? 'work' : 'episode';
      final targetId = target.workId ?? target.episodeId!;
      final existing =
          await (db.select(db.playbackProgresses)..where(
                (p) =>
                    p.targetType.equals(targetType) &
                    p.targetId.equals(targetId),
              ))
              .getSingleOrNull();
      var fileId = existing?.lastFileId;
      if (fileId != null &&
          !await _isLastFileIdValidForTarget(fileId, target)) {
        fileId = null;
      }
      fileId ??= await _findBestFileForTarget(target);
      final progress = PlaybackProgressesCompanion.insert(
        targetType: targetType,
        targetId: targetId,
        workId: Value(target.workId),
        episodeId: Value(target.episodeId),
        lastFileId: Value(fileId),
        positionMs: Value(record.value['positionMs'] as int),
        durationMs: Value(record.value['durationMs'] as int),
        completed: Value(record.value['completed'] as bool),
        updatedAt: Value(updatedAt),
      );
      await db
          .into(db.playbackProgresses)
          .insert(
            progress,
            onConflict: DoUpdate(
              (_) => progress,
              target: [
                db.playbackProgresses.targetType,
                db.playbackProgresses.targetId,
              ],
            ),
          );
    } else {
      await (db.update(
        db.works,
      )..where((w) => w.id.equals(target.workId!))).write(
        WorksCompanion(
          title: Value(record.value['title'] as String),
          year: Value(record.value['year'] as int?),
          overview: Value(record.value['overview'] as String?),
          posterPath: Value(record.value['posterPath'] as String?),
          metadataLocked: const Value(true),
          updatedAt: Value(updatedAt),
        ),
      );
    }
    await db
        .into(db.syncLocalRegisters)
        .insertOnConflictUpdate(
          SyncLocalRegistersCompanion.insert(
            recordKey: record.key,
            kind: record.kind.name,
            targetId: record.target.id,
            targetJson: jsonEncode(record.target.toJson()),
            versionStamp: record.version.stamp,
            versionDeviceId: record.version.deviceId,
            valueJson: jsonEncode(record.value),
            dirty: const Value(false),
            updatedAt: _clock().millisecondsSinceEpoch,
          ),
        );
    return true;
  }

  Future<void> _saveCursor(String deviceId, int sequence) => db.customStatement(
    '''
    INSERT INTO sync_cursors (device_id, last_sequence, updated_at)
    VALUES (?, ?, ?)
    ON CONFLICT(device_id) DO UPDATE SET
      last_sequence = MAX(last_sequence, excluded.last_sequence),
      updated_at = excluded.updated_at
    ''',
    [deviceId, sequence, _clock().millisecondsSinceEpoch],
  );

  /// 当前挂起等待本地匹配的远程记录数
  Future<int> pendingCount() async {
    final row = await db
        .customSelect('SELECT COUNT(*) AS cnt FROM sync_pending')
        .getSingle();
    return row.read<int>('cnt');
  }

  /// 本地未匹配 TMDB 的进度或锁定元数据数
  Future<int> localOnlyCount() async {
    final progressLocalOnly = await db.customSelect('''
      SELECT COUNT(*) AS cnt FROM playback_progress pp
      WHERE (
        pp.target_type = 'work' AND NOT EXISTS (
          SELECT 1 FROM external_ids ext
          WHERE ext.provider = 'tmdb' AND ext.work_id = pp.target_id
        )
      ) OR (
        pp.target_type = 'episode' AND NOT EXISTS (
          SELECT 1 FROM episodes ep
          JOIN seasons s ON ep.season_id = s.id
          JOIN external_ids ext ON ext.provider = 'tmdb' AND ext.work_id = s.series_id
          WHERE ep.id = pp.target_id
        )
      )
    ''').getSingle();

    final metadataLocalOnly = await db.customSelect('''
      SELECT COUNT(*) AS cnt FROM works w
      WHERE w.metadata_locked = 1 AND NOT EXISTS (
        SELECT 1 FROM external_ids ext
        WHERE ext.provider = 'tmdb' AND ext.work_id = w.id
      )
    ''').getSingle();

    return progressLocalOnly.read<int>('cnt') +
        metadataLocalOnly.read<int>('cnt');
  }

  /// 重置传输状态：清除游标与冻结发件箱，并将所有本地已登记记录置为 dirty，保留本地数据与设备标识，不丢弃挂起同步记录
  Future<void> resetTransport() async {
    await db.transaction(() async {
      await db.customStatement('DELETE FROM sync_cursors');
      await db.customStatement('DELETE FROM sync_outbox');
      await db.customStatement('UPDATE sync_local_registers SET dirty = 1');
    });
  }
}
