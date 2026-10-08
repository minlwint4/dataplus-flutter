import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:open_filex/open_filex.dart';
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

  // 🌟 Tab အလိုက် Screen Rotation ကို ထိန်းချုပ်ခြင်း
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

    final lower = item.name.toLowerCase();
    String mimeType = '*/*';
    
    if (lower.endsWith('.apk')) {
      mimeType = 'application/vnd.android.package-archive';
    } else if (lower.endsWith('.mp4') || lower.endsWith('.mkv') || lower.endsWith('.avi')) {
      mimeType = 'video/*';
    } else if (lower.endsWith('.jpg') || lower.endsWith('.png') || lower.endsWith('.jpeg')) {
      mimeType = 'image/*';
    } else if (lower.endsWith('.mp3') || lower.endsWith('.m4a') || lower.endsWith('.wav')) {
      mimeType = 'audio/*';
    }

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

        final isInternalActive = engine.storageTarget == 'internal';
        final isSdActive = engine.storageTarget == 'sdcard';

        return Scaffold(
          backgroundColor: const Color(0xFF101317),
          body: SafeArea(
            child: Column(
              children: [
                // Storage Bar
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

                // Tabs Header
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: currentTab == 'Queue' ? const Color(0xFF1F6FEB) : const Color(0xFF161B22),
                            foregroundColor: Colors.white,
                            minimumSize: const Size.fromHeight(34),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                          ),
                          onPressed: () => engine.activeTab.value = 'Queue',
                          icon: const Icon(Icons.downloading, size: 16),
                          label: Text("Queue ($qCount)", style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: currentTab == 'Finished' ? const Color(0xFF238636) : const Color(0xFF161B22),
                            foregroundColor: Colors.white,
                            minimumSize: const Size.fromHeight(34),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                          ),
                          onPressed: () => engine.activeTab.value = 'Finished',
                          icon: const Icon(Icons.check_circle_outline, size: 16),
                          label: Text("Finished ($fCount)", style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                        ),
                      ),
                    ],
                  ),
                ),

                // List Items with Full Action Buttons
                Expanded(
                  child: currentList.isEmpty
                      ? Center(
                          child: Text(
                            currentTab == 'Finished' ? "ပြီးဆုံးသွားသော ဖိုင်များ မရှိသေးပါ" : "ဒေါင်းလုဒ်ဆွဲရန် ဖိုင်များ မရှိသေးပါ",
                            style: const TextStyle(color: Color(0xFF8B949E), fontSize: 13),
                          ),
                        )
                      : ListView.builder(
                          itemCount: currentList.length,
                          itemBuilder: (context, index) {
                            final item = currentList[index];
                            return Card(
                              color: const Color(0xFF161B22),
                              margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              child: Padding(
                                padding: const EdgeInsets.all(8.0),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Checkbox(
                                          value: item.isSelected,
                                          activeColor: const Color(0xFF238636),
                                          onChanged: (val) {
                                            item.isSelected = val ?? false;
                                            setState(() {});
                                          },
                                        ),
                                        Expanded(
                                          child: Text(
                                            item.name,
                                            style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        if (item.status == 'finished')
                                          IconButton(
                                            icon: const Icon(Icons.play_circle_fill, color: Color(0xFF00E676), size: 26),
                                            onPressed: () => _openDownloadedFile(item),
                                            tooltip: "ဖွင့်မည်",
                                          ),
                                        IconButton(
                                          icon: const Icon(Icons.delete_outline, color: Color(0xFFF85149), size: 20),
                                          onPressed: () {
                                            engine.deleteFinishedItems([item], deleteActualFile: false);
                                            setState(() {});
                                          },
                                          tooltip: "ဖျက်မည်",
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(
                                          item.status == 'finished' ? "ဒေါင်းလုဒ်ပြီးပါပြီ" : "ဒေါင်းလုဒ်ဆွဲနေသည်... (${(item.progress * 100).toStringAsFixed(0)}%)",
                                          style: TextStyle(color: item.status == 'finished' ? const Color(0xFF00E676) : const Color(0xFF58A6FF), fontSize: 11),
                                        ),
                                        Text(_formatBytes(item.totalBytes), style: const TextStyle(color: Color(0xFF8B949E), fontSize: 11)),
                                      ],
                                    ),
                                    if (item.status != 'finished') ...[
                                      const SizedBox(height: 6),
                                      LinearProgressIndicator(
                                        value: item.progress,
                                        backgroundColor: const Color(0xFF21262D),
                                        color: const Color(0xFF58A6FF),
                                        minHeight: 4,
                                      ),
                                    ]
                                  ],
                                ),
                              ),
                            );
                          },
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