import 'dart:async';
import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:video_player/video_player.dart';
import 'package:screen_brightness/screen_brightness.dart';
import 'package:volume_controller/volume_controller.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  runApp(const MemcPlayerApp());
}

class MemcPlayerApp extends StatelessWidget {
  const MemcPlayerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MEMC Video Player',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true).copyWith(
        scaffoldBackgroundColor: Colors.black,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF6750A4),
          brightness: Brightness.dark,
        ),
      ),
      home: const VideoPlayerScreen(),
    );
  }
}

class VideoPlayerScreen extends StatefulWidget {
  const VideoPlayerScreen({super.key});

  @override
  State<VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends State<VideoPlayerScreen> {
  VideoPlayerController? _controller;
  bool _showControls = true;
  Timer? _hideTimer;
  double _currentVolume = 0.5;
  double _currentBrightness = 0.5;
  bool _showVolumeIndicator = false;
  bool _showBrightnessIndicator = false;
  Timer? _indicatorTimer;
  double _targetFps = 60.0;
  bool _memcEnabled = true;

  @override
  void initState() {
    super.initState();
    _initAudioAndBrightness();
  }

  Future<void> _initAudioAndBrightness() async {
    try {
      _currentBrightness = await ScreenBrightness().current;
      _currentVolume = await VolumeController().getVolume();
    } catch (_) {}
  }

  void _pickVideo() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.video,
    );

