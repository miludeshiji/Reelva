import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:reelva/core/database/app_database.dart';
import 'package:reelva/features/library/infrastructure/media_library_repository.dart';
import 'package:reelva/features/metadata/application/nfo_service.dart';
import 'package:reelva/features/metadata/domain/nfo_document.dart';
import 'package:reelva/features/metadata/domain/tmdb_models.dart';
import 'package:reelva/features/sources/domain/openlist_models.dart';
import 'package:reelva/features/sources/domain/source_models.dart';
import 'package:reelva/features/sources/infrastructure/openlist_rpc.dart';
import 'package:reelva/features/sources/infrastructure/openlist_service.dart';
import 'package:reelva/features/sources/infrastructure/openlist_source_adapter.dart';
import 'package:reelva/features/sources/infrastructure/remote_credentials_store.dart';
import 'package:reelva/features/sources/infrastructure/remote_http_client.dart';
import 'package:reelva/features/sources/infrastructure/remote_playback_bridge.dart';

const _accountId = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
final _imageBytes = Uint8List.fromList([0xff, 0xd8, ...List.filled(20, 0)]);

class _ImageHttp extends RemoteHttpClient {
  @override
  Future<Response<dynamic>> request(
    Uri uri, {
    String method = 'GET',
    Map<String, String> headers = const {},
    Object? data,
    ResponseType responseType = ResponseType.json,
    CancelToken? cancelToken,
    Set<int> allowedStatusCodes = const {},
  }) async => Response<dynamic>(
    requestOptions: RequestOptions(path: '$uri'),
    data: ResponseBody.fromBytes(_imageBytes, 200),
  );
}

/// 模拟内核文件协议；读取经过真实 HTTP，写入读取适配器提供的临时文件。
class _CloudRpc implements OpenListRpcClient {
  final files = <String, Uint8List>{};
  final directories = <String>{'/Movies'};
  final uploads = <String>[];
  final pending = <String, ({String path, Uint8List bytes})>{};
  late Uri upstream;
  bool failUploads = false;

  Map<String, dynamic> entry(String path, {bool directory = false}) => {
    'name': p.posix.basename(path),
    'path': path,
    'isDirectory': directory,
    'size': files[path]?.length ?? 0,
    'modifiedAt': 1700000000000,
  };

  @override
  Future<Map<String, dynamic>> invoke(
    String method,
    Map<String, dynamic> arguments,
  ) async {
    final path = arguments['path'] as String?;
    final Map<String, dynamic> data;
    switch (method) {
      case 'accounts':
        data = {
          'accounts': [
            {
              'id': _accountId,
              'driver': 'Quark',
              'addition': {'cookie': 'test-session'},
            },
          ],
        };
      case 'list':
        data = {
          'entries': [
            for (final directory in directories)
              if (p.posix.dirname(directory) == path)
                entry(directory, directory: true),
            for (final file in files.keys)
              if (p.posix.dirname(file) == path) entry(file),
          ],
        };
      case 'link':
        data = {
          'url': upstream.replace(path: path).toString(),
          'headers': <String, String>{},
        };
      case 'upload':
        uploads.add(path!);
        pending[arguments['taskId'] as String] = (
          path: path,
          bytes: await File(arguments['localPath'] as String).readAsBytes(),
        );
        data = {'taskId': arguments['taskId']};
      case 'taskStatus':
        final upload = pending[arguments['taskId']]!;
        if (!failUploads) files[upload.path] = upload.bytes;
        data = {
          'done': true,
          if (failUploads)
            'error': {
              'code': 'operation_failed',
              'message': 'permission denied',
            },
        };
      case 'initialize':
      case 'releaseTask':
      case 'close':
        data = {};
      default:
        throw StateError('Unexpected method: $method');
    }
    return {'data': data};
  }
}

