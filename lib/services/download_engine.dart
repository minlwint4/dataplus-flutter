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
        await _downloadFile(item);
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
      onAllDownloadsFinished?.call();
    }
  }

  // 🚀 LAN Speed အပြည့်ဖြင့် ဖိုင်မပျက်စီးအောင် တိုက်ရိုက်ဆွဲယူမည့် စနစ်
  Future<void> _downloadFile(DownloadItem item) async {
    final tempFile = File('$downloadPath/${item.name}.tmp');
    final finalFile = File('$downloadPath/${item.name}');

    final client = HttpClient();
    final req = await client.getUrl(Uri.parse(item.url));

    int existingBytes = 0;
    if (tempFile.existsSync()) {
      existingBytes = tempFile.lengthSync();
      if (existingBytes > 0) {
        req.headers.add(HttpHeaders.rangeHeader, 'bytes=$existingBytes-');
      }
    }

    final resp = await req.close();

    FileMode mode = FileMode.write;
    int downloadedBytes = 0;

    if (resp.statusCode == HttpStatus.partialContent) {
      mode = FileMode.append;
      downloadedBytes = existingBytes;
    } else if (resp.statusCode == HttpStatus.ok) {
      mode = FileMode.write;
      downloadedBytes = 0;
      if (resp.contentLength > 0) {
        item.sizeBytes = resp.contentLength;
      }
    } else {
      throw HttpException('Server status: ${resp.statusCode}');
    }

    if (resp.headers.value(HttpHeaders.contentRangeHeader) != null) {
      final cr = resp.headers.value(HttpHeaders.contentRangeHeader)!;
      final totalStr = cr.split('/').last;
      final parsed = int.tryParse(totalStr);
      if (parsed != null && parsed > 0) item.sizeBytes = parsed;
    } else if (item.sizeBytes == 0 && resp.contentLength > 0) {
      item.sizeBytes = downloadedBytes + resp.contentLength;
    }

    final totalLen = item.sizeBytes;
    final sink = tempFile.openWrite(mode: mode);

    int lastDownloaded = downloadedBytes;
    int lastTime = DateTime.now().millisecondsSinceEpoch;

    final timer = Timer.periodic(const Duration(milliseconds: 600), (_) {
      final now = DateTime.now().millisecondsSinceEpoch;
      final dt = (now - lastTime) / 1000.0;
      if (dt > 0) {
        final speedBytes = (downloadedBytes - lastDownloaded) / dt;
        final speedMb = speedBytes / (1024 * 1024);
        item.speed = "${speedMb.toStringAsFixed(1)} MB/s";
        if (totalLen > 0) {
          item.progress = (downloadedBytes / totalLen).clamp(0.0, 0.99);
          if (speedBytes > 0) {
            final remSec = ((totalLen - downloadedBytes) / speedBytes).round();
            item.eta = "${remSec ~/ 60}:${(remSec % 60).toString().padLeft(2, '0')}";
          }
        }
        lastDownloaded = downloadedBytes;
        lastTime = now;
        notifyListeners();
      }
    });

    try {
      await for (var chunk in resp) {
        if (item.isPaused || item.isCanceled) break;
        sink.add(chunk);
        downloadedBytes += chunk.length;
      }
      await sink.flush();
    } finally {
      timer.cancel();
      await sink.close();
      client.close();
    }

    if (item.isCanceled || item.isPaused) return;

    if (tempFile.existsSync()) {
      if (finalFile.existsSync()) finalFile.deleteSync();
      await tempFile.rename(finalFile.path); // နာမည်အမှန်သို့ ပြောင်းလဲခြင်း
    }
  }
}
