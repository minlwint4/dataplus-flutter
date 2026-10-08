import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';
import 'package:chewie/chewie.dart';

class VideoPlayerScreen extends StatefulWidget {
  final File videoFile;
  final String videoTitle;

  const VideoPlayerScreen({
    super.key,
    required this.videoFile,
    required this.videoTitle,
  });

  @override
  State<VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends State<VideoPlayerScreen> {
  late VideoPlayerController _videoPlayerController;
  ChewieController? _chewieController;
  bool _isError = false;

  @override
  void initState() {
    super.initState();
    _initializePlayer();
  }

  Future<void> _initializePlayer() async {
    try {
      _videoPlayerController = VideoPlayerController.file(widget.videoFile);
      await _videoPlayerController.initialize();

      _chewieController = ChewieController(
        videoPlayerController: _videoPlayerController,
        autoPlay: true,
        looping: false,
        fullScreenByDefault: true,
        allowFullScreen: true,
        allowedScreenSleep: false,
        deviceOrientationsOnEnterFullScreen: [
          DeviceOrientation.landscapeRight,
          DeviceOrientation.landscapeLeft,
        ],
        deviceOrientationsAfterFullScreen: [
          DeviceOrientation.portraitUp,
        ],
        errorBuilder: (context, errorMessage) {
          return Center(
            child: Text(
              "ဗီဒီယို ဖွင့်၍မရပါ - $errorMessage",
              style: const TextStyle(color: Colors.white),
            ),
          );
        },
      );
      setState(() {});
    } catch (e) {
      setState(() {
        _isError = true;
      });
    }
  }

  @override
  void dispose() {
    _videoPlayerController.dispose();
    _chewieController?.dispose();
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Text(
          widget.videoTitle,
          style: const TextStyle(fontSize: 14, color: Colors.white),
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: SafeArea(
        child: _isError
            ? const Center(
                child: Text(
                  "⚠️ ဤဗီဒီယိုဖိုင်ကို ဖွင့်၍မရပါ။ (Unsupported Format)",
                  style: TextStyle(color: Colors.redAccent, fontSize: 16),
                ),
              )
            : _chewieController != null && _videoPlayerController.value.isInitialized
                ? Chewie(controller: _chewieController!)
                : const Center(
                    child: CircularProgressIndicator(color: Color(0xFF00E676)),
                  ),
      ),
    );
  }
}
