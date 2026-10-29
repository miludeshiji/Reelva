import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reelva/features/player/domain/playback_resource.dart';
import 'package:reelva/features/sources/domain/openlist_models.dart';
import 'package:reelva/features/sources/domain/source_models.dart';
import 'package:reelva/features/sources/infrastructure/openlist_rpc.dart';
import 'package:reelva/features/sources/infrastructure/openlist_service.dart';
import 'package:reelva/features/sources/infrastructure/openlist_source_adapter.dart';
import 'package:reelva/features/sources/infrastructure/remote_credentials_store.dart';
import 'package:reelva/features/sources/infrastructure/remote_http_client.dart';
import 'package:reelva/features/sources/infrastructure/remote_playback_bridge.dart';

const _accountId = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

class _AdapterRpc implements OpenListRpcClient {
  final calls = <({String method, Map<String, dynamic> arguments})>[];
  FutureOr<Map<String, dynamic>> Function(String, Map<String, dynamic>)?
  operation;
  void Function(Map<String, dynamic>)? onCancel;

  @override
  Future<Map<String, dynamic>> invoke(
    String method,
    Map<String, dynamic> arguments,
  ) async {
    calls.add((
      method: method,
      arguments: Map<String, dynamic>.from(arguments),
    ));
    if (method == 'accounts') {
      return {
        'data': {
          'accounts': [
            {
              'id': _accountId,
              'driver': 'Quark',
              'addition': {'cookie': 'test-session'},
            },
          ],
        },
      };
    }
    if (method == 'cancel') {
      onCancel?.call(arguments);
      return const {'data': <String, dynamic>{}};
    }
    if (method == 'initialize' ||
        method == 'releaseTask' ||
        method == 'close') {
      return const {'data': <String, dynamic>{}};
    }
    return await operation?.call(method, arguments) ??
        const {'data': <String, dynamic>{}};
  }
}

class _CancellingPlaybackBridge extends RemotePlaybackBridge {
  _CancellingPlaybackBridge({required super.http});
  final token = CancelToken();

  @override
  Future<PlaybackResource> open({
    required String displayName,
    required Future<RemotePlaybackTarget> Function({
      required bool refresh,
      CancelToken? cancelToken,
    })
    resolve,
  }) async {
    final target = await resolve(refresh: false, cancelToken: token);
    return PlaybackResource(uri: target.uri, displayName: displayName);
  }
}

Map<String, dynamic> _entry(
  String name,
  String path, {
  bool directory = false,
  int size = 10,
}) => {
  'name': name,
  'path': path,
  'isDirectory': directory,
  'size': size,
  'modifiedAt': 1700000000000,
};

Matcher _sourceError(String code) =>
    isA<MediaSourceException>().having((error) => error.code, 'code', code);