void main() {
  late AppDatabase db;
  late MediaLibraryRepository repository;
  late MediaSourceConfig source;
  late _CloudRpc rpc;
  late OpenListService cloud;
  late OpenListSourceAdapter adapter;
  late NfoService nfo;
  late RemoteHttpClient http;
  late _ImageHttp imageHttp;
  late HttpServer server;

  setUp(() async {
    db = AppDatabase(executor: NativeDatabase.memory());
    repository = MediaLibraryRepository(db);
    source = await repository.upsertSource(
      kind: 'openlist',
      name: '网盘影视',
      rootLocator: buildOpenListRoot(_accountId, '/Movies'),
      credentialRef: OpenListService.credentialReference(_accountId),
    );
    rpc = _CloudRpc();
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    rpc.upstream = Uri.parse('http://127.0.0.1:${server.port}');
    server.listen((request) async {
      final bytes = rpc.files['/${request.uri.pathSegments.join('/')}'];
      if (bytes == null) {
        request.response.statusCode = HttpStatus.notFound;
      } else {
        request.response.add(bytes);
      }
      await request.response.close();
    });
    cloud = OpenListService(
      rpc: rpc,
      credentials: RemoteCredentialsStore(),
      dataDirectory: () async => '/reelva/openlist',
    );
    http = RemoteHttpClient();
    imageHttp = _ImageHttp();
    adapter = OpenListSourceAdapter(
      service: cloud,
      http: http,
      playback: RemotePlaybackBridge(http: http),
    );
    nfo = NfoService(
      repository: repository,
      adapters: {'openlist': adapter},
      http: imageHttp,
    );
  });

  tearDown(() async {
    await cloud.close();
    http.close(force: true);
    imageHttp.close();
    await server.close(force: true);
    await db.close();
  });

  Future<int> index(String relative) async {
    final path = '/Movies/$relative';
    rpc.files[path] = Uint8List.fromList([1, 2, 3]);
    var directory = p.posix.dirname(path);
    while (directory != '/Movies') {
      rpc.directories.add(directory);
      directory = p.posix.dirname(directory);
    }
    final indexed = await repository.indexSourceFiles(source.id, [
      MediaEntry(
        externalId: relative,
        locator: relative,
        name: p.posix.basename(relative),
        isDirectory: false,
        size: 3,
      ),
    ]);
    return indexed.values.single;
  }

  test('网盘电影导出 NFO 和图片，更新保留第三方字段与视频原文', () async {
    final id = await index('电影 #1.mkv');
    rpc.files['/Movies/电影 #1.nfo'] = Uint8List.fromList(
      utf8.encode(
        '<movie><title>旧标题</title><uniqueid type="tmdb">42</uniqueid>'
        '<actor><name>演员</name></actor></movie>',
      ),
    );
    await repository.applyMetadataToFiles(
      {id: null},
      const TmdbWork(
        id: 42,
        type: 'movie',
        title: '电影 & 新标题',
        posterPath: '/poster.jpg',
        backdropPath: '/backdrop.jpg',
      ),
    );
    final result = await nfo.export(fileIds: [id]);
    expect(result.errors, isEmpty);
    expect(result.saved, 1);
    final text = utf8.decode(rpc.files['/Movies/电影 #1.nfo']!);
    final document = NfoDocument.parse(text);
    expect(document.metadata.title, '电影 & 新标题');
    expect(document.metadata.tmdbId, 42);
    expect(document.poster, 'poster.jpg');
    expect(document.fanart, 'fanart.jpg');
    expect(text, contains('<actor>'));
    expect(text, contains('演员'));
    expect(rpc.files['/Movies/poster.jpg'], _imageBytes);
    expect(rpc.files['/Movies/fanart.jpg'], _imageBytes);
    expect(rpc.files['/Movies/电影 #1.mkv'], [1, 2, 3]);
    expect(rpc.uploads, [
      '/Movies/poster.jpg',
      '/Movies/fanart.jpg',
      '/Movies/电影 #1.nfo',
    ]);
  });

  test('跨季网盘剧集向作品目录写 tvshow，分集 NFO 保留真实季集身份', () async {
    const work = TmdbWork(id: 77, type: 'series', title: '剧名');
    for (final season in [1, 2]) {
      final id = await index('剧名/Season 0$season/原名.mkv');
      await repository.applyMetadataToFiles({
        id: TmdbEpisode(
          tmdbId: season * 1000 + 1,
          seasonNumber: season,
          episodeNumber: 1,
          title: '第 $season 季',
        ),
      }, work);
    }
    final result = await nfo.export();
    expect(result.errors, isEmpty);
    expect(result.saved, 2);
    expect(rpc.files.containsKey('/Movies/tvshow.nfo'), isFalse);
    final show = NfoDocument.parse(
      utf8.decode(rpc.files['/Movies/剧名/tvshow.nfo']!),
    );
    expect(show.metadata.tmdbId, 77);
    expect(
      rpc.uploads.where((path) => path.endsWith('tvshow.nfo')),
      hasLength(1),
    );
    for (final season in [1, 2]) {
      final episode = NfoDocument.parse(
        utf8.decode(rpc.files['/Movies/剧名/Season 0$season/原名.nfo']!),
      );
      expect(episode.episode!.tmdbId, season * 1000 + 1);
      expect(episode.episode!.seasonNumber, season);
      expect(episode.episode!.episodeNumber, 1);
    }
  });

  test('网盘拒绝写回时保留匹配，重新导出可恢复', () async {
    final id = await index('movie.mkv');
    await repository.applyMetadataToFiles({
      id: null,
    }, const TmdbWork(id: 10, type: 'movie', title: '已确认电影'));
    rpc.failUploads = true;
    var result = await nfo.export();
    expect(result.saved, 0);
    expect(result.errors, isNotEmpty);
    expect(rpc.files.containsKey('/Movies/movie.nfo'), isFalse);
    final file = (await repository.metadataFiles()).single;
    expect(file.metadata.tmdbId, 10);
    expect(file.locked, isTrue);
    rpc.failUploads = false;
    result = await nfo.export();
    expect(result.saved, 1);
    expect(result.errors, isEmpty);
    expect(rpc.files.containsKey('/Movies/movie.nfo'), isTrue);
  });
}
