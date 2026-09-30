import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/download_engine.dart';

class DownloaderScreen extends StatefulWidget {
  const DownloaderScreen({super.key});

  @override
  State<DownloaderScreen> createState() => _DownloaderScreenState();
}

class _DownloaderScreenState extends State<DownloaderScreen> {
  final engine = DownloadEngine();
  String currentTab = 'Finished';

  String _formatBytes(int bytes) {
    if (bytes <= 0) return "0 MB";
    double mb = bytes / (1024 * 1024);
    if (mb >= 1024) return "${(mb / 1024).toStringAsFixed(1)} GB";
    return "${mb.toStringAsFixed(1)} MB";
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
                setState(() => currentTab = 'Queue');
              }
            },
            child: const Text("🚀 စတင်ဒေါင်းမည်", style: TextStyle(color: Colors.white)),
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

        return Scaffold(
          backgroundColor: const Color(0xFF101317),
          body: SafeArea(
            child: Column(
              children: [
                Container(
                  color: const Color(0xFF1E232B),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.menu, color: Color(0xFFC9D1D9), size: 22),
                          const SizedBox(width: 10),
                          Text(currentTab, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
                        ],
                      ),
                      if (currentList.isNotEmpty)
                        Row(
                          children: [
                            TextButton.icon(
                              onPressed: () {
                                final selectAll = selectedList.length != currentList.length;
                                for (var item in currentList) {
                                  item.isSelected = selectAll;
                                }
                                setState(() {});
                              },
                              icon: const Icon(Icons.select_all, size: 16, color: Color(0xFF58A6FF)),
                              label: Text(selectedList.length == currentList.length ? 'None' : 'All', style: const TextStyle(color: Color(0xFF58A6FF))),
                            ),
                            if (selectedList.isNotEmpty)
                              ElevatedButton(
                                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFB91C1C), padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6)),
                                onPressed: () => engine.deleteSelected(selectedList),
                                child: Text('Delete (${selectedList.length})', style: const TextStyle(color: Colors.white, fontSize: 12)),
                              )
                            else
                              TextButton.icon(
                                onPressed: () => engine.removeAll(currentTab),
                                icon: const Icon(Icons.delete_sweep, size: 16, color: Color(0xFFF85149)),
                                label: const Text('Remove All', style: TextStyle(color: Color(0xFFF85149))),
                              ),
                          ],
                        )
                    ],
                  ),
                ),
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF16222F),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: engine.isStorageLow ? const Color(0xFFFF4444) : const Color(0xFF2563EB),
                      width: 1.5,
                    ),
                  ),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Row(
                            children: [
                              Icon(Icons.sd_storage, color: Color(0xFF00E676), size: 18),
                              SizedBox(width: 6),
                              Text("ဖုန်း STORAGE လက်ကျန်", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                            ],
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: engine.isStorageLow ? const Color(0xFFB91C1C) : const Color(0xFF1E40AF),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              "${((engine.freeStorageBytes / (engine.totalStorageBytes > 0 ? engine.totalStorageBytes : 1)) * 100).toStringAsFixed(0)}% ကျန်ရှိ",
                              style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                            ),
                          )
                        ],
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Text("လက်ကျန်: ${_formatBytes(engine.freeStorageBytes)}", style: const TextStyle(color: Color(0xFF00E676), fontWeight: FontWeight.bold, fontSize: 15)),
                          const SizedBox(width: 8),
                          Text("(စုစုပေါင်း: ${_formatBytes(engine.totalStorageBytes)})", style: const TextStyle(color: Color(0xFF8B949E), fontSize: 12)),
                        ],
                      ),
                      Container(
                        width: double.infinity,
                        margin: const EdgeInsets.symmetric(vertical: 6),
                        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 10),
                        decoration: BoxDecoration(
                          color: engine.isStorageLow ? const Color(0xFF2A1215) : const Color(0xFF0E1726),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: engine.isStorageLow ? const Color(0xFFFF4D4D) : const Color(0xFF1E3A8A)),
                        ),
                        child: Column(
                          children: [
                            Text(
                              "ဒေါင်းလုဒ်အရွယ်အစား: ${_formatBytes(engine.totalQueuedBytes)}",
                              style: TextStyle(
                                color: engine.isStorageLow ? const Color(0xFFFFA1A1) : const Color(0xFF38BDF8),
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                            if (engine.isStorageLow)
                              const Padding(
                                padding: EdgeInsets.only(top: 2),
                                child: Text("⚠️ လက်ကျန် storage မလုံလောက်ပါ!", style: TextStyle(color: Color(0xFFFF4D4D), fontWeight: FontWeight.bold, fontSize: 12.5)),
                              )
                          ],
                        ),
                      ),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: engine.totalStorageBytes > 0 ? (1.0 - (engine.freeStorageBytes / engine.totalStorageBytes)) : 0.0,
                          backgroundColor: const Color(0xFF263342),
                          color: engine.isStorageLow ? const Color(0xFFFF4444) : const Color(0xFF00E676),
                          minHeight: 7,
                        ),
                      )
                    ],
                  ),
                ),
                Expanded(
                  child: currentList.isEmpty
                      ? Center(child: Text("No $currentTab downloads", style: const TextStyle(color: Color(0xFF484F58))))
                      : ListView.builder(
                          itemCount: currentList.length,
                          itemBuilder: (context, index) {
                            final item = currentList[index];
                            final isDone = item.status == 'finished';
                            final isDl = item.status == 'downloading';
                            final isPaused = item.status == 'paused';

                            return Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              decoration: const BoxDecoration(
                                color: Color(0xFF13171D),
                                border: Border(bottom: BorderSide(color: Color(0xFF21262E), width: 0.6)),
                              ),
                              child: Column(
                                children: [
                                  Row(
                                    children: [
                                      Checkbox(
                                        value: item.isSelected,
                                        activeColor: const Color(0xFF2563EB),
                                        onChanged: (v) => setState(() => item.isSelected = v ?? false),
                                      ),
                                      if (isDone)
                                        const Icon(Icons.check_circle, color: Color(0xFF00E676), size: 20)
                                      else if (isDl)
                                        IconButton(
                                          icon: const Icon(Icons.pause_circle_filled, color: Color(0xFFE3B341), size: 22),
                                          onPressed: () => engine.togglePauseResume(item),
                                        )
                                      else if (isPaused)
                                        IconButton(
                                          icon: const Icon(Icons.play_circle_fill, color: Color(0xFF58A6FF), size: 22),
                                          onPressed: () => engine.togglePauseResume(item),
                                        )
                                      else
                                        const Icon(Icons.access_time, color: Color(0xFF8B949E), size: 20),
                                      const SizedBox(width: 6),
                                      Expanded(
                                        child: Text(item.name, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 13)),
                                      ),
                                      IconButton(
                                        icon: const Icon(Icons.delete_outline, color: Color(0xFF8B949E), size: 18),
                                        onPressed: () => engine.deleteItem(item),
                                      )
                                    ],
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(_formatBytes(item.sizeBytes), style: const TextStyle(color: Color(0xFF8B949E), fontSize: 11)),
                                        Text("${item.speed}  •  ${item.eta}", style: TextStyle(color: isPaused ? const Color(0xFFE3B341) : const Color(0xFF00E676), fontWeight: FontWeight.bold, fontSize: 12)),
                                        Text(item.date, style: const TextStyle(color: Color(0xFF8B949E), fontSize: 10.5)),
                                      ],
                                    ),
                                  ),
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(3),
                                    child: LinearProgressIndicator(
                                      value: item.progress,
                                      backgroundColor: const Color(0xFF21262E),
                                      color: isPaused ? const Color(0xFFE3B341) : const Color(0xFF00E676),
                                      minHeight: 6,
                                    ),
                                  )
                                ],
                              ),
                            );
                          },
                        ),
                ),
                Container(
                  color: const Color(0xFF1E232B),
                  padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 15),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.power_settings_new, color: Color(0xFFF85149), size: 22),
                        tooltip: "Exit",
                        onPressed: () => SystemNavigator.pop(),
                      ),
                      IconButton(
                        icon: Container(
                          padding: const EdgeInsets.all(5),
                          decoration: const BoxDecoration(color: Color(0xFF238636), shape: BoxShape.circle),
                          child: const Icon(Icons.add, color: Colors.white, size: 20),
                        ),
                        onPressed: _showAddLinksDialog,
                      ),
                      InkWell(
                        onTap: () => setState(() => currentTab = 'Queue'),
                        child: Row(
                          children: [
                            Icon(Icons.access_time, color: currentTab == 'Queue' ? const Color(0xFF58A6FF) : const Color(0xFF8B949E), size: 18),
                            const SizedBox(width: 4),
                            Text("Queue", style: TextStyle(color: currentTab == 'Queue' ? const Color(0xFF58A6FF) : const Color(0xFF8B949E), fontWeight: FontWeight.bold, fontSize: 12)),
                            const SizedBox(width: 4),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                              decoration: BoxDecoration(color: qCount > 0 ? const Color(0xFF2563EB) : const Color(0xFF2A3441), borderRadius: BorderRadius.circular(10)),
                              child: Text("$qCount", style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                            )
                          ],
                        ),
                      ),
                      InkWell(
                        onTap: () => setState(() => currentTab = 'Finished'),
                        child: Row(
                          children: [
                            Icon(Icons.check_circle, color: currentTab == 'Finished' ? const Color(0xFF00E676) : const Color(0xFF8B949E), size: 18),
                            const SizedBox(width: 4),
                            Text("Finished", style: TextStyle(color: currentTab == 'Finished' ? const Color(0xFF00E676) : const Color(0xFF8B949E), fontWeight: FontWeight.bold, fontSize: 12)),
                            const SizedBox(width: 4),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                              decoration: BoxDecoration(color: fCount > 0 ? const Color(0xFF238636) : const Color(0xFF2A3441), borderRadius: BorderRadius.circular(10)),
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
