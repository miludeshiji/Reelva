import 'dart:io';
import 'dart:math' as math;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/app_update_providers.dart';
import '../domain/app_release.dart';

class AppUpdateDialog extends ConsumerStatefulWidget {
  const AppUpdateDialog({
    super.key,
    required this.release,
    required this.currentVersion,
  });

  final AppRelease release;
  final String currentVersion;

  @override
  ConsumerState<AppUpdateDialog> createState() => _AppUpdateDialogState();
}

class _AppUpdateDialogState extends ConsumerState<AppUpdateDialog> {
  CancelToken? _cancelToken;
  File? _apk;
  bool _busy = false;
  int _received = 0;
  int _total = 0;
  String? _status;
  String? _error;

  Future<void> _open(Uri uri) async {
    try {
      await ref.read(openUpdateUrlProvider)(uri);
    } catch (_) {
      if (mounted) setState(() => _error = '无法打开链接，请稍后重试');
    }
  }

  Future<void> _install(ReleaseAsset asset) async {
    if (_busy) return;
    final token = CancelToken();
    setState(() {
      _busy = true;
      _cancelToken = token;
      _error = null;
      _status = _apk == null ? '正在下载安装包…' : '正在打开安装界面…';
      _received = 0;
      _total = asset.size;
    });
    try {
      if (_apk == null || !await _apk!.exists()) {
        final file = await ref
            .read(apkDownloaderProvider)
            .download(
              asset,
              cancelToken: token,
              onProgress: (received, total) {
                if (!mounted) return;
                setState(() {
                  _received = received;
                  _total = total > 0 ? total : asset.size;
                });
              },
            );
        if (!mounted) return;
        _apk = file;
      }
      if (!mounted) return;
      setState(() {
        _cancelToken = null;
        _status = '正在打开安装界面…';
      });
      final opened = await ref
          .read(androidUpdateInstallerProvider)
          .installApk(_apk!.path);
      if (!mounted) return;
      setState(() {
        _status = opened ? '已打开系统安装界面' : '允许 Reelva 安装未知应用后，可点击继续安装';
      });
    } on DioException catch (e) {
      if (!mounted) return;
      setState(() {
        if (CancelToken.isCancel(e)) {
          _status = '已取消下载';
        } else {
          _error = '安装包下载失败，请重试';
        }
      });
    } on FormatException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) {
        setState(() => _error = _apk == null ? '安装包下载失败，请重试' : '无法打开安装界面，请重试');
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _cancelToken = null;
        });
      }
    }
  }

  @override
  void dispose() {
    _cancelToken?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final release = widget.release;
    final android = defaultTargetPlatform == TargetPlatform.android;
    final hasAssets = release.assets.isNotEmpty;
    final abis = android && hasAssets ? ref.watch(updateAbisProvider) : null;
    final supportedAbis = abis?.asData?.value ?? const <String>[];
    final apk = release.androidApk(supportedAbis);
    final abi = AppRelease.androidAbi(supportedAbis);
    final date = release.publishedAt?.toLocal();
    final theme = Theme.of(context);
    final downloading = _busy && _cancelToken != null;

    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text('发现新版本', style: theme.textTheme.titleLarge),
                  ),
                  IconButton(
                    key: const Key('update_dialog_close'),
                    tooltip: '关闭',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              Text(
                '${widget.currentVersion} → ${release.version.text}',
                style: theme.textTheme.titleMedium,
              ),
              if (date != null)
                Text(
                  '发布于 ${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}',
                ),
              const SizedBox(height: 16),
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: math.min(
                    320,
                    MediaQuery.sizeOf(context).height * 0.4,
                  ),
                ),
                child: SingleChildScrollView(
                  child: MarkdownBody(
                    data: release.notes.trim().isEmpty
                        ? '此版本未提供更新说明。'
                        : release.notes,
                    selectable: true,
                    onTapLink: (text, href, title) {
                      if (href != null) _open(release.url.resolve(href));
                    },
                  ),
                ),
              ),
              const SizedBox(height: 20),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    _error!,
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                )
              else if (_status != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(_status!),
                ),
              if (downloading) ...[
                LinearProgressIndicator(
                  value: _total > 0 ? (_received / _total).clamp(0, 1) : null,
                ),
                const SizedBox(height: 8),
                Text(
                  '${(_received / 1048576).toStringAsFixed(1)} / ${(_total / 1048576).toStringAsFixed(1)} MB',
                ),
                TextButton(
                  onPressed: () => _cancelToken?.cancel(),
                  child: const Text('取消下载'),
                ),
              ],
              if (android && hasAssets) ...[
                if (abis!.hasError)
                  FilledButton(
                    onPressed: () => ref.invalidate(updateAbisProvider),
                    child: const Text('重试识别设备架构'),
                  )
                else
                  FilledButton.icon(
                    key: const Key('update_android_apk'),
                    onPressed: _busy || apk == null
                        ? null
                        : () => _install(apk),
                    icon: const Icon(Icons.system_update_rounded),
                    label: Text(
                      abis.isLoading
                          ? '正在识别设备架构…'
                          : _apk != null
                          ? '继续安装'
                          : apk == null
                          ? '无适用的安装包'
                          : '下载并安装（$abi）',
                    ),
                  ),
              ] else if (hasAssets &&
                  defaultTargetPlatform == TargetPlatform.windows) ...[
                FilledButton.icon(
                  key: const Key('update_windows_installer'),
                  onPressed: release.windowsInstaller == null
                      ? null
                      : () => _open(release.windowsInstaller!.url),
                  icon: const Icon(Icons.download_rounded),
                  label: const Text('下载安装包（x64）'),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  key: const Key('update_windows_portable'),
                  onPressed: release.windowsPortable == null
                      ? null
                      : () => _open(release.windowsPortable!.url),
                  icon: const Icon(Icons.folder_zip_outlined),
                  label: const Text('下载便携包（x64）'),
                ),
              ],
              const SizedBox(height: 8),
              OutlinedButton.icon(
                key: const Key('update_release_github'),
                onPressed: () => _open(release.url),
                icon: const Icon(Icons.open_in_new_rounded),
                label: Text(hasAssets ? '在 GitHub 查看此版本' : '在 GitHub 查看并下载'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
