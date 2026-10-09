import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/download_engine.dart';

class WebPortalScreen extends StatefulWidget {
  final Function(int)? onTabChangeRequested;

  const WebPortalScreen({super.key, this.onTabChangeRequested});

  @override
  State<WebPortalScreen> createState() => _WebPortalScreenState();
}

class _WebPortalScreenState extends State<WebPortalScreen> {
  late final WebViewController _controller;
  final DownloadEngine _engine = DownloadEngine();
  bool _isLoading = true;
  bool _isConnectionError = false;
  DateTime? _lastBackPressTime;

  static const List<String> _servers = [
    'http://10.10.10.10:1000',
    'http://192.168.1.50:1000',
  ];
  String _activeBaseUrl = 'http://10.10.10.10:1000';

  static const String _userNameFilePath = '/storage/emulated/0/.Dataplus/user_name.txt';

  @override
  void initState() {
    super.initState();
    _initController();
    _connectToFastestServer();
  }

  Future<void> _connectToFastestServer() async {
    setState(() {
      _isLoading = true;
      _isConnectionError = false;
    });

    final completer = Completer<String>();
    final client = HttpClient()..connectionTimeout = const Duration(milliseconds: 1200);
    int failedCount = 0;

    for (final host in _servers) {
      () async {
        try {
          final req = await client.getUrl(Uri.parse('$host/api/cart/count'));
          final resp = await req.close();
          if (resp.statusCode == HttpStatus.ok && !completer.isCompleted) {
            completer.complete(host);
          } else {
            failedCount++;
          }
        } catch (_) {
          failedCount++;
        }
        if (failedCount >= _servers.length && !completer.isCompleted) {
          completer.complete(_servers.first);
        }
      }();
    }

    Future.delayed(const Duration(milliseconds: 1500), () {
      if (!completer.isCompleted) {
        completer.complete(_servers.first);
      }
    });

    final selectedHost = await completer.future;
    client.close();

    _activeBaseUrl = selectedHost;
    _controller.loadRequest(Uri.parse('$_activeBaseUrl/'));
  }

