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
  final DownloadEngine _engine = DownloadEngine();

  @override
  void initState() {
    super.initState();
    _engine.updateStorageInfo();
  }

  // 🌟 Link Paste ချပြီး ဒေါင်းလုဒ်ထည့်မည့် Dialog Window
  Future<void> _showAddUrlDialog(BuildContext context) async {
    final textController = TextEditingController();

    // Clipboard ထဲတွင် Link ရှိနေပါက အလိုအလျောက် ဖြည့်သွင်းပေးခြင်း
    try {
      final clipData = await Clipboard.getData(Clipboard.kTextPlain);
      final clipText = clipData?.text?.trim() ?? '';
      if (clipText.startsWith('http')) {
        textController.text = clipText;
      }
    } catch (_) {}

    if (!context.mounted) return;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF161B22),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Color(0xFF30363D)),
        ),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: const Color(0xFF00E676).withOpacity(0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.add_link_rounded, color: Color(0xFF00E676), size: 22),
            ),
            const SizedBox(width: 10),
            const Text(
              "Download Link ထည့်ရန်",
              style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
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
                fillColor: const Color(0xFF0D1117),
                hintText: "http://... download link များ paste ချပါ\n(တစ်ကြောင်းလျှင် link တစ်ခု)",
                hintStyle: const TextStyle(color: Color(0xFF484F58), fontSize: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: Color(0xFF30363D)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: Color(0xFF00E676)),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () async {
                  final data = await Clipboard.getData(Clipboard.kTextPlain);
                  if (data?.text != null && data!.text!.isNotEmpty) {
                    textController.text = data.text!.trim();
                  }
                },
                icon: const Icon(Icons.content_paste_rounded, size: 15, color: Color(0xFF38BDF8)),
                label: const Text(
                  "Paste Link",
                  style: TextStyle(color: Color(0xFF38BDF8), fontSize: 12, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("ပယ်ဖျက်", style: TextStyle(color: Color(0xFF8B949E))),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF238636),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
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
                  _engine.addUrls(urls);
                  _engine.startAllQueued();
                }
              }
              Navigator.pop(ctx);
            },
            child: const Text(
              "ဒေါင်းလုဒ်စမည်",
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  void _openFile(DownloadItem item) async {
    final folder = item.savePath.isNotEmpty ? item.savePath : _engine.currentActivePath;
    final filePath = '$folder/${item.name}';
    final file = File(filePath);

    if (await file.exists()) {
      await OpenFilex.open(filePath);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('⚠️ ဖိုင်ရှာမတွေ့ပါ သို့မဟုတ် ဖျက်လိုက်ပြီးဖြစ်သည်')),
        );
      }
    }
  }

  String _formatBytes(int bytes) {
    if (bytes <= 0) return '0 B';
    const suffixes = ['B', 'KB', 'MB', 'GB', 'TB'];
    int i = (bytes.bitLength - 1) ~/ 10;
    if (i >= suffixes.length) i = suffixes.length - 1;
    double size = bytes / (1 << (i * 10));
    return '${size.toStringAsFixed(1)} ${suffixes[i]}';
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _engine,
      builder: (context, _) {
        final currentTab = _engine.activeTab.value;
        final filteredList = _engine.downloads.where((d) {
          if (currentTab == 'Finished') return d.status == 'finished';
          return d.status != 'finished';
        }).toList();

        final queueCount = _engine.downloads.where((d) => d.status != 'finished').length;
        final finishedCount = _engine.downloads.where((d) => d.status == 'finished').length;

        final activeFreeBytes = (_engine.storageTarget == 'sdcard' && _engine.isSdAvailable)
            ? _engine.freeSdBytes
            : _engine.freeStorageBytes;

        return Scaffold(
          backgroundColor: const Color(0xFF0A0A0A),
          appBar: AppBar(
            backgroundColor: const Color(0xFF141920),
            elevation: 0,
            title: Row(
              children: [
                const Icon(Icons.downloading_rounded, color: Color(0xFF00E676), size: 22),
                const SizedBox(width: 8),
                const Text(
                  "Downloader",
                  style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                // Storage Free Badge
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF21262D),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFF30363D)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _engine.storageTarget == 'sdcard' ? Icons.sd_card_outlined : Icons.phone_android_rounded,
                        size: 13,
                        color: const Color(0xFF38BDF8),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        "${_formatBytes(activeFreeBytes)} ကျန်",
                        style: const TextStyle(color: Color(0xFF38BDF8), fontSize: 11, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          body: Column(
            children: [
              // 📑 Tab Selector (Queue / Finished) & Top Action Controls
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: const BoxDecoration(
                  color: Color(0xFF101317),
                  border: Border(bottom: BorderSide(color: Color(0xFF21262D), width: 0.8)),
                ),
                child: Row(
                  children: [
                    // Queue Tab Button
                    GestureDetector(
                      onTap: () {
                        _engine.activeTab.value = 'Queue';
                        setState(() {});
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                        decoration: BoxDecoration(
                          color: currentTab == 'Queue' ? const Color(0xFF238636) : const Color(0xFF1E232B),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          "Queue ($queueCount)",
                          style: TextStyle(
                            color: currentTab == 'Queue' ? Colors.white : const Color(0xFF8B949E),
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Finished Tab Button
                    GestureDetector(
                      onTap: () {
                        _engine.activeTab.value = 'Finished';
                        setState(() {});
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                        decoration: BoxDecoration(
                          color: currentTab == 'Finished' ? const Color(0xFF238636) : const Color(0xFF1E232B),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          "Finished ($finishedCount)",
                          style: TextStyle(
                            color: currentTab == 'Finished' ? Colors.white : const Color(0xFF8B949E),
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                    const Spacer(),

                    // Action Controls (Start / Pause / Delete All)
                    if (currentTab == 'Queue' && queueCount > 0) ...[
                      IconButton(
                        tooltip: "အားလုံး စတင်မည်",
                        icon: const Icon(Icons.play_arrow_rounded, color: Color(0xFF00E676), size: 22),
                        onPressed: () => _engine.startAllQueued(),
                      ),
                      IconButton(
                        tooltip: "ခဏရပ်မည်",
                        icon: const Icon(Icons.pause_rounded, color: Color(0xFFF59E0B), size: 20),
                        onPressed: () => _engine.pauseAll(),
                      ),
                    ],
                    if (filteredList.isNotEmpty)
                      IconButton(
                        tooltip: "အားလုံး ရှင်းမည်",
                        icon: const Icon(Icons.delete_sweep_rounded, color: Color(0xFFEF4444), size: 20),
                        onPressed: () => _engine.removeAll(currentTab),
                      ),
                  ],
                ),
              ),

              // 📋 Download Items List
              Expanded(
                child: filteredList.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              currentTab == 'Queue' ? Icons.download_done_rounded : Icons.folder_open_rounded,
                              size: 48,
                              color: const Color(0xFF30363D),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              currentTab == 'Queue'
                                  ? "ဒေါင်းလုဒ်ဆွဲရန် စာရင်းမရှိပါ\nအောက်ရှိ (+) ကိုနှိပ်၍ Link ထည့်နိုင်သည်"
                                  : "ပြီးစီးထားသော ဖိုင်မရှိသေးပါ",
                              textAlign: TextAlign.center,
                              style: const TextStyle(color: Color(0xFF6E7681), fontSize: 13),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.only(top: 8, bottom: 85),
                        itemCount: filteredList.length,
                        itemBuilder: (context, index) {
                          final item = filteredList[index];
                          final isFinished = item.status == 'finished';

                          return Container(
                            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: const Color(0xFF141920),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: item.status == 'downloading'
                                    ? const Color(0xFF238636)
                                    : const Color(0xFF21262D),
                                width: 0.8,
                              ),
                            ),
                            child: InkWell(
                              onTap: isFinished ? () => _openFile(item) : null,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Icon(
                                        item.name.toLowerCase().endsWith('.apk')
                                            ? Icons.android_rounded
                                            : Icons.movie_outlined,
                                        size: 20,
                                        color: isFinished ? const Color(0xFF00E676) : const Color(0xFF38BDF8),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          item.name,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 13,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                      if (!isFinished) ...[
                                        IconButton(
                                          padding: EdgeInsets.zero,
                                          constraints: const BoxConstraints(),
                                          icon: Icon(
                                            item.status == 'downloading'
                                                ? Icons.pause_circle_filled_rounded
                                                : Icons.play_circle_fill_rounded,
                                            color: item.status == 'downloading'
                                                ? const Color(0xFFF59E0B)
                                                : const Color(0xFF00E676),
                                            size: 26,
                                          ),
                                          onPressed: () => _engine.togglePauseResume(item),
                                        ),
                                        const SizedBox(width: 8),
                                      ],
                                      IconButton(
                                        padding: EdgeInsets.zero,
                                        constraints: const BoxConstraints(),
                                        icon: const Icon(Icons.close_rounded, color: Color(0xFF8B949E), size: 20),
                                        onPressed: () {
                                          if (isFinished) {
                                            _engine.deleteFinishedItems([item], deleteActualFile: true);
                                          } else {
                                            _engine.deleteItem(item);
                                          }
                                        },
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),

                                  // Progress Bar (Queue Only)
                                  if (!isFinished) ...[
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(4),
                                      child: LinearProgressIndicator(
                                        value: item.progress > 0 ? item.progress : null,
                                        backgroundColor: const Color(0xFF21262D),
                                        valueColor: AlwaysStoppedAnimation<Color>(
                                          item.status == 'downloading'
                                              ? const Color(0xFF00E676)
                                              : (item.status == 'error'
                                                  ? const Color(0xFFEF4444)
                                                  : const Color(0xFFF59E0B)),
                                        ),
                                        minHeight: 5,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                  ],

                                  // Meta Information
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        isFinished
                                            ? _formatBytes(item.sizeBytes)
                                            : "${(item.progress * 100).toStringAsFixed(1)}% • ${_formatBytes(item.sizeBytes)}",
                                        style: const TextStyle(color: Color(0xFF8B949E), fontSize: 11),
                                      ),
                                      Text(
                                        isFinished ? item.date : "${item.speed}  ${item.eta.isNotEmpty && item.eta != '--:--' ? '• ETA: ${item.eta}' : ''}",
                                        style: TextStyle(
                                          color: isFinished
                                              ? const Color(0xFF00E676)
                                              : (item.status == 'downloading'
                                                  ? const Color(0xFF38BDF8)
                                                  : const Color(0xFF8B949E)),
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),

          // 🌟 အလယ်တည့်တည့်ရှိ Link Paste ချနိုင်မည့် (+) Floating Action Button
          floatingActionButton: FloatingActionButton(
            backgroundColor: const Color(0xFF00E676),
            elevation: 6,
            shape: const CircleBorder(),
            tooltip: "Link ထည့်ရန်",
            onPressed: () => _showAddUrlDialog(context),
            child: const Icon(Icons.add_rounded, color: Colors.black, size: 34),
          ),
          floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
        );
      },
    );
  }
}
