import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'screens/web_portal_screen.dart';
import 'screens/downloader_screen.dart';

// 🚀 GitHub Actions မှ ထည့်ပေးလိုက်သော Dynamic Version (ဥပမာ 1.0.55)
const String kAppVersion = String.fromEnvironment('APP_VERSION', defaultValue: '1.0.0');

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (Platform.isAndroid) {
    if (!await Permission.storage.isGranted) {
      await Permission.storage.request();
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

  // 🚀 DownloaderScreen ဘက်က လှမ်းခေါ်နိုင်မည့် Static Method
  static Future<void> checkLocalServerUpdate(BuildContext context, {bool isManual = false}) async {
    try {
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 3);
      final req = await client.getUrl(Uri.parse('http://10.10.10.10:1000/api/app_version'));
      final resp = await req.close();

      if (resp.statusCode == 200) {
        final body = await resp.transform(utf8.decoder).join();
        final data = jsonDecode(body);
        final String serverVersionName = data['version_name'] ?? '';
        final String apkUrl = data['apk_url'] ?? 'http://10.10.10.10:1000/api/download/apk?app=dataplus';
        final String changelog = data['changelog'] ?? 'လုပ်ဆောင်ချက်အသစ်များ ပါဝင်ပါသည်';

        client.close();

        if (serverVersionName.isNotEmpty && serverVersionName != kAppVersion) {
          if (context.mounted) {
            _showUpdateDialog(context, serverVersionName, apkUrl, changelog);
          }
        } else if (isManual && context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('✅ နောက်ဆုံးထွက် ဗားရှင်း ($kAppVersion) ကို အသုံးပြုနေပါသည်'),
              backgroundColor: const Color(0xFF238636),
            ),
          );
        }
      } else {
        client.close();
        if (isManual && context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('⚠️ Server မှ Version အချက်အလက် မရရှိပါ')),
          );
        }
      }
    } catch (_) {
      if (isManual && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('⚠️ Local Server (10.10.10.10) နှင့် မချိတ်ဆက်မိပါ')),
        );
      }
    }
  }

  static void _showUpdateDialog(BuildContext context, String newVersion, String apkUrl, String changelog) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E232B),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Row(
          children: [
            const Icon(Icons.system_update_rounded, color: Color(0xFF00E676), size: 24),
            const SizedBox(width: 8),
            Text("Update အသစ်ရှိပါသည် ($newVersion)", style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("လက်ရှိဗားရှင်း: $kAppVersion", style: const TextStyle(color: Color(0xFF8B949E), fontSize: 12)),
            const SizedBox(height: 6),
            Text("အသစ်ပါဝင်ချက်များ:\n$changelog", style: const TextStyle(color: Color(0xFFC9D1D9), fontSize: 13)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("နောက်မှ", style: TextStyle(color: Color(0xFF8B949E))),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF238636)),
            onPressed: () {
              Navigator.pop(ctx);
              _downloadAndInstallApk(context, apkUrl);
            },
            icon: const Icon(Icons.download, size: 16, color: Colors.white),
            label: const Text("အခုပဲ Update မည်", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          )
        ],
      ),
    );
  }

  static Future<void> _downloadAndInstallApk(BuildContext context, String url) async {
    final progressNotifier = ValueNotifier<double>(0.0);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
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
    );

    try {
      final client = HttpClient();
      final req = await client.getUrl(Uri.parse(url));
      final resp = await req.close();
      final total = resp.contentLength;

      final saveDir = Directory('/storage/emulated/0/Download/DataPlus');
      if (!await saveDir.exists()) {
        await saveDir.create(recursive: true);
      }
      final savePath = '${saveDir.path}/dataplus_update.apk';
      final file = File(savePath);
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

      if (context.mounted) Navigator.pop(context);

      const channel = MethodChannel('com.dataplus/storage');
      await channel.invokeMethod('openFile', {
        'path': savePath,
        'mimeType': 'application/vnd.android.package-archive',
      });
    } catch (e) {
      if (context.mounted) Navigator.pop(context);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Update ဒေါင်းမရပါ: $e')));
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
    Future.delayed(const Duration(milliseconds: 1500), () {
      MainNavigationScreen.checkLocalServerUpdate(context, isManual: false);
    });
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
