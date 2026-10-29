import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:xml/xml.dart';

Map<String, dynamic> releaseJson(
  String version, {
  bool draft = false,
  bool prerelease = false,
}) => {
  'tag_name': 'v$version',
  'html_url': 'https://github.com/miludeshiji/Reelva/releases/tag/v$version',
  'body': '### 新增\n\n- 支持应用内检查更新',
  'published_at': '2026-10-27T00:00:00Z',
  'draft': draft,
  'prerelease': prerelease,
  'assets': [
    for (final suffix in [
      'android-arm64-v8a.apk',
      'android-armeabi-v7a.apk',
      'android-x86_64.apk',
      'windows-x64-installer.exe',
      'windows-x64.zip',
    ])
      {
        'name': 'Reelva-$version-$suffix',
        'browser_download_url':
            'https://github.com/miludeshiji/Reelva/releases/download/v$version/Reelva-$version-$suffix',
        'size': 3,
        'digest': 'sha256:ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
      },
  ],
};

ResponseBody jsonResponse(Object? body, {int status = 200}) =>
    ResponseBody.fromString(
      jsonEncode(body),
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );

ResponseBody atomResponse(List<String> versions) {
  final builder = XmlBuilder();
  builder.element(
    'feed',
    namespaceUris: {null: 'http://www.w3.org/2005/Atom'},
    nest: () {
      for (final version in versions) {
        builder.element(
          'entry',
          nest: () {
            builder.element('title', nest: '发行说明');
            builder.element(
              'link',
              attributes: {
                'rel': 'alternate',
                'href':
                    'https://github.com/miludeshiji/Reelva/releases/tag/v$version',
              },
            );
          },
        );
      }
    },
  );
  return ResponseBody.fromString(
    builder.buildDocument().toXmlString(),
    200,
    headers: {
      Headers.contentTypeHeader: ['application/atom+xml; charset=utf-8'],
    },
  );
}

class UpdateHttpAdapter implements HttpClientAdapter {
  UpdateHttpAdapter(this.handler);

  final FutureOr<ResponseBody> Function(RequestOptions options) handler;
  final requests = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return handler(options);
  }

  @override
  void close({bool force = false}) {}
}
