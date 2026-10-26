import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:reelva/features/sources/application/source_providers.dart';
import 'package:reelva/features/metadata/application/metadata_providers.dart';
import 'package:path/path.dart' as p;
import 'package:reelva/core/database/app_database.dart';
import 'package:reelva/features/library/infrastructure/media_library_repository.dart';
import 'package:reelva/features/metadata/application/nfo_service.dart';
import 'package:reelva/features/metadata/domain/nfo_document.dart';
import 'package:reelva/features/metadata/domain/tmdb_models.dart';
import 'package:reelva/features/sources/domain/source_models.dart';
import 'package:reelva/features/sources/infrastructure/local_source_adapter.dart';
import 'package:reelva/features/sources/infrastructure/remote_http_client.dart';

class _ImageHttp extends RemoteHttpClient {
  bool fail = false;
  int requests = 0;
  @override
  Future<Response<dynamic>> request(
    Uri uri, {
    String method = 'GET',
    Map<String, String> headers = const {},
    Object? data,
    ResponseType responseType = ResponseType.json,
    CancelToken? cancelToken,
    Set<int> allowedStatusCodes = const {},
  }) async {
    requests++;
    if (fail) throw const MediaSourceException('图片下载失败');
    return Response<dynamic>(
      requestOptions: RequestOptions(path: '$uri'),
      data: ResponseBody.fromBytes([0xff, 0xd8, ...List.filled(20, 0)], 200),
    );
  }
}

class _IdleMetadata extends MetadataController {
  @override
  Future<void> refresh() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const adapter = LocalSourceAdapter();
  late Directory directory;
  late AppDatabase db;
  late MediaLibraryRepository repository;
  late MediaSourceConfig source;
  late NfoService service;
  late _ImageHttp http;

  Future<void> openDatabase() async {
    db = AppDatabase(executor: NativeDatabase.memory());
    repository = MediaLibraryRepository(db);
    source = await repository.upsertSource(
      kind: 'local',
      name: '媒体',
      rootLocator: directory.path,
    );
    service = NfoService(
      repository: repository,
      adapters: {'local': adapter},
      http: http,
    );
  }

