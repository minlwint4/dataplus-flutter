import 'dart:io';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

class WebPortalScreen extends StatefulWidget {
  final Function(int)? onTabChangeRequested;

  const WebPortalScreen({super.key, this.onTabChangeRequested});

  @override
  State<WebPortalScreen> createState() => _WebPortalScreenState();
}

class _WebPortalScreenState extends State<WebPortalScreen> {
  late final WebViewController _controller;
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

  void _initWebView() {
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFF0A0A0A))
      // 🚀 Web Page နှင့် Flutter ကြား ချိတ်ဆက်ပြီး နာမည်အသစ်ရိုက်တိုင်း အလိုအလျောက် ဖိုင်ထဲသိမ်းမည့် Channel
      ..addJavaScriptChannel(
        'DataPlusUserBridge',
        onMessageReceived: (JavaScriptMessage message) {
          final name = message.message.trim();
          if (name.isNotEmpty) {
            _saveUserNamePermanently(name);
          }
        },
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (String url) {
            setState(() => _isLoading = true);
          },
          onPageFinished: (String url) async {
            setState(() => _isLoading = false);

            // ⚡ ၁။ Web Page ထဲတွင် နာမည်ရိုက်ထည့်တိုင်း Flutter ထံ သတင်းပို့မည့် Hook ကို ထည့်သွင်းခြင်း
            await _controller.runJavaScript('''
              (function() {
                // localStorage.setItem ကို စောင့်ကြည့်ပြီး Flutter ဆီ အလိုအလျောက် ပို့ပေးခြင်း
                var origSetItem = localStorage.setItem;
                localStorage.setItem = function(key, val) {
                  origSetItem.apply(this, arguments);
                  if (key === 'customer_name' && val && window.DataPlusUserBridge) {
                    window.DataPlusUserBridge.postMessage(val);
                  }
                };
              })();
            ''');

            // ⚡ ၂။ ဖုန်းထဲတွင် ယခင်သိမ်းထားသော နာမည်ရှိပါက အလိုအလျောက် ပြန်လည် ထည့်သွင်းပေးခြင်း (Auto-Restore)
            final savedName = await _getSavedUserName();
            if (savedName != null && savedName.isNotEmpty) {
              await _controller.runJavaScript('''
                (function() {
                  var current = localStorage.getItem('customer_name');
                  if (!current || current === '' || current === 'Customer') {
                    localStorage.setItem('customer_name', '$savedName');
                    // Server session ဆီသို့ပါ တန်းပို့ခြင်း
                    fetch('/api/user/identify', {
                      method: 'POST',
                      headers: {'Content-Type': 'application/json'},
                      body: JSON.stringify({name: '$savedName'})
                    }).catch(function(){});

                    // နာမည်မေးသည့် Input box ရှိနေပါက နာမည်ဖြည့်ပြီး ပိတ်ပေးခြင်း
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
