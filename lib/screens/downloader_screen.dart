import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:open_filex/open_filex.dart';
import 'package:android_intent_plus/android_intent.dart';
import 'package:android_intent_plus/flag.dart';
import '../services/download_engine.dart';
import '../main.dart'; 

class DownloaderScreen extends StatefulWidget {
  const DownloaderScreen({super.key});

  @override
  State<DownloaderScreen> createState() => _DownloaderScreenState();
}

class _DownloaderScreenState extends State<DownloaderScreen> {
  final engine = DownloadEngine();
  late String currentTab;

  @override
  void initState() {
    super.initState();
    currentTab = engine.activeTab.value;
    engine.activeTab.addListener(_handleTabChange);
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

  // 🌟 Download Link များ Paste ချနိုင်မည့် Dialog
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
          // 🌟 စာသားများကို Clear လုပ်ပေးမည့် "ပယ်ဖျက်" ခလုတ်
          TextButton(
            onPressed: () {
              textController.clear();
            },
            child: const Text("ပယ်ဖျက်", style: TextStyle(color: Color(0xFF8B949E))),
          ),
          // 🌟 Dialog ကို ပိတ်မည့် "ပိတ်မည်" ခလုတ်
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
            content: Column(
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

                // 🌟 USB Debugging / Xiaomi My Device အဆင့် (၂) ဆင့် ခလုတ်များ
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
                        // ခလုတ် ၁: My device သို့ တိုက်ရိုက်သွားရန် (အပြာရောင်)
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
                              // ၁။ Xiaomi MyDeviceInfoActivity တိုက်ရိုက် စမ်းသပ်ဖွင့်မည်
                              try {
                                const miuiIntent = AndroidIntent(
                                  action: 'android.intent.action.MAIN',
                                  package: 'com.android.settings',
                                  componentName: 'com.android.settings.Settings\$MyDeviceInfoActivity',
                                  flags: <int>[Flag.FLAG_ACTIVITY_NEW_TASK],
                                );
                                await miuiIntent.launch();
                                opened = true;
                              } catch (_) {}

                              // ၂။ Android စံ About Phone ဖွင့်မည်
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

                              // ၃။ Settings ပင်မစာမျက်နှာကို ၁၀၀% မပျက်မကွက် ဖွင့်မည် (ထိပ်ဆုံးတွင် My device အသင့်ရှိသည်)
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

                        // ခလုတ် ၂: USB Debugging တိုက်ရိုက်ဖွင့်ရန် (အစိမ်းရောင်)
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
    bool deleteActualFile = false;
    
    if (isFinishedTab) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
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
                      ? "'${items.first.name}' ကို ဖျက်ရန် သေချာပါသလား?"
                      : "ရွေးချယ်ထားသော (${items.length}) ဖိုင်ကို ဖျက်ရန် သေချာပါသလား?",
                  style: const TextStyle(color: Color(0xFFC9D1D9), fontSize: 13),
                ),
                const SizedBox(height: 12),
                Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFF141A22),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFF30363D)),
                  ),
                  child: CheckboxListTile(
                    value: deleteActualFile,
                    activeColor: const Color(0xFFF85149),
                    dense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                    title: const Text(
                      "With file (ဖိုင်ပါ အပြီးဖျက်မည်)",
                      style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                    ),
                    subtitle: const Text(
                      "အမှန်ခြစ်ပါက ဖုန်း/SD ထဲမှ မူရင်းဖိုင်ပါ အပြီးတိုင် ဖျက်ပစ်ပါမည်",
                      style: TextStyle(color: Color(0xFF8B949E), fontSize: 10.5),
                    ),
                    onChanged: (val) {
                      setDialogState(() {
                        deleteActualFile = val ?? false;
                      });
                    },
                  ),
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
                child: const Text("ဖျက်မည်", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ),
      );

      if (confirmed == true) {
        engine.deleteFinishedItems(items, deleteActualFile: deleteActualFile);
        setState(() {});
      }
    } else {
      engine.deleteSelected(items);
      setState(() {});
    }
  }

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
    final mimeType = isApk ? 'application/vnd.android.package-archive' : 'video/*';

    try {
      const channel = MethodChannel('com.dataplus/storage');
      await channel.invokeMethod('openFile', {
        'path': file.path,
        'mimeType': mimeType,
      });
    } catch (_) {
      final result = await OpenFilex.open(file.path, type: mimeType);
      if (result.type != ResultType.done && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('⚠️ ${result.message}')));
      }
    }
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
                // 1. Queue Tab တွင်သာ Storage Bar ပြသမည်
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

                // 2. Header with Select All & Bin Icon Clear All
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

                // 3. List Items
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

                // 4. Bottom Action Bar (Settings + Queue + [+] + Finished)
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
                            // Queue Tab
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

                            // 🌟 အလယ်ရှိ Link Paste ချနိုင်မည့် (+) Button
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

                            // Finished Tab
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
