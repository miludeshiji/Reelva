import 'dart:convert';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'app_log_store.dart';

class LogExporter {
  const LogExporter({this.channel = const MethodChannel('reelva/log_export')});

  final MethodChannel channel;

  /// 导出全部保留日志；用户取消保存返回 false。
  Future<bool> export(AppLogStore store) async {
    final package = await PackageInfo.fromPlatform();
    final text = await store.exportText(
      appVersion: '${package.version}+${package.buildNumber}',
    );
    final filename = 'reelva-logs-${DateTime.now().millisecondsSinceEpoch}.txt';
    final bytes = Uint8List.fromList(utf8.encode(text));
    if (defaultTargetPlatform == TargetPlatform.android) {
      return await channel.invokeMethod<bool>('save', {
            'name': filename,
            'data': bytes,
          }) ??
          false;
    }
    final location = await getSaveLocation(suggestedName: filename);
    if (location == null) return false;
    await XFile.fromData(
      bytes,
      mimeType: 'text/plain',
      name: filename,
    ).saveTo(location.path);
    return true;
  }
}
