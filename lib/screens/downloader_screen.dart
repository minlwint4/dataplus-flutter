import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:open_filex/open_filex.dart';
import '../services/download_engine.dart';

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
  }

  void _handleTabChange() {
    if (mounted) {
      setState(() {
        currentTab = engine.activeTab.value;
      });
    }
  }

  @override
  void dispose() {
    engine.activeTab.removeListener(_handleTabChange);
    super.dispose();
  }

  String _formatBytes(int bytes) {
    if (bytes <= 0) return "0 MB";
    double mb = bytes / (1024 * 1024);
    if (mb >= 1024) return "${(mb / 1024).toStringAsFixed(1)} GB";
    return "${mb.toStringAsFixed(1)} MB";
  }

  // ⚙️ Storage ရွေးချယ်မည့် Setting Dialog
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
                Text("ဒေါင်းလုဒ် သိမ်းဆည်းမည့်နေရာ", style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                RadioListTile<String>(
                  value: 'internal',
                  groupValue: engine.storageTarget,
                  activeColor: const Color(0xFF00E676),
                  title: const Text("📱 ဖုန်း Storage (Internal)", style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
                  subtitle: Text("လက်ကျန်: ${_formatBytes(engine.freeStorageBytes)}", style: const TextStyle(color: Color(0xFF8B949E), fontSize: 11)),
                  onChanged: (val) {
                    if (val != null) {
                      engine.setStorageTarget(val);
                      setModalState(() {});
                      setState(() {});
                      Navigator.pop(ctx);
                    }
                  },
                ),
                RadioListTile<String>(
                  value: 'sdcard',
                  groupValue: engine.storageTarget,
                  activeColor: const Color(0xFF00E676),
                  title: Row(
                    children: [
                      const Text("💾 SD ကတ် (Memory Card)", style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
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
                            Navigator.pop(ctx);
                          }
                        }
                      : null,
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

  Future<void> _openDownloadedFile(DownloadItem item) async {
    final folder = item.savePath.isNotEmpty ? item.savePath : engine.currentActivePath;
    var file = File('$folder/${item.name}');

    if (!await file.exists()) {
      final altFolder = (folder == DownloadEngine.internalDownloadPath) ? '${engine.sdDownloadPath}/DataPlus' : DownloadEngine.internalDownloadPath;
      final altFile = File('$altFolder/${item.name}');
      if (await altFile.exists()) {
        file = altFile;
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('⚠️ ဖိုင်မတွေ့ရှိပါ')));
        }
        return;
      }
    }

    String? type;
    final lower = item.name.toLowerCase();
    if (lower.endsWith('.apk')) {
      type = 'application/vnd.android.package-archive';
    } else if (lower.endsWith('.mp4')) {
      type = 'video/mp4';
    } else if (lower.endsWith('.mkv')) {
      type = 'video/*';
    }

    final result = await OpenFilex.open(file.path, type: type);
    if (result.type != ResultType.done && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('⚠️ ${result.message}')));
    }
  }

  void _showAddLinksDialog() {
    final textController = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E232B),
        title: const Row(
          children: [
            Icon(Icons.add_link, color: Color(0xFF238636), size: 22),
            SizedBox(width: 8),
            Text("Add Download Links", style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
          ],
        ),
        content: SizedBox(
          width: 320,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text("ဒေါင်းလုဒ် Link များ ထည့်သွင်းပါ:", style: TextStyle(color: Color(0xFF8B949E), fontSize: 12)),
                  TextButton.icon(
                    onPressed: () async {
                      final data = await Clipboard.getData('text/plain');
                      if (data?.text != null) {
                        textController.text = data!.text!;
                      }
                    },
                    icon: const Icon(Icons.content_paste, size: 16, color: Color(0xFF58A6FF)),
                    label: const Text("Paste", style: TextStyle(color: Color(0xFF58A6FF), fontSize: 12)),
                  )
                ],
              ),
              TextField(
                controller: textController,
                maxLines: 5,
                style: const TextStyle(color: Colors.white, fontSize: 12),
                decoration: InputDecoration(
                  filled: true,
                  fillColor: const Color(0xFF0D1117),
                  hintText: "ဒီနေရာတွင် Link များကို ကူးထည့်ပါ...",
                  hintStyle: const TextStyle(color: Color(0xFF484F58), fontSize: 12),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFF30363D))),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFF238636))),
                ),
              )
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancel", style: TextStyle(color: Color(0xFF8B949E)))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF238636)),
            onPressed: () {
              final text = textController.text.trim();
              final urls = text.split('\n').map((e) => e.trim()).where((e) => e.startsWith('http')).toList();
              Navigator.pop(ctx);
              if (urls.isNotEmpty) {
                engine.addUrls(urls);
              }
            },
            child: const Text("Queue ထဲ ထည့်မည်", style: TextStyle(color: Colors.white)),
          )
        ],
      ),
    );
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

        final selectedList = currentList.where((d) => d.isSelected).toList();

        final isInternalActive = engine.storageTarget == 'internal';
        final isSdActive = engine.storageTarget == 'sdcard';

        return Scaffold(
          backgroundColor: const Color(0xFF101317),
          body: SafeArea(
            child: Column(
              children: [
                // 💾 ဖုန်း STORAGE နှင့် SD ကတ် (Ultra-Compact Slim Card - အပေါ်ဆုံးမှ တန်းစတင်ပါသည်)
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
                  child: Column(
                    children: [
                      Row(
                        children: [
                          // 📱 ဘယ်ဘက်ကွက်: ဖုန်း Storage
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

                          // 💾 ညာဘက်ကွက်: SD ကတ်
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
                                        Row(
                                          children: [
                                            Icon(Icons.sd_card, color: engine.isSdAvailable ? const Color(0xFF38BDF8) : const Color(0xFF6E7681), size: 13),
                                            const SizedBox(width: 3),
                                            const Text("SD ကတ်", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 10.5)),
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
                                    if (engine.isSdAvailable) ...[
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Text(_formatBytes(engine.freeSdBytes), style: const TextStyle(color: Color(0xFF38BDF8), fontWeight: FontWeight.bold, fontSize: 12)),
                                          Text("/ ${_formatBytes(engine.totalSdBytes)}", style: const TextStyle(color: Color(0xFF8B949E), fontSize: 9.5)),
                                        ],
                                      ),
                                      const SizedBox(height: 3),
                                      ClipRRect(
                                        borderRadius: BorderRadius.circular(2),
                                        child: LinearProgressIndicator(
                                          value: engine.totalSdBytes > 0 ? (1.0 - (engine.freeSdBytes / engine.totalSdBytes)) : 0.0,
                                          backgroundColor: const Color(0xFF263342),
                                          color: const Color(0xFF38BDF8),
                                          minHeight: 3.5,
                                        ),
                                      )
                                    ] else ...[
                                      const Text("မရှိပါ", style: TextStyle(color: Color(0xFF8B949E), fontWeight: FontWeight.bold, fontSize: 12)),
                                      const SizedBox(height: 6),
                                    ]
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),

                      // ဒေါင်းလုဒ် အရွယ်အစား & Warning (Slim Strip)
                      Container(
                        width: double.infinity,
                        margin: const EdgeInsets.only(top: 5),
                        padding: const EdgeInsets.symmetric(vertical: 3, horizontal: 8),
                        decoration: BoxDecoration(
                          color: engine.isStorageLow ? const Color(0xFF2A1215) : const Color(0xFF0E1726),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: engine.isStorageLow ? const Color(0xFFFF4D4D) : const Color(0xFF1E3A8A), width: 0.8),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              "ဒေါင်းလုဒ်အရွယ်အစား: ${_formatBytes(engine.totalQueuedBytes)}",
                              style: TextStyle(
                                color: engine.isStorageLow ? const Color(0xFFFFA1A1) : const Color(0xFF38BDF8),
                                fontWeight: FontWeight.bold,
                                fontSize: 11,
                              ),
                            ),
                            if (engine.isStorageLow)
                              const Text("⚠️ နေရာမလုံလောက်ပါ!", style: TextStyle(color: Color(0xFFFF4D4D), fontWeight: FontWeight.bold, fontSize: 10)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                // 🚀 Queue Start/Pause Banner (Queue ထဲ ဖိုင်ရှိမှသာ ပေါ်မည်)
                if (currentTab == 'Queue' && qCount > 0)
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    child: engine.isDownloading
                        ? ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFD97706),
                              minimumSize: const Size(double.infinity, 38),
                              padding: EdgeInsets.zero,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                            ),
                            onPressed: () => engine.pauseAll(),
                            icon: const Icon(Icons.pause, color: Colors.white, size: 18),
                            label: const Text("⏸️ အားလုံး ခေတ္တရပ်မည်", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                          )
                        : ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: engine.isStorageLow ? const Color(0xFFB91C1C) : const Color(0xFF059669),
                              minimumSize: const Size(double.infinity, 38),
                              padding: EdgeInsets.zero,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                            ),
                            onPressed: () => engine.startAllQueued(),
                            icon: const Icon(Icons.play_arrow, color: Colors.white, size: 20),
                            label: Text(
                              "🚀 စတင်ဒေါင်းမည် ($qCount ဖိုင်)",
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                            ),
                          ),
                  ),

                // 📋 Contextual Action Bar (စာရင်းရှိမှသာ ပေါ်မည့် Select All / Delete အတန်းကျဉ်းလေး)
                if (currentList.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                    color: const Color(0xFF141A22),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          "$currentTab (${currentList.length})",
                          style: const TextStyle(color: Color(0xFF8B949E), fontSize: 11, fontWeight: FontWeight.bold),
                        ),
                        Row(
                          children: [
                            InkWell(
                              onTap: () {
                                final selectAll = selectedList.length != currentList.length;
                                for (var item in currentList) {
                                  item.isSelected = selectAll;
                                }
                                setState(() {});
                              },
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                child: Text(
                                  selectedList.length == currentList.length ? 'None' : 'Select All',
                                  style: const TextStyle(color: Color(0xFF58A6FF), fontSize: 11, fontWeight: FontWeight.bold),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            if (selectedList.isNotEmpty)
                              InkWell(
                                onTap: () => engine.deleteSelected(selectedList),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(color: const Color(0xFFB91C1C), borderRadius: BorderRadius.circular(4)),
                                  child: Text('Delete (${selectedList.length})', style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                                ),
                              )
                            else
                              InkWell(
                                onTap: () => engine.removeAll(currentTab),
                                child: const Padding(
                                  padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  child: Text('Clear All', style: TextStyle(color: Color(0xFFF85149), fontSize: 11, fontWeight: FontWeight.bold)),
                                ),
                              ),
                          ],
                        )
                      ],
                    ),
                  ),

                // 📋 List View (ကျစ်လျစ်သော Slim Padding ဖြင့် ဖိုင်အများအပြား မြင်နိုင်ပါသည်)
                Expanded(
                  child: currentList.isEmpty
                      ? Center(child: Text("No $currentTab items", style: const TextStyle(color: Color(0xFF484F58), fontSize: 13)))
                      : ListView.builder(
                          itemCount: currentList.length,
                          itemBuilder: (context, index) {
                            final item = currentList[index];
                            final isDone = item.status == 'finished';
                            final isDl = item.status == 'downloading';
                            final isPaused = item.status == 'paused';
                            final isApk = item.name.toLowerCase().endsWith('.apk');

                            return InkWell(
                              onTap: isDone ? () => _openDownloadedFile(item) : null,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: const BoxDecoration(
                                  color: Color(0xFF101317),
                                  border: Border(bottom: BorderSide(color: Color(0xFF1E232B), width: 0.6)),
                                ),
                                child: Column(
                                  children: [
                                    Row(
                                      children: [
                                        SizedBox(
                                          width: 24,
                                          height: 24,
                                          child: Checkbox(
                                            value: item.isSelected,
                                            activeColor: const Color(0xFF2563EB),
                                            onChanged: (v) => setState(() => item.isSelected = v ?? false),
                                          ),
                                        ),
                                        const SizedBox(width: 4),
                                        if (isDone)
                                          Icon(isApk ? Icons.android : Icons.check_circle, color: const Color(0xFF00E676), size: 18)
                                        else if (isDl)
                                          InkWell(
                                            onTap: () => engine.togglePauseResume(item),
                                            child: const Icon(Icons.pause_circle_filled, color: Color(0xFFE3B341), size: 20),
                                          )
                                        else if (isPaused)
                                          InkWell(
                                            onTap: () => engine.togglePauseResume(item),
                                            child: const Icon(Icons.play_circle_fill, color: Color(0xFF58A6FF), size: 20),
                                          )
                                        else
                                          const Icon(Icons.access_time, color: Color(0xFF8B949E), size: 18),
                                        const SizedBox(width: 6),
                                        Expanded(
                                          child: Text(item.name, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 12.5)),
                                        ),
                                        if (isDone)
                                          ElevatedButton.icon(
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor: isApk ? const Color(0xFF1E40AF) : const Color(0xFF047857),
                                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                              minimumSize: Size.zero,
                                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                            ),
                                            onPressed: () => _openDownloadedFile(item),
                                            icon: Icon(isApk ? Icons.system_update : Icons.play_arrow, size: 13, color: Colors.white),
                                            label: Text(isApk ? "သွင်းမည်" : "ဖွင့်မည်", style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                                          ),
                                        InkWell(
                                          onTap: () => engine.deleteItem(item),
                                          child: const Padding(
                                            padding: EdgeInsets.all(4.0),
                                            child: Icon(Icons.close, color: Color(0xFF8B949E), size: 16),
                                          ),
                                        )
                                      ],
                                    ),
                                    Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      child: Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Text(_formatBytes(item.sizeBytes), style: const TextStyle(color: Color(0xFF8B949E), fontSize: 10.5)),
                                          Text(
                                            item.status == 'queued' ? "စောင့်ဆိုင်းနေသည်" : "${item.speed}  •  ${item.eta}",
                                            style: TextStyle(
                                              color: isPaused
                                                  ? const Color(0xFFE3B341)
                                                  : (item.status == 'queued' ? const Color(0xFF58A6FF) : const Color(0xFF00E676)),
                                              fontWeight: FontWeight.bold,
                                              fontSize: 11,
                                            ),
                                          ),
                                          Text(item.date, style: const TextStyle(color: Color(0xFF6E7681), fontSize: 10)),
                                        ],
                                      ),
                                    ),
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(2),
                                      child: LinearProgressIndicator(
                                        value: item.progress,
                                        backgroundColor: const Color(0xFF1E232B),
                                        color: isPaused ? const Color(0xFFE3B341) : const Color(0xFF00E676),
                                        minHeight: 4,
                                      ),
                                    )
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                ),

                // 🔻 ADM Bottom Bar (Power ➔ Settings ➔ Add ➔ Queue ➔ Finished)
                Container(
                  color: const Color(0xFF1E232B),
                  padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 12),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      // 1. Power (Exit)
                      IconButton(
                        icon: const Icon(Icons.power_settings_new, color: Color(0xFFF85149), size: 21),
                        tooltip: "Exit",
                        onPressed: () => SystemNavigator.pop(),
                      ),
                      // 2. ⚙️ Settings (Power နှင့် + ကြားထဲ ထည့်သွင်းထားပါသည်)
                      IconButton(
                        icon: const Icon(Icons.settings, color: Color(0xFF58A6FF), size: 21),
                        tooltip: "Storage Settings",
                        onPressed: _showStorageSettingDialog,
                      ),
                      // 3. ➕ Add Links
                      IconButton(
                        icon: Container(
                          padding: const EdgeInsets.all(5),
                          decoration: const BoxDecoration(color: Color(0xFF238636), shape: BoxShape.circle),
                          child: const Icon(Icons.add, color: Colors.white, size: 19),
                        ),
                        onPressed: _showAddLinksDialog,
                      ),
                      // 4. Queue Tab
                      InkWell(
                        onTap: () => setState(() => currentTab = 'Queue'),
                        child: Row(
                          children: [
                            Icon(Icons.access_time, color: currentTab == 'Queue' ? const Color(0xFF58A6FF) : const Color(0xFF8B949E), size: 17),
                            const SizedBox(width: 4),
                            Text("Queue", style: TextStyle(color: currentTab == 'Queue' ? const Color(0xFF58A6FF) : const Color(0xFF8B949E), fontWeight: FontWeight.bold, fontSize: 12)),
                            const SizedBox(width: 4),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                              decoration: BoxDecoration(color: qCount > 0 ? const Color(0xFF2563EB) : const Color(0xFF2A3441), borderRadius: BorderRadius.circular(8)),
                              child: Text("$qCount", style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                            )
                          ],
                        ),
                      ),
                      // 5. Finished Tab
                      InkWell(
                        onTap: () => setState(() => currentTab = 'Finished'),
                        child: Row(
                          children: [
                            Icon(Icons.check_circle, color: currentTab == 'Finished' ? const Color(0xFF00E676) : const Color(0xFF8B949E), size: 17),
                            const SizedBox(width: 4),
                            Text("Finished", style: TextStyle(color: currentTab == 'Finished' ? const Color(0xFF00E676) : const Color(0xFF8B949E), fontWeight: FontWeight.bold, fontSize: 12)),
                            const SizedBox(width: 4),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                              decoration: BoxDecoration(color: fCount > 0 ? const Color(0xFF238636) : const Color(0xFF2A3441), borderRadius: BorderRadius.circular(8)),
                              child: Text("$fCount", style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                            )
                          ],
                        ),
                      ),
                    ],
                  ),
                )
              ],
            ),
          ),
        );
      },
    );
  }
}
