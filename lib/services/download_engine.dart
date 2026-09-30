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
  });
}

class DownloadEngine extends ChangeNotifier {
  static final DownloadEngine _instance = DownloadEngine._internal();
  factory DownloadEngine() => _instance;
  DownloadEngine._internal() {
    _initDirectory();
    updateStorageInfo();
  }

  static const String downloadPath = '/storage/emulated/0/Download/DataPlus';
  final List<DownloadItem> downloads = [];
  bool isDownloading = false;

  // 🚀 တက်ဘ် အလိုအလျောက် ပြောင်းလဲရန် Notifier (စဒေါင်းလျှင် Queue, ပြီးလျှင် Finished)
  final ValueNotifier<String> activeTab = ValueNotifier<String>('Queue');
  VoidCallback? onAllDownloadsFinished;

  int freeStorageBytes = 0;
  int totalStorageBytes = 0;

  Future<void> _initDirectory() async {
    final dir = Directory(downloadPath);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
  }

  Future<void> updateStorageInfo() async {
    try {
      const channel = MethodChannel('com.dataplus/storage');
      final res = await channel.invokeMethod<Map>('getStorageSpace');
      if (res != null) {
        totalStorageBytes = res['total'] ?? 0;
        freeStorageBytes = res['free'] ?? 0;
        notifyListeners();
      }
    } catch (_) {}
  }

  int get totalQueuedBytes {
    return downloads
        .where((d) => d.status != 'finished')
        .fold(0, (sum, item) => sum + item.sizeBytes);
  }

  bool get isStorageLow {
    return totalQueuedBytes > freeStorageBytes && totalQueuedBytes > 0;
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
        ));
        added = true;
      }
    }
    if (added) {
      activeTab.value = 'Queue'; // 🚀 ဒေါင်းလုဒ်ထည့်လိုက်သည်နှင့် QUEUE တက်ဘ်သို့ ချက်ချင်းညွှန်းမည်
      _fetchSizes();
      notifyListeners();
      if (!isDownloading) {
        _startWorker();
      }
    }
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

  void deleteItem(DownloadItem item) {
    item.isCanceled = true;
    item.isPaused = true;
    final file = File('$downloadPath/${item.name}.tmp');
    if (file.existsSync()) {
      try { file.deleteSync(); } catch (_) {}
    }
    downloads.remove(item);
    updateStorageInfo();
    notifyListeners();
  }

  void deleteSelected(List<DownloadItem> items) {
    for (var it in items) {
      it.isCanceled = true;
      final file = File('$downloadPath/${it.name}.tmp');
      if (file.existsSync()) {
        try { file.deleteSync(); } catch (_) {}
      }
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
      final file = File('$downloadPath/${it.name}.tmp');
      if (file.existsSync()) {
        try { file.deleteSync(); } catch (_) {}
      }
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

    // 🚀 Queue ထဲရှိ ဖိုင်အားလုံး ပြီးဆုံးသွားပါက Finished မျက်နှာပြင်ဆီ အလိုအလျောက် ကူးပြောင်းပေးခြင်း
    if (!downloads.any((d) => d.status != 'finished')) {
      activeTab.value = 'Finished';
      onAllDownloadsFinished?.call();
    }
  }

  // 🚀 ဖိုင်အမျိုးအစားအလိုက် စစ်ဆေးပြီး အမြန်ဆုံးဆွဲမည့် စနစ်
  Future<void> _downloadSmartEngine(DownloadItem item) async {
    final client = HttpClient();
    int totalBytes = 0;
    bool canMultiThread = false;

    // ၁။ Range Request ရမရ အရင်စစ်ဆေးပြီး ဖိုင်ဆိုဒ်အစစ်ကို ဆွဲထုတ်ခြင်း
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

    // APK ဖိုင် သို့မဟုတ် Range မရသော ဖိုင်ဖြစ်ပါက Single Stream ဖြင့် မပျက်စီးအောင် ဒေါင်းမည်
    if (!canMultiThread || totalBytes < 5 * 1024 * 1024 || item.name.toLowerCase().endsWith('.apk')) {
      await _downloadSingleStream(item, client, totalBytes);
    } else {
      // ဇာတ်ကားဖိုင်ဖြစ်ပါက 60MB/s ရရှိစေမည့် 4-Thread Direct-Seek ဖြင့် ဒေါင်းမည်
      await _downloadMultiThreadDirectSeek(item, totalBytes);
    }
    client.close();
  }

  // ⚡ 60~80 MB/s ထိုးဆွဲမည့် 4-Thread Direct-Seek Engine
  Future<void> _downloadMultiThreadDirectSeek(DownloadItem item, int totalBytes) async {
    item.sizeBytes = totalBytes;
    final tempFile = File('$downloadPath/${item.name}.tmp');
    final finalFile = File('$downloadPath/${item.name}');

    // File အရွယ်အစားကို ကြိုတင်နေရာချထားခြင်း (Zero Merge Time)
    final initRaf = await tempFile.open(mode: FileMode.write);
    await initRaf.truncate(totalBytes);
    await initRaf.close();

    const numThreads = 4; // 4-Thread Concurrent Bandwidth
    final partSize = totalBytes ~/ numThreads;
    final parts = List.generate(numThreads, (i) {
      final s = i * partSize;
      final e = (i == numThreads - 1) ? (totalBytes - 1) : (s + partSize - 1);
      return {'idx': i, 'start': s, 'end': e};
    });

    List<int> bytesDownloaded = List.filled(numThreads, 0);
    int lastDownloaded = 0;
    int lastTime = DateTime.now().millisecondsSinceEpoch;

    Future<void> downloadPart(Map p) async {
      final pClient = HttpClient();
      try {
        final req = await pClient.getUrl(Uri.parse(item.url));
        req.headers.add(HttpHeaders.rangeHeader, 'bytes=${p['start']}-${p['end']}');
        final resp = await req.close();

        if (resp.statusCode != HttpStatus.partialContent) {
          throw HttpException('Thread failed with status ${resp.statusCode}');
        }

        final raf = await tempFile.open(mode: FileMode.writeOnly);
        int writePos = p['start'];

        await for (var chunk in resp) {
          if (item.isPaused || item.isCanceled) break;
          await raf.setPosition(writePos);
          await raf.writeFrom(chunk);
          writePos += chunk.length;
          bytesDownloaded[p['idx']] += chunk.length;
        }
        await raf.flush();
        await raf.close();
      } finally {
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

    // အားလုံးပြီးစီးမှသာ နာမည်ပြောင်းပေးမည် (Corrupt မဖြစ်စေရန် စစ်ဆေးခြင်း)
    final totalDone = bytesDownloaded.reduce((a, b) => a + b);
    if (totalDone == totalBytes) {
      if (finalFile.existsSync()) finalFile.deleteSync();
      await tempFile.rename(finalFile.path);
    } else {
      throw Exception('Download incomplete');
    }
  }

  // APK များနှင့် ဖိုင်အသေးများအတွက် Single Stream
  Future<void> _downloadSingleStream(DownloadItem item, HttpClient client, int totalBytes) async {
    final tempFile = File('$downloadPath/${item.name}.tmp');
    final finalFile = File('$downloadPath/${item.name}');

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