  void _initController() {
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFF0A0A0A))
      ..addJavaScriptChannel(
        'DataPlusUserBridge',
        onMessageReceived: (JavaScriptMessage message) {
          final name = message.message.trim();
          if (name.isNotEmpty) {
            _saveUserNamePermanently(name);
          }
        },
      )
      ..addJavaScriptChannel(
        'DataPlusDownloadBridge',
        onMessageReceived: (JavaScriptMessage message) {
          _processIncomingDownloadLinks(message.message);
        },
      )
      ..addJavaScriptChannel(
        'DataPlusStorageBridge',
        onMessageReceived: (JavaScriptMessage message) async {
          final msg = message.message.trim();
          if (msg.startsWith('target:')) {
            final target = msg.substring(7);
            await _engine.setStorageTarget(target);
          }
          _sendStorageToWeb();
        },
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (NavigationRequest request) {
            final url = request.url;

            if (url.contains('/api/download/apk') ||
                url.toLowerCase().contains('.apk') ||
                url.contains('/api/download/file')) {
              _processIncomingDownloadLinks(url);
              return NavigationDecision.prevent;
            }

            if (url.startsWith('dataplus://') || url.startsWith('intent://')) {
              final matches = RegExp(r'https?://[^\s;"]+').allMatches(url);
              if (matches.isNotEmpty) {
                final links = matches.map((m) => m.group(0)!).toList();
                _processIncomingDownloadLinks(links.join('\n'));
              }
              return NavigationDecision.prevent;
            }
            return NavigationDecision.navigate;
          },
          onWebResourceError: (WebResourceError error) {
            if (error.isForMainFrame ?? true) {
              setState(() {
                _isLoading = false;
                _isConnectionError = true;
              });
            }
          },
          onPageStarted: (String url) {
            setState(() {
              _isConnectionError = false;
            });
          },
          onPageFinished: (String url) async {
            if (_isLoading) {
              setState(() => _isLoading = false);
            }

            final currentUri = Uri.tryParse(url);
            if (currentUri != null && currentUri.host.isNotEmpty) {
              _activeBaseUrl = '${currentUri.scheme}://${currentUri.host}:${currentUri.port}';
            }

            await _sendStorageToWeb();

            // 🌟 1. Web Portal Event Bridges
            await _controller.runJavaScript('''
              (function() {
                var origSetItem = localStorage.setItem;
                localStorage.setItem = function(key, val) {
                  origSetItem.apply(this, arguments);
                  if (key === 'customer_name' && val && window.DataPlusUserBridge) {
                    window.DataPlusUserBridge.postMessage(val);
                  }
                };

                if (navigator.clipboard) {
                  var origWriteText = navigator.clipboard.writeText;
                  navigator.clipboard.writeText = function(text) {
                    if (window.DataPlusDownloadBridge && typeof text === 'string' && text.indexOf('http') !== -1) {
                      window.DataPlusDownloadBridge.postMessage(text);
                    }
                    return origWriteText ? origWriteText.apply(navigator.clipboard, arguments) : Promise.resolve();
                  };
                }

                var origExec = document.execCommand;
                document.execCommand = function(cmd) {
                  if (cmd === 'copy') {
                    try {
                      var sel = window.getSelection().toString();
                      if (!sel) {
                        var activeEl = document.activeElement;
                        if (activeEl && (activeEl.tagName === 'TEXTAREA' || activeEl.tagName === 'INPUT')) {
                          sel = activeEl.value;
                        }
                      }
                      if (window.DataPlusDownloadBridge && sel && sel.indexOf('http') !== -1) {
                        window.DataPlusDownloadBridge.postMessage(sel);
                      }
                    } catch(e) {}
                  }
                  return origExec ? origExec.apply(document, arguments) : true;
                };

                document.addEventListener('click', function(e) {
                  var a = e.target.closest('a');
                  if (a && a.href && (a.href.indexOf('/api/download/apk') !== -1 || a.href.indexOf('.apk') !== -1)) {
                    e.preventDefault();
                    if (window.DataPlusDownloadBridge) {
                      window.DataPlusDownloadBridge.postMessage(a.href);
                    }
                    return;
                  }

                  var target = e.target.closest('button, a, div, input');
                  if (!target) return;
                  var txt = (target.innerText || target.value || '').toLowerCase();
                  if (txt.includes('ဖွင့်') || txt.includes('app') || txt.includes('download') || txt.includes('ဒေါင်း') || txt.includes('သွင်း')) {
                    setTimeout(function() {
                      var ta = document.querySelector('textarea');
                      if (ta && ta.value && ta.value.indexOf('http') !== -1) {
                        if (window.DataPlusDownloadBridge) {
                          window.DataPlusDownloadBridge.postMessage(ta.value);
                        }
                      }
                    }, 150);
                  }
                }, true);
              })();
            ''');

            // 🌟 2. Fast Smooth Scrolling & Poster Caching Optimizer Injection
            await _controller.runJavaScript('''
              (function() {
                try {
                  // Add CSS for Hardware Acceleration and Content-Visibility
                  var fastStyle = document.getElementById('dp-fast-scroll-style');
                  if (!fastStyle) {
                    fastStyle = document.createElement('style');
                    fastStyle.id = 'dp-fast-scroll-style';
                    fastStyle.innerHTML = `
                      * {
                        -webkit-overflow-scrolling: touch !important;
                      }
                      img {
                        content-visibility: auto;
                        contain-intrinsic-size: 200px 300px;
                      }
                    `;
                    document.head.appendChild(fastStyle);
                  }

                  // Force Lazy Loading & Async Decoding on all Movie Posters
                  var imgs = document.querySelectorAll('img');
                  for (var i = 0; i < imgs.length; i++) {
                    imgs[i].setAttribute('loading', 'lazy');
                    imgs[i].setAttribute('decoding', 'async');
                  }
                } catch(e) {}
              })();
            ''');

            // 🌟 3. Username Auto-fill
            final savedName = await _getSavedUserName();
            if (savedName != null && savedName.isNotEmpty) {
              await _controller.runJavaScript('''
                (function() {
                  var current = localStorage.getItem('customer_name');
                  if (!current || current === '' || current === 'Customer') {
                    localStorage.setItem('customer_name', '$savedName');
                    fetch('/api/user/identify', {
                      method: 'POST',
                      headers: {'Content-Type': 'application/json'},
                      body: JSON.stringify({name: '$savedName'})
                    }).catch(function(){});

                    var nameInput = document.querySelector('input[name="customer"], input[id*="customer"], input[id*="name"]');
                    if (nameInput) {
                      nameInput.value = '$savedName';
                    }
                  }
                })();
              ''');
            }
          },
        ),
      );
  }

  void _processIncomingDownloadLinks(String payload) {
    if (payload.trim().isEmpty) return;

    List<String> rawUrls = [];
    try {
      final decoded = jsonDecode(payload);
      if (decoded is List) {
        rawUrls = decoded.map((e) => e.toString().trim()).where((u) => u.isNotEmpty).toList();
      }
    } catch (_) {
      rawUrls = payload
          .split(RegExp(r'[\r\n,]+'))
          .map((e) => e.trim())
          .where((u) => u.isNotEmpty)
          .toList();
    }

    List<String> finalUrls = rawUrls.map((u) {
      String link = u;
      if (!link.startsWith('http')) {
        link = link.startsWith('/') ? '$_activeBaseUrl$link' : '$_activeBaseUrl/$link';
      } else {
        for (final server in _servers) {
          if (link.startsWith(server)) {
            link = link.replaceFirst(server, _activeBaseUrl);
            break;
          }
        }
      }
      return link;
    }).where((u) => u.startsWith('http')).toList();

    if (finalUrls.isNotEmpty) {
      _engine.addUrls(finalUrls);
      widget.onTabChangeRequested?.call(1);
    }
  }

  Future<void> _sendStorageToWeb() async {
    await _engine.updateStorageInfo();
    final storageData = jsonEncode({
      'free': _engine.freeStorageBytes,
      'total': _engine.totalStorageBytes,
      'sdAvailable': _engine.isSdAvailable,
      'sdFree': _engine.freeSdBytes,
      'sdTotal': _engine.totalSdBytes,
      'target': _engine.storageTarget,
    });
    try {
      await _controller.runJavaScript('''
        (function() {
          if (window.setAppStorageInfo) {
            window.setAppStorageInfo($storageData);
          } else {
            window.DP_DEVICE_STORAGE = $storageData;
          }
        })();
      ''');
    } catch (_) {}
  }

  Future<void> _saveUserNamePermanently(String name) async {
    final cleanName = name.trim();
    if (cleanName.isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('saved_username', cleanName);

      final dir = Directory('/storage/emulated/0/.Dataplus');
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      final file = File(_userNameFilePath);
      await file.writeAsString(cleanName);
    } catch (_) {}
  }

  Future<String?> _getSavedUserName() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      String? name = prefs.getString('saved_username');
      if (name != null && name.trim().isNotEmpty) {
        return name.trim();
      }

      final file = File(_userNameFilePath);
      if (await file.exists()) {
        final fileContent = (await file.readAsString()).trim();
        if (fileContent.isNotEmpty) {
          await prefs.setString('saved_username', fileContent);
          return fileContent;
        }
      }
    } catch (_) {}
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, Object? result) async {
        if (didPop) return;

        final currentUrl = await _controller.currentUrl() ?? '';
        final uri = Uri.tryParse(currentUrl);
        final path = uri?.path ?? '';

        if (await _controller.canGoBack()) {
          if (path.isNotEmpty && path != '/' && path != '/?') {
            await _controller.goBack();
            return;
          }
        }

        final now = DateTime.now();
        if (_lastBackPressTime == null ||
            now.difference(_lastBackPressTime!) > const Duration(seconds: 2)) {
          _lastBackPressTime = now;
          if (mounted) {
            ScaffoldMessenger.of(context).clearSnackBars();
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'App မှ ထွက်ရန် နောက်တစ်ကြိမ် ထပ်နှိပ်ပါ',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                ),
                duration: Duration(seconds: 2),
                backgroundColor: Color(0xFF262626),
                behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.all(Radius.circular(25)),
                ),
                margin: EdgeInsets.symmetric(horizontal: 50, vertical: 20),
              ),
            );
          }
          return;
        }

        SystemNavigator.pop();
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF0A0A0A),
        body: SafeArea(
          child: Stack(
            children: [
              WebViewWidget(controller: _controller),
              if (_isLoading)
                const Center(
                  child: CircularProgressIndicator(color: Color(0xFF00E676)),
                ),
              if (_isConnectionError && !_isLoading)
                Center(
                  child: Container(
                    margin: const EdgeInsets.all(24),
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E1E2E),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.white12),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.wifi_off_rounded, size: 48, color: Colors.orangeAccent),
                        const SizedBox(height: 12),
                        const Text(
                          'ဆာဗာသို့ ချိတ်ဆက်မရပါ',
                          style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '10.10.10.10 သို့မဟုတ် 192.168.1.50 ဆာဗာ Wi-Fi သို့ ချိတ်ဆက်ထားပါသလား စစ်ဆေးပါ',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.grey.shade400, fontSize: 12),
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton.icon(
                          onPressed: _connectToFastestServer,
                          icon: const Icon(Icons.refresh, color: Colors.black),
                          label: const Text('ပြန်လည်ချိတ်ဆက်မည်', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF00E676),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