    if (result != null && result.files.single.path != null) {
      _initializeVideo(File(result.files.single.path!));
    }
  }

  void _initializeVideo(File file) async {
    await _controller?.dispose();
    _controller = VideoPlayerController.file(file);

    await _controller!.initialize();
    setState(() {});
    _controller!.play();
    _resetControlTimeout();
  }

  void _toggleControls() {
    setState(() {
      _showControls = !_showControls;
    });
    if (_showControls) {
      _resetControlTimeout();
    }
  }

  void _resetControlTimeout() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 4), () {
      if (mounted && _controller != null && _controller!.value.isPlaying) {
        setState(() {
          _showControls = false;
        });
      }
    });
  }

  void _handleVerticalDrag(DragUpdateDetails details, Size screenSize) {
    final double delta = -details.primaryDelta! / screenSize.height;
    final bool isLeft = details.globalPosition.dx < (screenSize.width / 2);

    if (isLeft) {
      _currentBrightness = (_currentBrightness + delta).clamp(0.0, 1.0);
      ScreenBrightness().setScreenBrightness(_currentBrightness);
      setState(() {
        _showBrightnessIndicator = true;
        _showVolumeIndicator = false;
      });
    } else {
      _currentVolume = (_currentVolume + delta).clamp(0.0, 1.0);
      VolumeController().setVolume(_currentVolume);
      setState(() {
        _showVolumeIndicator = true;
        _showBrightnessIndicator = false;
      });
    }

    _indicatorTimer?.cancel();
    _indicatorTimer = Timer(const Duration(milliseconds: 1500), () {
      if (mounted) {
        setState(() {
          _showVolumeIndicator = false;
          _showBrightnessIndicator = false;
        });
      }
    });
  }

  void _seekRelative(int seconds) {
    if (_controller != null && _controller!.value.isInitialized) {
      final current = _controller!.value.position;
      final target = current + Duration(seconds: seconds);
      _controller!.seekTo(target);
      _resetControlTimeout();
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    _hideTimer?.cancel();
    _indicatorTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Size size = MediaQuery.of(context).size;

    return Scaffold(
      body: GestureDetector(
        onTap: _toggleControls,
        onVerticalDragUpdate: (details) => _handleVerticalDrag(details, size),
        onDoubleTapDown: (details) {
          if (details.globalPosition.dx < size.width / 2) {
            _seekRelative(-10);
          } else {
            _seekRelative(10);
          }
        },
        child: Stack(
          children: [
            Center(
              child: Container(
                decoration: BoxDecoration(
                  boxShadow: [
                    BoxShadow(
                      color: Colors.deepPurple.withOpacity(0.25),
                      blurRadius: 100,
                      spreadRadius: 20,
                    )
                  ],
                ),
                child: _controller != null && _controller!.value.isInitialized
                    ? AspectRatio(
                        aspectRatio: _controller!.value.aspectRatio,
                        child: VideoPlayer(_controller!),
                      )
                    : _buildEmptyState(),
              ),
            ),
            if (_showBrightnessIndicator)
              _buildOverlaySlider(Icons.brightness_6, _currentBrightness, true),
            if (_showVolumeIndicator)
              _buildOverlaySlider(Icons.volume_up, _currentVolume, false),
            if (_showControls) _buildOneUiControls(),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.video_library_rounded, size: 72, color: Colors.white38),
          const SizedBox(height: 16),
          const Text(
            'Select a Video to Begin',
            style: TextStyle(color: Colors.white70, fontSize: 18),
          ),
          const SizedBox(height: 20),
          ElevatedButton.icon(
            onPressed: _pickVideo,
            icon: const Icon(Icons.folder_open),
            label: const Text('Open Local File'),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOverlaySlider(IconData icon, double value, bool isLeft) {
    return Positioned(
      top: 60,
      left: isLeft ? 40 : null,
      right: !isLeft ? 40 : null,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            color: Colors.black.withOpacity(0.4),
            child: Row(
              children: [
                Icon(icon, color: Colors.white, size: 20),
                const SizedBox(width: 8),
                SizedBox(
                  width: 100,
                  child: LinearProgressIndicator(
                    value: value,
                    backgroundColor: Colors.white24,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildOneUiControls() {
    final position = _controller?.value.position ?? Duration.zero;
    final duration = _controller?.value.duration ?? Duration.zero;

    return AnimatedOpacity(
      opacity: _showControls ? 1.0 : 0.0,
      duration: const Duration(milliseconds: 250),
      child: Container(
        color: Colors.black38,
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                  icon: const Icon(Icons.folder_open, color: Colors.white),
                  onPressed: _pickVideo,
                ),
                ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                      color: Colors.white.withOpacity(0.1),
                      child: Row(
                        children: [
                          const Text('MEMC', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                          Switch(
                            value: _memcEnabled,
                            activeColor: Colors.deepPurpleAccent,
                            onChanged: (val) {
                              setState(() => _memcEnabled = val);
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const Spacer(),
            if (_controller != null)
              IconButton(
                iconSize: 64,
                icon: Icon(
                  _controller!.value.isPlaying ? Icons.pause_circle_filled : Icons.play_circle_filled,
                  color: Colors.white,
                ),
                onPressed: () {
                  setState(() {
                    _controller!.value.isPlaying ? _controller!.pause() : _controller!.play();
                  });
                  _resetControlTimeout();
                },
              ),
            const Spacer(),
            ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  color: Colors.white.withOpacity(0.1),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Text(_formatDuration(position), style: const TextStyle(color: Colors.white70)),
                          Expanded(
                            child: Slider(
                              value: position.inMilliseconds.toDouble().clamp(
                                  0.0,
                                  duration.inMilliseconds.toDouble() > 0
                                      ? duration.inMilliseconds.toDouble()
                                      : 1.0),
                              max: duration.inMilliseconds.toDouble() > 0
                                  ? duration.inMilliseconds.toDouble()
                                  : 1.0,
                              onChanged: (val) {
                                _seekRelative((val / 1000).toInt() - position.inSeconds);
                              },
                            ),
                          ),
                          Text(_formatDuration(duration), style: const TextStyle(color: Colors.white70)),
                        ],
                      ),
                      Row(
                        children: [
                          const Text('Target FPS:', style: TextStyle(color: Colors.white, fontSize: 12)),
                          Expanded(
                            child: Slider(
                              value: _targetFps,
                              min: 30.0,
                              max: 120.0,
                              divisions: 3,
                              label: '${_targetFps.toInt()} FPS',
                              onChanged: (val) {
                                setState(() => _targetFps = val);
                              },
                            ),
                          ),
                          Text('${_targetFps.toInt()} FPS', style: const TextStyle(color: Colors.white, fontSize: 12)),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }
}
