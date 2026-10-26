import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reelva/core/database/app_database.dart';
import 'package:reelva/features/sync/domain/sync_models.dart';
import 'package:reelva/features/sync/infrastructure/sync_repository.dart';

void main() {
  group('SyncRepository behavioral tests', () {
    late AppDatabase db;
    late DateTime currentTime;
    DateTime clock() => currentTime;

    setUp(() async {
      currentTime = DateTime(2026, 10, 23, 12, 0, 0);
      db = AppDatabase(executor: NativeDatabase.memory());
      // 插入测试需要的关联媒体源、媒体实体与媒体文件
      await db.customStatement('''
        INSERT INTO media_sources (id, kind, name, root_locator)
        VALUES (1, 'local', 'Movies', '/movies');
      ''');
      await db.customStatement('''
        INSERT INTO media_entries (id, source_id, external_entry_id, relative_locator, name, is_directory, available)
        VALUES (1, 1, 'ent_1', 'movie1.mkv', 'movie1.mkv', 0, 1),
               (2, 1, 'ent_2', 'movie2.mkv', 'movie2.mkv', 0, 1),
               (3, 1, 'ent_3', 'ep1.mkv', 'ep1.mkv', 0, 1);
      ''');
      await db.customStatement('''
        INSERT INTO media_files (id, entry_id, parse_state)
        VALUES (1, 1, 'parsed'),
               (2, 2, 'parsed'),
               (3, 3, 'parsed');
      ''');
    });

    tearDown(() async {
      await db.close();
    });

    test('stable identity: only proven TMDB external_ids sync, unmatched remain local', () async {
      // 作品 1: 拥有 TMDB 外部标识
      await db.customStatement('''
        INSERT INTO works (id, type, title, metadata_locked)
        VALUES (1, 'movie', 'Matrix', 1);
      ''');
      await db.customStatement('''
        INSERT INTO external_ids (id, work_id, provider, provider_entity_id)
        VALUES (1, 1, 'tmdb', 'movie:603');
      ''');
      await db.customStatement('''
        INSERT INTO playback_progress (id, target_type, target_id, work_id, position_ms, duration_ms)
        VALUES (1, 'work', 1, 1, 5000, 100000);
      ''');

      // 作品 2: 无 TMDB 外部标识（纯本地）
      await db.customStatement('''
        INSERT INTO works (id, type, title, metadata_locked)
        VALUES (2, 'movie', 'Home Video', 1);
      ''');
      await db.customStatement('''
        INSERT INTO playback_progress (id, target_type, target_id, work_id, position_ms, duration_ms)
        VALUES (2, 'work', 2, 2, 12000, 80000);
      ''');

      final repo = SyncRepository(
        db,
        clock: clock,
        createDeviceId: () => '11111111111111111111111111111111',
      );

      // 未匹配的观看进度仅保存在本机；影视元数据不再参与同步。
      final localOnly = await repo.localOnlyCount();
      expect(localOnly, 1);

      // 捕获本地变更
      await repo.captureLocalChanges();

      final batch = await repo.prepareUpload();
      expect(batch, isNotNull);
      expect(batch!.records, hasLength(1)); // 仅作品 1 的观看进度

      final targetIds = batch.records.map((r) => r.target.id).toSet();
      expect(targetIds, contains('movie:603'));
      // 纯本地作品 2 绝不上云
      expect(targetIds.any((id) => id.contains('2')), isFalse);
    });

    test('deterministic conflict resolution: LWW with timestamp and lexicographical deviceId', () async {
      await db.customStatement('''
        INSERT INTO works (id, type, title) VALUES (1, 'movie', 'Matrix');
      ''');
      await db.customStatement('''
        INSERT INTO external_ids (id, work_id, provider, provider_entity_id)
        VALUES (1, 1, 'tmdb', 'movie:603');
      ''');

      final repo = SyncRepository(
        db,
        clock: clock,
        createDeviceId: () => 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      );

      // 远程设备 b 具有更高时间戳，胜出
      const remoteBatch1 = SyncBatch(
        deviceId: 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
        sequence: 1,
        records: [
          SyncRecord(
            target: SyncTarget(workType: 'movie', tmdbId: 603),
            kind: SyncRecordKind.progress,
            version: SyncVersion(
              stamp: 1000,
              deviceId: 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
            ),
            value: {
              'positionMs': 20000,
              'durationMs': 100000,
              'completed': false,
            },
          ),
        ],
      );

      final applied1 = await repo.acceptBatch(remoteBatch1);
      expect(applied1, 1);

      var prog = await db
          .customSelect(
            'SELECT position_ms FROM playback_progress WHERE work_id = 1',
          )
          .getSingle();
      expect(prog.read<int>('position_ms'), 20000);

      // 远程设备 c 时间戳相同（1000），但 deviceId 'cccc...' > 'bbbb...'，根据字典序胜出
      const remoteBatch2 = SyncBatch(
        deviceId: 'cccccccccccccccccccccccccccccccc',
        sequence: 1,
        records: [
          SyncRecord(
            target: SyncTarget(workType: 'movie', tmdbId: 603),
            kind: SyncRecordKind.progress,
            version: SyncVersion(
              stamp: 1000,
              deviceId: 'cccccccccccccccccccccccccccccccc',
            ),
            value: {
              'positionMs': 35000,
              'durationMs': 100000,
              'completed': false,
            },
          ),
        ],
      );

      final applied2 = await repo.acceptBatch(remoteBatch2);
      expect(applied2, 1);

      prog = await db
          .customSelect(
            'SELECT position_ms FROM playback_progress WHERE work_id = 1',
          )
          .getSingle();
      expect(prog.read<int>('position_ms'), 35000);

      // 远程设备 a 时间戳相同（1000），但 deviceId 'aaaa...' < 'cccc...'，判定为输，不覆盖
      const remoteBatch3 = SyncBatch(
        deviceId: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        sequence: 1,
        records: [
          SyncRecord(
            target: SyncTarget(workType: 'movie', tmdbId: 603),
            kind: SyncRecordKind.progress,
            version: SyncVersion(
              stamp: 1000,
              deviceId: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
            ),
            value: {
              'positionMs': 10000,
              'durationMs': 100000,
              'completed': false,
            },
          ),
        ],
      );

      final applied3 = await repo.acceptBatch(remoteBatch3);
      expect(applied3, 0);

      prog = await db
          .customSelect(
            'SELECT position_ms FROM playback_progress WHERE work_id = 1',
          )
          .getSingle();
      expect(prog.read<int>('position_ms'), 35000);
    });

    test(
      'preserves user rewinds/resets (LWW stamp, not max(position))',
      () async {
        await db.customStatement('''
        INSERT INTO works (id, type, title) VALUES (1, 'movie', 'Matrix');
      ''');
        await db.customStatement('''
        INSERT INTO external_ids (id, work_id, provider, provider_entity_id)
        VALUES (1, 1, 'tmdb', 'movie:603');
      ''');

        final repo = SyncRepository(
          db,
          clock: clock,
          createDeviceId: () => 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        );

        // 早期同步：进度 80000ms
        await repo.acceptBatch(
          const SyncBatch(
            deviceId: 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
            sequence: 1,
            records: [
              SyncRecord(
                target: SyncTarget(workType: 'movie', tmdbId: 603),
                kind: SyncRecordKind.progress,
                version: SyncVersion(
                  stamp: 1000,
                  deviceId: 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
                ),
                value: {
                  'positionMs': 80000,
                  'durationMs': 100000,
                  'completed': false,
                },
              ),
            ],
          ),
        );

        // 用户回退/重置播放进度至 5000ms，时间戳为 2000
        final applied = await repo.acceptBatch(
          const SyncBatch(
            deviceId: 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
            sequence: 2,
            records: [
              SyncRecord(
                target: SyncTarget(workType: 'movie', tmdbId: 603),
                kind: SyncRecordKind.progress,
                version: SyncVersion(
                  stamp: 2000,
                  deviceId: 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
                ),
                value: {
                  'positionMs': 5000,
                  'durationMs': 100000,
                  'completed': false,
                },
              ),
            ],
          ),
        );
        expect(applied, 1);

        final prog = await db
            .customSelect(
              'SELECT position_ms FROM playback_progress WHERE work_id = 1',
            )
            .getSingle();
        // 必须保留回退后的 5000ms，绝不取 max(position)
        expect(prog.read<int>('position_ms'), 5000);
      },
    );

    test(
      'projection diffs & no echo: imported records do not trigger re-upload',
      () async {
        await db.customStatement('''
        INSERT INTO works (id, type, title) VALUES (1, 'movie', 'Matrix');
      ''');
        await db.customStatement('''
        INSERT INTO external_ids (id, work_id, provider, provider_entity_id)
        VALUES (1, 1, 'tmdb', 'movie:603');
      ''');

        final repo = SyncRepository(
          db,
          clock: clock,
          createDeviceId: () => 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        );

        // 导入远端记录
        await repo.acceptBatch(
          const SyncBatch(
            deviceId: 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
            sequence: 1,
            records: [
              SyncRecord(
                target: SyncTarget(workType: 'movie', tmdbId: 603),
                kind: SyncRecordKind.progress,
                version: SyncVersion(
                  stamp: 1000,
                  deviceId: 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
                ),
                value: {
                  'positionMs': 20000,
                  'durationMs': 100000,
                  'completed': false,
                },
              ),
            ],
          ),
        );

        // 之后进行本地捕获
        await repo.captureLocalChanges();

        // 发件箱必须为空：已导入记录绝不回响为新的待上传修改
        final batch = await repo.prepareUpload();
        expect(batch, isNull);
      },
    );

    test('durable outbox and acknowledgement', () async {
      await db.customStatement('''
        INSERT INTO works (id, type, title, metadata_locked)
        VALUES (1, 'movie', 'Matrix', 0);
      ''');
      await db.customStatement('''
        INSERT INTO external_ids (id, work_id, provider, provider_entity_id)
        VALUES (1, 1, 'tmdb', 'movie:603');
      ''');
      await db.customStatement('''
        INSERT INTO playback_progress (id, target_type, target_id, work_id, position_ms, duration_ms)
        VALUES (1, 'work', 1, 1, 15000, 100000);
      ''');

      final repo = SyncRepository(
        db,
        clock: clock,
        createDeviceId: () => 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      );

      await repo.captureLocalChanges();

      // 首次 prepareUpload 冻结发件箱
      final batch1 = await repo.prepareUpload();
      expect(batch1, isNotNull);
      expect(batch1!.sequence, 1);
      expect(batch1.records, hasLength(1));

      // 模拟进程重试：再次调用 prepareUpload 返回相同序列号和内容的冻结批次
      final batch2 = await repo.prepareUpload();
      expect(batch2, isNotNull);
      expect(batch2!.sequence, 1);
      expect(batch2.records.first.value['positionMs'], 15000);

      // 确认上传完成
      await repo.acknowledgeUpload(batch1);

      // 发件箱已清空，且本地无新增 dirty 记录
      final batch3 = await repo.prepareUpload();
      expect(batch3, isNull);
    });

    test('concurrency: network-window local-edit race regression', () async {
      // 场景：在网络上传/下载窗口期间，用户本地播放器持续推进播放进度
      // 目标：acceptBatch 与 acknowledgeUpload 绝不破坏性静默覆盖或清空未上传的本地最新修改
      await db.customStatement('''
        INSERT INTO works (id, type, title) VALUES (1, 'movie', 'Matrix');
      ''');
      await db.customStatement('''
        INSERT INTO external_ids (id, work_id, provider, provider_entity_id)
        VALUES (1, 1, 'tmdb', 'movie:603');
      ''');
      await db.customStatement('''
        INSERT INTO playback_progress (id, target_type, target_id, work_id, position_ms, duration_ms, updated_at)
        VALUES (1, 'work', 1, 1, 10000, 100000, 1000);
      ''');

      currentTime = DateTime.fromMillisecondsSinceEpoch(1000);
      final repo = SyncRepository(
        db,
        clock: clock,
        createDeviceId: () => 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      );

      // 1. 本地捕获并准备上传批次（时间戳 stamp = 1001）
      await repo.captureLocalChanges();
      final inFlightBatch = await repo.prepareUpload();
      expect(inFlightBatch, isNotNull);
      expect(inFlightBatch!.records.first.value['positionMs'], 10000);

      // 2. 在网络上传未完成时，用户继续观影，播放器直接更新数据库至 50000ms（时间戳 5000）
      await db.customStatement('''
        UPDATE playback_progress
        SET position_ms = 50000, updated_at = 5000
        WHERE id = 1;
      ''');

      // 3. 同时从远端接收到批次（时间戳 3000，进度 30000ms）
      currentTime = DateTime.fromMillisecondsSinceEpoch(6000);
      const remoteBatch = SyncBatch(
        deviceId: 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
        sequence: 1,
        records: [
          SyncRecord(
            target: SyncTarget(workType: 'movie', tmdbId: 603),
            kind: SyncRecordKind.progress,
            version: SyncVersion(
              stamp: 3000,
              deviceId: 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
            ),
            value: {
              'positionMs': 30000,
              'durationMs': 100000,
              'completed': false,
            },
          ),
        ],
      );

      // acceptBatch 在事务内捕获最新投影（本地 50000ms, stamp = max(5000, clock) > 3000）
      final applied = await repo.acceptBatch(remoteBatch);
      expect(applied, 0); // 本地较新，远端未胜出

      // 验证本地数据库的 50000ms 没有被静默覆盖！
      var prog = await db
          .customSelect(
            'SELECT position_ms FROM playback_progress WHERE id = 1',
          )
          .getSingle();
      expect(prog.read<int>('position_ms'), 50000);

      // 4. 旧的上传终于返回成功，调用 acknowledgeUpload
      await repo.acknowledgeUpload(inFlightBatch);

      // 因为本地版本已升级为更新的时间戳，acknowledgeUpload 不得清除 dirty！
      // 5. 下一次同步时，prepareUpload 必须包含本地最新的 50000ms 修改！
      final nextBatch = await repo.prepareUpload();
      expect(nextBatch, isNotNull);
      expect(nextBatch!.sequence, 2);
      expect(nextBatch.records.first.value['positionMs'], 50000);
    });

    test(
      'local file preference preservation and reassociation rules on import',
      () async {
        await db.customStatement('''
        INSERT INTO works (id, type, title) VALUES (1, 'movie', 'Matrix');
      ''');
        await db.customStatement('''
        INSERT INTO external_ids (id, work_id, provider, provider_entity_id)
        VALUES (1, 1, 'tmdb', 'movie:603');
      ''');

        // 关联文件 1 与文件 2，其中文件 2 为用户本地偏好 (preferred = 1)
        await db.customStatement('''
        INSERT INTO media_assignments (id, file_id, work_id, preferred)
        VALUES (1, 1, 1, 0),
               (2, 2, 1, 1);
      ''');

        final repo = SyncRepository(
          db,
          clock: clock,
          createDeviceId: () => 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        );

        // 首次从远端导入进度，本地无现有 playback_progress 行
        // 必须自动重关联到本地 preferred 文件 (file_id = 2)
        await repo.acceptBatch(
          const SyncBatch(
            deviceId: 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
            sequence: 1,
            records: [
              SyncRecord(
                target: SyncTarget(workType: 'movie', tmdbId: 603),
                kind: SyncRecordKind.progress,
                version: SyncVersion(
                  stamp: 1000,
                  deviceId: 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
                ),
                value: {
                  'positionMs': 12000,
                  'durationMs': 100000,
                  'completed': false,
                },
              ),
            ],
          ),
        );

        var prog = await db
            .customSelect(
              'SELECT last_file_id FROM playback_progress WHERE work_id = 1',
            )
            .getSingle();
        expect(prog.read<int>('last_file_id'), 2);

        // 用户在本地手动切换关联至文件 1 并播放
        await db.customStatement('''
        UPDATE playback_progress SET last_file_id = 1 WHERE work_id = 1;
      ''');

        // 再次导入远端更新（stamp = 2000）
        // 因为已存在的 last_file_id (1) 仍然属于该作品，所以保留本地 last_file_id
        await repo.acceptBatch(
          const SyncBatch(
            deviceId: 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
            sequence: 2,
            records: [
              SyncRecord(
                target: SyncTarget(workType: 'movie', tmdbId: 603),
                kind: SyncRecordKind.progress,
                version: SyncVersion(
                  stamp: 2000,
                  deviceId: 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
                ),
                value: {
                  'positionMs': 24000,
                  'durationMs': 100000,
                  'completed': false,
                },
              ),
            ],
          ),
        );

        prog = await db
            .customSelect(
              'SELECT last_file_id, position_ms FROM playback_progress WHERE work_id = 1',
            )
            .getSingle();
        expect(prog.read<int>('last_file_id'), 1);
        expect(prog.read<int>('position_ms'), 24000);
      },
    );

    test('pending records: imported without local target persist pending and apply on later match', () async {
      final repo = SyncRepository(
        db,
        clock: clock,
        createDeviceId: () => 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      );

      // 远端记录指向 TMDB 999，但本地此时尚未建立该作品
      const remoteBatch = SyncBatch(
        deviceId: 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
        sequence: 1,
        records: [
          SyncRecord(
            target: SyncTarget(workType: 'movie', tmdbId: 999),
            kind: SyncRecordKind.progress,
            version: SyncVersion(
              stamp: 1000,
              deviceId: 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
            ),
            value: {
              'positionMs': 45000,
              'durationMs': 90000,
              'completed': false,
            },
          ),
          SyncRecord(
            target: SyncTarget(workType: 'movie', tmdbId: 999),
            kind: SyncRecordKind.metadata,
            version: SyncVersion(
              stamp: 1000,
              deviceId: 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
            ),
            value: {'title': 'Remote Movie Title', 'year': 2023},
          ),
        ],
      );

      final appliedInitial = await repo.acceptBatch(remoteBatch);
      expect(appliedInitial, 0);

      // 验证写入 pending 状态
      final pendingCount1 = await repo.pendingCount();
      expect(pendingCount1, 1);

      // 后来，本地扫描匹配成功创建了该作品并绑定 TMDB 999
      await db.customStatement('''
        INSERT INTO works (id, type, title) VALUES (10, 'movie', 'Local Placeholder');
      ''');
      await db.customStatement('''
        INSERT INTO external_ids (id, work_id, provider, provider_entity_id)
        VALUES (10, 10, 'tmdb', 'movie:999');
      ''');

      // 执行 applyPending
      final appliedPending = await repo.applyPending();
      expect(appliedPending, 1);

      // 验证 pending 清空
      final pendingCount2 = await repo.pendingCount();
      expect(pendingCount2, 0);

      // 验证真实本地数据已应用
      final work = await db
          .customSelect(
            'SELECT title, metadata_locked FROM works WHERE id = 10',
          )
          .getSingle();
      expect(work.read<String>('title'), 'Local Placeholder');
      expect(work.read<bool>('metadata_locked'), isFalse);

      final prog = await db
          .customSelect(
            'SELECT position_ms FROM playback_progress WHERE work_id = 10',
          )
          .getSingle();
      expect(prog.read<int>('position_ms'), 45000);
    });

    test('series episode progress sync and matching', () async {
      await db.customStatement('''
        INSERT INTO works (id, type, title) VALUES (20, 'series', 'Breaking Bad');
      ''');
      await db.customStatement('''
        INSERT INTO external_ids (id, work_id, provider, provider_entity_id)
        VALUES (20, 20, 'tmdb', 'series:1396');
      ''');
      await db.customStatement('''
        INSERT INTO seasons (id, series_id, season_number, title)
        VALUES (1, 20, 1, 'Season 1');
      ''');
      await db.customStatement('''
        INSERT INTO episodes (id, season_id, episode_number, title)
        VALUES (101, 1, 1, 'Pilot');
      ''');
      await db.customStatement('''
        INSERT INTO media_assignments (id, file_id, episode_id, preferred)
        VALUES (5, 3, 101, 1);
      ''');

      final repo = SyncRepository(
        db,
        clock: clock,
        createDeviceId: () => 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      );

      // 导入剧集分集进度
      final applied = await repo.acceptBatch(
        const SyncBatch(
          deviceId: 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
          sequence: 1,
          records: [
            SyncRecord(
              target: SyncTarget(
                workType: 'series',
                tmdbId: 1396,
                seasonNumber: 1,
                episodeNumber: 1,
              ),
              kind: SyncRecordKind.progress,
              version: SyncVersion(
                stamp: 1500,
                deviceId: 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
              ),
              value: {
                'positionMs': 15000,
                'durationMs': 3000000,
                'completed': false,
              },
            ),
          ],
        ),
      );
      expect(applied, 1);

      final prog = await db
          .customSelect(
            'SELECT target_type, target_id, episode_id, position_ms FROM playback_progress WHERE target_type = ? AND target_id = ?',
            variables: [Variable.withString('episode'), Variable.withInt(101)],
          )
          .getSingle();
      expect(prog.read<String>('target_type'), 'episode');
      expect(prog.read<int>('target_id'), 101);
      expect(prog.read<int>('episode_id'), 101);
      expect(prog.read<int>('position_ms'), 15000);
    });

    test('resetTransport clears cursors and outbox and marks registers dirty without losing local data', () async {
      await db.customStatement('''
        INSERT INTO works (id, type, title, metadata_locked) VALUES (1, 'movie', 'Matrix', 1);
      ''');
      await db.customStatement('''
        INSERT INTO external_ids (id, work_id, provider, provider_entity_id)
        VALUES (1, 1, 'tmdb', 'movie:603');
      ''');

      await db.customStatement(
        "INSERT INTO playback_progress (target_type, target_id, work_id, position_ms) VALUES ('work', 1, 1, 15000)",
      );

      final repo = SyncRepository(
        db,
        clock: clock,
        createDeviceId: () => 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      );

      await repo.captureLocalChanges();
      final batch = await repo.prepareUpload();
      expect(batch, isNotNull);
      await repo.acknowledgeUpload(batch!);

      // 模拟已存在远端游标
      await db.customStatement(
        'INSERT INTO sync_cursors (device_id, last_sequence, updated_at) VALUES (?, ?, ?)',
        ['bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb', 5, 1000],
      );

      // 重置传输状态
      await repo.resetTransport();

      // 游标已清空
      final cursors = await repo.readCursors();
      expect(cursors, isEmpty);

      // 本地数据全部完好
      final work = await db
          .customSelect('SELECT title FROM works WHERE id = 1')
          .getSingle();
      expect(work.read<String>('title'), 'Matrix');

      // 本地寄存器全部被标记为 dirty，后续同步可完整上传至新端点
      final nextBatch = await repo.prepareUpload();
      expect(nextBatch, isNotNull);
      expect(nextBatch!.records, hasLength(1));
    });
    test(
      'old progress is not made newer by another work during initial capture',
      () async {
        await db.customStatement(
          "INSERT INTO works (id, type, title) VALUES (1, 'movie', 'Recent'), (2, 'movie', 'Old')",
        );
        await db.customStatement(
          "INSERT INTO external_ids (work_id, provider, provider_entity_id) VALUES (1, 'tmdb', 'movie:42'), (2, 'tmdb', 'movie:43')",
        );
        await db.customStatement(
          "INSERT INTO playback_progress (target_type, target_id, work_id, position_ms, updated_at) VALUES ('work', 1, 1, 1000, 200), ('work', 2, 2, 1000, 100)",
        );
        final repo = SyncRepository(db);
        await repo.captureLocalChanges();
        await repo.acceptBatch(
          const SyncBatch(
            deviceId: 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
            sequence: 1,
            records: [
              SyncRecord(
                target: SyncTarget(workType: 'movie', tmdbId: 43),
                kind: SyncRecordKind.progress,
                version: SyncVersion(
                  stamp: 150000,
                  deviceId: 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
                ),
                value: {
                  'positionMs': 5000,
                  'durationMs': 60000,
                  'completed': false,
                },
              ),
            ],
          ),
        );
        final oldWorkProgress = await (db.select(
          db.playbackProgresses,
        )..where((p) => p.workId.equals(2))).getSingle();
        expect(oldWorkProgress.positionMs, 5000);
      },
    );

    test('legacy metadata is ignored while progress notifies consumers without upload echo', () async {
      await db.customStatement(
        "INSERT INTO works (id, type, title) VALUES (1, 'movie', 'Before')",
      );
      await db.customStatement(
        "INSERT INTO external_ids (work_id, provider, provider_entity_id) VALUES (1, 'tmdb', 'movie:42')",
      );
      final progressStream = db
          .select(db.playbackProgresses)
          .watch()
          .asBroadcastStream();
      await progressStream.first;
      final progressChanged = progressStream.firstWhere(
        (rows) => rows.any((p) => p.positionMs == 6000),
      );
      final repo = SyncRepository(db);
      await repo.acceptBatch(
        const SyncBatch(
          deviceId: 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
          sequence: 1,
          records: [
            SyncRecord(
              target: SyncTarget(workType: 'movie', tmdbId: 42),
              kind: SyncRecordKind.progress,
              version: SyncVersion(
                stamp: 2000,
                deviceId: 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
              ),
              value: {
                'positionMs': 6000,
                'durationMs': 60000,
                'completed': false,
              },
            ),
            SyncRecord(
              target: SyncTarget(workType: 'movie', tmdbId: 42),
              kind: SyncRecordKind.metadata,
              version: SyncVersion(
                stamp: 2000,
                deviceId: 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
              ),
              value: {
                'title': 'After',
                'year': null,
                'overview': null,
                'posterPath': null,
              },
            ),
          ],
        ),
      );
      expect((await progressChanged).single.positionMs, 6000);
      final work = await db.select(db.works).getSingle();
      expect(work.title, 'Before');
      expect(work.metadataLocked, isFalse);
      await repo.captureLocalChanges();
      expect(await repo.prepareUpload(), isNull);
    });

    test(
      'invalid later record rejects the entire batch without advancing cursor',
      () async {
        final repo = SyncRepository(db);
        await expectLater(
          repo.acceptBatch(
            const SyncBatch(
              deviceId: 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
              sequence: 1,
              records: [
                SyncRecord(
                  target: SyncTarget(workType: 'movie', tmdbId: 42),
                  kind: SyncRecordKind.progress,
                  version: SyncVersion(
                    stamp: 1000,
                    deviceId: 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
                  ),
                  value: {
                    'positionMs': 6000,
                    'durationMs': 60000,
                    'completed': false,
                  },
                ),
                SyncRecord(
                  target: SyncTarget(workType: 'movie', tmdbId: 43),
                  kind: SyncRecordKind.progress,
                  version: SyncVersion(
                    stamp: 1000,
                    deviceId: 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
                  ),
                  value: {
                    'positionMs': 'invalid',
                    'durationMs': 60000,
                    'completed': false,
                  },
                ),
              ],
            ),
          ),
          throwsA(isA<SyncException>()),
        );
        expect(await repo.pendingCount(), 0);
        expect(await repo.readCursors(), isEmpty);
      },
    );
  });
}
