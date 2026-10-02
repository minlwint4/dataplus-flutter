import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class DownloadItem {
  final String url;
  final String name;
  String status; // 'queued', 'downloading', 'paused', 'finished', 'error'
  double progress;
  int sizeBytes;
  String speed;
  String eta;
  String date;
  String savePath;
  bool isPaused = false;
  bool isCanceled = false;
  bool isSelected = false;

  DownloadItem({
    required this.url,
    required this.name,
    this.status = 'queued',
    this.progress = 0.0,
    this.sizeBytes = 0,
    this.speed = '0.0 MB/s',
    this.eta = '--:--',
    required this.date,
    this.savePath = '',
  });
}

class DownloadEngine extends ChangeNotifier {
  static final DownloadEngine _instance = DownloadEngine._internal();
  factory DownloadEngine() => _instance;
  DownloadEngine._internal() {
    updateStorageInfo();
  }

  static const String internalDownloadPath = '/storage/emulated/0/Download/DataPlus';
  String sdDownloadPath = '';

  String storageTarget = 'internal';

  final List<DownloadItem> downloads = [];
  bool isDownloading = false;

  final ValueNotifier<String> activeTab = ValueNotifier<String>('Queue');
  VoidCallback? onAllDownloadsFinished;

  int freeStorageBytes = 0;
  int totalStorageBytes = 0;

  bool isSdAvailable = false;
  int freeSdBytes = 0;
  int totalSdBytes = 0;

  String get currentActivePath {
    if (storageTarget == 'sdcard' && isSdAvailable && sdDownloadPath.isNotEmpty) {
      return '$sdDownloadPath/DataPlus';
    }
    return internalDownloadPath;
  }

  Future<void> updateStorageInfo() async {
    try {
      const channel = MethodChannel('com.dataplus/storage');
      final res = await channel.invokeMethod<Map>('getStorageSpace');
      if (res != null) {
        totalStorageBytes = res['total'] ?? 0;
        freeStorageBytes = res['free'] ?? 0;

        isSdAvailable = res['sdAvailable'] ?? false;
        totalSdBytes = res['sdTotal'] ?? 0;
        freeSdBytes = res['sdFree'] ?? 0;
        sdDownloadPath = res['sdPath'] ?? '';

        if (storageTarget == 'sdcard' && !isSdAvailable) {
          storageTarget = 'internal';
        }

        final dir = Directory(currentActivePath);
        if (!await dir.exists()) {
          await dir.create(recursive: true);
        }

        notifyListeners();
      }
    } catch (_) {}
  }

  Future<void> setStorageTarget(String target) async {
    if (target == 'sdcard' && !isSdAvailable) return;
    storageTarget = target;
    final dir = Directory(currentActivePath);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    for (var item in downloads) {
      if (item.status == 'queued' || item.status == 'paused') {
        item.savePath = currentActivePath;
      }
    }
    notifyListeners();
  }

  int get totalQueuedBytes {
    return downloads
        .where((d) => d.status != 'finished')
        .fold(0, (sum, item) => sum + item.sizeBytes);
  }

  bool get isStorageLow {
    final activeFree = (storageTarget == 'sdcard' && isSdAvailable) ? freeSdBytes : freeStorageBytes;
    return totalQueuedBytes > activeFree && totalQueuedBytes > 0;
  }

  void addUrls(List<String> urls) {
    bool added = false;
    for (var u in urls) {
      final cleanUrl = u.trim();
      if (cleanUrl.startsWith('http') && !downloads.any((d) => d.url == cleanUrl)) {
        String filename = '';
        final uri = Uri.parse(cleanUrl);

        if (uri.path.contains('/api/download/apk')) {
          final appName = uri.queryParameters['app'] ?? 'dataplus';
          filename = "$appName.apk";
        } else {
          filename = Uri.decodeComponent(cleanUrl.split('/').last.split('?').first);
        }

        if (filename.isEmpty || filename == 'apk') {
          filename = "file_${DateTime.now().millisecondsSinceEpoch}.mp4";
        }

        downloads.add(DownloadItem(
          url: cleanUrl,
          name: filename,
          date: "${DateTime.now().hour}:${DateTime.now().minute.toString().padLeft(2, '0')}",
          savePath: currentActivePath,
        ));
        added = true;
      }
    }
    if (added) {
      activeTab.value = 'Queue';
      _fetchSizes();
      notifyListeners();
    }
  }

