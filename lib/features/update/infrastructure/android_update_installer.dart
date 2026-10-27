import 'package:flutter/services.dart';

class AndroidUpdateInstaller {
  const AndroidUpdateInstaller({
    this.channel = const MethodChannel('reelva/app_update'),
  });

  final MethodChannel channel;

  Future<List<String>> supportedAbis() async =>
      await channel.invokeListMethod<String>('supportedAbis') ?? [];

  /// 首次安装会等待未知来源授权；拒绝授权返回 false，可复用已下载文件重试。
  Future<bool> installApk(String path) async =>
      await channel.invokeMethod<bool>('installApk', {'path': path}) ?? false;
}
