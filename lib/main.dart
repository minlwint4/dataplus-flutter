import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'screens/web_portal_screen.dart';
import 'screens/downloader_screen.dart';

const String kAppVersion = String.fromEnvironment('APP_VERSION', defaultValue: '1.0.0');

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (Platform.isAndroid) {
    if (!await Permission.storage.isGranted) {
      await Permission.storage.request();
    }
    if (!await Permission.manageExternalStorage.isGranted) {
      await Permission.manageExternalStorage.request();
    }
  }
  runApp(const DataPlusApp());
}

class DataPlusApp extends StatelessWidget {
  const DataPlusApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'DATA_PLUS',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF0A0A0A),
      ),
      home: const MainNavigationScreen(),
    );
  }
}

class MainNavigationScreen extends StatefulWidget {
  const MainNavigationScreen({super.key});

  static Future<void> checkLocalServerUpdate(BuildContext context, {bool isManual = false}) async {
    final possibleIps = ['192.168.1.50', '10.10.10.10', 'localhost'];
    
    for (var ip in possibleIps) {
      HttpClient? client;
      try {
        client = HttpClient();
        client.connectionTimeout = const Duration(seconds: 1);
        
        final req = await client.getUrl(Uri.parse('http://$ip:1000/api/app_version'));
        final resp = await req.close();

        if (resp.statusCode == 200) {
          final body = await resp.transform(utf8.decoder).join();
          final data = jsonDecode(body);
          
          final String serverVersionName = data['version_name'] ?? '1.0.0';
          final dynamic rawCode = data['version_code'] ?? 999;
          final int serverVersionCode = rawCode is int ? rawCode : int.tryParse(rawCode.toString()) ?? 999;
          
          final String apkUrl = 'http://$ip:1000/api/download/apk?app=dataplus';
          final String changelog = data['changelog'] ?? 'လုပ်ဆောင်ချက်အသစ်များ ပါဝင်ပါသည်';

          client.close();

          int currentVersionCode = 1;
          try {
            final parts = kAppVersion.split('.');
            if (parts.length >= 3) {
              currentVersionCode = int.parse(parts.last);
            }
          } catch (_) {}

          if (serverVersionCode > currentVersionCode) {
            if (context.mounted) {
              _showUpdateDialog(context, serverVersionName, apkUrl, changelog);
            }
          } else if (isManual && context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('✅ နောက်ဆုံးထွက် ဗားရှင်း ($kAppVersion) ကို အသုံးပြုနေပါသည် ($ip)'),
                backgroundColor: const Color(0xFF238636),
              ),
            );
          }
          return;
        }
        client.close();
      } catch (_) {
        try { client?.close(); } catch (_) {}
      }
    }

    if (isManual && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('⚠️ Server သို့ ချိတ်ဆက်၍မရပါ (192.168.1.50 နှင့် 10.10.10.10 ကို စစ်ဆေးပါ)')),
      );
    }
  }

  static void _showUpdateDialog(BuildContext context, String newVersion, String apkUrl, String changelog) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => PopScope(
        canPop: false,
        child: AlertDialog(
          backgroundColor: const Color(0xFF1E232B),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          title: Row(
            children: [
              const Icon(Icons.system_update_rounded, color: Color(0xFF00E676), size: 24),
              const SizedBox(width: 8),
              Text("ဗားရှင်းအသစ် လိုအပ်ပါသည် ($newVersion)", style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("လက်ရှိဗားရှင်း: $kAppVersion", style: const TextStyle(color: Color(0xFF8B949E), fontSize: 12)),
              const SizedBox(height: 6),
              Text("အသစ်ပါဝင်ချက်များ:\n$changelog", style: const TextStyle(color: Color(0xFFC9D1D9), fontSize: 13)),
              const SizedBox(height: 10),
              const Text("ဆက်လက်အသုံးပြုရန် ဗားရှင်းအသစ်သို့ မဖြစ်မနေ အပ်ဒိတ်လုပ်ရန် လိုအပ်ပါသည်။", style: TextStyle(color: Color(0xFFFF4444), fontSize: 11.5, fontWeight: FontWeight.bold)),
            ],
          ),
          actions: [
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF238636),
                minimumSize: const Size(double.infinity, 38),
              ),
              onPressed: () {
                Navigator.pop(ctx);
                _downloadAndInstallApk(context, apkUrl);
              },
              icon: const Icon(Icons.download, size: 16, color: Colors.white),
              label: const Text("အခုပဲ Update မည်", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            )
          ],
        ),
      ),
    );
  }

  static Future<void> _downloadAndInstallApk(BuildContext context, String initialUrl) async {
    final progressNotifier = ValueNotifier<double>(0.0);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => PopScope(
        canPop: false,
        child: AlertDialog(
          backgroundColor: const Color(0xFF1E232B),
          title: const Text("Update APK ဒေါင်းလုဒ်ဆွဲနေသည်...", style: TextStyle(color: Colors.white, fontSize: 14)),
          content: ValueListenableBuilder<double>(
            valueListenable: progressNotifier,
            builder: (context, val, _) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  LinearProgressIndicator(value: val > 0 ? val : null, color: const Color(0xFF00E676)),
                  const SizedBox(height: 10),
                  Text("${(val * 100).toStringAsFixed(0)}%", style: const TextStyle(color: Color(0xFF00E676), fontWeight: FontWeight.bold)),
                ],
              );
            },
          ),
        ),
      ),
    );

    final candidateUrls = <String>[];
    try {
      final uri = Uri.parse(initialUrl);
      candidateUrls.add('http://10.10.10.10:1000${uri.path}${uri.hasQuery ? '?${uri.query}' : ''}');
      candidateUrls.add('http://192.168.1.50:1000${uri.path}${uri.hasQuery ? '?${uri.query}' : ''}');
      candidateUrls.add(initialUrl);
    } catch (_) {
      candidateUrls.add(initialUrl);
    }

    bool success = false;
    final saveDir = Directory('/storage/emulated/0/Download/.Dataplus');
    if (!await saveDir.exists()) {
      await saveDir.create(recursive: true);
    }
    final savePath = '${saveDir.path}/dataplus_update.apk';
    final file = File(savePath);

    for (var url in candidateUrls) {
      HttpClient? client;
      try {
        if (await file.exists()) {
          try { await file.delete(); } catch (_) {}
        }

        client = HttpClient();
        client.connectionTimeout = const Duration(seconds: 3);
        
        final req = await client.getUrl(Uri.parse(url));
        final resp = await req.close();

        if (resp.statusCode == 200) {
          final total = resp.contentLength;
          final sink = file.openWrite();

          int downloaded = 0;
          await for (var chunk in resp) {
            sink.add(chunk);
            downloaded += chunk.length;
            if (total > 0) {
              progressNotifier.value = downloaded / total;
            }
          }
          await sink.flush();
          await sink.close();
          client.close();
          success = true;
          break;
        }
        client.close();
      } catch (_) {
        try { client?.close(); } catch (_) {}
      }
    }

    if (context.mounted) Navigator.pop(context);

    if (success) {
      await Future.delayed(const Duration(milliseconds: 600));
      const channel = MethodChannel('com.dataplus/storage');
      await channel.invokeMethod('openFile', {
        'path': savePath,
        'mimeType': 'application/vnd.android.package-archive',
      });
    } else {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('⚠️ Update ဖိုင် ဒေါင်းလုဒ်ဆွဲ၍မရပါ (Network လိုင်းကို စစ်ဆေးပါ)')),
        );
      }
    }
  }

  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen> {
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    // 🌟 App စတက်လာတာနဲ့ Persistent Device ID ဖြင့် Server နှင့် အလိုအလျောက် Sync ပြုလုပ်မည်
    _syncPersistentUser();

    Future.delayed(const Duration(milliseconds: 1500), () {
      MainNavigationScreen.checkLocalServerUpdate(context, isManual: false);
    });
  }

  // 🌟 App ကို Uninstall/Reinstall လုပ်လည်း လုံးဝမပြောင်းလဲမည့် Persistent Device ID ဆွဲယူခြင်း
  Future<String> _getPersistentDeviceId(SharedPreferences prefs) async {
    String? deviceId = prefs.getString('device_id');

    final backupDir = Directory('/storage/emulated/0/Download/.Dataplus');
    final backupFile = File('${backupDir.path}/.device_id');

    try {
      if (deviceId == null || deviceId.isEmpty) {
        if (await backupFile.exists()) {
          final content = (await backupFile.readAsString()).trim();
          if (content.isNotEmpty) {
            deviceId = content;
            await prefs.setString('device_id', deviceId);
          }
        }
      }
    } catch (_) {}

    // ပထမဆုံးအကြိမ် ဖြစ်ပါက Hardware Time အခြေပြု Unique ID ထုတ်မည်
    if (deviceId == null || deviceId.isEmpty) {
      final rand = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
      deviceId = 'dp_${rand}_${DateTime.now().millisecond}';
      await prefs.setString('device_id', deviceId);
    }

    // Storage ထဲရှိ .device_id ဖိုင်ထဲ အမြဲတမ်း Mirror သိမ်းဆည်းထားမည်
    try {
      if (!await backupDir.exists()) {
        await backupDir.create(recursive: true);
      }
      await backupFile.writeAsString(deviceId);
    } catch (_) {}

    return deviceId;
  }

  // 🌟 Server ပေါ်ရှိ devices.json နှင့် အလိုအလျောက် Sync လုပ်ပြီး Last Update အမည် ရယူခြင်း
  Future<void> _syncPersistentUser() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final deviceId = await _getPersistentDeviceId(prefs);
      final localName = prefs.getString('customer_name') ?? '';

      final possibleIps = ['10.10.10.10', '192.168.1.50', 'localhost'];
      for (var ip in possibleIps) {
        HttpClient? client;
        try {
          client = HttpClient();
          client.connectionTimeout = const Duration(seconds: 1);
          final req = await client.postUrl(Uri.parse('http://$ip:1000/api/user/sync_device'));
          req.headers.set('Content-Type', 'application/json');
          req.add(utf8.encode(jsonEncode({
            'device_id': deviceId,
            'name': localName,
          })));
          final resp = await req.close();

          if (resp.statusCode == 200) {
            final body = await resp.transform(utf8.decoder).join();
            final data = jsonDecode(body);
            // Server က ပြန်ပို့ပေးသော နောက်ဆုံးအမည် (Last Update Name) အတိုင်း App တွင် သိမ်းခြင်း
            if (data['success'] == true && data['name'] != null) {
              final String serverName = data['name'].toString().trim();
              if (serverName.isNotEmpty) {
                await prefs.setString('customer_name', serverName);
              }
            }
            client.close();
            break;
          }
          client.close();
        } catch (_) {
          try { client?.close(); } catch (_) {}
        }
      }
    } catch (_) {}
  }

  Widget _buildSlimTabItem({
    required int index,
    required IconData icon,
    required String label,
  }) {
    final isSelected = _currentIndex == index;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _currentIndex = index),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 6),
          decoration: BoxDecoration(
            color: isSelected ? const Color(0xFF238636).withOpacity(0.25) : Colors.transparent,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isSelected ? const Color(0xFF238636) : Colors.transparent,
              width: 1,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 15,
                color: isSelected ? const Color(0xFF00E676) : const Color(0xFF8B949E),
              ),
              const SizedBox(width: 5),
              Flexible(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    color: isSelected ? Colors.white : const Color(0xFF8B949E),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: [
          WebPortalScreen(onTabChangeRequested: (index) => setState(() => _currentIndex = index)),
          const DownloaderScreen(),
        ],
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Container(
          height: 42,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
          decoration: const BoxDecoration(
            color: Color(0xFF141920),
            border: Border(top: BorderSide(color: Color(0xFF21262D), width: 0.8)),
          ),
          child: Row(
            children: [
              _buildSlimTabItem(index: 0, icon: Icons.movie_creation_outlined, label: 'DATA PLUS ($kAppVersion)'),
              const SizedBox(width: 8),
              _buildSlimTabItem(index: 1, icon: Icons.download_rounded, label: 'Downloader'),
            ],
          ),
        ),
      ),
    );
  }
}
