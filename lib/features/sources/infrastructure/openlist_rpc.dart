import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/services.dart';

import '../domain/source_models.dart';

abstract interface class OpenListRpcClient {
  Future<Map<String, dynamic>> invoke(
    String method,
    Map<String, dynamic> arguments,
  );
}

/// 移动端与桌面共享内核 JSON ABI，阻塞的 Go 调用不在 UI 线程执行。
class EmbeddedOpenListRpc implements OpenListRpcClient {
  EmbeddedOpenListRpc({MethodChannel? channel, this.libraryPath})
    : _channel = channel ?? const MethodChannel('reelva/openlist');

  final MethodChannel _channel;
  final String? libraryPath;

  @override
  Future<Map<String, dynamic>> invoke(
    String method,
    Map<String, dynamic> arguments,
  ) async {
    try {
      final message = jsonEncode({'method': method, 'arguments': arguments});
      final String? response;
      if (Platform.isAndroid) {
        response = await _channel.invokeMethod<String>('invoke', message);
      } else if (Platform.isWindows) {
        final path =
            libraryPath ??
            '${File(Platform.resolvedExecutable).parent.path}${Platform.pathSeparator}venera_openlist.dll';
        response = await Isolate.run(() => _invokeDesktop(path, message));
      } else {
        throw const MediaSourceException(
          '当前平台不支持内置网盘',
          code: 'unsupported_platform',
        );
      }
      final decoded = response == null ? null : jsonDecode(response);
      if (decoded is! Map<String, dynamic>) {
        throw const MediaSourceException(
          '网盘内核返回数据无效',
          code: 'invalid_response',
        );
      }
      return decoded;
    } on MediaSourceException {
      rethrow;
    } catch (_) {
      throw const MediaSourceException(
        '无法调用网盘内核，请检查安装包是否完整',
        code: 'core_unavailable',
      );
    }
  }

  static String _invokeDesktop(String path, String message) {
    final library = DynamicLibrary.open(path);
    final allocate = library
        .lookupFunction<
          Pointer<Void> Function(Int32),
          Pointer<Void> Function(int)
        >('OpenListAllocate');
    final free = library
        .lookupFunction<
          Void Function(Pointer<Void>),
          void Function(Pointer<Void>)
        >('OpenListFree');
    final invoke = library
        .lookupFunction<
          Pointer<Char> Function(Pointer<Char>),
          Pointer<Char> Function(Pointer<Char>)
        >('OpenListInvoke');
    final encoded = utf8.encode(message);
    final input = allocate(encoded.length + 1);
    if (input == nullptr) throw StateError('OpenListAllocate failed');
    try {
      final bytes = input.cast<Uint8>().asTypedList(encoded.length + 1);
      bytes.setAll(0, encoded);
      bytes[encoded.length] = 0;
      final output = invoke(input.cast<Char>());
      if (output == nullptr) throw StateError('OpenListInvoke failed');
      try {
        final pointer = output.cast<Uint8>();
        final values = <int>[];
        for (var index = 0; pointer[index] != 0; index++) {
          values.add(pointer[index]);
        }
        return utf8.decode(values);
      } finally {
        free(output.cast<Void>());
      }
    } finally {
      free(input);
    }
  }
}
