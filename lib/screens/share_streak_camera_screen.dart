import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import '../theme/app_theme.dart';

/// Camera + streak-design overlay, photo capture, color/B&W toggle, share.
/// Video capture is a separate future step — this screen is photo-only.
class ShareStreakCameraScreen extends StatefulWidget {
  final int currentStreak;
  final DateTime? currentStreakStart;

  const ShareStreakCameraScreen({
    super.key,
    required this.currentStreak,
    this.currentStreakStart,
  });

  @override
  State<ShareStreakCameraScreen> createState() =>
      _ShareStreakCameraScreenState();
}

class _ShareStreakCameraScreenState extends State<ShareStreakCameraScreen> {
  CameraController? _controller;
  List<CameraDescription> _cameras = [];
  bool _initializing = true;
  String? _error;

  // After capture:
  Uint8List? _capturedBytes;
  bool _isBlackAndWhite = false;
  final GlobalKey _compositeKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _initCamera();
  }

  Future<void> _initCamera() async {
    try {
      _cameras = await availableCameras();
      if (_cameras.isEmpty) {
        setState(() => _error = 'No camera found on this device.');
        return;
      }
      final back = _cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => _cameras.first,
      );
      _controller = CameraController(
        back,
        ResolutionPreset.high,
        enableAudio: false,
      );
      await _controller!.initialize();
      if (!mounted) return;
      setState(() => _initializing = false);
    } catch (e) {
      setState(() => _error = 'Could not open camera: $e');
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _takePhoto() async {
    if (_controller == null || !_controller!.value.isInitialized) return;
    try {
      final shot = await _controller!.takePicture();
      final bytes = await shot.readAsBytes();
      setState(() => _capturedBytes = bytes);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('❌ Could not capture photo: $e')),
      );
    }
  }

  Future<void> _shareComposite() async {
    try {
      final boundary = _compositeKey.currentContext!.findRenderObject()
          as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 3.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      final pngBytes = byteData!.buffer.asUint8List();

      final xFile = XFile.fromData(
        pngBytes,
        mimeType: 'image/png',
        name: 'conquer_club_streak.png',
      );

      await Share.shareXFiles(
        [xFile],
        text: 'CONSISTENCY. DISCIPLINE. RESULTS. — THE CONQUER CLUB',
        subject: 'My Conquer Club Streak',
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('❌ Error sharing: $e')),
      );
    }
  }

  // The gold-frame streak card, drawn as pure widgets — no image asset,
  // so it sits as a genuinely see-through overlay on the camera feed.
  Widget _streakOverlay() {
    final streak = widget.currentStreak;
    return IgnorePointer(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 60),
        child: Container(
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.gold, width: 2),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 24),
                child: Column(
                  children: [
                    const Text(
                      'THE',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        letterSpacing: 3,
                        fontWeight: FontWeight.w600,
                        shadows: [Shadow(blurRadius: 6, color: Colors.black)],
                      ),
                    ),
                    Text(
                      'CONQUER',
                      style: TextStyle(
                        color: AppColors.gold,
                        fontSize: 34,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 2,
                        shadows: const [
                          Shadow(blurRadius: 8, color: Colors.black),
                        ],
                      ),
                    ),
                    const Text(
                      'CLUB',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 4,
                        shadows: [Shadow(blurRadius: 6, color: Colors.black)],
                      ),
                    ),
                  ],
                ),
              ),
              Column(
                children: [
                  Text(
                    streak > 0 ? '🔥 $streak DAY${streak > 1 ? 'S' : ''}' : '🔥 NO STREAK',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 30,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.5,
                      shadows: [Shadow(blurRadius: 8, color: Colors.black)],
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    DateFormat('d-MMM-yyyy').format(DateTime.now()),
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 14,
                      shadows: [Shadow(blurRadius: 4, color: Colors.black)],
                    ),
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 24),
                child: RichText(
                  text: const TextSpan(
                    style: TextStyle(fontSize: 11, letterSpacing: 1),
                    children: [
                      TextSpan(
                        text: 'CONSISTENCY. ',
                        style: TextStyle(color: Colors.white),
                      ),
                      TextSpan(
                        text: 'DISCIPLINE. ',
                        style: TextStyle(color: AppColors.gold),
                      ),
                      TextSpan(
                        text: 'RESULTS.',
                        style: TextStyle(color: Colors.white),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Simple grayscale color matrix for the B&W toggle.
  static const _grayscaleMatrix = <double>[
    0.2126, 0.7152, 0.0722, 0, 0,
    0.2126, 0.7152, 0.0722, 0, 0,
    0.2126, 0.7152, 0.0722, 0, 0,
    0, 0, 0, 1, 0,
  ];

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(backgroundColor: Colors.black),
        body: Center(
          child: Text(_error!, style: const TextStyle(color: Colors.white)),
        ),
      );
    }

    if (_capturedBytes != null) {
      // ── Preview / edit screen ──
      final photo = ColorFiltered(
        colorFilter: _isBlackAndWhite
            ? const ColorFilter.matrix(_grayscaleMatrix)
            : const ColorFilter.mode(Colors.transparent, BlendMode.multiply),
        child: Image.memory(_capturedBytes!, fit: BoxFit.cover),
      );

      return Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: RepaintBoundary(
                  key: _compositeKey,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      photo,
                      _streakOverlay(),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _editButton(
                      icon: Icons.color_lens,
                      label: 'Color',
                      selected: !_isBlackAndWhite,
                      onTap: () => setState(() => _isBlackAndWhite = false),
                    ),
                    _editButton(
                      icon: Icons.filter_b_and_w,
                      label: 'B & W',
                      selected: _isBlackAndWhite,
                      onTap: () => setState(() => _isBlackAndWhite = true),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => setState(() => _capturedBytes = null),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white,
                          side: const BorderSide(color: Colors.white54),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        child: const Text('Retake'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: ElevatedButton(
                        onPressed: _shareComposite,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.gold,
                          foregroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        child: const Text(
                          'Share',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      );
    }

    // ── Camera screen ──
    return Scaffold(
      backgroundColor: Colors.black,
      body: _initializing
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.gold),
            )
          : Stack(
              fit: StackFit.expand,
              children: [
                CameraPreview(_controller!),
                _streakOverlay(),
                SafeArea(
                  child: Align(
                    alignment: Alignment.topLeft,
                    child: IconButton(
                      icon: const Icon(Icons.close, color: Colors.white, size: 28),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ),
                ),
                SafeArea(
                  child: Align(
                    alignment: Alignment.bottomCenter,
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 24),
                      child: GestureDetector(
                        onTap: _takePhoto,
                        child: Container(
                          width: 72,
                          height: 72,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 4),
                          ),
                          child: Container(
                            margin: const EdgeInsets.all(4),
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              color: AppColors.gold,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _editButton({
    required IconData icon,
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: selected ? AppColors.gold : Colors.white12,
            ),
            child: Icon(icon, color: selected ? Colors.black : Colors.white),
          ),
          const SizedBox(height: 4),
          Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12)),
        ],
      ),
    );
  }
}