  void startAllQueued() {
    for (var item in downloads) {
      if (item.status == 'paused') {
        item.status = 'queued';
        item.isPaused = false;
      }
    }
    notifyListeners();
    if (!isDownloading) {
      _startWorker();
    }
  }

  void pauseAll() {
    for (var item in downloads) {
      if (item.status == 'downloading' || item.status == 'queued') {
        item.status = 'paused';
        item.isPaused = true;
        item.speed = 'Paused';
      }
    }
    notifyListeners();
  }

  Future<void> _fetchSizes() async {
    final client = HttpClient();
    for (var item in downloads) {
      if (item.sizeBytes == 0) {
        try {
          final req = await client.headUrl(Uri.parse(item.url));
          final resp = await req.close();
          item.sizeBytes = resp.contentLength > 0 ? resp.contentLength : 0;
        } catch (_) {}
      }
    }
    client.close();
    notifyListeners();
  }

  void togglePauseResume(DownloadItem item) {
    if (item.status == 'downloading') {
      item.isPaused = true;
      item.status = 'paused';
      item.speed = 'Paused';
      notifyListeners();
    } else if (item.status == 'paused') {
      item.isPaused = false;
      item.status = 'queued';
      item.speed = 'Resuming...';
      activeTab.value = 'Queue';
      notifyListeners();
      if (!isDownloading) _startWorker();
    }
  }

  void _cleanupTempFiles(String folder, String name) {
    try {
      final tmp = File('$folder/$name.tmp');
      if (tmp.existsSync()) tmp.deleteSync();
      final merging = File('$folder/$name.merging');
      if (merging.existsSync()) merging.deleteSync();
      for (int i = 0; i < 8; i++) {
        final part = File('$folder/$name.part$i');
        if (part.existsSync()) part.deleteSync();
      }
    } catch (_) {}
  }

  void deleteItem(DownloadItem item) {
    item.isCanceled = true;
    item.isPaused = true;
    final folder = item.savePath.isNotEmpty ? item.savePath : currentActivePath;
    _cleanupTempFiles(folder, item.name);
    downloads.remove(item);
    updateStorageInfo();
    notifyListeners();
  }

  void deleteSelected(List<DownloadItem> items) {
    for (var it in items) {
      it.isCanceled = true;
      final folder = it.savePath.isNotEmpty ? it.savePath : currentActivePath;
      _cleanupTempFiles(folder, it.name);
      downloads.remove(it);
    }
    updateStorageInfo();
    notifyListeners();
  }

  void removeAll(String currentTab) {
    final toRemove = downloads.where((d) =>
      (currentTab == 'Finished' && d.status == 'finished') ||
      (currentTab == 'Queue' && d.status != 'finished')
    ).toList();
    for (var it in toRemove) {
      it.isCanceled = true;
      final folder = it.savePath.isNotEmpty ? it.savePath : currentActivePath;
      _cleanupTempFiles(folder, it.name);
      downloads.remove(it);
    }
    updateStorageInfo();
    notifyListeners();
  }

  Future<void> _startWorker() async {
    isDownloading = true;
    while (true) {
      final queued = downloads.where((d) => d.status == 'queued').toList();
      if (queued.isEmpty) break;

      final item = queued.first;
      item.status = 'downloading';
      item.isPaused = false;
      item.isCanceled = false;
      if (item.savePath.isEmpty) item.savePath = currentActivePath;
      notifyListeners();

      try {
        await _downloadSmartEngine(item);
        if (!item.isPaused && !item.isCanceled) {
          item.status = 'finished';
          item.progress = 1.0;
          item.speed = 'COMPLETE ✅';
          updateStorageInfo();
        }
      } catch (e) {
        if (!item.isPaused && !item.isCanceled) {
          item.status = 'error';
          item.speed = 'Error';
        }
      }
      notifyListeners();
    }
    isDownloading = false;

    if (!downloads.any((d) => d.status != 'finished')) {
      activeTab.value = 'Finished';
      onAllDownloadsFinished?.call();
    }
  }