  Future<Map<String, int>> index(String relative) async {
    final file = File(p.join(directory.path, relative));
    await file.parent.create(recursive: true);
    await file.writeAsBytes([1, 2, 3]);
    final entry = (await adapter.listEntries(source, file.parent.path).toList())
        .singleWhere((entry) => entry.name == p.basename(relative));
    return repository.indexSourceFiles(source.id, [entry]);
  }

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('reelva_nfo_');
    http = _ImageHttp();
    await openDatabase();
  });
  tearDown(() async {
    await db.close();
    http.close();
    await directory.delete(recursive: true);
  });

  test('源扫描先导入 NFO，且不把 NFO 和图片登记为视频', () async {
    await File(p.join(directory.path, 'opaque.mkv')).writeAsBytes([1]);
    await File(p.join(directory.path, 'opaque.nfo')).writeAsString(
      '<movie><title>目录标题</title><uniqueid type="tmdb">33</uniqueid></movie>',
    );
    final container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        mediaLibraryRepositoryProvider.overrideWithValue(repository),
        sourceAdaptersProvider.overrideWithValue({'local': adapter}),
        metadataControllerProvider.overrideWith(_IdleMetadata.new),
      ],
    );
    try {
      await container
          .read(sourceControllerProvider.notifier)
          .refreshSource(source.id);
      expect((await repository.metadataFiles()).single.metadata.title, '目录标题');
      expect(await db.select(db.mediaFiles).get(), hasLength(1));
      expect(await File(p.join(directory.path, 'opaque.mkv')).readAsBytes(), [
        1,
      ]);
    } finally {
      container.dispose();
    }
  });

  test('电影 NFO 与图片可从空数据库重新导入，视频不变', () async {
    final indexed = await index('电影 原版.mkv');
    await repository.applyMetadataToFiles(
      {indexed.values.single: null},
      TmdbWork(
        id: 42,
        type: 'movie',
        title: '电影 & 原版',
        year: 2024,
        premiered: DateTime(2024, 3, 2),
        overview: '<简介>',
        posterPath: '/poster.jpg',
        backdropPath: '/backdrop.jpg',
      ),
      manual: false,
    );
    final result = await service.export();
    expect(result.errors, isEmpty);
    expect(result.saved, 1);
    final nfo = File(p.join(directory.path, '电影 原版.nfo'));
    final document = NfoDocument.parse(await nfo.readAsString());
    expect(document.metadata.title, '电影 & 原版');
    expect(document.metadata.tmdbId, 42);
    expect(document.metadata.premiered, DateTime(2024, 3, 2));
    expect(await File(p.join(directory.path, 'poster.jpg')).exists(), isTrue);
    expect(await File(p.join(directory.path, 'fanart.jpg')).exists(), isTrue);
    expect(http.requests, 2);

    await db.close();
    await openDatabase();
    await index('电影 原版.mkv');
    await service.importDirectory(
      source,
      source.rootLocator,
      await adapter.listEntries(source, source.rootLocator).toList(),
    );
    final files = await repository.metadataFiles();
    expect(files.single.metadata.tmdbId, 42);
    expect(files.single.metadata.title, '电影 & 原版');
    final works = await repository.watchWorks().first;
    expect(works.single.posterPath, startsWith('reelva-art:'));
    expect(await File(p.join(directory.path, '电影 原版.mkv')).readAsBytes(), [
      1,
      2,
      3,
    ]);
    expect(http.requests, 2);
  });

  test('跨季导出到电视剧目录，分集保存真实 ID 且能重新关联', () async {
    final first = await index('剧名/Season 01/原名 [01].mkv');
    final second = await index('剧名/Season 02/原名 [13].mkv');
    const work = TmdbWork(id: 77, type: 'series', title: '剧名');
    await repository.applyMetadataToFiles(
      {
        first.values.single: const TmdbEpisode(
          tmdbId: 1001,
          seasonNumber: 1,
          episodeNumber: 1,
          title: '第一集',
        ),
      },
      work,
      manual: false,
    );
    await repository.applyMetadataToFiles(
      {
        second.values.single: const TmdbEpisode(
          tmdbId: 2001,
          seasonNumber: 2,
          episodeNumber: 1,
          title: '新一季',
        ),
      },
      work,
      manual: false,
    );
    final result = await service.export();
    expect(result.errors, isEmpty);
    expect(result.saved, 2);
    final showDirectory = p.join(directory.path, '剧名');
    expect(await File(p.join(showDirectory, 'tvshow.nfo')).exists(), isTrue);
    expect(await File(p.join(directory.path, 'tvshow.nfo')).exists(), isFalse);
    final episode = NfoDocument.parse(
      await File(p.join(showDirectory, 'Season 02', '原名 [13].nfo'))
          .readAsString(),
    );
    expect(episode.episode!.tmdbId, 2001);
    expect(episode.episode!.episodeNumber, 1);

    await db.close();
    await openDatabase();
    await index('剧名/Season 01/原名 [01].mkv');
    await index('剧名/Season 02/原名 [13].mkv');
    final context = await service.importDirectory(
      source,
      showDirectory,
      await adapter.listEntries(source, showDirectory).toList(),
    );
    for (final season in ['Season 01', 'Season 02']) {
      final path = p.join(showDirectory, season);
      await service.importDirectory(
        source,
        path,
        await adapter.listEntries(source, path).toList(),
        inherited: context,
      );
    }
    final files = await repository.metadataFiles();
    expect(files.map((file) => file.workId).toSet(), hasLength(1));
    expect(files.map((file) => file.episode!.tmdbId).toSet(), {1001, 2001});
    expect(files.every((file) => file.metadata.tmdbId == 77), isTrue);
  });

  test('无 TMDB 身份的第三方 NFO 导入，修改保留演员和评分', () async {
    await index('本地电影.mkv');
    final nfo = File(p.join(directory.path, 'movie.nfo'));
    await nfo.writeAsString(
      '<movie><title>人工标题</title><plot>简介</plot>'
      '<actor><name>演员</name></actor><ratings><rating name="custom"><value>8</value></rating></ratings></movie>',
    );
    await service.importDirectory(
      source,
      directory.path,
      await adapter.listEntries(source, directory.path).toList(),
    );
    final files = await repository.metadataFiles();
    expect(files.single.metadata.tmdbId, isNull);
    expect(await db.select(db.externalIds).get(), isEmpty);
    await repository.editMetadata(
      files.single.workId,
      title: '修正标题',
      overview: '新简介',
    );
    final result = await service.export();
    expect(result.errors, isEmpty);
    final text = await nfo.readAsString();
    expect(text, contains('演员'));
    expect(text, contains('<ratings>'));
    expect(NfoDocument.parse(text).metadata.title, '修正标题');
    expect(await File(p.join(directory.path, '本地电影.nfo')).exists(), isFalse);
  });

  test('人工锁不被扫描中的 NFO 覆盖', () async {
    final indexed = await index('movie.mkv');
    await repository.applyMetadataToFiles({
      indexed.values.single: null,
    }, const TmdbWork(id: 10, type: 'movie', title: '人工确认'));
    await File(p.join(directory.path, 'movie.nfo')).writeAsString(
      '<movie><title>其他电影</title><uniqueid type="tmdb">20</uniqueid></movie>',
    );
    await service.importDirectory(
      source,
      directory.path,
      await adapter.listEntries(source, directory.path).toList(),
    );
    expect((await repository.metadataFiles()).single.metadata.title, '人工确认');
    final result = await service.export();
    expect(result.errors, isNotEmpty);
    expect(
      await File(p.join(directory.path, 'movie.nfo')).readAsString(),
      contains('其他电影'),
    );
  });

  test('已写回的人工元数据可读取其他设备的 NFO 更新，未写回修改继续受保护', () async {
    final indexed = await index('movie.mkv');
    await repository.applyMetadataToFiles({
      indexed.values.single: null,
    }, const TmdbWork(id: 10, type: 'movie', title: '最初标题'));
    expect((await service.export()).errors, isEmpty);
    await File(p.join(directory.path, 'movie.nfo')).writeAsString(
      '<movie><title>其他设备修正</title><uniqueid type="tmdb">10</uniqueid></movie>',
    );
    Future<void> readNfo() async {
      await service.importDirectory(
        source,
        directory.path,
        await adapter.listEntries(source, directory.path).toList(),
      );
    }

    await readNfo();
    var file = (await repository.metadataFiles()).single;
    expect(file.metadata.title, '其他设备修正');
    expect(file.locked, isTrue);
    await repository.editMetadata(file.workId, title: '尚未写回的本机修改');
    await readNfo();
    file = (await repository.metadataFiles()).single;
    expect(file.metadata.title, '尚未写回的本机修改');
  });

  test('图片失败仍保存文字 NFO，不回滚匹配', () async {
    final indexed = await index('movie.mkv');
    await repository.applyMetadataToFiles(
      {indexed.values.single: null},
      const TmdbWork(
        id: 10,
        type: 'movie',
        title: '电影',
        posterPath: '/cover.jpg',
      ),
      manual: false,
    );
    http.fail = true;
    final result = await service.export();
    expect(result.saved, 1);
    expect(result.errors, isNotEmpty);
    expect(await File(p.join(directory.path, 'movie.nfo')).exists(), isTrue);
    expect((await repository.metadataFiles()).single.metadata.tmdbId, 10);
  });

  test('损坏 NFO 不被导出覆盖，错误可重试', () async {
    final indexed = await index('movie.mkv');
    await repository.applyMetadataToFiles(
      {indexed.values.single: null},
      const TmdbWork(id: 10, type: 'movie', title: '电影'),
      manual: false,
    );
    final file = File(p.join(directory.path, 'movie.nfo'));
    await file.writeAsString('<movie><title>broken');
    final result = await service.export();
    expect(result.saved, 0);
    expect(result.errors, isNotEmpty);
    expect(await file.readAsString(), '<movie><title>broken');
    await file.delete();
    expect((await service.export()).saved, 1);
  });

  test('同目录多部电影使用各自的 NFO 和图片名称', () async {
    final first = await index('A.mkv');
    final second = await index('B.mkv');
    await repository.applyMetadataToFiles(
      {first.values.single: null},
      const TmdbWork(id: 1, type: 'movie', title: 'A', posterPath: '/a.jpg'),
      manual: false,
    );
    await repository.applyMetadataToFiles(
      {second.values.single: null},
      const TmdbWork(id: 2, type: 'movie', title: 'B', posterPath: '/b.jpg'),
      manual: false,
    );
    expect((await service.export()).errors, isEmpty);
    expect(await File(p.join(directory.path, 'A-poster.jpg')).exists(), isTrue);
    expect(await File(p.join(directory.path, 'B-poster.jpg')).exists(), isTrue);
    expect(await File(p.join(directory.path, 'poster.jpg')).exists(), isFalse);
  });

  test('本地附属文件读取有界，写入不能逃出授权目录', () async {
    await File(p.join(directory.path, 'large.nfo'))
        .writeAsBytes(List.filled(30, 65));
    await expectLater(
      adapter.readBytes(source, 'large.nfo', maxBytes: 20),
      throwsA(isA<MediaSourceException>()),
    );
    await expectLater(
      adapter.writeBytes(source, directory.path, '../escape.nfo', Uint8List(0)),
      throwsA(isA<MediaSourceException>()),
    );
    await expectLater(
      adapter.writeBytes(
        source,
        p.dirname(directory.path),
        'escape.nfo',
        Uint8List(0),
      ),
      throwsA(isA<MediaSourceException>()),
    );
  });
}
