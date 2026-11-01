import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:open_filex/open_filex.dart';
import 'package:android_intent_plus/android_intent.dart';
import 'package:android_intent_plus/flag.dart';
import 'package:video_player/video_player.dart';
import '../services/download_engine.dart';
import '../main.dart';

class DownloaderScreen extends StatefulWidget {
  const DownloaderScreen({super.key});

  static String? pendingCustomerName;
  static int pendingMovieCount = 0;
  static int pendingSeriesCount = 0;
  static String pendingServerUrl = 'http://10.10.10.10:1000';
  static bool hasPendingVoucher = false;

  static void setPendingVoucher({
    required String customerName,
    required int movieCount,
    required int seriesCount,
    required String serverUrl,
  }) {
    pendingCustomerName = customerName;
    pendingMovieCount = movieCount;
    pendingSeriesCount = seriesCount;
    pendingServerUrl = serverUrl;
    hasPendingVoucher = true;
  }

  @override
  State<DownloaderScreen> createState() => _DownloaderScreenState();
}

class _DownloaderScreenState extends State<DownloaderScreen> {
  final engine = DownloadEngine();
  late String currentTab;

  bool _wasDownloading = false;
  bool _isVoucherShowing = false;
  VideoPlayerController? _voiceController;

  @override
  void initState() {
    super.initState();
    currentTab = engine.activeTab.value;
    engine.activeTab.addListener(_handleTabChange);
    engine.addListener(_handleEngineStateChange);
    _updateOrientations(currentTab);
  }

  void _handleTabChange() {
    if (mounted) {
      setState(() {
        currentTab = engine.activeTab.value;
      });
      _updateOrientations(currentTab);
    }
  }

  void _handleEngineStateChange() {
    final bool isDownloading = engine.downloads.any((d) => d.status == 'downloading' || engine.isDownloading);
    final int qCount = engine.downloads.where((d) => d.status != 'finished').length;
    final int fCount = engine.downloads.where((d) => d.status == 'finished').length;

    if (isDownloading) {
      _wasDownloading = true;
    } else if (_wasDownloading && qCount == 0 && fCount > 0) {
      _wasDownloading = false;
      _triggerVoucherAndVoice();
    }
  }

  void _triggerVoucherAndVoice() {
    if (!DownloaderScreen.hasPendingVoucher || _isVoucherShowing) return;

    Future.delayed(const Duration(milliseconds: 500), () {
      if (!mounted || !DownloaderScreen.hasPendingVoucher || _isVoucherShowing) return;

      _isVoucherShowing = true;
      _showVoucherDialog(
        customerName: DownloaderScreen.pendingCustomerName ?? 'Customer',
        movieCount: DownloaderScreen.pendingMovieCount,
        seriesCount: DownloaderScreen.pendingSeriesCount,
        serverUrl: DownloaderScreen.pendingServerUrl,
      ).then((_) {
        _isVoucherShowing = false;
        DownloaderScreen.hasPendingVoucher = false;
        _stopVoicePlayback();
      });
    });
  }

  // 🔊 VideoPlayer Engine ဖြင့် ဖုန်းစပီကာမှ ကျသင့်ငွေ အသံဖိုင်များ ဖွင့်ခြင်း
  Future<void> _playPhoneVoiceSequence(String serverUrl, int totalPrice) async {
    try {
      final List<String> targetServers = [
        serverUrl,
        'http://10.10.10.10:1000',
        'http://192.168.1.50:1000',
      ].toSet().toList();

      List<dynamic> files = [];
      String workingServer = serverUrl;

      for (final srv in targetServers) {
        if (srv.isEmpty) continue;
        try {
          final client = HttpClient()..connectionTimeout = const Duration(milliseconds: 1500);
          final req = await client.getUrl(Uri.parse('$srv/api/voice/price_files?price=$totalPrice'));
          final resp = await req.close();
          if (resp.statusCode == HttpStatus.ok) {
            final body = await resp.transform(utf8.decoder).join();
            final data = jsonDecode(body);
            files = data['files'] ?? [];
            workingServer = srv;
            client.close();
            if (files.isNotEmpty) break;
          } else {
            client.close();
          }
        } catch (_) {}
      }

      if (files.isEmpty || !mounted) return;

      await _stopVoicePlayback();

      for (final relativeUrl in files) {
        if (!_isVoucherShowing || !mounted) break;
        final fullUrl = '$workingServer$relativeUrl';

        try {
          final controller = VideoPlayerController.networkUrl(Uri.parse(fullUrl));
          _voiceController = controller;
          await controller.initialize();
          await controller.play();

          final dur = controller.value.duration;
          final startTime = DateTime.now();

          while (controller.value.isPlaying &&
              DateTime.now().difference(startTime) < dur + const Duration(milliseconds: 400)) {
            if (!_isVoucherShowing || !mounted) break;
            await Future.delayed(const Duration(milliseconds: 50));
          }

          await controller.dispose();
          if (_voiceController == controller) {
            _voiceController = null;
          }
          await Future.delayed(const Duration(milliseconds: 50));
        } catch (_) {}
      }
    } catch (_) {}
  }

  Future<void> _stopVoicePlayback() async {
    try {
      if (_voiceController != null) {
        await _voiceController!.pause();
        await _voiceController!.dispose();
        _voiceController = null;
      }
    } catch (_) {}
  }

