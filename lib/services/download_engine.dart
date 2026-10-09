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

  // 🌟 ဖိုင်သိမ်းမည့်လမ်းကြောင်းကို Download ဖိုဒါအောက်သို့ ပြောင်းလဲထားပါသည်
  static const String internalDownloadPath = '/storage/emulated/0/Download/.Dataplus';
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
      return '$sdDownloadPath/Download/.Dataplus';
    }
    return internalDownloadPath;
  }

  Future<void> _ensureDirectoryAndNoMedia(String path) async {
    final dir = Directory(path);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    final noMedia = File('${dir.path}/.nomedia');
    if (!await noMedia.exists()) {
      try { await noMedia.create(); } catch (_) {}
    }
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

        await _ensureDirectoryAndNoMedia(currentActivePath);
        await _scanLocalFiles();
        notifyListeners();
      }
    } catch (_) {}
  }

  Future<void> _scanLocalFiles() async {
    final paths = [internalDownloadPath];
    if (isSdAvailable && sdDownloadPath.isNotEmpty) {
      paths.add('$sdDownloadPath/Download/.Dataplus');
    }

    bool hasNew = false;
    for (var path in paths) {
      final dir = Directory(path);
      if (await dir.exists()) {
        final files = dir.listSync();
        for (var f in files) {
          if (f is File) {
            final name = f.path.split('/').last;
            if (name == '.nomedia' || name.endsWith('.tmp') || name.contains('.part')) continue;

            if (!downloads.any((d) => d.name == name && d.status == 'finished')) {
              final stat = f.statSync();
              downloads.add(DownloadItem(
                url: 'local_file',
                name: name,
                status: 'finished',
                progress: 1.0,
                sizeBytes: stat.size,
                speed: 'COMPLETE ✅',
                date: "${stat.modified.hour}:${stat.modified.minute.toString().padLeft(2, '0')}",
                savePath: path,
              ));
              hasNew = true;
            }
          }
        }
      }
    }
    if (hasNew) notifyListeners();
  }

  Future<void> setStorageTarget(String target) async {
    if (target == 'sdcard' && !isSdAvailable) return;
    storageTarget = target;
    
    await _ensureDirectoryAndNoMedia(currentActivePath);

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
      if (item.status == 'paused' || item.status == 'error') {
        item.status = 'queued';
        item.isPaused = false;
        item.speed = '0.0 MB/s';
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
    } else if (item.status == 'paused' || item.status == 'error') {
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
      for (int i = 0; i < 16; i++) {
        final part = File('$folder/$name.part$i');
        if (part.existsSync()) part.deleteSync();
      }
    } catch (_) {}
  }

  void deleteFinishedItems(List<DownloadItem> items, {required bool deleteActualFile}) {
    for (var item in items) {
      if (deleteActualFile) {
        final folder = item.savePath.isNotEmpty ? item.savePath : currentActivePath;
        final file = File('$folder/${item.name}');
        if (file.existsSync()) {
          try { file.deleteSync(); } catch (_) {}
        }
        final altFolder = (folder == internalDownloadPath)
            ? '$sdDownloadPath/Download/.Dataplus'
            : internalDownloadPath;
        final altFile = File('$altFolder/${item.name}');
        if (altFile.existsSync()) {
          try { altFile.deleteSync(); } catch (_) {}
        }
        _cleanupTempFiles(folder, item.name);
      }
      downloads.remove(item);
    }
    updateStorageInfo();
    notifyListeners();
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
        await _ensureDirectoryAndNoMedia(item.savePath);
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
          String errorMsg = e.toString().split('\n').first;
          if (errorMsg.contains('Permission')) {
            item.speed = "Storage Permission မရှိပါ!";
          } else if (errorMsg.contains('SocketException') || errorMsg.contains('HttpException')) {
            item.speed = "Network / Server ပြဿနာ";
          } else {
            item.speed = "Error: $errorMsg";
          }
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
    int totalBytes = item.sizeBytes;
    bool canMultiThread = false;

    try {
      final probeReq = await client.headUrl(Uri.parse(item.url));
      final probeResp = await probeReq.close();
      if (probeResp.headers.value('accept-ranges') == 'bytes') {
        canMultiThread = true;
      }
      if (totalBytes <= 0) {
        totalBytes = probeResp.contentLength > 0 ? probeResp.contentLength : 0;
      }
    } catch (_) {}

    if (totalBytes > 5 * 1024 * 1024 && !item.name.toLowerCase().endsWith('.apk')) {
       canMultiThread = true;
    }

    if (!canMultiThread || totalBytes < 5 * 1024 * 1024 || item.name.toLowerCase().endsWith('.apk')) {
      await _downloadSingleStream(item, client, totalBytes);
    } else {
      await _downloadMultiPartDirect(item, totalBytes);
    }
    client.close();
  }

  Future<void> _downloadMultiPartDirect(DownloadItem item, int totalBytes) async {
    item.sizeBytes = totalBytes;
    final folder = item.savePath.isNotEmpty ? item.savePath : currentActivePath;
    final tempFile = File('$folder/${item.name}.tmp');
    final finalFile = File('$folder/${item.name}');

    if (tempFile.existsSync()) {
      try { tempFile.deleteSync(); } catch (_) {}
    }

    final raf = await tempFile.open(mode: FileMode.write);
    try { raf.truncateSync(totalBytes); } catch (_) {}

    const numThreads = 4;
    final partSize = totalBytes ~/ numThreads;
    final parts = List.generate(numThreads, (i) {
      final s = i * partSize;
      final e = (i == numThreads - 1) ? (totalBytes - 1) : (s + partSize - 1);
      return {'idx': i, 'start': s, 'end': e};
    });

    List<int> bytesDownloaded = List.filled(numThreads, 0);
    int lastDownloaded = 0;
    int lastTime = DateTime.now().millisecondsSinceEpoch;

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

    Future<void> downloadPart(Map p) async {
      final pClient = HttpClient();
      int writePos = p['start'];
      try {
        final req = await pClient.getUrl(Uri.parse(item.url));
        req.headers.add(HttpHeaders.rangeHeader, 'bytes=${p['start']}-${p['end']}');
        final resp = await req.close();

        if (resp.statusCode != HttpStatus.partialContent && resp.statusCode != HttpStatus.ok) {
          throw HttpException('Part ${p['idx']} failed: ${resp.statusCode}');
        }

        await for (var chunk in resp) {
          if (item.isPaused || item.isCanceled) break;
          raf.setPositionSync(writePos);
          raf.writeFromSync(chunk);
          writePos += chunk.length;
          bytesDownloaded[p['idx']] += chunk.length;
        }
      } finally {
        pClient.close();
      }
    }

    try {
      await Future.wait(parts.map((p) => downloadPart(p)));
      await raf.flush();
    } finally {
      timer.cancel();
      try { raf.closeSync(); } catch (_) {}
    }

    if (item.isCanceled || item.isPaused) {
      if (item.isCanceled && tempFile.existsSync()) {
        try { tempFile.deleteSync(); } catch (_) {}
      }
      return;
    }

    if (finalFile.existsSync()) {
      try { finalFile.deleteSync(); } catch (_) {}
    }
    await tempFile.rename(finalFile.path);
  }

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
