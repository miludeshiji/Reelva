import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reelva/features/player/domain/playback_resource.dart';
import 'package:reelva/features/sources/domain/source_models.dart';
import 'package:reelva/features/sources/infrastructure/openlist_source_adapter.dart';
import 'package:reelva/features/sources/infrastructure/remote_credentials_store.dart';
import 'package:reelva/features/sources/infrastructure/remote_http_client.dart';
import 'package:reelva/features/sources/infrastructure/remote_playback_bridge.dart';

class _FakeRemoteHttpClient extends RemoteHttpClient {
  _FakeRemoteHttpClient();

  Future<Response<dynamic>> Function(
    Uri uri, {
    required String method,
    required Map<String, String> headers,
    required Object? data,
    required ResponseType responseType,
    required Set<int> allowedStatusCodes,
  })?
  handler;

  final List<
    ({Uri uri, String method, Map<String, String> headers, Object? data})
  >
  recordedRequests = [];

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
    recordedRequests.add((
      uri: uri,
      method: method,
      headers: headers,
      data: data,
    ));

    if (handler != null) {
      return handler!(
        uri,
        method: method,
        headers: headers,
        data: data,
        responseType: responseType,
        allowedStatusCodes: allowedStatusCodes,
      );
    }

    return Response<dynamic>(
      requestOptions: RequestOptions(path: uri.toString()),
      statusCode: 200,
      data: <String, dynamic>{'code': 200, 'message': 'success', 'data': null},
    );
  }
}

class _FakeRemoteCredentialsStore extends RemoteCredentialsStore {
  final Map<String, RemoteCredentials> store = {};
  int readCount = 0;

  @override
  Future<RemoteCredentials> read(String? reference) async {
    readCount++;
    if (reference == null || reference.isEmpty) {
      return const RemoteCredentials.anonymous();
    }
    final creds = store[reference];
    if (creds == null) {
      throw const MediaSourceException('未找到指定凭据记录', code: 'credential_missing');
    }
    return creds;
  }

  @override
  Future<void> write(String reference, RemoteCredentials credentials) async {
    store[reference] = credentials;
  }

  @override
  Future<void> delete(String reference) async {
    store.remove(reference);
  }
}

class _FakeRemotePlaybackBridge extends RemotePlaybackBridge {
  _FakeRemotePlaybackBridge() : super(http: RemoteHttpClient());

  String? lastDisplayName;
  Future<RemotePlaybackTarget> Function({
    required bool refresh,
    CancelToken? cancelToken,
  })?
  lastResolver;
  RemotePlaybackTarget? lastTarget;

  @override
  Future<PlaybackResource> open({
    required String displayName,
    required Future<RemotePlaybackTarget> Function({
      required bool refresh,
      CancelToken? cancelToken,
    })
    resolve,
  }) async {
    lastDisplayName = displayName;
    lastResolver = resolve;
    final target = await resolve(refresh: false);
    lastTarget = target;
    return PlaybackResource(
      uri: Uri.parse('http://127.0.0.1:9999/relay'),
      displayName: displayName,
      httpHeaders: target.headers,
    );
  }
}

class _RealHttpOverrides extends HttpOverrides {}

