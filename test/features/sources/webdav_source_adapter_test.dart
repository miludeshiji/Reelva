import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reelva/features/player/domain/playback_resource.dart';
import 'package:reelva/features/sources/domain/source_models.dart';
import 'package:reelva/features/sources/infrastructure/remote_credentials_store.dart';
import 'package:reelva/features/sources/infrastructure/remote_http_client.dart';
import 'package:reelva/features/sources/infrastructure/remote_playback_bridge.dart';
import 'package:reelva/features/sources/infrastructure/webdav_source_adapter.dart';

class _FakeRemoteHttpClient extends RemoteHttpClient {
  _FakeRemoteHttpClient();

  Future<Response<dynamic>> Function(
    Uri uri, {
    required String method,
    required Map<String, String> headers,
    required Object? data,
    required ResponseType responseType,
    CancelToken? cancelToken,
  })?
  handler;

  final List<
    ({
      Uri uri,
      String method,
      Map<String, String> headers,
      Object? data,
      CancelToken? cancelToken,
    })
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
      cancelToken: cancelToken,
    ));

    if (handler != null) {
      return handler!(
        uri,
        method: method,
        headers: headers,
        data: data,
        responseType: responseType,
        cancelToken: cancelToken,
      );
    }

    return Response<dynamic>(
      requestOptions: RequestOptions(path: uri.toString()),
      statusCode: 200,
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
    return PlaybackResource(
      uri: Uri.parse('http://127.0.0.1:9999/relay'),
      displayName: displayName,
      httpHeaders: target.headers,
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const openListFixtureXml =
      '<?xml version="1.0" encoding="UTF-8"?>'
      '<D:multistatus xmlns:D="DAV:">'
      '<D:response>'
      '<D:href>/dav/Media/</D:href>'
      '<D:propstat>'
      '<D:prop>'
      '<D:displayname>Media</D:displayname>'
      '<D:resourcetype><D:collection xmlns:D="DAV:"/></D:resourcetype>'
      '<D:getlastmodified>Fri, 23 Oct 2026 10:38:48 GMT</D:getlastmodified>'
      '</D:prop>'
      '<D:status>HTTP/1.1 200 OK</D:status>'
      '</D:propstat>'
      '</D:response>'
      '<D:response>'
      '<D:href>/dav/Media/Example.Movie.2025.1080p.mp4</D:href>'
      '<D:propstat>'
      '<D:prop>'
      '<D:getetag>"6adb37dc-67543a"</D:getetag>'
      '<D:displayname>Example.Movie.2025.1080p.mp4</D:displayname>'
      '<D:getcontentlength>6771770</D:getcontentlength>'
      '<D:resourcetype></D:resourcetype>'
      '<D:getlastmodified>Fri, 23 Oct 2026 10:33:00 GMT</D:getlastmodified>'
      '</D:prop>'
      '<D:status>HTTP/1.1 200 OK</D:status>'
      '</D:propstat>'
      '</D:response>'
      '<D:response>'
      '<D:href>/dav/Media/Example.Movie.2025.2160p.mkv</D:href>'
      '<D:propstat>'
      '<D:prop>'
      '<D:displayname>Example.Movie.2025.2160p.mkv</D:displayname>'
      '<D:getcontentlength>1316394</D:getcontentlength>'
      '<D:resourcetype></D:resourcetype>'
      '<D:getlastmodified>Fri, 23 Oct 2026 10:39:07 GMT</D:getlastmodified>'
      '<D:getetag>"6adb394b-14162a"</D:getetag>'
      '</D:prop>'
      '<D:status>HTTP/1.1 200 OK</D:status>'
      '</D:propstat>'
      '</D:response>'
      '<D:response>'
      '<D:href>/dav/Media/Example.Show.S01E05.1080p.mp4</D:href>'
      '<D:propstat>'
      '<D:prop>'
      '<D:resourcetype></D:resourcetype>'
      '<D:getlastmodified>Fri, 23 Oct 2026 10:39:07 GMT</D:getlastmodified>'
      '<D:getetag>"6adb394b-e936f"</D:getetag>'
      '<D:displayname>Example.Show.S01E05.1080p.mp4</D:displayname>'
      '<D:getcontentlength>955247</D:getcontentlength>'
      '</D:prop>'
      '<D:status>HTTP/1.1 200 OK</D:status>'
      '</D:propstat>'
      '</D:response>'
      '</D:multistatus>';

  group('WebDavSourceAdapter', () {
    late _FakeRemoteHttpClient httpClient;
    late _FakeRemoteCredentialsStore credentialsStore;
    late _FakeRemotePlaybackBridge playbackBridge;
    late WebDavSourceAdapter adapter;
    late MediaSourceConfig source;

    setUp(() {
      httpClient = _FakeRemoteHttpClient();
      credentialsStore = _FakeRemoteCredentialsStore();
      playbackBridge = _FakeRemotePlaybackBridge();
      adapter = WebDavSourceAdapter(
        credentials: credentialsStore,
        http: httpClient,
        playback: playbackBridge,
      );
      source = const MediaSourceConfig(
        id: 1,
        kind: 'webdav',
        name: 'OpenList DAV',
        rootLocator: 'http://127.0.0.1:15244/dav/Media/',
      );
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

    group('rootLocator validation', () {
      test('rejects rootLocator with userInfo credentials', () async {
        final invalidSource = source.copyWith(
          rootLocator: 'http://user:pass@127.0.0.1:15244/dav/Media/',
        );
        expect(
          () => adapter
              .listEntries(invalidSource, invalidSource.rootLocator)
              .toList(),
          throwsA(
            isA<MediaSourceException>().having(
              (e) => e.code,
              'code',
              'invalid_url',
            ),
          ),
        );
      });

      test('rejects rootLocator with query parameters or fragment', () async {
        final withQuery = source.copyWith(
          rootLocator: 'http://127.0.0.1:15244/dav/Media/?token=secret',
        );
        expect(
          () => adapter.listEntries(withQuery, withQuery.rootLocator).toList(),
          throwsA(
            isA<MediaSourceException>().having(
              (e) => e.code,
              'code',
              'invalid_url',
            ),
          ),
        );

        final withFragment = source.copyWith(
          rootLocator: 'http://127.0.0.1:15244/dav/Media/#folder',
        );
        expect(
          () => adapter
              .listEntries(withFragment, withFragment.rootLocator)
              .toList(),
          throwsA(
            isA<MediaSourceException>().having(
              (e) => e.code,
              'code',
              'invalid_url',
            ),
          ),
        );
      });

      test('rejects rootLocator with dot segments (. or ..)', () async {
        final withDots = source.copyWith(
          rootLocator: 'http://127.0.0.1:15244/dav/../other/',
        );
        expect(
          () => adapter.listEntries(withDots, withDots.rootLocator).toList(),
          throwsA(
            isA<MediaSourceException>().having(
              (e) => e.code,
              'code',
              'invalid_url',
            ),
          ),
        );
      });
    });

    group('listEntries', () {
      test(
        'streams 207 XML, skips directory self and yields entries',
        () async {
          httpClient.handler =
              (
                uri, {
                required method,
                required headers,
                required data,
                required responseType,
                cancelToken,
              }) async {
                expect(method, 'PROPFIND');
                expect(headers['Depth'], '1');
                expect(responseType, ResponseType.stream);
                expect(uri.toString(), 'http://127.0.0.1:15244/dav/Media/');

                return Response<dynamic>(
                  requestOptions: RequestOptions(path: uri.toString()),
                  statusCode: 207,
                  data: Stream.value(openListFixtureXml),
                );
              };

          final entries = await adapter
              .listEntries(source, source.rootLocator)
              .toList();

          expect(entries.length, 3);

          expect(entries[0].name, 'Example.Movie.2025.1080p.mp4');
          expect(entries[0].externalId, 'Example.Movie.2025.1080p.mp4');
          expect(entries[0].locator, 'Example.Movie.2025.1080p.mp4');
          expect(entries[0].isDirectory, isFalse);
          expect(entries[0].size, 6771770);
          expect(entries[0].etag, '"6adb37dc-67543a"');
          expect(entries[0].modifiedAt, DateTime.utc(2026, 10, 23, 10, 33, 0));

          expect(entries[1].name, 'Example.Movie.2025.2160p.mkv');
          expect(entries[1].externalId, 'Example.Movie.2025.2160p.mkv');
          expect(entries[1].size, 1316394);

          expect(entries[2].name, 'Example.Show.S01E05.1080p.mp4');
          expect(entries[2].externalId, 'Example.Show.S01E05.1080p.mp4');
          expect(entries[2].size, 955247);
        },
      );

      test('sends Basic Auth when credentials exist in store', () async {
        final credSource = source.copyWith(credentialRef: 'cred_1');
        await credentialsStore.write(
          'cred_1',
          const RemoteCredentials(
            username: 'reelva_smoke',
            password: 'smoke_fixture_only',
          ),
        );

        httpClient.handler =
            (
              uri, {
              required method,
              required headers,
              required data,
              required responseType,
              cancelToken,
            }) async {
              final expectedAuth =
                  'Basic ${base64Encode(utf8.encode('reelva_smoke:smoke_fixture_only'))}';
              expect(headers['Authorization'], expectedAuth);

              return Response<dynamic>(
                requestOptions: RequestOptions(path: uri.toString()),
                statusCode: 207,
                data: Stream.value(openListFixtureXml),
              );
            };

        final entries = await adapter
            .listEntries(credSource, credSource.rootLocator)
            .toList();
        expect(entries.length, 3);
      });

      test(
        'handles subdirectories, URL decoding, and ignores non-direct children',
        () async {
          const nestedXml =
              '<?xml version="1.0" encoding="UTF-8"?>'
              '<d:multistatus xmlns:d="DAV:">'
              '<d:response>'
              '<d:href>/dav/Media/Movies/</d:href>'
              '<d:propstat>'
              '<d:prop><d:resourcetype><d:collection/></d:resourcetype></d:prop>'
              '<d:status>HTTP/1.1 200 OK</d:status>'
              '</d:propstat>'
              '</d:response>'
              '<d:response>'
              '<d:href>/dav/Media/Movies/Action%20Movies/</d:href>'
              '<d:propstat>'
              '<d:prop>'
              '<d:resourcetype><d:collection/></d:resourcetype>'
              '<d:getlastmodified>Fri, 23 Oct 2026 10:00:00 GMT</d:getlastmodified>'
              '</d:prop>'
              '<d:status>HTTP/1.1 200 OK</d:status>'
              '</d:propstat>'
              '</d:response>'
              '<d:response>'
              '<d:href>/dav/Media/Movies/Action%20Movies/Deep.mp4</d:href>'
              '<d:propstat>'
              '<d:prop>'
              '<d:resourcetype/>'
              '<d:getcontentlength>12345</d:getcontentlength>'
              '</d:prop>'
              '<d:status>HTTP/1.1 200 OK</d:status>'
              '</d:propstat>'
              '</d:response>'
              '<d:response>'
              '<d:href>/dav/Media/Movies/Movie%201.mp4</d:href>'
              '<d:propstat>'
              '<d:prop>'
              '<d:resourcetype/>'
              '<d:getcontentlength>1048576</d:getcontentlength>'
              '</d:prop>'
              '<d:status>HTTP/1.1 200 OK</d:status>'
              '</d:propstat>'
              '</d:response>'
              '</d:multistatus>';

          httpClient.handler =
              (
                uri, {
                required method,
                required headers,
                required data,
                required responseType,
                cancelToken,
              }) async {
                expect(
                  uri.toString(),
                  'http://127.0.0.1:15244/dav/Media/Movies/',
                );
                return Response<dynamic>(
                  requestOptions: RequestOptions(path: uri.toString()),
                  statusCode: 207,
                  data: Stream.value(nestedXml),
                );
              };

          final entries = await adapter.listEntries(source, 'Movies').toList();

          expect(entries.length, 2);

          final dirEntry = entries.firstWhere((e) => e.isDirectory);
          expect(dirEntry.name, 'Action Movies');
          expect(dirEntry.externalId, 'Movies/Action Movies');
          expect(dirEntry.locator, 'Movies/Action Movies');
          expect(dirEntry.size, isNull);

          final fileEntry = entries.firstWhere((e) => !e.isDirectory);
          expect(fileEntry.name, 'Movie 1.mp4');
          expect(fileEntry.externalId, 'Movies/Movie 1.mp4');
          expect(fileEntry.size, 1048576);
        },
      );

      test(
        'fails listing when a child returns 403 Forbidden (preserves failure)',
        () async {
          const with403ChildXml =
              '<?xml version="1.0" encoding="UTF-8"?>'
              '<D:multistatus xmlns:D="DAV:">'
              '<D:response>'
              '<D:href>/dav/Media/</D:href>'
              '<D:propstat>'
              '<D:prop><D:resourcetype><D:collection/></D:resourcetype></D:prop>'
              '<D:status>HTTP/1.1 200 OK</D:status>'
              '</D:propstat>'
              '</D:response>'
              '<D:response>'
              '<D:href>/dav/Media/Allowed.mp4</D:href>'
              '<D:propstat>'
              '<D:prop><D:resourcetype/><D:getcontentlength>100</D:getcontentlength></D:prop>'
              '<D:status>HTTP/1.1 200 OK</D:status>'
              '</D:propstat>'
              '</D:response>'
              '<D:response>'
              '<D:href>/dav/Media/Protected.mp4</D:href>'
              '<D:propstat>'
              '<D:status>HTTP/1.1 403 Forbidden</D:status>'
              '</D:propstat>'
              '</D:response>'
              '</D:multistatus>';

          httpClient.handler =
              (
                uri, {
                required method,
                required headers,
                required data,
                required responseType,
                cancelToken,
              }) async {
                return Response<dynamic>(
                  requestOptions: RequestOptions(path: uri.toString()),
                  statusCode: 207,
                  data: Stream.value(with403ChildXml),
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
        },
      );
      test(
        'fails listing when a collection without trailing slash has denied resourcetype and 200 displayname',
        () async {
          const noTrailingSlashDeniedResTypeXml =
              '<?xml version="1.0" encoding="UTF-8"?>'
              '<D:multistatus xmlns:D="DAV:">'
              '<D:response>'
              '<D:href>/dav/Media/</D:href>'
              '<D:propstat>'
              '<D:prop><D:resourcetype><D:collection/></D:resourcetype></D:prop>'
              '<D:status>HTTP/1.1 200 OK</D:status>'
              '</D:propstat>'
              '</D:response>'
              '<D:response>'
              '<D:href>/dav/Media/RestrictedFolder</D:href>'
              '<D:propstat>'
              '<D:prop><D:displayname>RestrictedFolder</D:displayname></D:prop>'
              '<D:status>HTTP/1.1 200 OK</D:status>'
              '</D:propstat>'
              '<D:propstat>'
              '<D:prop><D:resourcetype/></D:prop>'
              '<D:status>HTTP/1.1 403 Forbidden</D:status>'
              '</D:propstat>'
              '</D:response>'
              '</D:multistatus>';

          httpClient.handler =
              (
                uri, {
                required method,
                required headers,
                required data,
                required responseType,
                cancelToken,
              }) async {
                return Response<dynamic>(
                  requestOptions: RequestOptions(path: uri.toString()),
                  statusCode: 207,
                  data: Stream.value(noTrailingSlashDeniedResTypeXml),
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
        },
      );

      test(
        'fails listing when target self collection is missing from response',
        () async {
          const withoutSelfXml =
              '<?xml version="1.0" encoding="UTF-8"?>'
              '<D:multistatus xmlns:D="DAV:">'
              '<D:response>'
              '<D:href>/dav/Media/ChildOnly.mp4</D:href>'
              '<D:propstat>'
              '<D:prop><D:resourcetype/><D:getcontentlength>100</D:getcontentlength></D:prop>'
              '<D:status>HTTP/1.1 200 OK</D:status>'
              '</D:propstat>'
              '</D:response>'
              '</D:multistatus>';

          httpClient.handler =
              (
                uri, {
                required method,
                required headers,
                required data,
                required responseType,
                cancelToken,
              }) async {
                return Response<dynamic>(
                  requestOptions: RequestOptions(path: uri.toString()),
                  statusCode: 207,
                  data: Stream.value(withoutSelfXml),
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
        },
      );

      test(
        'throws MediaSourceException on empty responses (no false empty)',
        () async {
          httpClient.handler =
              (
                uri, {
                required method,
                required headers,
                required data,
                required responseType,
                cancelToken,
              }) async {
                return Response<dynamic>(
                  requestOptions: RequestOptions(path: uri.toString()),
                  statusCode: 207,
                  data: Stream.value(
                    '<?xml version="1.0"?><D:multistatus xmlns:D="DAV:"></D:multistatus>',
                  ),
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
        },
      );
    });

    group('Unicode, spaces, literal %, # in paths and stat', () {
      test(
        'resolves literal % and # without double-encoding or decoding as logical IDs',
        () async {
          const specialName = 'Special 100% #1 电影.mp4';
          const fileStatXml =
              '<?xml version="1.0" encoding="UTF-8"?>'
              '<D:multistatus xmlns:D="DAV:">'
              '<D:response>'
              '<D:href>/dav/Media/Special%20100%25%20%231%20%E7%94%B5%E5%BD%B1.mp4</D:href>'
              '<D:propstat>'
              '<D:prop>'
              '<D:resourcetype/>'
              '<D:getcontentlength>54321</D:getcontentlength>'
              '<D:getetag>"special-etag"</D:getetag>'
              '<D:getlastmodified>Fri, 23 Oct 2026 10:33:00 GMT</D:getlastmodified>'
              '</D:prop>'
              '<D:status>HTTP/1.1 200 OK</D:status>'
              '</D:propstat>'
              '</D:response>'
              '</D:multistatus>';

          httpClient.handler =
              (
                uri, {
                required method,
                required headers,
                required data,
                required responseType,
                cancelToken,
              }) async {
                expect(method, 'PROPFIND');
                expect(headers['Depth'], '0');
                // 确认 URL 编码中空格为 %20，% 为 %25，# 为 %23，Unicode 正确编码
                expect(
                  uri.path,
                  '/dav/Media/Special%20100%25%20%231%20%E7%94%B5%E5%BD%B1.mp4',
                );

                return Response<dynamic>(
                  requestOptions: RequestOptions(path: uri.toString()),
                  statusCode: 207,
                  data: fileStatXml,
                );
              };

          final stat = await adapter.stat(source, specialName);
          expect(stat.size, 54321);
          expect(stat.etag, '"special-etag"');
        },
      );

      test(
        'stat matches requested resource and ignores unrelated responses in 207',
        () async {
          const multipleResponsesXml =
              '<?xml version="1.0" encoding="UTF-8"?>'
              '<D:multistatus xmlns:D="DAV:">'
              '<D:response>'
              '<D:href>/dav/Media/Unrelated.mp4</D:href>'
              '<D:propstat>'
              '<D:prop><D:resourcetype/><D:getcontentlength>999</D:getcontentlength></D:prop>'
              '<D:status>HTTP/1.1 200 OK</D:status>'
              '</D:propstat>'
              '</D:response>'
              '<D:response>'
              '<D:href>/dav/Media/Target.mp4</D:href>'
              '<D:propstat>'
              '<D:prop><D:resourcetype/><D:getcontentlength>888</D:getcontentlength></D:prop>'
              '<D:status>HTTP/1.1 200 OK</D:status>'
              '</D:propstat>'
              '</D:response>'
              '</D:multistatus>';

          httpClient.handler =
              (
                uri, {
                required method,
                required headers,
                required data,
                required responseType,
                cancelToken,
              }) async {
                return Response<dynamic>(
                  requestOptions: RequestOptions(path: uri.toString()),
                  statusCode: 207,
                  data: multipleResponsesXml,
                );
              };

          final stat = await adapter.stat(source, 'Target.mp4');
          expect(stat.size, 888);
        },
      );
    });

    group('strict containment', () {
      test('rejects relative paths attempting escape via ..', () async {
        expect(
          () => adapter.listEntries(source, '../EscapeDir').toList(),
          throwsA(
            isA<MediaSourceException>().having(
              (e) => e.code,
              'code',
              'path_escape',
            ),
          ),
        );

        expect(
          () => adapter.stat(source, 'Movies/../../etc/passwd'),
          throwsA(
            isA<MediaSourceException>().having(
              (e) => e.code,
              'code',
              'path_escape',
            ),
          ),
        );
      });

      test('rejects foreign origin or outside root paths', () async {
        expect(
          () => adapter.stat(source, 'http://attacker.com/Media/video.mp4'),
          throwsA(
            isA<MediaSourceException>().having(
              (e) => e.code,
              'code',
              'path_escape',
            ),
          ),
        );

        expect(
          () => adapter.stat(
            source,
            'http://127.0.0.1:15244/other_root/video.mp4',
          ),
          throwsA(
            isA<MediaSourceException>().having(
              (e) => e.code,
              'code',
              'path_escape',
            ),
          ),
        );
      });
    });

    group('resolvePlayback', () {
      test(
        'returns PlaybackResource with prepare bridge rereading credentials',
        () async {
          final credSource = source.copyWith(credentialRef: 'cred_1');
          await credentialsStore.write(
            'cred_1',
            const RemoteCredentials(username: 'user_a', password: 'pwd_a'),
          );

          final resource = await adapter.resolvePlayback(
            credSource,
            'Example.Movie.2025.1080p.mp4',
          );

          expect(resource.displayName, 'Example.Movie.2025.1080p.mp4');
          expect(
            resource.uri.toString(),
            'http://127.0.0.1:15244/dav/Media/Example.Movie.2025.1080p.mp4',
          );
          expect(resource.prepare, isNotNull);

          final concreteLease = await resource.prepare!();
          expect(concreteLease.uri.toString(), 'http://127.0.0.1:9999/relay');
          expect(
            playbackBridge.lastDisplayName,
            'Example.Movie.2025.1080p.mp4',
          );

          final authInitial =
              'Basic ${base64Encode(utf8.encode('user_a:pwd_a'))}';
          expect(concreteLease.httpHeaders['Authorization'], authInitial);

          await credentialsStore.write(
            'cred_1',
            const RemoteCredentials(username: 'user_b', password: 'pwd_b'),
          );
          final refreshedTarget = await playbackBridge.lastResolver!(
            refresh: true,
          );
          final authRefreshed =
              'Basic ${base64Encode(utf8.encode('user_b:pwd_b'))}';
          expect(refreshedTarget.headers['Authorization'], authRefreshed);
        },
      );
      test('aborts resolve if cancelToken is already cancelled', () async {
        final credSource = source.copyWith(credentialRef: 'cred_1');
        await credentialsStore.write(
          'cred_1',
          const RemoteCredentials(username: 'user_a', password: 'pwd_a'),
        );

        final resource = await adapter.resolvePlayback(
          credSource,
          'Example.Movie.2025.1080p.mp4',
        );
        await resource.prepare!();

        final token = CancelToken();
        token.cancel('cancelled by test');

        expect(
          () => playbackBridge.lastResolver!(refresh: true, cancelToken: token),
          throwsA(isA<PlaybackResourceException>()),
        );
      });
    });
  });
}