  Future<void> _downloadSmartEngine(DownloadItem item) async {
    final client = HttpClient();
    int totalBytes = 0;
    bool canMultiThread = false;

    try {
      final probeReq = await client.getUrl(Uri.parse(item.url));
      probeReq.headers.add(HttpHeaders.rangeHeader, 'bytes=0-0');
      final probeResp = await probeReq.close();

      if (probeResp.statusCode == HttpStatus.partialContent) {
        final cr = probeResp.headers.value(HttpHeaders.contentRangeHeader);
        if (cr != null && cr.contains('/')) {
          final totalStr = cr.split('/').last.trim();
          final parsed = int.tryParse(totalStr);
          if (parsed != null && parsed > 0) {
            totalBytes = parsed;
            canMultiThread = true;
          }
        }
      } else if (probeResp.statusCode == HttpStatus.ok) {
        totalBytes = probeResp.contentLength;
      }
      await probeResp.drain();
    } catch (_) {}

    // APK ဖိုင် သို့မဟုတ် Range မရပါက Single Stream ဖြင့် ဒေါင်းမည်
    if (!canMultiThread || totalBytes < 5 * 1024 * 1024 || item.name.toLowerCase().endsWith('.apk')) {
      await _downloadSingleStream(item, client, totalBytes);
    } else {
      // ဇာတ်ကားဖိုင်များအတွက် Zero-Corruption Part-File 4-Thread စနစ်ဖြင့် ဒေါင်းမည်
      await _downloadMultiPartVerified(item, totalBytes);
    }
    client.close();
  }

