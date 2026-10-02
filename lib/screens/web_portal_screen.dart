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

  // 📁 ဖုန်းထဲတွင် User Name အမြဲတမ်း သိမ်းထားမည့် ဖိုင်လမ်းကြောင်း
  static const String _userNameFilePath = '/storage/emulated/0/Download/DataPlus/user_name.txt';

  @override
  void initState() {
    super.initState();
    _initWebView();
  }

  // 💾 User Name ကို ဖိုင်ထဲသို့ အမြဲတမ်း သိမ်းဆည်းခြင်း
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

  // 📖 ဖိုင်ထဲမှ User Name ကို ပြန်ဖတ်ယူခြင်း
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

  // 📥 ဝဘ်ဆိုက်မှ ရောက်လာသော Download Link များကို Queue ထဲထည့်ပြီး Downloader Tab သို့ တန်းပြောင်းခြင်း
  void _processIncomingDownloadLinks(String payload) {
    if (payload.trim().isEmpty) return;

    List<String> urls = [];
    try {
      final decoded = jsonDecode(payload);
      if (decoded is List) {
        urls = decoded.map((e) => e.toString().trim()).where((u) => u.startsWith('http')).toList();
      }
    } catch (_) {
      urls = payload
          .split(RegExp(r'[\r\n,]+'))
          .map((e) => e.trim())
          .where((u) => u.startsWith('http'))
          .toList();
    }

    if (urls.isNotEmpty) {
      _engine.addUrls(urls);
      // 🚀 Downloader Tab (Index 1) သို့ ချက်ချင်း ကူးပြောင်းပေးခြင်း
      widget.onTabChangeRequested?.call(1);
    }
  }

  void _initWebView() {
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFF0A0A0A))
      // 👤 User Name သိမ်းမည့် Channel
      ..addJavaScriptChannel(
        'DataPlusUserBridge',
        onMessageReceived: (JavaScriptMessage message) {
          final name = message.message.trim();
          if (name.isNotEmpty) {
            _saveUserNamePermanently(name);
          }
        },
      )
      // 🚀 ဒေါင်းလုဒ် Link များကို လက်ခံမည့် Channel
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
            final uri = Uri.tryParse(url);

            // intent:// သို့မဟုတ် dataplus:// စသော Link များကို ကြားဖြတ်ဖမ်းယူခြင်း
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
            setState(() => _isLoading = true);
          },
          onPageFinished: (String url) async {
            setState(() => _isLoading = false);

            // ⚡ ၁။ ဝဘ်ဆိုက်ပေါ်ရှိ User Name နှင့် Clipboard Copy Hook များ ထည့်သွင်းခြင်း
            await _controller.runJavaScript('''
              (function() {
                // 1. User Name စောင့်ကြည့်ခြင်း
                var origSetItem = localStorage.setItem;
                localStorage.setItem = function(key, val) {
                  origSetItem.apply(this, arguments);
                  if (key === 'customer_name' && val && window.DataPlusUserBridge) {
                    window.DataPlusUserBridge.postMessage(val);
                  }
                };

                // 2. Clipboard သို့ Link များ Copy ကူးလိုက်သည်နှင့် App ထံ တိုက်ရိုက် သတင်းပို့ခြင်း
                if (navigator.clipboard) {
                  var origWriteText = navigator.clipboard.writeText;
                  navigator.clipboard.writeText = function(text) {
                    if (window.DataPlusDownloadBridge && typeof text === 'string' && text.indexOf('http') !== -1) {
                      window.DataPlusDownloadBridge.postMessage(text);
                    }
                    return origWriteText ? origWriteText.apply(navigator.clipboard, arguments) : Promise.resolve();
                  };
                }

                // 3. document.execCommand('copy') ဖြင့် ကူးယူခြင်းများကိုပါ ဖမ်းယူခြင်း
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

                // 4. "ဖွင့်မည်" သို့မဟုတ် ဒေါင်းလုဒ် ခလုတ်များကို နှိပ်သည့်အခါ Link များ ရှာဖွေပေးပို့ခြင်း
                document.addEventListener('click', function(e) {
                  var target = e.target.closest('button, a, div, input');
                  if (!target) return;
                  var txt = (target.innerText || target.value || '').toLowerCase();
                  if (txt.includes('ဖွင့်') || txt.includes('app') || txt.includes('download') || txt.includes('ဒေါင်း')) {
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

            // ⚡ ၂။ သိမ်းဆည်းထားသော User Name ရှိပါက Auto-Restore ပြုလုပ်ခြင်း
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
