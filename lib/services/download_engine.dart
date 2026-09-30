import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class DownloadItem {
  final String url;
  final String name;
  String status;
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
        String filename = Uri.decodeComponent(cleanUrl.split('/').last.split('?').first);
        if (filename.isEmpty) filename = "file_${DateTime.now().millisecondsSinceEpoch}.mp4";

        downloads.add(DownloadItem(
          url: cleanUrl,
          name: filename,
          date: "${DateTime.now().hour}:${DateTime.now().minute.toString().padLeft(2, '0')}",
        ));
        added = true;
      }
    }
    if (added) {
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
        await _downloadDirectSeek4(item);
        if (!item.isPaused && !item.isCanceled) {
          item.status = 'finished';
          item.progress = 1.0;
          item.speed = 'COMPLETE ✅';
          updateStorageInfo();
        }
      } catch (e) {
        if (!item.isPaused && !item.isCanceled) item.status = 'error';
      }
      notifyListeners();
    }
    isDownloading = false;
  }

  Future<void> _downloadDirectSeek4(DownloadItem item) async {
    final client = HttpClient();
    final headReq = await client.headUrl(Uri.parse(item.url));
    final headResp = await headReq.close();
    final totalLen = headResp.contentLength;
    if (totalLen > 0) item.sizeBytes = totalLen;

    final tempFile = File('$downloadPath/${item.name}.tmp');
    final finalFile = File('$downloadPath/${item.name}');

    if (!tempFile.existsSync() || tempFile.lengthSync() != totalLen) {
      final raf = await tempFile.open(mode: FileMode.write);
      await raf.truncate(totalLen);
      await raf.close();
    }

    const numThreads = 4;
    final partSize = totalLen ~/ numThreads;
    final parts = List.generate(numThreads, (i) {
      final s = i * partSize;
      final e = (i == numThreads - 1) ? (totalLen - 1) : (s + partSize - 1);
      return {'idx': i, 'start': s, 'end': e};
    });

    List<int> bytesDownloaded = List.filled(numThreads, 0);
    int lastDownloaded = 0;
    int lastTime = DateTime.now().millisecondsSinceEpoch;

    Future<void> downloadPart(Map p) async {
      final pClient = HttpClient();
      final req = await pClient.getUrl(Uri.parse(item.url));
      req.headers.add(HttpHeaders.rangeHeader, 'bytes=${p['start']}-${p['end']}');
      final resp = await req.close();

      final raf = await tempFile.open(mode: FileMode.writeOnly);
      await raf.setPosition(p['start']);

      await for (var chunk in resp) {
        if (item.isPaused || item.isCanceled) break;
        await raf.writeFrom(chunk);
        bytesDownloaded[p['idx']] += chunk.length;
      }
      await raf.close();
      pClient.close();
    }

    final futures = parts.map((p) => downloadPart(p)).toList();

    final timer = Timer.periodic(const Duration(milliseconds: 700), (_) {
      final currentBytes = bytesDownloaded.reduce((a, b) => a + b);
      final now = DateTime.now().millisecondsSinceEpoch;
      final dt = (now - lastTime) / 1000.0;
      if (dt > 0) {
        final speedBytes = (currentBytes - lastDownloaded) / dt;
        final speedMb = speedBytes / (1024 * 1024);
        item.speed = "${speedMb.toStringAsFixed(1)} MB/s";
        item.progress = totalLen > 0 ? (currentBytes / totalLen).clamp(0.0, 0.99) : 0.0;

        if (speedBytes > 0 && totalLen > 0) {
          final remSec = ((totalLen - currentBytes) / speedBytes).round();
          item.eta = "${remSec ~/ 60}:${(remSec % 60).toString().padLeft(2, '0')}";
        }
        lastDownloaded = currentBytes;
        lastTime = now;
        notifyListeners();
      }
    });

    await Future.wait(futures);
    timer.cancel();

    if (item.isCanceled || item.isPaused) return;

    if (tempFile.existsSync() && tempFile.lengthSync() == totalLen) {
      if (finalFile.existsSync()) finalFile.deleteSync();
      await tempFile.rename(finalFile.path);
    }
  }
}
