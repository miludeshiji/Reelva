import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../../../app/theme/reelva_theme.dart';
import '../domain/playback_resource.dart';

/// 安全网络视频地址输入对话框
///
/// 严格仅允许解析并接受带有有效 host 的 HTTP 或 HTTPS 链接；
/// 显示名称统一使用通用的“网络视频”，不泄漏敏感签名参数或鉴权信息。
class NetworkAddressDialog extends StatefulWidget {
  const NetworkAddressDialog({super.key});

  @override
  State<NetworkAddressDialog> createState() => _NetworkAddressDialogState();
}

class _NetworkAddressDialogState extends State<NetworkAddressDialog> {
  final _controller = TextEditingController();
  String? _errorText;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final rawText = _controller.text.trim();
    if (rawText.isEmpty) {
      setState(() {
        _errorText = '请输入网络视频地址';
      });
      return;
    }

    final uri = Uri.tryParse(rawText);
    if (uri == null ||
        !uri.hasScheme ||
        (uri.scheme != 'http' && uri.scheme != 'https') ||
        uri.host.isEmpty) {
      setState(() {
        _errorText = '请输入有效的 HTTP 或 HTTPS 视频链接';
      });
      return;
    }

    Navigator.of(context).pop(PlaybackResource(uri: uri, displayName: '网络视频'));
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: ReelvaTheme.player,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: AlertDialog(
          backgroundColor: const Color(0xED17212D),
          scrollable: true,
          insetPadding: const EdgeInsets.symmetric(
            horizontal: ReelvaDesign.space20,
            vertical: ReelvaDesign.space24,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(ReelvaDesign.radiusLarge),
            side: const BorderSide(color: Colors.white38),
          ),
          title: const Text('输入网络视频地址'),
          content: SizedBox(
            width: 480,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  key: const Key('network_url_text_field'),
                  controller: _controller,
                  autofocus: true,
                  keyboardType: TextInputType.url,
                  decoration: InputDecoration(
                    hintText: 'https://example.com/video.mp4',
                    labelText: '视频 URL (HTTP/HTTPS)',
                    errorText: _errorText,
                    prefixIcon: const Icon(Icons.link),
                    border: const OutlineInputBorder(),
                  ),
                  onSubmitted: (_) => _submit(),
                  onChanged: (_) {
                    if (_errorText != null) {
                      setState(() => _errorText = null);
                    }
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              key: const Key('network_dialog_cancel_button'),
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('取消'),
            ),
            FilledButton(
              key: const Key('network_dialog_confirm_button'),
              onPressed: _submit,
              style: FilledButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: const Color(0xFF0E141C),
              ),
              child: const Text('播放'),
            ),
          ],
        ),
      ),
    );
  }
}