  // 🖨️ ဆာဗာသို့ Print Job လှမ်းပို့မည့် Function
  Future<void> _sendPrintJob(BuildContext ctx, String serverUrl, String customer, int mc, int sc) async {
    final List<String> targetServers = [
      serverUrl,
      'http://10.10.10.10:1000',
      'http://192.168.1.50:1000',
    ].toSet().toList();

    bool printSuccess = false;
    String lastError = "ဆာဗာသို့ ချိတ်ဆက်မရပါ";

    for (final target in targetServers) {
      if (target.isEmpty) continue;
      try {
        final client = HttpClient()..connectionTimeout = const Duration(milliseconds: 2000);
        final req = await client.postUrl(Uri.parse('$target/api/voucher/print'));
        req.headers.set('Content-Type', 'application/json');
        req.add(utf8.encode(jsonEncode({
          'customer': customer,
          'movie_count': mc,
          'series_count': sc,
        })));
        final resp = await req.close();
        final respBody = await resp.transform(utf8.decoder).join();
        client.close();

        if (resp.statusCode == HttpStatus.ok) {
          printSuccess = true;
          break;
        } else {
          lastError = "Server ($target): HTTP ${resp.statusCode} - $respBody";
        }
      } catch (e) {
        lastError = "ချိတ်ဆက်မှုမအောင်မြင်ပါ ($target): $e";
      }
    }

    if (!ctx.mounted) return;

    if (printSuccess) {
      ScaffoldMessenger.of(ctx).showSnackBar(
        const SnackBar(
          content: Text("✅ ဘောက်ချာ ထုတ်ပြီးပါပြီ"),
          backgroundColor: Color(0xFF238636),
          duration: Duration(seconds: 2),
        ),
      );
    } else {
      ScaffoldMessenger.of(ctx).showSnackBar(
        SnackBar(
          content: Text("⚠️ $lastError"),
          backgroundColor: const Color(0xFFB91C1C),
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }

  Future<void> _showVoucherDialog({
    required String customerName,
    required int movieCount,
    required int seriesCount,
    required String serverUrl,
  }) async {
    final int mBundles = movieCount ~/ 4;
    final int mBundleCount = mBundles * 4;
    final int mBundlePrice = mBundles * 1000;
    final int mRemCount = movieCount % 4;
    final int mRemPrice = mRemCount * 300;
    final int movieTotal = mBundlePrice + mRemPrice;

    final int seriesTotal;
    final int sBundleCount;
    final int sBundlePrice;
    final int sRemCount;
    final int sRemPrice;

    if (seriesCount >= 40) {
      seriesTotal = seriesCount * 100;
      sBundleCount = 0;
      sBundlePrice = 0;
      sRemCount = 0;
      sRemPrice = 0;
    } else {
      final int sBundles = seriesCount ~/ 10;
      sBundleCount = sBundles * 10;
      sBundlePrice = sBundles * 1200;
      sRemCount = seriesCount % 10;
      sRemPrice = sRemCount * 150;
      seriesTotal = sBundlePrice + sRemPrice;
    }

    final int grandTotal = movieTotal + seriesTotal;
    final String nowStr = DateTime.now().toString().substring(0, 16);

    _playPhoneVoiceSequence(serverUrl, grandTotal);

    await showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E232B),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        titlePadding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
        contentPadding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
        title: const Column(
          children: [
            Text(
              "DATA PLUS",
              style: TextStyle(
                color: Color(0xFF00E676),
                fontSize: 18,
                fontWeight: FontWeight.bold,
                letterSpacing: 2,
              ),
            ),
            SizedBox(height: 3),
            Text(
              "ငွေရှင်းပြေစာ (Voucher)",
              style: TextStyle(color: Color(0xFF8B949E), fontSize: 11),
            ),
            Divider(color: Color(0xFF30363D), height: 16),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text("Customer: $customerName", style: const TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.bold)),
                  Text(nowStr, style: const TextStyle(color: Color(0xFF8B949E), fontSize: 11)),
                ],
              ),
              const SizedBox(height: 12),

              if (movieCount > 0) ...[
                Text(
                  "MOVIES ($movieCount)",
                  style: const TextStyle(color: Color(0xFF58A6FF), fontSize: 12.5, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                if (mBundleCount > 0)
                  _buildVoucherRow("$mBundleCount x 250", "$mBundlePrice"),
                if (mRemCount > 0)
                  _buildVoucherRow("$mRemCount x 300", "$mRemPrice"),
                const SizedBox(height: 10),
              ],

              if (seriesCount > 0) ...[
                Text(
                  "SERIES ($seriesCount)",
                  style: const TextStyle(color: Color(0xFF00E676), fontSize: 12.5, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                if (seriesCount >= 40)
                  _buildVoucherRow("$seriesCount x 100", "$seriesTotal")
                else ...[
                  if (sBundleCount > 0)
                    _buildVoucherRow("$sBundleCount x 120", "$sBundlePrice"),
                  if (sRemCount > 0)
                    _buildVoucherRow("$sRemCount x 150", "$sRemPrice"),
                ],
                const SizedBox(height: 10),
              ],

              const Divider(color: Color(0xFF30363D), height: 16),

              _buildVoucherRow("TOTAL", "$grandTotal Ks", isTotal: true),
            ],
          ),
        ),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
        actions: [
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1F6FEB),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                  ),
                  onPressed: () {
                    _sendPrintJob(context, serverUrl, customerName, movieCount, seriesCount);
                  },
                  icon: const Icon(Icons.receipt_long, size: 16, color: Colors.white),
                  label: const Text(
                    "ဘောက်ချာယူမယ်",
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF238636),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                  ),
                  onPressed: () {
                    _stopVoicePlayback();
                    Navigator.pop(ctx);
                  },
                  child: const Text(
                    "OK (ပိတ်မည်)",
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildVoucherRow(String left, String right, {bool isTotal = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.5),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            left,
            style: TextStyle(
              color: isTotal ? Colors.white : const Color(0xFFC9D1D9),
              fontSize: isTotal ? 14 : 12,
              fontWeight: isTotal ? FontWeight.bold : FontWeight.normal,
              fontFamily: 'monospace',
            ),
          ),
          Text(
            right,
            style: TextStyle(
              color: isTotal ? const Color(0xFF00E676) : Colors.white,
              fontSize: isTotal ? 15 : 12,
              fontWeight: isTotal ? FontWeight.bold : FontWeight.normal,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }

  void _updateOrientations(String tab) {
    if (tab == 'Finished') {
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    } else {
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
      ]);
    }
  }

  @override
  void dispose() {
    _stopVoicePlayback();
    engine.removeListener(_handleEngineStateChange);
    engine.activeTab.removeListener(_handleTabChange);
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
    ]);
    super.dispose();
  }

  String _formatBytes(int bytes) {
    if (bytes <= 0) return "0 MB";
    double mb = bytes / (1024 * 1024);
    if (mb >= 1024) return "${(mb / 1024).toStringAsFixed(1)} GB";
    return "${mb.toStringAsFixed(1)} MB";
  }

  Future<void> _openDefaultAppsSettings() async {
    final List<AndroidIntent> candidateIntents = [
      const AndroidIntent(
        action: 'android.intent.action.MAIN',
        package: 'com.miui.securitycenter',
        componentName: 'com.miui.appmanager.AppManagerMainActivity',
        flags: <int>[Flag.FLAG_ACTIVITY_NEW_TASK],
      ),
      const AndroidIntent(
        action: 'android.settings.MANAGE_DEFAULT_APPS_SETTINGS',
        flags: <int>[Flag.FLAG_ACTIVITY_NEW_TASK],
      ),
      const AndroidIntent(
        action: 'android.settings.MANAGE_APPLICATIONS_SETTINGS',
        flags: <int>[Flag.FLAG_ACTIVITY_NEW_TASK],
      ),
      const AndroidIntent(
        action: 'android.settings.APPLICATION_SETTINGS',
        flags: <int>[Flag.FLAG_ACTIVITY_NEW_TASK],
      ),
      const AndroidIntent(
        action: 'android.settings.SETTINGS',
        flags: <int>[Flag.FLAG_ACTIVITY_NEW_TASK],
      ),
    ];

    for (final intent in candidateIntents) {
      try {
        final bool? canResolve = await intent.canResolveActivity();
        if (canResolve == true) {
          await intent.launch();
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  "ℹ️ ညာဘက်အပေါ်ထောင့် (⋮) > 'Other settings' > 'Default apps' ကို နှိပ်၍ Play video ကို ရွေးပါ",
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                ),
                duration: Duration(seconds: 5),
                backgroundColor: Color(0xFF1E293B),
              ),
            );
          }
          return;
        }
      } catch (_) {}
    }
  }

  Future<void> _showAddUrlDialog() async {
    final textController = TextEditingController();
    try {
      final clipData = await Clipboard.getData(Clipboard.kTextPlain);
      final clipText = clipData?.text?.trim() ?? '';
      if (clipText.startsWith('http')) {
        textController.text = clipText;
      }
    } catch (_) {}

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E232B),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        title: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Row(
              children: [
                Icon(Icons.add_link, color: Color(0xFF00E676), size: 22),
                SizedBox(width: 8),
                Text("Download Link ထည့်ရန်", style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
              ],
            ),
            IconButton(
              onPressed: () => Navigator.pop(ctx),
              icon: const Icon(Icons.close, color: Color(0xFF8B949E), size: 20),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              tooltip: "ပိတ်မည်",
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: textController,
              maxLines: 4,
              minLines: 2,
              style: const TextStyle(color: Colors.white, fontSize: 13),
              decoration: InputDecoration(
                filled: true,
                fillColor: const Color(0xFF0F1824),
                hintText: "http://... download link များ paste ချပါ\n(တစ်ကြောင်းလျှင် link တစ်ခု)",
                hintStyle: const TextStyle(color: Color(0xFF8B949E), fontSize: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: Color(0xFF30363D)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: Color(0xFF00E676)),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () async {
                  final data = await Clipboard.getData(Clipboard.kTextPlain);
                  if (data?.text != null && data!.text!.isNotEmpty) {
                    textController.text = data.text!.trim();
                  }
                },
                icon: const Icon(Icons.content_paste, size: 14, color: Color(0xFF58A6FF)),
                label: const Text("Paste Link", style: TextStyle(color: Color(0xFF58A6FF), fontSize: 12)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              textController.clear();
            },
            child: const Text("ပယ်ဖျက်", style: TextStyle(color: Color(0xFF8B949E))),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("ပိတ်မည်", style: TextStyle(color: Color(0xFF8B949E))),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF238636),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
            ),
            onPressed: () {
              final raw = textController.text.trim();
              if (raw.isNotEmpty) {
                final urls = raw
                    .split(RegExp(r'[\r\n,]+'))
                    .map((e) => e.trim())
                    .where((e) => e.startsWith('http'))
                    .toList();
                if (urls.isNotEmpty) {
                  engine.addUrls(urls);
                  engine.startAllQueued();
                }
              }
              Navigator.pop(ctx);
            },
            child: const Text("ဒေါင်းလုဒ်စမည်", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _showStorageSettingDialog() {
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) {
          return AlertDialog(
            backgroundColor: const Color(0xFF1E232B),
            title: const Row(
              children: [
                Icon(Icons.settings_suggest, color: Color(0xFF58A6FF), size: 22),
                SizedBox(width: 8),
                Text("Settings & Update", style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("ဒေါင်းလုဒ် သိမ်းဆည်းမည့်နေရာ:", style: TextStyle(color: Color(0xFF8B949E), fontSize: 12, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  RadioListTile<String>(
                    value: 'internal',
                    groupValue: engine.storageTarget,
                    activeColor: const Color(0xFF00E676),
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    title: const Text("📱 ဖုန်း Storage (Internal)", style: TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.bold)),
                    subtitle: Text("လက်ကျန်: ${_formatBytes(engine.freeStorageBytes)}", style: const TextStyle(color: Color(0xFF8B949E), fontSize: 11)),
                    onChanged: (val) {
                      if (val != null) {
                        engine.setStorageTarget(val);
                        setModalState(() {});
                        setState(() {});
                      }
                    },
                  ),
                  RadioListTile<String>(
                    value: 'sdcard',
                    groupValue: engine.storageTarget,
                    activeColor: const Color(0xFF00E676),
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    title: Row(
                      children: [
                        const Text("💾 SD ကတ် (Memory Card)", style: TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.bold)),
                        if (!engine.isSdAvailable)
                          const Text(" (မရှိပါ)", style: TextStyle(color: Color(0xFFF85149), fontSize: 11)),
                      ],
                    ),
                    subtitle: Text(
                      engine.isSdAvailable ? "လက်ကျန်: ${_formatBytes(engine.freeSdBytes)}" : "ဖုန်းထဲတွင် SD ကတ် ထည့်မထားပါ",
                      style: TextStyle(color: engine.isSdAvailable ? const Color(0xFF8B949E) : const Color(0xFFF85149), fontSize: 11),
                    ),
                    onChanged: engine.isSdAvailable
                        ? (val) {
                            if (val != null) {
                              engine.setStorageTarget(val);
                              setModalState(() {});
                              setState(() {});
                            }
                          }
                        : null,
                  ),
                  const Divider(color: Color(0xFF30363D), height: 18),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text("App Version", style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                          Text(kAppVersion, style: TextStyle(color: Color(0xFF58A6FF), fontSize: 11)),
                        ],
                      ),
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF238636),
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          minimumSize: Size.zero,
                        ),
                        onPressed: () {
                          Navigator.pop(ctx);
                          MainNavigationScreen.checkLocalServerUpdate(context, isManual: true);
                        },
                        icon: const Icon(Icons.refresh, size: 14, color: Colors.white),
                        label: const Text("Update စစ်မည်", style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
                      )
                    ],
                  ),
                  const Divider(color: Color(0xFF30363D), height: 18),
                  const Text(
                    "Default Apps (Video Player / Browser ရွေးရန်):",
                    style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 3),
                  const Text(
                    "Manage apps > (⋮) Other settings > Default apps သို့ ဖွင့်ရန်:",
                    style: TextStyle(color: Color(0xFF8B949E), fontSize: 11),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF8B5CF6),
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                      ),
                      onPressed: () async {
                        await _openDefaultAppsSettings();
                      },
                      icon: const Icon(Icons.video_settings_rounded, size: 16, color: Colors.white),
                      label: const Text(
                        "Default Apps (Play video / Browser) ရွေးမည်",
                        style: TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                  const Divider(color: Color(0xFF30363D), height: 18),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        "Developer Mode & USB Debugging",
                        style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 3),
                      const Text(
                        "ဖွင့်ရန် အဆင့် (၂) ဆင့်:",
                        style: TextStyle(color: Color(0xFF8B949E), fontSize: 11),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF1F6FEB),
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                                minimumSize: Size.zero,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                              ),
                              onPressed: () async {
                                bool opened = false;
                                try {
                                  const miuiIntent = AndroidIntent(
                                    action: 'android.intent.action.MAIN',
                                    package: 'com.android.settings',
                                    componentName: 'com.android.settings.Settings\$MyDeviceInfoActivity',
                                    flags: <int>[Flag.FLAG_ACTIVITY_NEW_TASK],
                                  );
                                  if (await miuiIntent.canResolveActivity() == true) {
                                    await miuiIntent.launch();
                                    opened = true;
                                  }
                                } catch (_) {}

                                if (!opened) {
                                  try {
                                    const infoIntent = AndroidIntent(
                                      action: 'android.settings.DEVICE_INFO_SETTINGS',
                                      flags: <int>[Flag.FLAG_ACTIVITY_NEW_TASK],
                                    );
                                    await infoIntent.launch();
                                    opened = true;
                                  } catch (_) {}
                                }

                                if (!opened) {
                                  try {
                                    const settingsIntent = AndroidIntent(
                                      action: 'android.settings.SETTINGS',
                                      flags: <int>[Flag.FLAG_ACTIVITY_NEW_TASK],
                                    );
                                    await settingsIntent.launch();
                                  } catch (_) {}
                                }

                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                        "ℹ️ 'My device' > 'Detailed info and specs' ထဲမှ 'OS version' ကို ၇ ချက် နှိပ်ပါ",
                                        textAlign: TextAlign.center,
                                        style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                                      ),
                                      duration: Duration(seconds: 5),
                                      backgroundColor: Color(0xFF1E293B),
                                    ),
                                  );
                                }
                              },
                              icon: const Icon(Icons.phone_android, size: 13, color: Colors.white),
                              label: const Text(
                                "၁။ My device",
                                style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF238636),
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                                minimumSize: Size.zero,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                              ),
                              onPressed: () async {
                                try {
                                  const devIntent = AndroidIntent(
                                    action: 'android.settings.APPLICATION_DEVELOPMENT_SETTINGS',
                                    flags: <int>[Flag.FLAG_ACTIVITY_NEW_TASK],
                                  );
                                  await devIntent.launch();
                                } catch (_) {
                                  const settingsIntent = AndroidIntent(
                                    action: 'android.settings.SETTINGS',
                                    flags: <int>[Flag.FLAG_ACTIVITY_NEW_TASK],
                                  );
                                  await settingsIntent.launch();
                                }

                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                        "⚡ Developer Options ထဲမှ 'USB debugging' ကို On ပေးပါ",
                                        textAlign: TextAlign.center,
                                        style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                                      ),
                                      duration: Duration(seconds: 4),
                                      backgroundColor: Color(0xFF1E293B),
                                    ),
                                  );
                                }
                              },
                              icon: const Icon(Icons.adb_rounded, size: 13, color: Colors.white),
                              label: const Text(
                                "၂။ USB Debug",
                                style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text("ပိတ်မည်", style: TextStyle(color: Color(0xFF8B949E))),
              )
            ],
          );
        },
      ),
    );
  }

  Future<void> _confirmDelete({
    required List<DownloadItem> items,
    required String title,
    required bool isFinishedTab,
  }) async {
    if (isFinishedTab) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: const Color(0xFF1E232B),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          title: Row(
            children: [
              const Icon(Icons.delete_forever, color: Color(0xFFF85149), size: 26),
              const SizedBox(width: 8),
              Text(title, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                items.length == 1
                    ? "'${items.first.name}' ကို ဖုန်းထဲမှ အပြီးတိုင် ဖျက်ရန် သေချာပါသလား?"
                    : "ရွေးချယ်ထားသော (${items.length}) ဖိုင်ကို ဖုန်းထဲမှ အပြီးတိုင် ဖျက်ရန် သေချာပါသလား?",
                style: const TextStyle(color: Color(0xFFC9D1D9), fontSize: 13.5),
              ),
              const SizedBox(height: 8),
              const Text(
                "⚠️ ဖျက်လိုက်ပါက ဖုန်း/SD ကတ်ထဲမှ မူရင်းဗီဒီယိုဖိုင်ပါ တစ်ပါတည်း ပျက်သွားပါမည်။",
                style: TextStyle(color: Color(0xFFF85149), fontSize: 11.5),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text("မဖျက်ပါ", style: TextStyle(color: Color(0xFF8B949E))),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFB91C1C),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              ),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text("အပြီးဖျက်မည်", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      );

      if (confirmed == true) {
        engine.deleteFinishedItems(items, deleteActualFile: true);
        setState(() {});
      }
    } else {
      engine.deleteSelected(items);
      setState(() {});
    }
  }

  // 🌟 ပြင်ပ Player (MX Player / VLC / System) ဖြင့် ဖွင့်ရန် Function
  static Future<void> openInExternalPlayer(BuildContext context, File file) async {
    final bool isApk = file.path.toLowerCase().endsWith('.apk');
    final mimeType = isApk ? 'application/vnd.android.package-archive' : 'video/*';

    try {
      const channel = MethodChannel('com.dataplus/storage');
      await channel.invokeMethod('openFile', {
        'path': file.path,
        'mimeType': mimeType,
      });
    } catch (_) {
      final result = await OpenFilex.open(file.path, type: mimeType);
      if (result.type != ResultType.done && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('⚠️ ${result.message}')));
      }
    }
  }

  // 🌟 ဗီဒီယိုဖိုင်ဖြစ်ပါက DATA PLUS Built-in MX Style Player ဖြင့် ချက်ချင်း တန်းဖွင့်ပေးမည်
  Future<void> _openDownloadedFile(DownloadItem item) async {
    final folder = item.savePath.isNotEmpty ? item.savePath : engine.currentActivePath;
    var file = File('$folder/${item.name}');

    if (!await file.exists()) {
      final altFolder = (folder == DownloadEngine.internalDownloadPath)
          ? '${engine.sdDownloadPath}/Download/.Dataplus'
          : DownloadEngine.internalDownloadPath;
      final altFile = File('$altFolder/${item.name}');
      if (await altFile.exists()) {
        file = altFile;
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('⚠️ ဖုန်းထဲတွင် ဖိုင်မတွေ့ရှိတော့ပါ။')));
        }
        return;
      }
    }

    final bool isApk = item.name.toLowerCase().endsWith('.apk');

    if (isApk) {
      await openInExternalPlayer(context, file);
      return;
    }

    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => DataPlusVideoPlayerScreen(
          file: file,
          title: item.name,
        ),
      ),
    );
    _updateOrientations(currentTab);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: engine,
      builder: (context, _) {
        final qCount = engine.downloads.where((d) => d.status != 'finished').length;
        final fCount = engine.downloads.where((d) => d.status == 'finished').length;

        final currentList = engine.downloads.where((d) =>
          (currentTab == 'Finished' && d.status == 'finished') ||
          (currentTab == 'Queue' && d.status != 'finished')
        ).toList();

        final totalQueueBytes = engine.downloads
            .where((d) => d.status != 'finished')
            .fold(0, (sum, item) => sum + item.sizeBytes);

        final isInternalActive = engine.storageTarget == 'internal';
        final isSdActive = engine.storageTarget == 'sdcard';
        final bool isAnyDownloading = engine.downloads.any((d) => d.status == 'downloading' || engine.isDownloading);

        return Scaffold(
          backgroundColor: const Color(0xFF101317),
          body: SafeArea(
            child: Column(
              children: [
                if (currentTab == 'Queue') ...[
                  Container(
                    margin: const EdgeInsets.fromLTRB(8, 6, 8, 4),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFF16222F),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: engine.isStorageLow ? const Color(0xFFFF4444) : const Color(0xFF2563EB),
                        width: 1.0,
                      ),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: InkWell(
                            onTap: () => engine.setStorageTarget('internal'),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                              decoration: BoxDecoration(
                                color: isInternalActive ? const Color(0xFF1E2F44) : const Color(0xFF0F1824),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: isInternalActive ? const Color(0xFF00E676) : const Color(0xFF2B3A4F)),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      const Row(
                                        children: [
                                          Icon(Icons.phone_android, color: Color(0xFF00E676), size: 13),
                                          SizedBox(width: 3),
                                          Text("ဖုန်း Storage", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 10.5)),
                                        ],
                                      ),
                                      if (isInternalActive)
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                          decoration: BoxDecoration(color: const Color(0xFF00E676), borderRadius: BorderRadius.circular(3)),
                                          child: const Text("သုံးနေ", style: TextStyle(color: Colors.black, fontSize: 8.5, fontWeight: FontWeight.bold)),
                                        )
                                    ],
                                  ),
                                  const SizedBox(height: 2),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(_formatBytes(engine.freeStorageBytes), style: const TextStyle(color: Color(0xFF00E676), fontWeight: FontWeight.bold, fontSize: 12)),
                                      Text("/ ${_formatBytes(engine.totalStorageBytes)}", style: const TextStyle(color: Color(0xFF8B949E), fontSize: 9.5)),
                                    ],
                                  ),
                                  const SizedBox(height: 3),
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(2),
                                    child: LinearProgressIndicator(
                                      value: engine.totalStorageBytes > 0 ? (1.0 - (engine.freeStorageBytes / engine.totalStorageBytes)) : 0.0,
                                      backgroundColor: const Color(0xFF263342),
                                      color: const Color(0xFF00E676),
                                      minHeight: 3.5,
                                    ),
                                  )
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: InkWell(
                            onTap: engine.isSdAvailable ? () => engine.setStorageTarget('sdcard') : null,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                              decoration: BoxDecoration(
                                color: isSdActive ? const Color(0xFF1E2F44) : const Color(0xFF0F1824),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: isSdActive ? const Color(0xFF00E676) : const Color(0xFF2B3A4F)),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      const Row(
                                        children: [
                                          Icon(Icons.sd_card, color: Color(0xFF00E676), size: 13),
                                          SizedBox(width: 3),
                                          Text("SD ကတ်", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 10.5)),
                                        ],
                                      ),
                                      if (isSdActive)
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                          decoration: BoxDecoration(color: const Color(0xFF00E676), borderRadius: BorderRadius.circular(3)),
                                          child: const Text("သုံးနေ", style: TextStyle(color: Colors.black, fontSize: 8.5, fontWeight: FontWeight.bold)),
                                        )
                                    ],
                                  ),
                                  const SizedBox(height: 2),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(engine.isSdAvailable ? _formatBytes(engine.freeSdBytes) : "မရှိပါ", style: const TextStyle(color: Color(0xFF00E676), fontWeight: FontWeight.bold, fontSize: 12)),
                                      Text(engine.isSdAvailable ? "/ ${_formatBytes(engine.totalSdBytes)}" : "", style: const TextStyle(color: Color(0xFF8B949E), fontSize: 9.5)),
                                    ],
                                  ),
                                  const SizedBox(height: 3),
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(2),
                                    child: LinearProgressIndicator(
                                      value: (engine.isSdAvailable && engine.totalSdBytes > 0) ? (1.0 - (engine.freeSdBytes / engine.totalSdBytes)) : 0.0,
                                      backgroundColor: const Color(0xFF263342),
                                      color: const Color(0xFF00E676),
                                      minHeight: 3.5,
                                    ),
                                  )
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFF16222F),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: const Color(0xFF2563EB), width: 0.8),
                    ),
                    child: Row(
                      children: [
                        const Text("ဒေါင်းလုဒ်အစုအဝေးအရွယ်အစား: ", style: TextStyle(color: Color(0xFF8B949E), fontSize: 11.5)),
                        Text(_formatBytes(totalQueueBytes), style: const TextStyle(color: Color(0xFF00E676), fontWeight: FontWeight.bold, fontSize: 12)),
                      ],
                    ),
                  ),
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    child: SizedBox(
                      width: double.infinity,
                      height: 38,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: isAnyDownloading ? const Color(0xFFD97706) : const Color(0xFF238636),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                        ),
                        onPressed: () {
                          if (isAnyDownloading) {
                            engine.pauseAll();
                          } else {
                            engine.startAllQueued();
                          }
                        },
                        icon: Icon(isAnyDownloading ? Icons.pause : Icons.play_arrow, size: 18, color: Colors.white),
                        label: Text(
                          isAnyDownloading ? "ခေတ္တရပ်မည် (Pause All)" : "စတင်ဒေါင်းမည် (Start All)",
                          style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  ),
                ],

                Container(
                  margin: const EdgeInsets.fromLTRB(8, 4, 8, 4),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFF16222F),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: const Color(0xFF2563EB), width: 0.8),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Icon(currentTab == 'Finished' ? Icons.video_library : Icons.hourglass_empty, color: const Color(0xFF58A6FF), size: 16),
                          const SizedBox(width: 6),
                          Text(
                            currentTab == 'Finished' ? "FINISHED (ဗီဒီယိုများ - $fCount)" : "QUEUE (ဆိုင်းငံ့စာရင်း - $qCount)",
                            style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                      Row(
                        children: [
                          OutlinedButton(
                            style: OutlinedButton.styleFrom(
                              side: const BorderSide(color: Color(0xFF2563EB)),
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                              minimumSize: const Size(0, 28),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                            ),
                            onPressed: () {
                              setState(() {
                                final selectVal = !currentList.every((d) => d.isSelected);
                                for (var d in currentList) {
                                  d.isSelected = selectVal;
                                }
                              });
                            },
                            child: const Text("Select All", style: TextStyle(color: Color(0xFF58A6FF), fontSize: 11)),
                          ),
                          const SizedBox(width: 8),
                          IconButton(
                            onPressed: () {
                              final selectedItems = currentList.where((d) => d.isSelected).toList();
                              final itemsToDelete = selectedItems.isNotEmpty ? selectedItems : currentList;
                              if (itemsToDelete.isNotEmpty) {
                                _confirmDelete(
                                  items: itemsToDelete,
                                  title: currentTab == 'Finished' ? "ဗီဒီယိုစာရင်း ရှင်းလင်းမည်" : "ဆိုင်းငံ့စာရင်း ရှင်းလင်းမည်",
                                  isFinishedTab: currentTab == 'Finished',
                                );
                              }
                            },
                            icon: const Icon(Icons.delete_sweep_rounded, color: Color(0xFFF85149), size: 26),
                            tooltip: "Clear All",
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                          ),
                        ],
                      )
                    ],
                  ),
                ),

                Expanded(
                  child: currentList.isEmpty
                      ? Center(
                          child: Text(
                            currentTab == 'Finished' ? "ပြီးဆုံးသွားသော ဇာတ်ကားများ မရှိသေးပါ" : "ဒေါင်းလုဒ်ဆွဲရန် ဖိုင်များ မရှိသေးပါ",
                            style: const TextStyle(color: Color(0xFF8B949E), fontSize: 13),
                          ),
                        )
                      : ListView.builder(
                          itemCount: currentList.length,
                          itemBuilder: (context, index) {
                            final item = currentList[index];
                            final isFinished = currentTab == 'Finished';
                            final bool isApk = item.name.toLowerCase().endsWith('.apk');

                            return Card(
                              color: const Color(0xFF161B22),
                              margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                                side: BorderSide(
                                  color: item.isSelected ? const Color(0xFF238636) : const Color(0xFF2B3A4F),
                                  width: item.isSelected ? 1.5 : 1,
                                ),
                              ),
                              child: InkWell(
                                onTap: isFinished ? () => _openDownloadedFile(item) : null,
                                borderRadius: BorderRadius.circular(8),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          SizedBox(
                                            height: 20,
                                            width: 20,
                                            child: Checkbox(
                                              value: item.isSelected,
                                              activeColor: const Color(0xFF238636),
                                              side: const BorderSide(color: Color(0xFF8B949E)),
                                              onChanged: (val) {
                                                setState(() {
                                                  item.isSelected = val ?? false;
                                                });
                                              },
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          if (isFinished)
                                            Container(
                                              padding: const EdgeInsets.all(6),
                                              decoration: const BoxDecoration(
                                                color: Color(0xFF0D1117),
                                                shape: BoxShape.circle,
                                              ),
                                              child: Icon(
                                                isApk ? Icons.android : Icons.play_arrow,
                                                size: 16,
                                                color: isApk ? const Color(0xFF58A6FF) : const Color(0xFF00E676),
                                              ),
                                            )
                                          else
                                            InkWell(
                                              onTap: () => engine.togglePauseResume(item),
                                              child: Container(
                                                padding: const EdgeInsets.all(4),
                                                decoration: BoxDecoration(
                                                  color: item.status == 'downloading' ? const Color(0xFFD97706) : const Color(0xFF238636),
                                                  shape: BoxShape.circle,
                                                ),
                                                child: Icon(
                                                  item.status == 'downloading' ? Icons.pause : Icons.play_arrow,
                                                  size: 14,
                                                  color: Colors.white,
                                                ),
                                              ),
                                            ),
                                          const SizedBox(width: 10),
                                          Expanded(
                                            child: Text(
                                              item.name,
                                              style: const TextStyle(color: Colors.white, fontSize: 13.5, fontWeight: FontWeight.bold),
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          InkWell(
                                            onTap: () => _confirmDelete(
                                              items: [item],
                                              title: isFinished ? "ဖိုင်ဖျက်ခြင်း" : "စာရင်းဖျက်ခြင်း",
                                              isFinishedTab: isFinished,
                                            ),
                                            child: const Padding(
                                              padding: EdgeInsets.all(4.0),
                                              child: Icon(Icons.delete_outline, color: Color(0xFFF85149), size: 22),
                                            ),
                                          ),
                                        ],
                                      ),
                                      if (!isFinished) ...[
                                        const SizedBox(height: 8),
                                        Row(
                                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                          children: [
                                            Text(_formatBytes(item.sizeBytes), style: const TextStyle(color: Color(0xFF8B949E), fontSize: 11)),
                                            Text("${item.speed} • ${item.eta}", style: const TextStyle(color: Color(0xFF00E676), fontSize: 11, fontWeight: FontWeight.bold)),
                                            Text("${(item.progress * 100).toStringAsFixed(0)}%", style: const TextStyle(color: Color(0xFF8B949E), fontSize: 11)),
                                          ],
                                        ),
                                        const SizedBox(height: 6),
                                        ClipRRect(
                                          borderRadius: BorderRadius.circular(3),
                                          child: LinearProgressIndicator(
                                            value: item.progress,
                                            backgroundColor: const Color(0xFF21262D),
                                            color: const Color(0xFF00E676),
                                            minHeight: 4,
                                          ),
                                        ),
                                      ] else ...[
                                        const SizedBox(height: 4),
                                        Padding(
                                          padding: const EdgeInsets.only(left: 38),
                                          child: Text(_formatBytes(item.sizeBytes), style: const TextStyle(color: Color(0xFF8B949E), fontSize: 11)),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                ),

                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  color: const Color(0xFF16222F),
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.settings_suggest, color: Color(0xFF58A6FF), size: 24),
                        onPressed: _showStorageSettingDialog,
                        tooltip: "Settings",
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Row(
                          children: [
                            Expanded(
                              child: InkWell(
                                onTap: () => engine.activeTab.value = 'Queue',
                                child: Container(
                                  padding: const EdgeInsets.symmetric(vertical: 8),
                                  decoration: BoxDecoration(
                                    color: currentTab == 'Queue' ? const Color(0xFF1F6FEB) : const Color(0xFF0F1824),
                                    borderRadius: BorderRadius.circular(18),
                                    border: Border.all(color: currentTab == 'Queue' ? const Color(0xFF58A6FF) : const Color(0xFF2B3A4F)),
                                  ),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      const Icon(Icons.downloading, size: 16, color: Colors.white),
                                      const SizedBox(width: 6),
                                      Text("Queue ($qCount)", style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            InkWell(
                              onTap: _showAddUrlDialog,
                              borderRadius: BorderRadius.circular(18),
                              child: Container(
                                padding: const EdgeInsets.all(7),
                                decoration: const BoxDecoration(
                                  color: Color(0xFF00E676),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(Icons.add, size: 20, color: Colors.black),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: InkWell(
                                onTap: () => engine.activeTab.value = 'Finished',
                                child: Container(
                                  padding: const EdgeInsets.symmetric(vertical: 8),
                                  decoration: BoxDecoration(
                                    color: currentTab == 'Finished' ? const Color(0xFF238636) : const Color(0xFF0F1824),
                                    borderRadius: BorderRadius.circular(18),
                                    border: Border.all(color: currentTab == 'Finished' ? const Color(0xFF00E676) : const Color(0xFF2B3A4F)),
                                  ),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      const Icon(Icons.check_circle_outline, size: 16, color: Colors.white),
                                      const SizedBox(width: 6),
                                      Text("Finished ($fCount)", style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ============================================================================
// 🎬 DATA PLUS BUILT-IN MX PLAYER STYLE VIDEO PLAYER
// ============================================================================
class DataPlusVideoPlayerScreen extends StatefulWidget {
  final File file;
  final String title;

  const DataPlusVideoPlayerScreen({
    super.key,
    required this.file,
    required this.title,
  });

  static final Map<String, Duration> _savedPositions = {};

  @override
  State<DataPlusVideoPlayerScreen> createState() => _DataPlusVideoPlayerScreenState();
}

class _DataPlusVideoPlayerScreenState extends State<DataPlusVideoPlayerScreen> {
  late VideoPlayerController _controller;
  bool _isInitialized = false;
  bool _hasError = false;
  String _errorText = '';

  bool _showControls = true;
  bool _isLocked = false;
  bool _isLandscape = true;
  Timer? _hideTimer;

  // Aspect Ratio Modes: 0 = Fit, 1 = Stretch (Fill), 2 = Zoom (Cover)
  int _aspectMode = 0;
  double _playbackSpeed = 1.0;

  // Gesture states
  double _volume = 1.0;
  double _brightness = 1.0;
  String? _centerHudText;
  IconData? _centerHudIcon;
  Timer? _hudTimer;

  Duration? _dragSeekTarget;

  @override
  void initState() {
    super.initState();
    _enterFullscreenLandscape();
    _setKeepScreenOn(true);
    _initVideo();
  }

  Future<void> _setKeepScreenOn(bool enable) async {
    try {
      const channel = MethodChannel('com.dataplus/storage');
      await channel.invokeMethod('keepScreenOn', {'enable': enable});
    } catch (_) {}
  }

  void _enterFullscreenLandscape() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
  }

  void _toggleOrientation() {
    setState(() {
      _isLandscape = !_isLandscape;
    });
    if (_isLandscape) {
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    } else {
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
      ]);
    }
    _startHideTimer();
  }

  Future<void> _initVideo() async {
    _controller = VideoPlayerController.file(widget.file);
    try {
      await _controller.initialize();
      final savedPos = DataPlusVideoPlayerScreen._savedPositions[widget.file.path];
      if (savedPos != null && savedPos < _controller.value.duration - const Duration(seconds: 5)) {
        await _controller.seekTo(savedPos);
        _showHud(Icons.restore, "ကြည့်လက်စမှ ပြန်ဖွင့်သည် (${_formatDuration(savedPos)})");
      }
      await _controller.setVolume(_volume);
      await _controller.play();
      _controller.addListener(_onControllerUpdate);

      if (mounted) {
        setState(() {
          _isInitialized = true;
        });
        _startHideTimer();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _hasError = true;
          _errorText = e.toString();
        });
      }
    }
  }

  void _onControllerUpdate() {
    if (!mounted) return;
    if (_controller.value.isInitialized) {
      DataPlusVideoPlayerScreen._savedPositions[widget.file.path] = _controller.value.position;
    }
    setState(() {});
  }

  void _startHideTimer() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 4), () {
      if (mounted && _controller.value.isPlaying) {
        setState(() {
          _showControls = false;
        });
      }
    });
  }

  void _toggleControls() {
    setState(() {
      _showControls = !_showControls;
    });
    if (_showControls) {
      _startHideTimer();
    }
  }

  void _showHud(IconData icon, String text) {
    _hudTimer?.cancel();
    setState(() {
      _centerHudIcon = icon;
      _centerHudText = text;
    });
    _hudTimer = Timer(const Duration(milliseconds: 900), () {
      if (mounted) {
        setState(() {
          _centerHudText = null;
          _centerHudIcon = null;
        });
      }
    });
  }

  void _seekRelative(Duration offset) {
    if (!_isInitialized) return;
    final current = _controller.value.position;
    final total = _controller.value.duration;
    var target = current + offset;
    if (target < Duration.zero) target = Duration.zero;
    if (target > total) target = total;
    _controller.seekTo(target);
    _showHud(
      offset.isNegative ? Icons.replay_10_rounded : Icons.forward_10_rounded,
      "${offset.isNegative ? '-10s' : '+10s'} (${_formatDuration(target)})",
    );
    _startHideTimer();
  }

  void _cycleAspectRatio() {
    setState(() {
      _aspectMode = (_aspectMode + 1) % 3;
    });
    final labels = ['မူရင်းအချိုး (Fit)', 'မျက်နှာပြင်အပြည့် (Stretch)', 'အနားဖြတ်အပြည့် (Zoom)'];
    _showHud(Icons.aspect_ratio_rounded, labels[_aspectMode]);
    _startHideTimer();
  }

  void _cycleSpeed() {
    final speeds = [0.75, 1.0, 1.25, 1.5, 2.0];
    final nextIdx = (speeds.indexOf(_playbackSpeed) + 1) % speeds.length;
    _playbackSpeed = speeds[nextIdx];
    _controller.setPlaybackSpeed(_playbackSpeed);
    _showHud(Icons.speed_rounded, "အမြန်နှုန်း ${_playbackSpeed}x");
    _startHideTimer();
  }

  String _formatDuration(Duration d) {
    final hours = d.inHours;
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    if (hours > 0) {
      return "$hours:$minutes:$seconds";
    }
    return "$minutes:$seconds";
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _hudTimer?.cancel();
    _controller.removeListener(_onControllerUpdate);
    _controller.dispose();
    _setKeepScreenOn(false);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  Widget _buildVideoSurface() {
    final videoWidth = _controller.value.size.width;
    final videoHeight = _controller.value.size.height;

    if (_aspectMode == 1) {
      // Stretch to fill entire screen
      return SizedBox.expand(
        child: FittedBox(
          fit: BoxFit.fill,
          child: SizedBox(
            width: videoWidth,
            height: videoHeight,
            child: VideoPlayer(_controller),
          ),
        ),
      );
    } else if (_aspectMode == 2) {
      // Zoom / Cover
      return SizedBox.expand(
        child: FittedBox(
          fit: BoxFit.cover,
          child: SizedBox(
            width: videoWidth,
            height: videoHeight,
            child: VideoPlayer(_controller),
          ),
        ),
      );
    }

    // Default Fit
    return Center(
      child: AspectRatio(
        aspectRatio: _controller.value.aspectRatio,
        child: VideoPlayer(_controller),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // 1. Video Layer
          if (_isInitialized)
            _buildVideoSurface()
          else if (_hasError)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.error_outline, color: Colors.orangeAccent, size: 48),
                    const SizedBox(height: 12),
                    const Text(
                      "ဤဗီဒီယို Format ကို ပြင်ပ Player ဖြင့် ဖွင့်ရန် လိုအပ်ပါသည်",
                      style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _errorText,
                      style: const TextStyle(color: Colors.white54, fontSize: 11),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1F6FEB)),
                      onPressed: () {
                        _DownloaderScreenState.openInExternalPlayer(context, widget.file);
                      },
                      icon: const Icon(Icons.open_in_new, color: Colors.white),
                      label: const Text("MX / ပြင်ပ Player ဖြင့် ဖွင့်မည်", style: TextStyle(color: Colors.white)),
                    ),
                  ],
                ),
              ),
            )
          else
            const Center(
              child: CircularProgressIndicator(color: Color(0xFF00E676)),
            ),

          // 2. Brightness Dimming Overlay (MX Style)
          if (_brightness < 1.0)
            IgnorePointer(
              child: Container(
                color: Colors.black.withOpacity(((1.0 - _brightness) * 0.82).clamp(0.0, 0.82)),
              ),
            ),

          // 3. MX Player Touch Gesture Layer
          if (_isInitialized)
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _toggleControls,
              onDoubleTapDown: (details) {
                if (_isLocked) return;
                final dx = details.localPosition.dx;
                if (dx < size.width * 0.4) {
                  _seekRelative(const Duration(seconds: -10));
                } else if (dx > size.width * 0.6) {
                  _seekRelative(const Duration(seconds: 10));
                } else {
                  if (_controller.value.isPlaying) {
                    _controller.pause();
                    _showHud(Icons.pause_rounded, "ခေတ္တရပ်ထားသည်");
                  } else {
                    _controller.play();
                    _showHud(Icons.play_arrow_rounded, "ဆက်ဖွင့်နေသည်");
                  }
                }
              },
              onVerticalDragUpdate: (details) {
                if (_isLocked) return;
                final delta = -details.primaryDelta! / (size.height * 0.65);
                final isLeftSide = details.localPosition.dx < size.width / 2;
                if (isLeftSide) {
                  _brightness = (_brightness + delta).clamp(0.05, 1.0);
                  _showHud(Icons.brightness_6_rounded, "အလင်းအမှောင်: ${(_brightness * 100).round()}%");
                } else {
                  _volume = (_volume + delta).clamp(0.0, 1.0);
                  _controller.setVolume(_volume);
                  _showHud(
                    _volume == 0 ? Icons.volume_off_rounded : Icons.volume_up_rounded,
                    "အသံ: ${(_volume * 100).round()}%",
                  );
                }
              },
              onHorizontalDragStart: (_) {
                if (_isLocked) return;
                _dragSeekTarget = _controller.value.position;
              },
              onHorizontalDragUpdate: (details) {
                if (_isLocked || _dragSeekTarget == null) return;
                final totalSec = _controller.value.duration.inSeconds;
                final seekDeltaSec = (details.primaryDelta! / size.width) * (totalSec > 600 ? 180 : 90);
                final nextMillis = (_dragSeekTarget!.inMilliseconds + (seekDeltaSec * 1000).round())
                    .clamp(0, _controller.value.duration.inMilliseconds);
                _dragSeekTarget = Duration(milliseconds: nextMillis);
                _showHud(
                  Icons.fast_forward_rounded,
                  "${_formatDuration(_dragSeekTarget!)} / ${_formatDuration(_controller.value.duration)}",
                );
              },
              onHorizontalDragEnd: (_) {
                if (_isLocked || _dragSeekTarget == null) return;
                _controller.seekTo(_dragSeekTarget!);
                _dragSeekTarget = null;
                _startHideTimer();
              },
              child: const SizedBox.expand(),
            ),

          // 4. Center HUD Indicator (Volume / Brightness / Seek)
          if (_centerHudText != null)
            Center(
              child: IgnorePointer(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.75),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.white24),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_centerHudIcon != null)
                        Icon(_centerHudIcon, color: const Color(0xFF00E676), size: 34),
                      const SizedBox(height: 6),
                      Text(
                        _centerHudText!,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          // 5. Locked Mode Floating Unlock Button
          if (_isLocked && _showControls)
            Positioned(
              left: 24,
              top: 24,
              child: SafeArea(
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.black87,
                    side: const BorderSide(color: Color(0xFF00E676), width: 1.5),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
                  ),
                  onPressed: () {
                    setState(() {
                      _isLocked = false;
                    });
                    _showHud(Icons.lock_open_rounded, "သော့ပြန်ဖွင့်ပြီး");
                    _startHideTimer();
                  },
                  icon: const Icon(Icons.lock_outline_rounded, color: Color(0xFF00E676), size: 20),
                  label: const Text("သော့ဖွင့်ရန် နှိပ်ပါ", style: TextStyle(color: Colors.white, fontSize: 12)),
                ),
              ),
            ),

          // 6. Full MX Player Top & Bottom Controls
          if (!_isLocked && _showControls && _isInitialized) ...[
            // Top Bar
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Container(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 16),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.black87, Colors.transparent],
                  ),
                ),
                child: SafeArea(
                  bottom: false,
                  child: Row(
                    children: [
                      IconButton(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          widget.title,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14.5,
                            fontWeight: FontWeight.bold,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      TextButton.icon(
                        onPressed: _cycleSpeed,
                        icon: const Icon(Icons.speed, color: Color(0xFF00E676), size: 18),
                        label: Text(
                          "${_playbackSpeed}x",
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                        ),
                      ),
                      IconButton(
                        onPressed: _toggleOrientation,
                        tooltip: "မျက်နှာပြင် လှည့်မည်",
                        icon: const Icon(Icons.screen_rotation_rounded, color: Colors.white, size: 20),
                      ),
                      TextButton.icon(
                        style: TextButton.styleFrom(
                          backgroundColor: Colors.white12,
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        ),
                        onPressed: () {
                          _controller.pause();
                          _DownloaderScreenState.openInExternalPlayer(context, widget.file);
                        },
                        icon: const Icon(Icons.open_in_new_rounded, color: Color(0xFF58A6FF), size: 15),
                        label: const Text(
                          "MX ဖြင့်ဖွင့်",
                          style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // Bottom Control Bar
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                padding: const EdgeInsets.fromLTRB(14, 16, 14, 10),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [Colors.black87, Colors.transparent],
                  ),
                ),
                child: SafeArea(
                  top: false,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Progress Slider Row
                      Row(
                        children: [
                          Text(
                            _formatDuration(_controller.value.position),
                            style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                          ),
                          Expanded(
                            child: SliderTheme(
                              data: SliderTheme.of(context).copyWith(
                                trackHeight: 3.5,
                                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
                                activeTrackColor: const Color(0xFF00E676),
                                inactiveTrackColor: Colors.white24,
                                thumbColor: const Color(0xFF00E676),
                              ),
                              child: Slider(
                                value: _controller.value.position.inMilliseconds
                                    .toDouble()
                                    .clamp(0.0, _controller.value.duration.inMilliseconds.toDouble().clamp(1.0, double.infinity)),
                                min: 0.0,
                                max: _controller.value.duration.inMilliseconds.toDouble().clamp(1.0, double.infinity),
                                onChanged: (val) {
                                  _controller.seekTo(Duration(milliseconds: val.round()));
                                  _startHideTimer();
                                },
                              ),
                            ),
                          ),
                          Text(
                            _formatDuration(_controller.value.duration),
                            style: const TextStyle(color: Colors.white70, fontSize: 12),
                          ),
                        ],
                      ),

                      // MX Style Action Buttons Row
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          IconButton(
                            onPressed: () {
                              setState(() {
                                _isLocked = true;
                              });
                              _showHud(Icons.lock_rounded, "မျက်နှာပြင် သော့ခတ်ထားသည်");
                            },
                            tooltip: "Lock Screen",
                            icon: const Icon(Icons.lock_open_rounded, color: Colors.white),
                          ),
                          Row(
                            children: [
                              IconButton(
                                onPressed: () => _seekRelative(const Duration(seconds: -10)),
                                icon: const Icon(Icons.replay_10_rounded, color: Colors.white, size: 30),
                              ),
                              const SizedBox(width: 12),
                              InkWell(
                                onTap: () {
                                  if (_controller.value.isPlaying) {
                                    _controller.pause();
                                  } else {
                                    _controller.play();
                                  }
                                  _startHideTimer();
                                },
                                borderRadius: BorderRadius.circular(30),
                                child: Container(
                                  padding: const EdgeInsets.all(10),
                                  decoration: const BoxDecoration(
                                    color: Color(0xFF00E676),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(
                                    _controller.value.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                                    color: Colors.black,
                                    size: 30,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              IconButton(
                                onPressed: () => _seekRelative(const Duration(seconds: 10)),
                                icon: const Icon(Icons.forward_10_rounded, color: Colors.white, size: 30),
                              ),
                            ],
                          ),
                          IconButton(
                            onPressed: _cycleAspectRatio,
                            tooltip: "Aspect Ratio",
                            icon: const Icon(Icons.aspect_ratio_rounded, color: Colors.white),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