void main() {
  group('OpenListSourceAdapter Unit Tests', () {
    late _FakeRemoteHttpClient httpClient;
    late _FakeRemoteCredentialsStore credentialsStore;
    late _FakeRemotePlaybackBridge playbackBridge;
    late OpenListSourceAdapter adapter;
    late MediaSourceConfig source;

    setUp(() {
      httpClient = _FakeRemoteHttpClient();
      credentialsStore = _FakeRemoteCredentialsStore();
      playbackBridge = _FakeRemotePlaybackBridge();
      adapter = OpenListSourceAdapter(
        credentials: credentialsStore,
        http: httpClient,
        playback: playbackBridge,
      );
      source = const MediaSourceConfig(
        id: 1,
        kind: 'openlist',
        name: 'OpenList Server',
        rootLocator: 'http://127.0.0.1:15244#/Media',
      );
      credentialsStore.store['cred_1'] = const RemoteCredentials.anonymous();
    });

    test('pickDirectory throws remote_configuration_required', () async {
      expect(
        () => adapter.pickDirectory(),
        throwsA(
          isA<MediaSourceException>().having(
            (e) => e.code,
            'code',
            'remote_configuration_required',
          ),
        ),
      );
    });

    group('rootLocator validation and normalization', () {
      test('rejects rootLocator with userInfo credentials', () async {
        final invalid = source.copyWith(
          rootLocator: 'http://user:pass@127.0.0.1:15244#/Media',
        );
        expect(
          () => adapter.listEntries(invalid, invalid.rootLocator).toList(),
          throwsA(
            isA<MediaSourceException>().having(
              (e) => e.code,
              'code',
              'credentials_in_url',
            ),
          ),
        );
      });

      test('rejects rootLocator with query parameters', () async {
        final invalid = source.copyWith(
          rootLocator: 'http://127.0.0.1:15244?token=secret#/Media',
        );
        expect(
          () => adapter.listEntries(invalid, invalid.rootLocator).toList(),
          throwsA(
            isA<MediaSourceException>().having(
              (e) => e.code,
              'code',
              'query_in_url',
            ),
          ),
        );
      });

      test('rejects invalid schemes or missing host', () async {
        final invalidScheme = source.copyWith(
          rootLocator: 'ftp://127.0.0.1:15244#/Media',
        );
        expect(
          () => adapter
              .listEntries(invalidScheme, invalidScheme.rootLocator)
              .toList(),
          throwsA(
            isA<MediaSourceException>().having(
              (e) => e.code,
              'code',
              'invalid_url',
            ),
          ),
        );

        final emptyHost = source.copyWith(rootLocator: 'http://#/Media');
        expect(
          () => adapter.listEntries(emptyHost, emptyHost.rootLocator).toList(),
          throwsA(
            isA<MediaSourceException>().having(
              (e) => e.code,
              'code',
              'invalid_url',
            ),
          ),
        );
      });

      test('rejects root paths with relative dot segments', () async {
        final invalidDot = source.copyWith(
          rootLocator: 'http://127.0.0.1:15244#/Media/../escape',
        );
        expect(
          () =>
              adapter.listEntries(invalidDot, invalidDot.rootLocator).toList(),
          throwsA(
            isA<MediaSourceException>().having(
              (e) => e.code,
              'code',
              'path_escape',
            ),
          ),
        );
      });

      test(
        'defaults to / root path when fragment is absent or empty',
        () async {
          final noFragment = source.copyWith(
            rootLocator: 'http://127.0.0.1:15244',
          );

          httpClient.handler =
              (
                uri, {
                required method,
                required headers,
                required data,
                required responseType,
                required allowedStatusCodes,
              }) async {
                expect(uri.toString(), 'http://127.0.0.1:15244/api/fs/list');
                final reqJson =
                    jsonDecode(data as String) as Map<String, dynamic>;
                expect(reqJson['path'], '/');
                return Response<dynamic>(
                  requestOptions: RequestOptions(path: uri.toString()),
                  statusCode: 200,
                  data: <String, dynamic>{
                    'code': 200,
                    'message': 'success',
                    'data': <String, dynamic>{
                      'content': <dynamic>[],
                      'total': 0,
                    },
                  },
                );
              };

          final list = await adapter
              .listEntries(noFragment, noFragment.rootLocator)
              .toList();
          expect(list, isEmpty);
        },
      );

      test('decodes percent-encoded fragment correctly', () async {
        final encodedFragment = source.copyWith(
          rootLocator: 'http://127.0.0.1:15244#/%E7%94%B5%E5%BD%B1',
        );

        httpClient.handler =
            (
              uri, {
              required method,
              required headers,
              required data,
              required responseType,
              required allowedStatusCodes,
            }) async {
              final reqJson =
                  jsonDecode(data as String) as Map<String, dynamic>;
              expect(reqJson['path'], '/电影');
              return Response<dynamic>(
                requestOptions: RequestOptions(path: uri.toString()),
                statusCode: 200,
                data: <String, dynamic>{
                  'code': 200,
                  'message': 'success',
                  'data': <String, dynamic>{'content': <dynamic>[], 'total': 0},
                },
              );
            };

        final list = await adapter
            .listEntries(encodedFragment, encodedFragment.rootLocator)
            .toList();
        expect(list, isEmpty);
      });
    });

    group('strict containment and path escape prevention', () {
      test('rejects directoryId attempting escape via ..', () async {
        expect(
          () => adapter.listEntries(source, '/Media/../Other').toList(),
          throwsA(
            isA<MediaSourceException>().having(
              (e) => e.code,
              'code',
              'path_escape',
            ),
          ),
        );

        expect(
          () => adapter.stat(source, '/Media/sub/../../etc/passwd'),
          throwsA(
            isA<MediaSourceException>().having(
              (e) => e.code,
              'code',
              'path_escape',
            ),
          ),
        );
      });

      test('rejects path outside root scope', () async {
        expect(
          () => adapter.listEntries(source, '/OtherScope').toList(),
          throwsA(
            isA<MediaSourceException>().having(
              (e) => e.code,
              'code',
              'path_escape',
            ),
          ),
        );

        expect(
          () => adapter.stat(source, '/MediaEscape'),
          throwsA(
            isA<MediaSourceException>().having(
              (e) => e.code,
              'code',
              'path_escape',
            ),
          ),
        );
      });

      test('rejects foreign origin URL as directoryId', () async {
        expect(
          () => adapter.stat(source, 'http://attacker.com/Media/file.mp4'),
          throwsA(
            isA<MediaSourceException>().having(
              (e) => e.code,
              'code',
              'path_escape',
            ),
          ),
        );
      });

      test(
        'supports paths containing spaces, #, %, and Chinese characters',
        () async {
          httpClient.handler =
              (
                uri, {
                required method,
                required headers,
                required data,
                required responseType,
                required allowedStatusCodes,
              }) async {
                expect(uri.toString(), 'http://127.0.0.1:15244/api/fs/get');
                final reqJson =
                    jsonDecode(data as String) as Map<String, dynamic>;
                expect(reqJson['path'], '/Media/特辑 #1 100% 电影/preview.mp4');

                return Response<dynamic>(
                  requestOptions: RequestOptions(path: uri.toString()),
                  statusCode: 200,
                  data: <String, dynamic>{
                    'code': 200,
                    'message': 'success',
                    'data': <String, dynamic>{
                      'name': 'preview.mp4',
                      'size': 1024,
                      'is_dir': false,
                      'modified': '2026-10-23T10:00:00Z',
                      'sign': 'temporary_sign_credential',
                      'hash_info': <String, dynamic>{
                        'sha256': 'hash_test_sha256',
                      },
                    },
                  },
                );
              };

          final stat = await adapter.stat(
            source,
            '/Media/特辑 #1 100% 电影/preview.mp4',
          );
          expect(stat.size, 1024);
          expect(stat.etag, 'hash_test_sha256');
        },
      );
    });

    group('listEntries and pagination consistency', () {
      test('sends raw Authorization token and directory password', () async {
        final authSource = source.copyWith(credentialRef: 'cred_1');
        await credentialsStore.write(
          'cred_1',
          const RemoteCredentials(
            token: 'raw_api_token_123',
            password: 'dir_password_456',
          ),
        );

        httpClient.handler =
            (
              uri, {
              required method,
              required headers,
              required data,
              required responseType,
              required allowedStatusCodes,
            }) async {
              expect(headers['Authorization'], 'raw_api_token_123');
              expect(headers['Authorization']!.startsWith('Bearer '), isFalse);

              final reqJson =
                  jsonDecode(data as String) as Map<String, dynamic>;
              expect(reqJson['password'], 'dir_password_456');
              expect(reqJson['path'], '/Media');
              expect(reqJson['page'], 1);
              expect(reqJson['per_page'], 100);

              return Response<dynamic>(
                requestOptions: RequestOptions(path: uri.toString()),
                statusCode: 200,
                data: <String, dynamic>{
                  'code': 200,
                  'message': 'success',
                  'data': <String, dynamic>{
                    'content': <dynamic>[
                      <String, dynamic>{
                        'name': 'movie.mp4',
                        'size': 5000,
                        'is_dir': false,
                        'modified': '2026-10-23T12:00:00Z',
                        'sign': 'temporary_sign_123',
                        'hash_info': <String, dynamic>{'md5': 'hash_md5_abc'},
                      },
                    ],
                    'total': 1,
                  },
                },
              );
            };

        final entries = await adapter
            .listEntries(authSource, authSource.rootLocator)
            .toList();

        expect(entries.length, 1);
        expect(entries[0].name, 'movie.mp4');
        expect(entries[0].externalId, '/Media/movie.mp4');
        expect(entries[0].locator, '/Media/movie.mp4');
        expect(entries[0].size, 5000);
        expect(entries[0].etag, 'hash_md5_abc');
        expect(entries[0].modifiedAt, DateTime.utc(2026, 10, 23, 12, 0, 0));
      });

      test('never stores sign as etag when only sign is present', () async {
        httpClient.handler =
            (
              uri, {
              required method,
              required headers,
              required data,
              required responseType,
              required allowedStatusCodes,
            }) async {
              return Response<dynamic>(
                requestOptions: RequestOptions(path: uri.toString()),
                statusCode: 200,
                data: <String, dynamic>{
                  'code': 200,
                  'message': 'success',
                  'data': <String, dynamic>{
                    'content': <dynamic>[
                      <String, dynamic>{
                        'name': 'nosign.mp4',
                        'size': 1234,
                        'is_dir': false,
                        'sign': 'ephemeral_download_credential_token',
                        'hash_info': null,
                      },
                    ],
                    'total': 1,
                  },
                },
              );
            };

        final entries = await adapter
            .listEntries(source, source.rootLocator)
            .toList();

        expect(entries.length, 1);
        expect(entries[0].etag, isNull);
      });

      test('handles multi-page pagination (page 1 + page 2)', () async {
        int requestedPage = 0;

        httpClient.handler =
            (
              uri, {
              required method,
              required headers,
              required data,
              required responseType,
              required allowedStatusCodes,
            }) async {
              final reqJson =
                  jsonDecode(data as String) as Map<String, dynamic>;
              final page = reqJson['page'] as int;
              requestedPage++;

              if (page == 1) {
                final page1Content = List.generate(
                  100,
                  (i) => <String, dynamic>{
                    'name': 'video_$i.mp4',
                    'size': 1000 + i,
                    'is_dir': false,
                  },
                );
                return Response<dynamic>(
                  requestOptions: RequestOptions(path: uri.toString()),
                  statusCode: 200,
                  data: <String, dynamic>{
                    'code': 200,
                    'message': 'success',
                    'data': <String, dynamic>{
                      'content': page1Content,
                      'total': 150,
                    },
                  },
                );
              } else if (page == 2) {
                final page2Content = List.generate(
                  50,
                  (i) => <String, dynamic>{
                    'name': 'video_${100 + i}.mp4',
                    'size': 2000 + i,
                    'is_dir': false,
                  },
                );
                return Response<dynamic>(
                  requestOptions: RequestOptions(path: uri.toString()),
                  statusCode: 200,
                  data: <String, dynamic>{
                    'code': 200,
                    'message': 'success',
                    'data': <String, dynamic>{
                      'content': page2Content,
                      'total': 150,
                    },
                  },
                );
              }

              throw StateError('Unexpected page: $page');
            };

        final entries = await adapter
            .listEntries(source, source.rootLocator)
            .toList();

        expect(entries.length, 150);
        expect(requestedPage, 2);
        expect(entries[0].name, 'video_0.mp4');
        expect(entries[0].externalId, '/Media/video_0.mp4');
        expect(entries[99].name, 'video_99.mp4');
        expect(entries[100].name, 'video_100.mp4');
        expect(entries[149].name, 'video_149.mp4');
      });

      test('handles empty directory when content is null (Go nil)', () async {
        httpClient.handler =
            (
              uri, {
              required method,
              required headers,
              required data,
              required responseType,
              required allowedStatusCodes,
            }) async {
              return Response<dynamic>(
                requestOptions: RequestOptions(path: uri.toString()),
                statusCode: 200,
                data: <String, dynamic>{
                  'code': 200,
                  'message': 'success',
                  'data': <String, dynamic>{'content': null, 'total': 0},
                },
              );
            };

        final entries = await adapter
            .listEntries(source, source.rootLocator)
            .toList();
        expect(entries, isEmpty);
      });

      test(
        'pagination failure throws pagination_error when prematurely truncated',
        () async {
          httpClient.handler =
              (
                uri, {
                required method,
                required headers,
                required data,
                required responseType,
                required allowedStatusCodes,
              }) async {
                return Response<dynamic>(
                  requestOptions: RequestOptions(path: uri.toString()),
                  statusCode: 200,
                  data: <String, dynamic>{
                    'code': 200,
                    'message': 'success',
                    'data': <String, dynamic>{
                      // 返回 50 项（少于 100 项），但 total 声称为 150
                      'content': List.generate(
                        50,
                        (i) => <String, dynamic>{
                          'name': 'file_$i.mp4',
                          'size': 100,
                          'is_dir': false,
                        },
                      ),
                      'total': 150,
                    },
                  },
                );
              };

          expect(
            () => adapter.listEntries(source, source.rootLocator).toList(),
            throwsA(
              isA<MediaSourceException>().having(
                (e) => e.code,
                'code',
                'pagination_error',
              ),
            ),
          );
        },
      );

      test('pagination failure throws pagination_error when page 2 returns empty list while total remains unreached', () async {
        httpClient.handler =
            (
              uri, {
              required method,
              required headers,
              required data,
              required responseType,
              required allowedStatusCodes,
            }) async {
              final reqJson =
                  jsonDecode(data as String) as Map<String, dynamic>;
              final page = reqJson['page'] as int;
              if (page == 1) {
                return Response<dynamic>(
                  requestOptions: RequestOptions(path: uri.toString()),
                  statusCode: 200,
                  data: <String, dynamic>{
                    'code': 200,
                    'message': 'success',
                    'data': <String, dynamic>{
                      'content': List.generate(
                        100,
                        (i) => <String, dynamic>{
                          'name': 'file_$i.mp4',
                          'size': 100,
                          'is_dir': false,
                        },
                      ),
                      'total': 150,
                    },
                  },
                );
              } else {
                return Response<dynamic>(
                  requestOptions: RequestOptions(path: uri.toString()),
                  statusCode: 200,
                  data: <String, dynamic>{
                    'code': 200,
                    'message': 'success',
                    'data': <String, dynamic>{
                      'content': <dynamic>[],
                      'total': 150,
                    },
                  },
                );
              }
            };

        expect(
          () => adapter.listEntries(source, source.rootLocator).toList(),
          throwsA(
            isA<MediaSourceException>().having(
              (e) => e.code,
              'code',
              'pagination_error',
            ),
          ),
        );
      });

      test('handles API envelope error codes safely', () async {
        httpClient.handler =
            (
              uri, {
              required method,
              required headers,
              required data,
              required responseType,
              required allowedStatusCodes,
            }) async {
              return Response<dynamic>(
                requestOptions: RequestOptions(path: uri.toString()),
                statusCode: 200,
                data: <String, dynamic>{
                  'code': 401,
                  'message': 'Guest user is disabled, login please',
                  'data': null,
                },
              );
            };

        expect(
          () => adapter.listEntries(source, source.rootLocator).toList(),
          throwsA(
            isA<MediaSourceException>().having(
              (e) => e.code,
              'code',
              'unauthorized',
            ),
          ),
        );
      });

      test('handles forbidden 403 envelope safely', () async {
        httpClient.handler =
            (
              uri, {
              required method,
              required headers,
              required data,
              required responseType,
              required allowedStatusCodes,
            }) async {
              return Response<dynamic>(
                requestOptions: RequestOptions(path: uri.toString()),
                statusCode: 200,
                data: <String, dynamic>{
                  'code': 403,
                  'message': 'Invalid password',
                  'data': null,
                },
              );
            };

        expect(
          () => adapter.listEntries(source, source.rootLocator).toList(),
          throwsA(
            isA<MediaSourceException>().having(
              (e) => e.code,
              'code',
              'forbidden',
            ),
          ),
        );
      });

      test('rejects missing data field even on page 1', () async {
        httpClient.handler =
            (
              uri, {
              required method,
              required headers,
              required data,
              required responseType,
              required allowedStatusCodes,
            }) async {
              return Response<dynamic>(
                requestOptions: RequestOptions(path: uri.toString()),
                statusCode: 200,
                data: <String, dynamic>{
                  'code': 200,
                  'message': 'success',
                  'data': null,
                },
              );
            };

        expect(
          () => adapter.listEntries(source, source.rootLocator).toList(),
          throwsA(
            isA<MediaSourceException>().having(
              (e) => e.code,
              'code',
              'invalid_response',
            ),
          ),
        );
      });

      test('rejects empty content when total > 0 on page 1 (prevents clearing library)', () async {
        httpClient.handler =
            (
              uri, {
              required method,
              required headers,
              required data,
              required responseType,
              required allowedStatusCodes,
            }) async {
              return Response<dynamic>(
                requestOptions: RequestOptions(path: uri.toString()),
                statusCode: 200,
                data: <String, dynamic>{
                  'code': 200,
                  'message': 'success',
                  'data': <String, dynamic>{
                    'content': <dynamic>[],
                    'total': 10,
                  },
                },
              );
            };

        expect(
          () => adapter.listEntries(source, source.rootLocator).toList(),
          throwsA(
            isA<MediaSourceException>().having(
              (e) => e.code,
              'code',
              'pagination_error',
            ),
          ),
        );
      });

      test(
        'rejects entry name with slash, backslash, dot segments or empty',
        () async {
          for (final invalidName in [
            'sub/movie.mp4',
            r'sub\movie.mp4',
            '.',
            '..',
            '   ',
          ]) {
            httpClient.handler =
                (
                  uri, {
                  required method,
                  required headers,
                  required data,
                  required responseType,
                  required allowedStatusCodes,
                }) async {
                  return Response<dynamic>(
                    requestOptions: RequestOptions(path: uri.toString()),
                    statusCode: 200,
                    data: <String, dynamic>{
                      'code': 200,
                      'message': 'success',
                      'data': <String, dynamic>{
                        'content': <dynamic>[
                          <String, dynamic>{
                            'name': invalidName,
                            'size': 100,
                            'is_dir': false,
                          },
                        ],
                        'total': 1,
                      },
                    },
                  );
                };

            expect(
              () => adapter.listEntries(source, source.rootLocator).toList(),
              throwsA(
                isA<MediaSourceException>().having(
                  (e) => e.code,
                  'code',
                  'invalid_response',
                ),
              ),
              reason: 'Should reject invalid entry name: "$invalidName"',
            );
          }
        },
      );

      test('rejects entry with non-boolean is_dir', () async {
        httpClient.handler =
            (
              uri, {
              required method,
              required headers,
              required data,
              required responseType,
              required allowedStatusCodes,
            }) async {
              return Response<dynamic>(
                requestOptions: RequestOptions(path: uri.toString()),
                statusCode: 200,
                data: <String, dynamic>{
                  'code': 200,
                  'message': 'success',
                  'data': <String, dynamic>{
                    'content': <dynamic>[
                      <String, dynamic>{
                        'name': 'invalid_dir.mp4',
                        'size': 100,
                        'is_dir': 'true', // string, not bool
                      },
                    ],
                    'total': 1,
                  },
                },
              );
            };

        expect(
          () => adapter.listEntries(source, source.rootLocator).toList(),
          throwsA(
            isA<MediaSourceException>().having(
              (e) => e.code,
              'code',
              'invalid_response',
            ),
          ),
        );
      });

      test('rejects entry with negative or non-num size', () async {
        httpClient.handler =
            (
              uri, {
              required method,
              required headers,
              required data,
              required responseType,
              required allowedStatusCodes,
            }) async {
              return Response<dynamic>(
                requestOptions: RequestOptions(path: uri.toString()),
                statusCode: 200,
                data: <String, dynamic>{
                  'code': 200,
                  'message': 'success',
                  'data': <String, dynamic>{
                    'content': <dynamic>[
                      <String, dynamic>{
                        'name': 'negative_size.mp4',
                        'size': -500,
                        'is_dir': false,
                      },
                    ],
                    'total': 1,
                  },
                },
              );
            };

        expect(
          () => adapter.listEntries(source, source.rootLocator).toList(),
          throwsA(
            isA<MediaSourceException>().having(
              (e) => e.code,
              'code',
              'invalid_response',
            ),
          ),
        );
      });

      test(
        'rejects duplicate child path / repeated page across pagination',
        () async {
          httpClient.handler =
              (
                uri, {
                required method,
                required headers,
                required data,
                required responseType,
                required allowedStatusCodes,
              }) async {
                jsonDecode(data as String);
                return Response<dynamic>(
                  requestOptions: RequestOptions(path: uri.toString()),
                  statusCode: 200,
                  data: <String, dynamic>{
                    'code': 200,
                    'message': 'success',
                    'data': <String, dynamic>{
                      // 模拟服务端分页 Bug 重复返回相同条目
                      'content': <dynamic>[
                        <String, dynamic>{
                          'name': 'duplicate_file.mp4',
                          'size': 100,
                          'is_dir': false,
                        },
                      ],
                      'total': 2,
                    },
                  },
                );
              };

          expect(
            () => adapter.listEntries(source, source.rootLocator).toList(),
            throwsA(
              isA<MediaSourceException>().having(
                (e) => e.code,
                'code',
                'pagination_error',
              ),
            ),
          );
        },
      );

      test('rejects pagination overshooting total', () async {
        httpClient.handler =
            (
              uri, {
              required method,
              required headers,
              required data,
              required responseType,
              required allowedStatusCodes,
            }) async {
              return Response<dynamic>(
                requestOptions: RequestOptions(path: uri.toString()),
                statusCode: 200,
                data: <String, dynamic>{
                  'code': 200,
                  'message': 'success',
                  'data': <String, dynamic>{
                    // 返回 2 项但 total 声称仅有 1 项
                    'content': <dynamic>[
                      <String, dynamic>{
                        'name': 'file1.mp4',
                        'size': 100,
                        'is_dir': false,
                      },
                      <String, dynamic>{
                        'name': 'file2.mp4',
                        'size': 200,
                        'is_dir': false,
                      },
                    ],
                    'total': 1,
                  },
                },
              );
            };

        expect(
          () => adapter.listEntries(source, source.rootLocator).toList(),
          throwsA(
            isA<MediaSourceException>().having(
              (e) => e.code,
              'code',
              'pagination_error',
            ),
          ),
        );
      });

      test(
        'exception secrecy: never echoes upstream message containing secrets',
        () async {
          httpClient.handler =
              (
                uri, {
                required method,
                required headers,
                required data,
                required responseType,
                required allowedStatusCodes,
              }) async {
                return Response<dynamic>(
                  requestOptions: RequestOptions(path: uri.toString()),
                  statusCode: 200,
                  data: <String, dynamic>{
                    'code': 401,
                    'message': 'Sensitive Token=secret_tok_123 Cookie=session_xyz signedURL=https://oss.example.com/movie.mp4?sign=leak',
                    'data': null,
                  },
                );
              };

          try {
            await adapter.listEntries(source, source.rootLocator).toList();
            fail('Should have thrown MediaSourceException');
          } on MediaSourceException catch (e) {
            expect(e.code, 'unauthorized');
            expect(e.message, 'OpenList 认证失败: 未授权');
            expect(e.message.contains('secret_tok_123'), isFalse);
            expect(e.message.contains('Cookie'), isFalse);
            expect(e.message.contains('signedURL'), isFalse);
            expect(e.message.contains('sign'), isFalse);
            expect(e.message.contains('Token'), isFalse);
          }
        },
      );

      test('exception secrecy: network errors throw constant safe message without raw error interpolation', () async {
        httpClient.handler =
            (
              uri, {
              required method,
              required headers,
              required data,
              required responseType,
              required allowedStatusCodes,
            }) async {
              throw const SocketException(
                'Sensitive internal IP 192.168.1.100 refused with auth token_leak',
              );
            };

        try {
          await adapter.listEntries(source, source.rootLocator).toList();
          fail('Should have thrown MediaSourceException');
        } on MediaSourceException catch (e) {
          expect(e.code, 'network_error');
          expect(e.message, '列出 OpenList 目录条目失败');
          expect(e.message.contains('192.168.1.100'), isFalse);
          expect(e.message.contains('token_leak'), isFalse);
        }
      });
    });

    group('stat', () {
      test('returns MediaStat for existing file', () async {
        httpClient.handler =
            (
              uri, {
              required method,
              required headers,
              required data,
              required responseType,
              required allowedStatusCodes,
            }) async {
              expect(uri.toString(), 'http://127.0.0.1:15244/api/fs/get');
              return Response<dynamic>(
                requestOptions: RequestOptions(path: uri.toString()),
                statusCode: 200,
                data: <String, dynamic>{
                  'code': 200,
                  'message': 'success',
                  'data': <String, dynamic>{
                    'name': 'video.mp4',
                    'size': 6771770,
                    'is_dir': false,
                    'modified': '2026-10-23T18:33:00.3435214+08:00',
                    'sign': 'ephemeral_sign_abc',
                    'hash': 'sha256_video_hash',
                  },
                },
              );
            };

        final stat = await adapter.stat(source, '/Media/video.mp4');
        expect(stat.size, 6771770);
        expect(stat.etag, 'sha256_video_hash');
        expect(stat.modifiedAt, isNotNull);
      });

      test('returns not_found code when file does not exist', () async {
        httpClient.handler =
            (
              uri, {
              required method,
              required headers,
              required data,
              required responseType,
              required allowedStatusCodes,
            }) async {
              return Response<dynamic>(
                requestOptions: RequestOptions(path: uri.toString()),
                statusCode: 200,
                data: <String, dynamic>{
                  'code': 404,
                  'message': 'object not found',
                  'data': null,
                },
              );
            };

        expect(
          () => adapter.stat(source, '/Media/missing.mp4'),
          throwsA(
            isA<MediaSourceException>().having(
              (e) => e.code,
              'code',
              'not_found',
            ),
          ),
        );
      });
    });

    group('resolvePlayback and prepare lease lifecycle', () {
      test('returns logical PlaybackResource with prepare callback', () async {
        final resource = await adapter.resolvePlayback(
          source,
          '/Media/movie.mp4',
        );

        expect(resource.displayName, 'movie.mp4');
        expect(
          resource.uri.toString(),
          'http://127.0.0.1:15244#/Media/movie.mp4',
        );
        expect(resource.prepare, isNotNull);
      });

      test('prepare resolves fresh raw_url, strips API token, and applies only User-Agent/Referer', () async {
        final authSource = source.copyWith(credentialRef: 'cred_1');
        await credentialsStore.write(
          'cred_1',
          const RemoteCredentials(
            token: 'super_secret_api_token',
            password: 'dir_pwd',
            playbackHeaders: {
              'User-Agent': 'CustomPlayer/1.0',
              'Referer': 'https://custom.site/',
              'X-Custom-Header': 'should_be_ignored',
              'Authorization': 'forbidden_token',
            },
          ),
        );

        httpClient.handler =
            (
              uri, {
              required method,
              required headers,
              required data,
              required responseType,
              required allowedStatusCodes,
            }) async {
              expect(uri.toString(), 'http://127.0.0.1:15244/api/fs/get');
              expect(headers['Authorization'], 'super_secret_api_token');

              return Response<dynamic>(
                requestOptions: RequestOptions(path: uri.toString()),
                statusCode: 200,
                data: <String, dynamic>{
                  'code': 200,
                  'message': 'success',
                  'data': <String, dynamic>{
                    'name': 'movie.mp4',
                    'size': 6771770,
                    'is_dir': false,
                    'raw_url': 'http://127.0.0.1:15244/p/Media/movie.mp4?sign=abc&expires=1893456789',
                    'header': '<h1>HTML directory header should not be used as HTTP header</h1>',
                  },
                },
              );
            };

        final resource = await adapter.resolvePlayback(
          authSource,
          '/Media/movie.mp4',
        );

        final concrete = await resource.prepare!();
        expect(concrete.uri.toString(), 'http://127.0.0.1:9999/relay');

        final target = playbackBridge.lastTarget!;
        expect(
          target.uri.toString(),
          'http://127.0.0.1:15244/p/Media/movie.mp4?sign=abc&expires=1893456789',
        );

        // 绝不透传 API Token 到媒体播放地址
        expect(target.headers['Authorization'], isNull);
        // 忽略非 User-Agent / Referer 的头部
        expect(target.headers['X-Custom-Header'], isNull);
        // HTML header 绝不当作 HTTP 头
        expect(target.headers.values.any((v) => v.contains('HTML')), isFalse);
        // 显式白名单头部透传
        expect(target.headers['User-Agent'], 'CustomPlayer/1.0');
        expect(target.headers['Referer'], 'https://custom.site/');
        // 解析过期时间
        expect(target.expiresAt, isNotNull);
        expect(
          target.expiresAt,
          DateTime.fromMillisecondsSinceEpoch(1893456789 * 1000, isUtc: true),
        );
      });

      test('resolves relative raw_url against API base', () async {
        httpClient.handler =
            (
              uri, {
              required method,
              required headers,
              required data,
              required responseType,
              required allowedStatusCodes,
            }) async {
              return Response<dynamic>(
                requestOptions: RequestOptions(path: uri.toString()),
                statusCode: 200,
                data: <String, dynamic>{
                  'code': 200,
                  'message': 'success',
                  'data': <String, dynamic>{
                    'name': 'movie.mp4',
                    'raw_url': '/p/Media/relative_movie.mp4?sign=xyz',
                  },
                },
              );
            };

        final resource = await adapter.resolvePlayback(
          source,
          '/Media/movie.mp4',
        );

        await resource.prepare!();
        final target = playbackBridge.lastTarget!;
        expect(
          target.uri.toString(),
          'http://127.0.0.1:15244/p/Media/relative_movie.mp4?sign=xyz',
        );
      });

      test('strips userInfo if raw_url includes credentials', () async {
        httpClient.handler =
            (
              uri, {
              required method,
              required headers,
              required data,
              required responseType,
              required allowedStatusCodes,
            }) async {
              return Response<dynamic>(
                requestOptions: RequestOptions(path: uri.toString()),
                statusCode: 200,
                data: <String, dynamic>{
                  'code': 200,
                  'message': 'success',
                  'data': <String, dynamic>{
                    'name': 'movie.mp4',
                    'raw_url':
                        'http://user:pass@127.0.0.1:15244/p/Media/movie.mp4',
                  },
                },
              );
            };

        final resource = await adapter.resolvePlayback(
          source,
          '/Media/movie.mp4',
        );

        await resource.prepare!();
        final target = playbackBridge.lastTarget!;
        expect(target.uri.userInfo, isEmpty);
        expect(
          target.uri.toString(),
          'http://127.0.0.1:15244/p/Media/movie.mp4',
        );
      });

      test('refresh resolver on 403 or expiry fetches fresh raw_url', () async {
        int getCallCount = 0;

        httpClient.handler =
            (
              uri, {
              required method,
              required headers,
              required data,
              required responseType,
              required allowedStatusCodes,
            }) async {
              getCallCount++;
              return Response<dynamic>(
                requestOptions: RequestOptions(path: uri.toString()),
                statusCode: 200,
                data: <String, dynamic>{
                  'code': 200,
                  'message': 'success',
                  'data': <String, dynamic>{
                    'name': 'movie.mp4',
                    'raw_url':
                        'http://127.0.0.1:15244/p/Media/movie.mp4?sign=call_$getCallCount',
                  },
                },
              );
            };

        final resource = await adapter.resolvePlayback(
          source,
          '/Media/movie.mp4',
        );

        await resource.prepare!();
        expect(getCallCount, 1);
        expect(
          playbackBridge.lastTarget!.uri.queryParameters['sign'],
          'call_1',
        );

        // 模拟 Bridge 触发刷新
        final refreshedTarget = await playbackBridge.lastResolver!(
          refresh: true,
        );
        expect(getCallCount, 2);
        expect(refreshedTarget.uri.queryParameters['sign'], 'call_2');
      });

      test(
        'missing raw_url throws raw_url_missing PlaybackResourceException',
        () async {
          httpClient.handler =
              (
                uri, {
                required method,
                required headers,
                required data,
                required responseType,
                required allowedStatusCodes,
              }) async {
                return Response<dynamic>(
                  requestOptions: RequestOptions(path: uri.toString()),
                  statusCode: 200,
                  data: <String, dynamic>{
                    'code': 200,
                    'message': 'success',
                    'data': <String, dynamic>{
                      'name': 'movie.mp4',
                      'raw_url': '',
                    },
                  },
                );
              };

          final resource = await adapter.resolvePlayback(
            source,
            '/Media/movie.mp4',
          );

          expect(
            () => resource.prepare!(),
            throwsA(
              isA<PlaybackResourceException>().having(
                (e) => e.code,
                'code',
                'raw_url_missing',
              ),
            ),
          );
        },
      );

      test('aborts and throws cancellation if cancelToken is cancelled during prepare/resolve', () async {
        httpClient.handler =
            (
              uri, {
              required method,
              required headers,
              required data,
              required responseType,
              required allowedStatusCodes,
            }) async {
              return Response<dynamic>(
                requestOptions: RequestOptions(path: uri.toString()),
                statusCode: 200,
                data: <String, dynamic>{
                  'code': 200,
                  'message': 'success',
                  'data': <String, dynamic>{
                    'name': 'movie.mp4',
                    'size': 1000,
                    'is_dir': false,
                    'raw_url': 'http://127.0.0.1:15244/p/Media/movie.mp4',
                  },
                },
              );
            };

        final resource = await adapter.resolvePlayback(
          source,
          '/Media/movie.mp4',
        );

        await resource.prepare!();
        expect(playbackBridge.lastResolver, isNotNull);
        final initialRequestCount = httpClient.recordedRequests.length;

        final cancelledToken = CancelToken();
        cancelledToken.cancel('Release requested');

        expect(
          () => playbackBridge.lastResolver!(
            refresh: true,
            cancelToken: cancelledToken,
          ),
          throwsA(
            isA<DioException>().having(
              (e) => CancelToken.isCancel(e),
              'isCancel',
              isTrue,
            ),
          ),
        );

        // 确认未发起任何新的 HTTP 请求
        expect(httpClient.recordedRequests.length, initialRequestCount);
      });
    });
  });
  group('OpenListSourceAdapter Real Loopback HttpServer Tests', () {
    late HttpServer server;
    late RemoteHttpClient realHttpClient;
    late _FakeRemoteCredentialsStore credentialsStore;
    late _FakeRemotePlaybackBridge playbackBridge;
    late OpenListSourceAdapter adapter;
    late MediaSourceConfig source;
    HttpOverrides? previousOverrides;

    setUp(() async {
      previousOverrides = HttpOverrides.current;
      HttpOverrides.global = _RealHttpOverrides();
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      realHttpClient = RemoteHttpClient();
      credentialsStore = _FakeRemoteCredentialsStore();
      playbackBridge = _FakeRemotePlaybackBridge();

      adapter = OpenListSourceAdapter(
        credentials: credentialsStore,
        http: realHttpClient,
        playback: playbackBridge,
      );

      source = MediaSourceConfig(
        id: 10,
        kind: 'openlist',
        name: 'Local HTTP Test',
        rootLocator: 'http://127.0.0.1:${server.port}#/Media',
      );
      await credentialsStore.write(
        'cred_loopback',
        const RemoteCredentials.anonymous(),
      );
    });

    tearDown(() async {
      HttpOverrides.global = previousOverrides;
      realHttpClient.close();
      await server.close(force: true);
    });

    test('verifies real HTTP request body, raw token and pagination over loopback socket', () async {
      final authSource = source.copyWith(credentialRef: 'cred_loopback');
      await credentialsStore.write(
        'cred_loopback',
        const RemoteCredentials(
          token: 'token_socket_123',
          password: 'pwd_socket_456',
        ),
      );

      server.listen((HttpRequest request) async {
        final path = request.uri.path;
        final auth = request.headers.value('Authorization');
        expect(auth, 'token_socket_123');

        if (path == '/api/fs/list') {
          final bodyBytes = await request.fold<List<int>>(
            [],
            (p, e) => p..addAll(e),
          );
          final bodyJson =
              jsonDecode(utf8.decode(bodyBytes)) as Map<String, dynamic>;
          expect(bodyJson['path'], '/Media');
          expect(bodyJson['password'], 'pwd_socket_456');

          request.response
            ..statusCode = HttpStatus.ok
            ..headers.contentType = ContentType.json
            ..write(
              jsonEncode({
                'code': 200,
                'message': 'success',
                'data': {
                  'content': [
                    {
                      'name': 'LoopbackMovie.mp4',
                      'size': 123456,
                      'is_dir': false,
                      'modified': '2026-10-23T10:00:00Z',
                    },
                  ],
                  'total': 1,
                },
              }),
            );
          await request.response.close();
        } else {
          request.response
            ..statusCode = HttpStatus.notFound
            ..close();
        }
      });

      final entries = await adapter
          .listEntries(authSource, authSource.rootLocator)
          .toList();

      expect(entries.length, 1);
      expect(entries[0].name, 'LoopbackMovie.mp4');
      expect(entries[0].externalId, '/Media/LoopbackMovie.mp4');
      expect(entries[0].size, 123456);
    });
    test('verifies stat and 404 mapping over loopback socket', () async {
      server.listen((HttpRequest request) async {
        final path = request.uri.path;
        if (path == '/api/fs/get') {
          final bodyBytes = await request.fold<List<int>>(
            [],
            (p, e) => p..addAll(e),
          );
          final bodyJson =
              jsonDecode(utf8.decode(bodyBytes)) as Map<String, dynamic>;

          if (bodyJson['path'] == '/Media/test.mp4') {
            request.response
              ..statusCode = HttpStatus.ok
              ..headers.contentType = ContentType.json
              ..write(
                jsonEncode({
                  'code': 200,
                  'message': 'success',
                  'data': {
                    'name': 'test.mp4',
                    'size': 9999,
                    'is_dir': false,
                    'hash_info': {'sha256': 'socket_sha256'},
                  },
                }),
              );
          } else {
            request.response
              ..statusCode = HttpStatus.ok
              ..headers.contentType = ContentType.json
              ..write(
                jsonEncode({
                  'code': 404,
                  'message': 'object not found',
                  'data': null,
                }),
              );
          }
          await request.response.close();
        } else {
          request.response
            ..statusCode = HttpStatus.notFound
            ..close();
        }
      });

      final stat = await adapter.stat(source, '/Media/test.mp4');
      expect(stat.size, 9999);
      expect(stat.etag, 'socket_sha256');

      expect(
        () => adapter.stat(source, '/Media/missing.mp4'),
        throwsA(
          isA<MediaSourceException>().having(
            (e) => e.code,
            'code',
            'not_found',
          ),
        ),
      );
    });

    test('verifies resolvePlayback and raw_url resolution without token leakage over loopback', () async {
      final authSource = source.copyWith(credentialRef: 'cred_loopback');
      await credentialsStore.write(
        'cred_loopback',
        const RemoteCredentials(
          token: 'secret_token_123',
          password: 'pwd',
          playbackHeaders: {'User-Agent': 'LoopbackUA'},
        ),
      );

      server.listen((HttpRequest request) async {
        final path = request.uri.path;
        if (path == '/api/fs/get') {
          final auth = request.headers.value('Authorization');
          expect(auth, 'secret_token_123');

          request.response
            ..statusCode = HttpStatus.ok
            ..headers.contentType = ContentType.json
            ..write(
              jsonEncode({
                'code': 200,
                'message': 'success',
                'data': {
                  'name': 'stream.mp4',
                  'raw_url': 'http://127.0.0.1:${server.port}/stream.mp4',
                },
              }),
            );
          await request.response.close();
        } else {
          request.response
            ..statusCode = HttpStatus.notFound
            ..close();
        }
      });

      final resource = await adapter.resolvePlayback(
        authSource,
        '/Media/stream.mp4',
      );
      final concrete = await resource.prepare!();
      expect(concrete, isNotNull);

      final target = playbackBridge.lastTarget!;
      expect(
        target.uri.toString(),
        'http://127.0.0.1:${server.port}/stream.mp4',
      );
      expect(target.headers['Authorization'], isNull);
      expect(target.headers['User-Agent'], 'LoopbackUA');
    });

    test('recovers from mid-playback 403 by refreshing ephemeral link and resuming Range on fresh target', () async {
      final authSource = source.copyWith(credentialRef: 'cred_loopback');
      await credentialsStore.write(
        'cred_loopback',
        const RemoteCredentials(
          token: 'secret_token_123',
          password: 'pwd',
          playbackHeaders: {'User-Agent': 'LoopbackUA'},
        ),
      );

      final realBridge = RemotePlaybackBridge(http: realHttpClient);
      final realAdapter = OpenListSourceAdapter(
        credentials: credentialsStore,
        http: realHttpClient,
        playback: realBridge,
      );

      int fsGetCallCount = 0;
      int oldMediaRequests = 0;
      int freshMediaRequests = 0;
      bool oldExpired = false;
      bool tokenLeakedToMedia = false;

      server.listen((HttpRequest request) async {
        final path = request.uri.path;
        final auth = request.headers.value('Authorization');

        if (path.startsWith('/media/')) {
          if (auth != null) {
            tokenLeakedToMedia = true;
          }
        }

        if (path == '/api/fs/get') {
          fsGetCallCount++;
          expect(auth, 'secret_token_123');
          final rawUrl = fsGetCallCount == 1
              ? 'http://127.0.0.1:${server.port}/media/old?sign=sig_old'
              : 'http://127.0.0.1:${server.port}/media/fresh?sign=sig_fresh';

          request.response
            ..statusCode = HttpStatus.ok
            ..headers.contentType = ContentType.json
            ..write(
              jsonEncode({
                'code': 200,
                'message': 'success',
                'data': {'name': 'movie.mp4', 'raw_url': rawUrl},
              }),
            );
          await request.response.close();
        } else if (path == '/media/old') {
          oldMediaRequests++;
          final rangeHeader = request.headers.value('Range');
          if (!oldExpired) {
            // 初始准备阶段探测：Range: bytes=0-0
            expect(rangeHeader, 'bytes=0-0');
            request.response
              ..statusCode = HttpStatus.partialContent
              ..headers.set('Content-Range', 'bytes 0-0/100')
              ..headers.set('Content-Length', '1')
              ..headers.set('Accept-Ranges', 'bytes')
              ..add([42]);
            await request.response.close();
          } else {
            // 过期链接直接返回 403 Forbidden
            request.response
              ..statusCode = HttpStatus.forbidden
              ..write('Link expired');
            await request.response.close();
          }
        } else if (path == '/media/fresh') {
          freshMediaRequests++;
          expect(oldExpired, isTrue);
          final rangeHeader = request.headers.value('Range');
          expect(rangeHeader, 'bytes=10-19');
          expect(request.headers.value('User-Agent'), 'LoopbackUA');

          final chunk = List<int>.generate(10, (i) => 10 + i);
          request.response
            ..statusCode = HttpStatus.partialContent
            ..headers.set('Content-Range', 'bytes 10-19/100')
            ..headers.set('Content-Length', '10')
            ..headers.set('Accept-Ranges', 'bytes')
            ..add(chunk);
          await request.response.close();
        } else {
          request.response
            ..statusCode = HttpStatus.notFound
            ..close();
        }
      });

      // 1. 初始 prepare 探测成功，获取本地 concrete 租约
      final resource = await realAdapter.resolvePlayback(
        authSource,
        '/Media/movie.mp4',
      );
      final concrete = await resource.prepare!();
      expect(concrete, isNotNull);
      expect(fsGetCallCount, 1);
      expect(oldMediaRequests, 1); // 成功探测 bytes 0-0
      expect(freshMediaRequests, 0);

      // 2. 模拟链接过期：后续对旧地址的请求将直接返回 403
      oldExpired = true;

      // 3. 向租约本地 URI 发送分段读取 Range: bytes=10-19
      final rangeResponse = await realHttpClient.request(
        concrete.uri,
        method: 'GET',
        headers: {'Range': 'bytes=10-19'},
        responseType: ResponseType.bytes,
        allowedStatusCodes: const {HttpStatus.partialContent},
      );

      // 4. 校验 206 Partial Content 及分段数据完整正确
      expect(rangeResponse.statusCode, HttpStatus.partialContent);
      final expectedBytes = List<int>.generate(10, (i) => 10 + i);
      expect(rangeResponse.data, expectedBytes);

      // 5. 严格断言重试契约与安全性
      expect(fsGetCallCount, 2); // /api/fs/get 刷新递增恰好 1 次
      expect(oldMediaRequests, 2); // 旧地址仅包含探测与 403 触发，刷新后绝不再被复用
      expect(freshMediaRequests, 1); // 刷新后的目标正确承接保留的 Range 分段
      expect(tokenLeakedToMedia, isFalse); // API 凭据绝不泄露给媒体服务器

      // 6. 安全释放资源
      await concrete.release?.call();
    });
  });
}
