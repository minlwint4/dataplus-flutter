import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
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

  // 📥 ရောက်လာသော Download Link များကို Downloader Engine ထဲ ထည့်သွင်းခြင်း
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

    // လိပ်စာ အပြည့်အစုံ (Absolute URL) ဖြစ်အောင် ပြုပြင်ခြင်း
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
      // 🚀 Downloader Tab (Index 1) သို့ ချက်ချင်း ခုန်ကူးပြောင်းပေးခြင်း
      widget.onTabChangeRequested?.call(1);
    }
  }

  void _initWebView() {
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFF0A0A0A))
      // 👤 User Name သိမ်းမည့် Bridge
      ..addJavaScriptChannel(
        'DataPlusUserBridge',
        onMessageReceived: (JavaScriptMessage message) {
          final name = message.message.trim();
          if (name.isNotEmpty) {
            _saveUserNamePermanently(name);
          }
        },
      )
      // 🚀 ဒေါင်းလုဒ် Link များကို လက်ခံမည့် Bridge
      ..addJavaScriptChannel(
        'DataPlusDownloadBridge',
        onMessageReceived: (JavaScriptMessage message) {
          _processIncomingDownloadLinks(message.message);
        },
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (NavigationRequest request) {
            final url = request.url;

            // ⚡ ၁။ "app သွင်းမယ်" APK Link သို့မဟုတ် ဖိုင်ဒေါင်းလုဒ် Link များကို ကြားဖြတ်ဖမ်းယူပြီး Downloader သို့ ပို့ပေးခြင်း
            if (url.contains('/api/download/apk') ||
                url.toLowerCase().contains('.apk') ||
                url.contains('/api/download/file')) {
              _processIncomingDownloadLinks(url);
              return NavigationDecision.prevent;
            }

            // ⚡ ၂။ intent:// နှင့် dataplus:// Link များကို ကြားဖြတ်ဖမ်းယူခြင်း
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
          onPageStarted: (String url) {
            // Page ကူးတိုင်း Loading အဝိုင်းမပြတော့ပါ
          },
          onPageFinished: (String url) async {
            if (_isLoading) {
              setState(() => _isLoading = false);
            }

            await _controller.runJavaScript('''
              (function() {
                // 1. User Name စောင့်ကြည့်မှတ်သားခြင်း
                var origSetItem = localStorage.setItem;
                localStorage.setItem = function(key, val) {
                  origSetItem.apply(this, arguments);
                  if (key === 'customer_name' && val && window.DataPlusUserBridge) {
                    window.DataPlusUserBridge.postMessage(val);
                  }
                };

                // 2. Clipboard သို့ Link Copy ကူးခြင်းများကို ဖမ်းယူခြင်း
                if (navigator.clipboard) {
                  var origWriteText = navigator.clipboard.writeText;
                  navigator.clipboard.writeText = function(text) {
                    if (window.DataPlusDownloadBridge && typeof text === 'string' && text.indexOf('http') !== -1) {
                      window.DataPlusDownloadBridge.postMessage(text);
                    }
                    return origWriteText ? origWriteText.apply(navigator.clipboard, arguments) : Promise.resolve();
                  };
                }

                // 3. execCommand('copy') ဖမ်းယူခြင်း
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

                // 4. "app သွင်းမယ်" နှင့် ဒေါင်းလုဒ် ခလုတ်များကို နှိပ်လိုက်သည်နှင့် Downloader ထံ ချက်ချင်း ပို့ပေးခြင်း
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

            // User Name အလိုအလျောက် ပြန်ထည့်ပေးခြင်း
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
    return Scaffold(
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
    );
  }
}