void main() {
  late _AdapterRpc rpc;
  late OpenListService service;
  late OpenListSourceAdapter adapter;
  late RemoteHttpClient http;
  late HttpServer server;
  late Uri upstream;
  late MediaSourceConfig source;

  setUp(() async {
    rpc = _AdapterRpc();
    service = OpenListService(
      rpc: rpc,
      credentials: RemoteCredentialsStore(),
      dataDirectory: () async => '/reelva/openlist',
    );
    http = RemoteHttpClient();
    adapter = OpenListSourceAdapter(
      service: service,
      http: http,
      playback: RemotePlaybackBridge(http: http),
    );
    source = MediaSourceConfig(
      id: 1,
      kind: 'openlist',
      name: '夸克影视',
      rootLocator: buildOpenListRoot(_accountId, '/Movies'),
      credentialRef: OpenListService.credentialReference(_accountId),
    );
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    upstream = Uri.parse('http://127.0.0.1:${server.port}');
  });

  tearDown(() async {
    http.close(force: true);
    await server.close(force: true);
    await service.close();
  });

  test('目录条目映射为源内相对路径并保留中文、空格及字面量符号', () async {
    const name = 'Episode #1 100% [中文].mkv';
    rpc.operation = (_, _) => {
      'data': {
        'entries': [
          _entry('Show', '/Movies/Show', directory: true),
          _entry(name, '/Movies/$name'),
        ],
      },
    };
    final entries = await adapter
        .listEntries(source, source.rootLocator)
        .toList();
    expect(entries.map((entry) => entry.externalId), ['Show', name]);
    expect(entries.map((entry) => entry.locator), ['Show', name]);
    expect(entries.last.name, name);
    expect(entries.last.size, 10);
    expect(
      entries.last.modifiedAt,
      DateTime.fromMillisecondsSinceEpoch(1700000000000),
    );
    final call = rpc.calls.singleWhere((call) => call.method == 'list');
    expect(call.arguments['path'], '/Movies');
    expect(call.arguments['refresh'], isTrue);
    expect(call.arguments['accountId'], _accountId);
  });

  test('子目录枚举仍返回相对于媒体源根的路径', () async {
    rpc.operation = (_, _) => {
      'data': {
        'entries': [_entry('episode.mkv', '/Movies/Show/Season 1/episode.mkv')],
      },
    };
    final entry = await adapter.listEntries(source, 'Show/Season 1').single;
    expect(entry.externalId, 'Show/Season 1/episode.mkv');
    expect(
      rpc.calls.singleWhere((call) => call.method == 'list').arguments['path'],
      '/Movies/Show/Season 1',
    );
  });

  test('拒绝目录外和非直接子级条目，不将异常伪装为空目录', () async {
    for (final path in ['/Other/movie.mkv', '/Movies/Sub/movie.mkv']) {
      rpc.operation = (_, _) => {
        'data': {
          'entries': [_entry('movie.mkv', path)],
        },
      };
      await expectLater(
        adapter.listEntries(source, source.rootLocator).toList(),
        throwsA(_sourceError('invalid_response')),
      );
    }
    rpc.operation = (_, _) => const {
      'error': {'code': 'unauthorized', 'message': 'cookie=private-session'},
    };
    await expectLater(
      adapter.listEntries(source, source.rootLocator).toList(),
      throwsA(_sourceError('unauthorized')),
    );
    rpc.operation = (_, _) => const {
      'data': {'entries': null},
    };
    await expectLater(
      adapter.listEntries(source, source.rootLocator).toList(),
      throwsA(_sourceError('invalid_response')),
    );
  });

  test('取消某源目录枚举不会取消共享账号下另一个源的请求', () async {
    final second = source.copyWith(
      id: 2,
      rootLocator: buildOpenListRoot(_accountId, '/Other'),
    );
    final entered = Completer<void>();
    final pending = <String, Completer<Map<String, dynamic>>>{};
    final taskIds = <String, String>{};
    rpc.operation = (method, arguments) {
      expect(method, 'list');
      final path = arguments['path'] as String;
      taskIds[path] = arguments['taskId'] as String;
      final result = pending[path] = Completer<Map<String, dynamic>>();
      if (pending.length == 2) entered.complete();
      return result.future;
    };
    rpc.onCancel = (arguments) {
      expect(arguments['taskId'], taskIds['/Movies']);
      pending['/Movies']!.complete(const {
        'error': {'code': 'cancelled'},
      });
    };
    final first = adapter.listEntries(source, source.rootLocator).toList();
    final cancelled = expectLater(first, throwsA(_sourceError('cancelled')));
    final other = adapter.listEntries(second, second.rootLocator).toList();
    await entered.future;
    await adapter.cancelListings(source.id);
    await cancelled;
    expect(pending['/Other']!.isCompleted, isFalse);
    expect(rpc.calls.where((call) => call.method == 'cancel'), hasLength(1));
    pending['/Other']!.complete({
      'data': {
        'entries': [_entry('kept.mkv', '/Other/kept.mkv')],
      },
    });
    expect((await other).single.externalId, 'kept.mkv');
    expect(
      rpc.calls.where((call) => call.method == 'releaseTask'),
      hasLength(2),
    );
  });

  test('根目录之外的输入在调用内核之前失败', () async {
    for (final path in [
      '../outside.mkv',
      '/outside.mkv',
      'https://other.test/file',
      r'Show\outside.mkv',
    ]) {
      await expectLater(
        adapter.resolvePlayback(source, path),
        throwsA(isA<MediaSourceException>()),
      );
    }
    expect(rpc.calls, isEmpty);
  });

  test('stat 使用账号和相对根解析文件路径', () async {
    rpc.operation = (_, _) => {
      'data': _entry('movie.mkv', '/Movies/Show/movie.mkv', size: 1234),
    };
    final stat = await adapter.stat(source, 'Show/movie.mkv');
    expect(stat.size, 1234);
    final call = rpc.calls.singleWhere((call) => call.method == 'stat');
    expect(call.arguments['path'], '/Movies/Show/movie.mkv');
    expect(call.arguments['accountId'], _accountId);
  });

  test('只在 prepare 时解析播放链接，携带完整请求头并在 401 后重取', () async {
    final payload = List<int>.generate(10, (index) => index);
    var links = 0;
    var expireFresh = false;
    final received =
        <({String path, String? ua, String? cookie, String? referer})>[];
    rpc.operation = (method, arguments) {
      expect(method, 'link');
      final path = switch (++links) {
        1 => '/expired',
        2 => '/fresh',
        _ => '/renewed',
      };
      return {
        'data': {
          'url': upstream.resolve(path).toString(),
          'headers': {
            'User-Agent': 'Provider-Playback-UA',
            'Cookie': 'provider=session',
            'Referer': 'https://pan.quark.cn/',
          },
        },
      };
    };
    server.listen((request) async {
      received.add((
        path: request.uri.path,
        ua: request.headers.value(HttpHeaders.userAgentHeader),
        cookie: request.headers.value(HttpHeaders.cookieHeader),
        referer: request.headers.value(HttpHeaders.refererHeader),
      ));
      if (request.uri.path == '/expired' ||
          (expireFresh && request.uri.path == '/fresh')) {
        request.response.statusCode = HttpStatus.unauthorized;
        await request.response.close();
        return;
      }
      final match = RegExp(r'^bytes=(\d+)-(\d*)$')
          .firstMatch(request.headers.value(HttpHeaders.rangeHeader) ?? '');
      final start = match == null ? 0 : int.parse(match[1]!);
      final end = match == null || match[2]!.isEmpty
          ? payload.length - 1
          : int.parse(match[2]!);
      request.response.statusCode = match == null
          ? HttpStatus.ok
          : HttpStatus.partialContent;
      if (match != null) {
        request.response.headers.set(
          HttpHeaders.contentRangeHeader,
          'bytes $start-$end/${payload.length}',
        );
      }
      request.response.contentLength = end - start + 1;
      request.response.add(payload.sublist(start, end + 1));
      await request.response.close();
    });
    final logical = await adapter.resolvePlayback(source, 'Show/movie.mkv');
    expect(links, 0);
    expect(rpc.calls, isEmpty);
    final prepared = await logical.prepare!();
    expect(links, 2);
    expect(prepared.uri.host, '127.0.0.1');
    final client = HttpClient();
    try {
      expireFresh = true;
      final request = await client.getUrl(prepared.uri);
      request.headers.set(HttpHeaders.rangeHeader, 'bytes=4-7');
      final response = await request.close();
      expect(response.statusCode, HttpStatus.partialContent);
      expect(
        await response.fold<List<int>>(
          [],
          (bytes, chunk) => bytes..addAll(chunk),
        ),
        [4, 5, 6, 7],
      );
      expect(links, 3);
      expect(received.map((request) => request.path), [
        '/expired',
        '/fresh',
        '/fresh',
        '/renewed',
      ]);
      expect(
        received.every(
          (request) =>
              request.ua == 'Provider-Playback-UA' &&
              request.cookie == 'provider=session' &&
              request.referer == 'https://pan.quark.cn/',
        ),
        isTrue,
      );
    } finally {
      client.close(force: true);
      await prepared.release?.call();
    }
  });

  test('播放准备取消会转发到当前内核 link 任务并释放任务', () async {
    final bridge = _CancellingPlaybackBridge(http: http);
    adapter = OpenListSourceAdapter(
      service: service,
      http: http,
      playback: bridge,
    );
    final entered = Completer<void>();
    final pendingLink = Completer<Map<String, dynamic>>();
    rpc.operation = (method, arguments) {
      expect(method, 'link');
      entered.complete();
      return pendingLink.future;
    };
    rpc.onCancel = (_) => pendingLink.complete(const {
      'error': {'code': 'cancelled'},
    });
    final logical = await adapter.resolvePlayback(source, 'movie.mkv');
    final preparing = logical.prepare!();
    final cancelled = expectLater(
      preparing,
      throwsA(_sourceError('cancelled')),
    );
    await entered.future;
    bridge.token.cancel();
    await cancelled;
    final link = rpc.calls.singleWhere((call) => call.method == 'link');
    final cancel = rpc.calls.singleWhere((call) => call.method == 'cancel');
    expect(cancel.arguments['taskId'], link.arguments['taskId']);
    expect(cancel.arguments['accountId'], _accountId);
    expect(
      rpc.calls.where((call) => call.method == 'releaseTask'),
      hasLength(1),
    );
  });

  test('下载地址及请求头响应无效时阻止读取', () async {
    for (final url in [
      'file:///private/movie.mkv',
      'https://user:secret@example.test/movie',
      'not-a-url',
    ]) {
      rpc.operation = (_, _) => {
        'data': {'url': url, 'headers': <String, String>{}},
      };
      await expectLater(
        adapter.readBytes(source, 'movie.nfo'),
        throwsA(_sourceError('invalid_response')),
      );
    }
    rpc.operation = (_, _) => {
      'data': {
        'url': upstream.resolve('/movie').toString(),
        'headers': {'Cookie': 42},
      },
    };
    await expectLater(
      adapter.readBytes(source, 'movie.nfo'),
      throwsA(_sourceError('invalid_response')),
    );
  });

  test('读取 NFO 和图片携带源请求头并按最大字节数截断失败', () async {
    final seenCookies = <String?>[];
    rpc.operation = (_, _) => {
      'data': {
        'url': upstream.resolve('/art').toString(),
        'headers': {'Cookie': 'sidecar=session'},
      },
    };
    server.listen((request) async {
      seenCookies.add(request.headers.value(HttpHeaders.cookieHeader));
      request.response.contentLength = 5;
      request.response.add([1, 2, 3, 4, 5]);
      await request.response.close();
    });
    expect(await adapter.readBytes(source, 'poster.jpg', maxBytes: 5), [
      1,
      2,
      3,
      4,
      5,
    ]);
    await expectLater(
      adapter.readBytes(source, 'poster.jpg', maxBytes: 4),
      throwsA(_sourceError('file_too_large')),
    );
    expect(seenCookies, ['sidecar=session', 'sidecar=session']);
  });

  test('小文件读取遇到 403 只重新获取一次直链', () async {
    var links = 0;
    rpc.operation = (_, _) => {
      'data': {
        'url': upstream.resolve(++links == 1 ? '/old' : '/new').toString(),
        'headers': <String, String>{},
      },
    };
    server.listen((request) async {
      if (request.uri.path == '/old') {
        request.response.statusCode = HttpStatus.forbidden;
      } else {
        request.response.add([7, 8]);
      }
      await request.response.close();
    });
    expect(await adapter.readBytes(source, 'movie.nfo'), [7, 8]);
    expect(links, 2);
  });

  test('父目录定位保留源根边界', () async {
    expect(await adapter.parentDirectory(source, source.rootLocator), isNull);
    expect(
      await adapter.parentDirectory(source, 'movie.mkv'),
      source.rootLocator,
    );
    expect(
      await adapter.parentDirectory(source, 'Show/Season 1/movie.mkv'),
      'Show/Season 1',
    );
    await expectLater(
      adapter.parentDirectory(source, '../movie.mkv'),
      throwsA(isA<MediaSourceException>()),
    );
    expect(rpc.calls, isEmpty);
  });

  test('写入在调用内核前拒绝目录越界和无效文件名', () async {
    for (final directory in ['../Other', '/Other', r'Show\Other']) {
      await expectLater(
        adapter.writeBytes(source, directory, 'movie.nfo', Uint8List(1)),
        throwsA(isA<MediaSourceException>()),
      );
    }
    for (final name in ['', '../movie.nfo', r'Show\movie.nfo', '..']) {
      await expectLater(
        adapter.writeBytes(source, source.rootLocator, name, Uint8List(1)),
        throwsA(_sourceError('invalid_name')),
      );
    }
    expect(rpc.calls, isEmpty);
  });

  test('新建前刷新目录，出现同名文件时不上传', () async {
    rpc.operation = (method, arguments) {
      expect(method, 'list');
      expect(arguments['refresh'], isTrue);
      return {
        'data': {
          'entries': [_entry('MOVIE.NFO', '/Movies/MOVIE.NFO')],
        },
      };
    };
    await expectLater(
      adapter.writeBytes(
        source,
        source.rootLocator,
        'movie.nfo',
        Uint8List(1),
        createOnly: true,
      ),
      throwsA(_sourceError('write_conflict')),
    );
    expect(rpc.calls.where((call) => call.method == 'upload'), isEmpty);
  });

  test('根目录 NFO 和子目录图片保持原始字节，上传结束前保留临时文件', () async {
    for (final (directory, name, path) in [
      (source.rootLocator, '电影 #1 100%.nfo', '/Movies/电影 #1 100%.nfo'),
      ('剧名/Season 01', 'poster.jpg', '/Movies/剧名/Season 01/poster.jpg'),
    ]) {
      final bytes = Uint8List.fromList([0xff, 0xd8, 0, 128, 42]);
      final entered = Completer<void>();
      final completed = Completer<Map<String, dynamic>>();
      late File temporary;
      var polls = 0;
      var finished = false;
      rpc.operation = (method, arguments) async {
        switch (method) {
          case 'list':
            return const {
              'data': {'entries': <Map<String, dynamic>>[]},
            };
          case 'upload':
            expect(arguments['accountId'], _accountId);
            expect(arguments['path'], path);
            temporary = File(arguments['localPath'] as String);
            expect(await temporary.readAsBytes(), bytes);
            return {
              'data': {'taskId': arguments['taskId']},
            };
          case 'taskStatus':
            if (++polls == 1) {
              entered.complete();
              return const {
                'data': {'done': false},
              };
            }
            return completed.future;
          default:
            throw StateError('Unexpected method: $method');
        }
      };
      final writing = adapter
          .writeBytes(source, directory, name, bytes, createOnly: true)
          .then((_) => finished = true);
      await entered.future;
      expect(finished, isFalse);
      expect(await temporary.exists(), isTrue);
      final upload = rpc.calls.lastWhere((call) => call.method == 'upload');
      expect(
        rpc.calls.where(
          (call) =>
              call.method == 'releaseTask' &&
              call.arguments['taskId'] == upload.arguments['taskId'],
        ),
        isEmpty,
      );
      completed.complete(const {
        'data': {'done': true},
      });
      await writing;
      expect(await temporary.parent.exists(), isFalse);
      expect(
        rpc.calls.lastWhere((call) => call.method == 'releaseTask').arguments,
        {'accountId': _accountId, 'taskId': upload.arguments['taskId']},
      );
    }
  });

  test('上传失败保留安全错误、清理临时文件并可重试', () async {
    final temporaryFiles = <File>[];
    var fail = true;
    rpc.operation = (method, arguments) {
      if (method == 'upload') {
        temporaryFiles.add(File(arguments['localPath'] as String));
        return {
          'data': {'taskId': arguments['taskId']},
        };
      }
      expect(method, 'taskStatus');
      return {
        'data': {
          'done': true,
          if (fail)
            'error': {
              'code': 'operation_failed',
              'message': 'cookie=private-upload-session https://signed.test/',
            },
        },
      };
    };
    await expectLater(
      adapter.writeBytes(source, source.rootLocator, 'movie.nfo', Uint8List(1)),
      throwsA(
        isA<MediaSourceException>()
            .having((error) => error.code, 'code', 'operation_failed')
            .having(
              (error) => error.toString(),
              'safe text',
              allOf(
                isNot(contains('private-upload-session')),
                isNot(contains('signed.test')),
              ),
            ),
      ),
    );
    expect(await temporaryFiles.single.parent.exists(), isFalse);
    fail = false;
    await adapter.writeBytes(
      source,
      source.rootLocator,
      'movie.nfo',
      Uint8List(1),
    );
    expect(await temporaryFiles.last.parent.exists(), isFalse);
    expect(
      rpc.calls.where((call) => call.method == 'releaseTask'),
      hasLength(2),
    );
  });

  test('取消上传后等待内核真正结束再释放任务和临时文件', () async {
    final entered = Completer<void>();
    final completed = Completer<Map<String, dynamic>>();
    late File temporary;
    var polls = 0;
    rpc.operation = (method, arguments) {
      if (method == 'upload') {
        temporary = File(arguments['localPath'] as String);
        return {
          'data': {'taskId': arguments['taskId']},
        };
      }
      expect(method, 'taskStatus');
      if (++polls == 1) {
        entered.complete();
        return const {
          'data': {'done': false},
        };
      }
      return completed.future;
    };
    final writing = adapter.writeBytes(
      source,
      source.rootLocator,
      'movie.nfo',
      Uint8List(1),
    );
    final cancelled = expectLater(writing, throwsA(_sourceError('cancelled')));
    await entered.future;
    await service.cancelAccount(_accountId);
    expect(await temporary.exists(), isTrue);
    expect(rpc.calls.where((call) => call.method == 'releaseTask'), isEmpty);
    completed.complete(const {
      'data': {'done': true},
    });
    await cancelled;
    expect(await temporary.parent.exists(), isFalse);
    final upload = rpc.calls.singleWhere((call) => call.method == 'upload');
    expect(
      rpc.calls
          .singleWhere((call) => call.method == 'cancel')
          .arguments['taskId'],
      upload.arguments['taskId'],
    );
    expect(
      rpc.calls.where((call) => call.method == 'releaseTask'),
      hasLength(1),
    );
  });
}
