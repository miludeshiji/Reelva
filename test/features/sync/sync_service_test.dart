import 'dart:async';

import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reelva/core/database/app_database.dart';
import 'package:reelva/features/sync/application/sync_service.dart';
import 'package:reelva/features/sync/domain/sync_models.dart';
import 'package:reelva/features/sync/domain/sync_transport.dart';
import 'package:reelva/features/sync/infrastructure/sync_repository.dart';

class _Transport implements SyncTransport {
  final files = <String, SyncBatch>{};
  final listingStarted = Completer<void>();
  Completer<void>? listingGate;
  bool failUpload = false;
  int listings = 0;
  int downloads = 0;

  @override
  Future<List<SyncRemoteBatch>> listBatches() async {
    listings++;
    if (!listingStarted.isCompleted) listingStarted.complete();
    await listingGate?.future;
    return files.values
        .map((b) => SyncRemoteBatch(deviceId: b.deviceId, sequence: b.sequence))
        .toList();
  }

  @override
  Future<SyncBatch> download(SyncRemoteBatch batch) async {
    downloads++;
    return files[batch.fileName]!;
  }

  @override
  Future<void> upload(SyncBatch batch) async {
    if (failUpload) throw const SyncException('网络不可用');
    files[batch.fileName] = batch;
  }
}

void main() {
  late AppDatabase db;
  late SyncRepository repository;
  late _Transport transport;

  setUp(() {
    db = AppDatabase(executor: NativeDatabase.memory());
    repository = SyncRepository(db);
    transport = _Transport();
  });
  tearDown(() => db.close());

  test(
    'concurrent callers share one operation and a later call starts another',
    () async {
      transport.listingGate = Completer<void>();
      final service = SyncService(repository: repository, transport: transport);
      final first = service.synchronize();
      final second = service.synchronize();
      await transport.listingStarted.future;
      expect(transport.listings, 1);
      expect(identical(first, second), isTrue);
      transport.listingGate!.complete();
      await Future.wait([first, second]);
      transport.listingGate = null;
      await service.synchronize();
      expect(transport.listings, 2);
    },
  );

  test('failed upload survives service recreation and retries the frozen batch once', () async {
    final workId = await db
        .into(db.works)
        .insert(
          WorksCompanion.insert(
            title: '本地修正',
            type: const Value('movie'),
            metadataLocked: const Value(true),
          ),
        );
    await db
        .into(db.externalIds)
        .insert(
          ExternalIdsCompanion.insert(
            workId: workId,
            provider: 'tmdb',
            providerEntityId: 'movie:42',
          ),
        );
    transport.failUpload = true;
    final service = SyncService(repository: repository, transport: transport);
    await expectLater(service.synchronize(), throwsA(isA<SyncException>()));
    final frozen = (await repository.prepareUpload())!;
    expect(transport.files, isEmpty);

    transport.failUpload = false;
    final reopenedRepository = SyncRepository(db);
    final retry = SyncService(
      repository: reopenedRepository,
      transport: transport,
    );
    final report = await retry.synchronize();
    expect(report.uploaded, 1);
    expect(transport.files.keys, [frozen.fileName]);
    expect(transport.files.values.single.records.single.value['title'], '本地修正');
    expect(await reopenedRepository.prepareUpload(), isNull);
    expect(transport.downloads, 0);

    final unchanged = await retry.synchronize();
    expect(unchanged.uploaded, 0);
    expect(unchanged.downloaded, 0);
    expect(transport.files.keys, [frozen.fileName]);
  });
}
