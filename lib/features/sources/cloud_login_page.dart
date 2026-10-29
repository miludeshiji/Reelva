import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:path/path.dart' as p;
import 'package:reelva/shared/widgets/glass_widgets.dart';

import 'domain/openlist_models.dart';
import 'openlist_authorization.dart';

const _quarkUrl = 'https://pan.quark.cn/';
const _quarkApi = 'https://drive.quark.cn/1/clouddrive';
const _desktopUserAgent =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
    'AppleWebKit/537.36 (KHTML, like Gecko) '
    'Chrome/133.0.0.0 Safari/537.36';
const _captureCallback = '''
if (window.top === window &&
    location.origin === 'https://api.oplist.org' &&
    location.pathname === '/' && location.hash.length > 1) {
  window.__reelvaOpenListCallback = location.href;
}
''';
const _checkQuarkLogin =
    '''
(() => {
  if (location.origin !== 'https://pan.quark.cn') return false;
  if (window.__reelvaQuarkLoggedIn) return true;
  if (!window.__reelvaQuarkChecking) {
    window.__reelvaQuarkChecking = true;
    fetch('$_quarkApi/file/sort?pr=ucpro&fr=pc&pdir_fid=0&_page=1&_size=1',
      {credentials: 'include'})
      .then(response => response.json())
      .then(data => {
        window.__reelvaQuarkLoggedIn = data.status === 200 && data.code === 0;
      })
      .catch(() => {})
      .finally(() => { window.__reelvaQuarkChecking = false; });
  }
  return false;
})()
''';

class CloudLoginPage extends StatefulWidget {
  const CloudLoginPage({super.key, required this.driver});

  final String driver;

  @override
  State<CloudLoginPage> createState() => _CloudLoginPageState();
}

class _CloudLoginPageState extends State<CloudLoginPage> {
  InAppWebViewController? _controller;
  WebViewEnvironment? _environment;
  Directory? _profile;
  Timer? _timer;
  bool _ready = false;
  bool _checking = false;
  bool _redirected = false;
  bool _finished = false;
  int _progress = 0;
  String? _error;

  bool get _quark => widget.driver == 'Quark';
  String get _initialUrl =>
      _quark ? _quarkUrl : openListLoginUri(widget.driver).toString();

  @override
  void initState() {
    super.initState();
    unawaited(_initialize());
  }

  Future<void> _initialize() async {
    try {
      if (Platform.isWindows) {
        final profile = await Directory.systemTemp.createTemp(
          'reelva_cloud_login_',
        );
        _profile = profile;
        final environment = await WebViewEnvironment.create(
          settings: WebViewEnvironmentSettings(userDataFolder: profile.path),
        );
        if (!mounted) {
          await environment.dispose();
          await _deleteProfile(profile);
          return;
        }
        _environment = environment;
      }
      if (mounted) setState(() => _ready = true);
    } catch (_) {
      if (mounted) {
        setState(() => _error = '无法打开登录页面，请确认系统已安装 WebView2，或返回手动填写凭据');
      }
    }
  }

  @override
  void dispose() {
    _finished = true;
    _timer?.cancel();
    unawaited(_disposeProfile());
    super.dispose();
  }

  Future<void> _deleteProfile(Directory profile) async {
    final target = p.normalize(profile.absolute.path);
    final temporary = p.normalize(Directory.systemTemp.absolute.path);
    if (p.isWithin(temporary, target) &&
        p.basename(target).startsWith('reelva_cloud_login_') &&
        await profile.exists()) {
      await profile.delete(recursive: true);
    }
  }

  Future<void> _disposeProfile() async {
    try {
      await _environment?.dispose();
      final profile = _profile;
      if (profile != null) await _deleteProfile(profile);
    } catch (_) {
      // WebView2 may still hold the temporary profile while its view closes.
    }
  }

  bool _receiveCallback(String url) {
    if (_finished || _quark) return false;
    try {
      final authorization = parseOpenListLoginCallback(
        url,
        driver: widget.driver,
      );
      if (authorization == null) return false;
      _complete(authorization);
    } on FormatException catch (error) {
      if (mounted) setState(() => _error = error.message);
    }
    return true;
  }

  void _complete(Map<String, dynamic> authorization) {
    if (_finished || !mounted) return;
    _finished = true;
    _timer?.cancel();
    Navigator.of(context).pop(authorization);
  }