  // 🚀 ၁၀၀% ဖိုင်မပျက်စီးစေသော Zero-Corruption Part-File Engine
  Future<void> _downloadMultiPartVerified(DownloadItem item, int totalBytes) async {
    item.sizeBytes = totalBytes;
    final folder = item.savePath.isNotEmpty ? item.savePath : currentActivePath;
    final finalFile = File('$folder/${item.name}');

    const numThreads = 4;
    final partSize = totalBytes ~/ numThreads;
    final parts = List.generate(numThreads, (i) {
      final s = i * partSize;
      final e = (i == numThreads - 1) ? (totalBytes - 1) : (s + partSize - 1);
      final expected = e - s + 1;
      return {'idx': i, 'start': s, 'end': e, 'expected': expected};
    });

    List<int> bytesDownloaded = List.filled(numThreads, 0);
    int lastDownloaded = 0;
    int lastTime = DateTime.now().millisecondsSinceEpoch;

    // Thread တစ်ခုချင်းစီ သီးခြား Part File ရေးသားခြင်း
    Future<void> downloadPart(Map p) async {
      final pClient = HttpClient();
      final partFile = File('$folder/${item.name}.part${p['idx']}');
      final sink = partFile.openWrite(mode: FileMode.write);

      try {
        final req = await pClient.getUrl(Uri.parse(item.url));
        req.headers.add(HttpHeaders.rangeHeader, 'bytes=${p['start']}-${p['end']}');
        final resp = await req.close();

        if (resp.statusCode != HttpStatus.partialContent) {
          throw HttpException('Part ${p['idx']} failed: ${resp.statusCode}');
        }

        await for (var chunk in resp) {
          if (item.isPaused || item.isCanceled) break;
          sink.add(chunk);
          bytesDownloaded[p['idx']] += chunk.length;
        }
        await sink.flush();
      } finally {
        await sink.close();
        pClient.close();
      }
    }

    final timer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      final currentBytes = bytesDownloaded.reduce((a, b) => a + b);
      final now = DateTime.now().millisecondsSinceEpoch;
      final dt = (now - lastTime) / 1000.0;
      if (dt > 0) {
        final speedBytes = (currentBytes - lastDownloaded) / dt;
        final speedMb = speedBytes / (1024 * 1024);
        item.speed = "${speedMb.toStringAsFixed(1)} MB/s";
        item.progress = (currentBytes / totalBytes).clamp(0.0, 0.99);

        if (speedBytes > 0) {
          final remSec = ((totalBytes - currentBytes) / speedBytes).round();
          item.eta = "${remSec ~/ 60}:${(remSec % 60).toString().padLeft(2, '0')}";
        }
        lastDownloaded = currentBytes;
        lastTime = now;
        notifyListeners();
      }
    });

    try {
      await Future.wait(parts.map((p) => downloadPart(p)));
    } finally {
      timer.cancel();
    }

    if (item.isCanceled || item.isPaused) return;

    // ⚡ ၁။ Part တစ်ခုချင်းစီ၏ Byte အရေအတွက်ကို ၁ Byte မလွဲအောင် အရင်စစ်ဆေးခြင်း
    for (var p in parts) {
      final partFile = File('$folder/${item.name}.part${p['idx']}');
      if (!partFile.existsSync() || partFile.lengthSync() != p['expected']) {
        throw Exception("Part ${p['idx']} size mismatch (Incomplete download)");
      }
    }

    // ⚡ ၂။ အားလုံး ပြည့်စုံမှသာ အစအဆုံး စနစ်တကျ ပြန်ပေါင်းစပ်ခြင်း (Stream Assembly)
    item.speed = "Verifying...";
    notifyListeners();

    final tempMerge = File('$folder/${item.name}.merging');
    final mergeSink = tempMerge.openWrite(mode: FileMode.write);

    for (int i = 0; i < numThreads; i++) {
      final partFile = File('$folder/${item.name}.part$i');
      await mergeSink.addStream(partFile.openRead());
    }
    await mergeSink.flush();
    await mergeSink.close();

    // ⚡ ၃။ ဖိုင်တစ်ခုလုံး မူရင်း Size အတိုင်း ကွက်တိ ဟုတ်မဟုတ် နောက်ဆုံး အတည်ပြုခြင်း
    if (tempMerge.existsSync() && tempMerge.lengthSync() == totalBytes) {
      if (finalFile.existsSync()) finalFile.deleteSync();
      await tempMerge.rename(finalFile.path);

      // ပြီးစီးသွားသော Part ဖိုင်ယာယီများကို ရှင်းလင်းခြင်း
      for (int i = 0; i < numThreads; i++) {
        final p = File('$folder/${item.name}.part$i');
        if (p.existsSync()) p.deleteSync();
      }
    } else {
      throw Exception("Merged file corrupted or size mismatch");
    }
  }

  // APK များနှင့် ဖိုင်အသေးများအတွက် Single Stream
  Future<void> _downloadSingleStream(DownloadItem item, HttpClient client, int totalBytes) async {
    final folder = item.savePath.isNotEmpty ? item.savePath : currentActivePath;
    final tempFile = File('$folder/${item.name}.tmp');
    final finalFile = File('$folder/${item.name}');

    final req = await client.getUrl(Uri.parse(item.url));
    final resp = await req.close();
    if (resp.statusCode != HttpStatus.ok && resp.statusCode != HttpStatus.partialContent) {
      throw HttpException('Failed: ${resp.statusCode}');
    }

    final totalLen = (totalBytes > 0) ? totalBytes : (resp.contentLength > 0 ? resp.contentLength : 0);
    item.sizeBytes = totalLen;

    final sink = tempFile.openWrite(mode: FileMode.write);
    int downloaded = 0;
    int lastDownloaded = 0;
    int lastTime = DateTime.now().millisecondsSinceEpoch;

    final timer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      final now = DateTime.now().millisecondsSinceEpoch;
      final dt = (now - lastTime) / 1000.0;
      if (dt > 0) {
        final speedBytes = (downloaded - lastDownloaded) / dt;
        final speedMb = speedBytes / (1024 * 1024);
        item.speed = "${speedMb.toStringAsFixed(1)} MB/s";
        if (totalLen > 0) {
          item.progress = (downloaded / totalLen).clamp(0.0, 0.99);
          if (speedBytes > 0) {
            final remSec = ((totalLen - downloaded) / speedBytes).round();
            item.eta = "${remSec ~/ 60}:${(remSec % 60).toString().padLeft(2, '0')}";
          }
        }
        lastDownloaded = downloaded;
        lastTime = now;
        notifyListeners();
      }
    });

    try {
      await for (var chunk in resp) {
        if (item.isPaused || item.isCanceled) break;
        sink.add(chunk);
        downloaded += chunk.length;
      }
      await sink.flush();
    } finally {
      timer.cancel();
      await sink.close();
    }

    if (item.isCanceled || item.isPaused) return;

    if (finalFile.existsSync()) finalFile.deleteSync();
    await tempFile.rename(finalFile.path);
  }
}
