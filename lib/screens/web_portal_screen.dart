import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';
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
  DateTime? _lastBackPressTime;

  static const String _userNameFilePath = '/storage/emulated/0/Download/DataPlus/user_name.txt';

  @override
  void initState() {
    super.initState();
    _initWebView();
  }

  Future<void> _saveUserNamePermanently(String name) async {
    final cleanName = name.trim();
    if (cleanName.isEmpty) return;
    try {
      final dir = Directory('/storage/emulated/0/Download/DataPlus');
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      final file = File(_userNameFilePath);
      await file.writeAsString(cleanName);
    } catch (_) {}
  }

  Future<String?> _getSavedUserName() async {
    try {
      final file = File(_userNameFilePath);
      if (await file.exists()) {
        final name = (await file.readAsString()).trim();
        if (name.isNotEmpty) return name;
      }
    } catch (_) {}
    return null;
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
      if (!u.startsWith('http')) {
        if (u.startsWith('/')) {
          return 'http://10.10.10.10:1000$u';
        } else {
          return 'http://10.10.10.10:1000/$u';
        }
      }
      return u;
    }).where((u) => u.startsWith('http')).toList();

    if (finalUrls.isNotEmpty) {
      _engine.addUrls(finalUrls);
      widget.onTabChangeRequested?.call(1);
    }
  }

  // 💾 ဖုန်း Storage အချက်အလက်များကို WebView ထဲသို့ လှမ်းပို့ပေးသည့် စနစ်
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

  void _initWebView() {
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
      // 💾 Storage Channel ချိတ်ဆက်ခြင်း
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
          onPageStarted: (String url) {},
          onPageFinished: (String url) async {
            if (_isLoading) {
              setState(() => _isLoading = false);
            }

            await _sendStorageToWeb();

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
      )
      ..loadRequest(Uri.parse('http://10.10.10.10:1000/'));
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, Object? result) async {
        if (didPop) return;

        if (await _controller.canGoBack()) {
          await _controller.goBack();
          return;
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
            ],
          ),
        ),
      ),
    );
  }
}