  Future<void> _checkLogin() async {
    final controller = _controller;
    if (_finished || _checking || controller == null) return;
    _checking = true;
    try {
      if (_quark) {
        final manager = CookieManager.instance(
          webViewEnvironment: _environment,
        );
        final cookies = await manager.getCookies(url: WebUri(_quarkApi));
        if (_finished ||
            !cookies.any(
              (cookie) =>
                  cookie.name == '__pus' &&
                  cookie.value is String &&
                  (cookie.value as String).isNotEmpty,
            )) {
          return;
        }
        final loggedIn = await controller.evaluateJavascript(
          source: _checkQuarkLogin,
        );
        if (_finished || (loggedIn != true && loggedIn != 'true')) return;
        // The login probe can renew __puus. Fetch native cookies again,
        // including HttpOnly values, from the same browser environment.
        final current = await manager.getCookies(url: WebUri(_quarkApi));
        if (!current.any(
          (cookie) =>
              cookie.name == '__pus' &&
              cookie.value is String &&
              (cookie.value as String).isNotEmpty,
        )) {
          return;
        }
        _complete({
          'cookie': current
              .map((cookie) => '${cookie.name}=${cookie.value}')
              .join('; '),
        });
      } else {
        var raw = await controller.evaluateJavascript(
          source:
              '''
(() => {
  if (location.origin !== 'https://api.oplist.org') return null;
  return {
    url: window.__reelvaOpenListCallback || location.href,
    body: location.href === ${jsonEncode(_initialUrl)} ? document.body.textContent : null
  };
})()
''',
        );
        if (_finished) return;
        if (raw is String) raw = jsonDecode(raw);
        if (raw is! Map) return;
        final url = raw['url'] as String? ?? '';
        if (_receiveCallback(url) || _redirected || url != _initialUrl) return;
        final body = raw['body'];
        if (body is! String) return;
        final response = jsonDecode(body);
        final target = response is Map ? response['text'] : null;
        final loginUri = target is String ? Uri.tryParse(target) : null;
        if (loginUri == null ||
            loginUri.scheme != 'https' ||
            loginUri.host.isEmpty) {
          if (mounted) setState(() => _error = '无法开始网盘授权，请返回重试或手动填写凭据');
          return;
        }
        _redirected = true;
        // Keep /requests and provider authorization in one browser session.
        await controller.evaluateJavascript(
          source: 'location.replace(${jsonEncode(loginUri.toString())})',
        );
      }
    } catch (_) {
      // Navigation can invalidate JavaScript while redirects are in progress.
      // The next load event or timer tick checks the new document.
    } finally {
      _checking = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ReelvaDesign.background,
      body: SafeArea(
        child: Column(
          children: [
            GlassPageHeader(
              title: '登录 ${openListDrivers[widget.driver] ?? '网盘'}',
              leading: GlassIconButton(
                icon: Icons.close,
                tooltip: '取消登录',
                onPressed: () => Navigator.of(context).pop(),
              ),
              trailing: GlassIconButton(
                icon: Icons.refresh,
                tooltip: '刷新登录页面',
                onPressed: _controller == null
                    ? null
                    : () async {
                        _redirected = false;
                        setState(() => _error = null);
                        await _controller!.loadUrl(
                          urlRequest: URLRequest(url: WebUri(_initialUrl)),
                        );
                      },
              ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: ReelvaDesign.space24,
                  vertical: ReelvaDesign.space12,
                ),
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            if (_ready && _progress < 100)
              LinearProgressIndicator(value: _progress / 100),
            Expanded(
              child: !_ready
                  ? Center(
                      child: _error == null
                          ? const CircularProgressIndicator()
                          : const Icon(Icons.web_asset_off_outlined),
                    )
                  : InAppWebView(
                      webViewEnvironment: _environment,
                      initialUrlRequest: URLRequest(url: WebUri(_initialUrl)),
                      initialSettings: InAppWebViewSettings(
                        javaScriptEnabled: true,
                        incognito: !Platform.isWindows,
                        userAgent: _quark ? _desktopUserAgent : null,
                        useShouldOverrideUrlLoading: true,
                        thirdPartyCookiesEnabled: true,
                      ),
                      initialUserScripts: UnmodifiableListView([
                        UserScript(
                          source: _captureCallback,
                          injectionTime:
                              UserScriptInjectionTime.AT_DOCUMENT_START,
                        ),
                      ]),
                      onWebViewCreated: (controller) {
                        _controller = controller;
                        _timer = Timer.periodic(
                          const Duration(seconds: 2),
                          (_) => unawaited(_checkLogin()),
                        );
                      },
                      onLoadStart: (_, url) {
                        if (url != null) _receiveCallback(url.toString());
                      },
                      onUpdateVisitedHistory: (_, url, _) {
                        if (url != null) _receiveCallback(url.toString());
                      },
                      onLoadStop: (_, _) => _checkLogin(),
                      onProgressChanged: (_, progress) {
                        if (mounted) setState(() => _progress = progress);
                      },
                      shouldOverrideUrlLoading: (_, action) async {
                        final url = action.request.url;
                        if (url != null && _receiveCallback(url.toString())) {
                          return NavigationActionPolicy.CANCEL;
                        }
                        return NavigationActionPolicy.ALLOW;
                      },
                      onReceivedError: (_, request, _) {
                        if (request.isForMainFrame == true &&
                            mounted &&
                            !_finished) {
                          setState(() => _error = '登录页面加载失败，请刷新页面或返回手动填写凭据');
                        }
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
