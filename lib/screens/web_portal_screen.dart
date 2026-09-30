import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../services/download_engine.dart';

class WebPortalScreen extends StatefulWidget {
  final Function(int) onTabChangeRequested;
  const WebPortalScreen({super.key, required this.onTabChangeRequested});

  @override
  State<WebPortalScreen> createState() => _WebPortalScreenState();
}

class _WebPortalScreenState extends State<WebPortalScreen> {
  late final WebViewController _controller;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFF0A0A0A))
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (request) async {
            // 🚀 ၁။ HOME စာမျက်နှာရှိ "app သွင်းမည်" / "downloader သွင်းမည်" ခလုတ်များကို ဖမ်းယူခြင်း
            if (request.url.contains('/api/download/apk') || request.url.endsWith('.apk')) {
              DownloadEngine().addUrls([request.url]);
              widget.onTabChangeRequested(1); // Downloader Tab သို့ တန်းကူးမည်
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('📥 APK ကို ဒေါင်းလုဒ် စတင်နေပါသည်...'),
                  backgroundColor: Color(0xFF238636),
                ),
              );
              return NavigationDecision.prevent;
            }

            // 🚀 ၂။ download.html ထဲက 'dataplus://open' ခလုတ်ကို ဖမ်းယူခြင်း
            if (request.url.startsWith('dataplus://')) {
              try {
                final dynamic result = await _controller.runJavaScriptReturningResult(
                  'JSON.stringify(typeof downloadLinks !== "undefined" ? downloadLinks : [])'
                );
                String raw = result.toString();
                if (raw.startsWith('"') && raw.endsWith('"')) {
                  raw = jsonDecode(raw);
                }
                final List<dynamic> list = jsonDecode(raw);
                final urls = list.map((e) => e.toString()).toList();

                if (urls.isNotEmpty) {
                  DownloadEngine().addUrls(urls);
                  widget.onTabChangeRequested(1);
                }
              } catch (_) {}
              return NavigationDecision.prevent;
            }

            // 🚀 ၃။ တစ်ကားချင်း Download ခလုတ် နှိပ်လျှင်လည်း ဖမ်းယူခြင်း
            if (request.url.contains('/api/download/file/')) {
              DownloadEngine().addUrls([request.url]);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('✅ ဒေါင်းလုဒ် Queue ထဲသို့ ထည့်ပြီးပါပြီ'), backgroundColor: Color(0xFF238636))
              );
              return NavigationDecision.prevent;
            }

            return NavigationDecision.navigate;
          },
        ),
      )
      ..loadRequest(Uri.parse('http://10.10.10.10:1000'));
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) async {
        if (await _controller.canGoBack()) {
          _controller.goBack();
        }
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF0A0A0A),
        body: SafeArea(
          child: WebViewWidget(controller: _controller),
        ),
      ),
    );
  }
}
