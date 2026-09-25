import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../providers/master_data_provider.dart';
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
  static const _instagramChannel =
      MethodChannel('com.conquerclub.app/instagram_share');

  CameraController? _controller;
  List<CameraDescription> _cameras = [];
  bool _initializing = true;
  String? _error;

  // After capture:
  Uint8List? _capturedBytes;
  bool _isBlackAndWhite = false;
  final GlobalKey _compositeKey = GlobalKey();
  String? _workoutName;

  @override
  void initState() {
    super.initState();
    _initCamera();
    _loadWorkoutName();
  }

  Future<void> _loadWorkoutName() async {
    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) return;
      final dashboardData =
          await MasterDataProvider.instance.fetchMemberData(userId);
      if (!mounted) return;
      setState(() {
        _workoutName = dashboardData.todayWorkout?['workout_name'] as String?;
      });
    } catch (_) {}
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

  // Shared by both destinations — renders the photo + overlay into one PNG.
  Future<Uint8List> _renderComposite() async {
    final boundary = _compositeKey.currentContext!.findRenderObject()
        as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 3.0);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    return byteData!.buffer.asUint8List();
  }

  // "Status" — normal share sheet, every app (WhatsApp, Snapchat, Instagram, etc.)
  Future<void> _shareStatus() async {
    try {
      final pngBytes = await _renderComposite();
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

  // "Feed" — opens Instagram directly, skipping the app picker (Android).
  // Falls back to the normal share sheet if Instagram isn't installed,
  // or on iOS where this direct-targeting trick isn't available.
  Future<void> _shareFeed() async {
    try {
      final pngBytes = await _renderComposite();
      final tempDir = await getTemporaryDirectory();
      final file = File('${tempDir.path}/conquer_club_feed.png');
      await file.writeAsBytes(pngBytes);

      bool openedInstagram = false;
      if (Platform.isAndroid) {
        try {
          openedInstagram = await _instagramChannel.invokeMethod<bool>(
                'shareToInstagramFeed',
                {'path': file.path},
              ) ??
              false;
        } catch (_) {
          openedInstagram = false;
        }
      }

      if (!openedInstagram) {
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
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('❌ Error sharing: $e')),
      );
    }
  }

  // ── Top header: "THE CONQUER CLUB", sitting a little lower than before, ──
  // ── with a translucent dark panel behind just this text block. ──
  Widget _topHeader() {
    return Padding(
      padding: const EdgeInsets.only(top: 24),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 24),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.18),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'THE',
              style: TextStyle(
                color: Colors.white,
                fontSize: 13,
                letterSpacing: 3,
                fontWeight: FontWeight.w600,
                shadows: [Shadow(blurRadius: 6, color: Colors.black)],
              ),
            ),
            const SizedBox(height: 2),
            Text(
              'CONQUER',
              style: TextStyle(
                color: AppColors.gold,
                fontSize: 22,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.5,
                shadows: const [Shadow(blurRadius: 8, color: Colors.black)],
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(width: 28, height: 1.5, color: AppColors.gold),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Text(
                    'CLUB',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 3,
                      shadows: const [
                        Shadow(blurRadius: 6, color: Colors.black),
                      ],
                    ),
                  ),
                ),
                Container(width: 28, height: 1.5, color: AppColors.gold),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // Shows today's workout name (as stored, unmodified) on weekdays, or
  // "TASK COMPLETED" on Sunday once the Sunday streak requirement is met.
  Widget _workoutOrTaskRow() {
    final now = DateTime.now();
    if (now.weekday == DateTime.sunday) {
      if (widget.currentStreak <= 0) return const SizedBox.shrink();
      return const Padding(
        padding: EdgeInsets.only(top: 4),
        child: Row(
          children: [
            SizedBox(
                width: 24,
                child:
                    Icon(Icons.check_circle, color: AppColors.gold, size: 12)),
            SizedBox(width: 10),
            Text(
              'TASK COMPLETED',
              style: TextStyle(
                color: AppColors.gold,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      );
    }
    if (_workoutName == null || _workoutName!.trim().isEmpty) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        children: [
          const SizedBox(
              width: 24,
              child:
                  Icon(Icons.fitness_center, color: AppColors.gold, size: 14)),
          const SizedBox(width: 10),
          Expanded(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                _workoutName!,
                style: const TextStyle(
                  color: AppColors.gold,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Streak sticker: app icon, streak/progress, date/day, workout ──
  Widget _bottomStatCard() {
    final streak = widget.currentStreak;
    final now = DateTime.now();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 18),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.78),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: AppColors.gold,
            width: 2.5,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            FittedBox(
              fit: BoxFit.scaleDown,
              child: SizedBox(
                width: 460,
                child: Row(
                  children: [
                    // Left: app logo
                    SizedBox(
                      width: 52,
                      height: 52,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          Image.asset(
                            'assets/images/app_logo.png',
                            fit: BoxFit.contain,
                            errorBuilder: (context, error, stacktrace) {
                              debugPrint('❌ logo load failed: $error');
                              return const Icon(Icons.error,
                                  color: Colors.red, size: 32);
                            },
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    Container(
                      width: 1,
                      height: 70,
                      color: Colors.white.withOpacity(0.25),
                    ),
                    const SizedBox(width: 12),

                    // Middle: streak + progress
                    Expanded(
                      flex: 5,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Text(
                              streak > 0
                                  ? '$streak DAY${streak > 1 ? 'S' : ''} STREAK'
                                  : 'NO STREAK',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 21,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.5,
                                shadows: [
                                  Shadow(blurRadius: 6, color: Colors.black),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            streak > 0 ? 'GOOD PROGRESS' : '',
                            style: const TextStyle(
                              color: AppColors.gold,
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1,
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(width: 12),
                    Container(
                      width: 1,
                      height: 70,
                      color: Colors.white.withOpacity(0.25),
                    ),
                    const SizedBox(width: 12),

                    // Right: date/day + today's workout
                    Expanded(
                      flex: 7,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            children: [
                              const Icon(
                                Icons.calendar_today,
                                color: AppColors.gold,
                                size: 24,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  DateFormat('dd-MMM-yyyy')
                                      .format(now)
                                      .toUpperCase(),
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Padding(
                            padding: const EdgeInsets.only(left: 34),
                            child: Text(
                              DateFormat('EEEE').format(now).toUpperCase(),
                              style: const TextStyle(
                                color: Colors.white54,
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                                letterSpacing: 0.8,
                              ),
                            ),
                          ),
                          _workoutOrTaskRow(),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 6),
            _tagline(),
          ],
        ),
      ),
    );
  }

  Widget _tagline() {
    return RichText(
      textAlign: TextAlign.center,
      text: TextSpan(
        style: const TextStyle(fontSize: 9, letterSpacing: 1),
        children: [
          const TextSpan(
              text: 'CONSISTENCY. ', style: TextStyle(color: Colors.white)),
          TextSpan(
              text: 'DISCIPLINE. ', style: TextStyle(color: AppColors.gold)),
          const TextSpan(
              text: 'RESULTS.', style: TextStyle(color: Colors.white)),
        ],
      ),
    );
  }

  Widget _streakOverlay() {
    return IgnorePointer(
      child: SafeArea(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _topHeader(),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _bottomStatCard(),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // Simple grayscale color matrix for the B&W toggle.
  static const _grayscaleMatrix = <double>[
    0.2126,
    0.7152,
    0.0722,
    0,
    0,
    0.2126,
    0.7152,
    0.0722,
    0,
    0,
    0.2126,
    0.7152,
    0.0722,
    0,
    0,
    0,
    0,
    0,
    1,
    0,
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
              SingleChildScrollView(
                // Wrapped so these controls never overflow on shorter
                // screens — they scroll instead of erroring.
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          _editButton(
                            icon: Icons.color_lens,
                            label: 'Color',
                            selected: !_isBlackAndWhite,
                            onTap: () =>
                                setState(() => _isBlackAndWhite = false),
                          ),
                          _editButton(
                            icon: Icons.filter_b_and_w,
                            label: 'B & W',
                            selected: _isBlackAndWhite,
                            onTap: () =>
                                setState(() => _isBlackAndWhite = true),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      child: Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () =>
                                  setState(() => _capturedBytes = null),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.white,
                                side: const BorderSide(color: Colors.white54),
                                padding:
                                    const EdgeInsets.symmetric(vertical: 14),
                              ),
                              child: const Text('Retake'),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: OutlinedButton(
                              onPressed: _shareStatus,
                              style: OutlinedButton.styleFrom(
                                foregroundColor: AppColors.gold,
                                side: BorderSide(color: AppColors.gold),
                                padding:
                                    const EdgeInsets.symmetric(vertical: 14),
                              ),
                              child: const Text(
                                'Status',
                                style: TextStyle(fontWeight: FontWeight.bold),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: ElevatedButton(
                              onPressed: _shareFeed,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.gold,
                                foregroundColor: Colors.black,
                                padding:
                                    const EdgeInsets.symmetric(vertical: 14),
                              ),
                              child: const Text(
                                'Feed',
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
                      icon: const Icon(Icons.close,
                          color: Colors.white, size: 28),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ),
                ),
                SafeArea(
                  child: Align(
                    alignment: Alignment.bottomCenter,
                    child: Padding(
                      padding: EdgeInsets.only(
                        bottom: MediaQuery.of(context).size.height * 0.18,
                      ),
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
          Text(label,
              style: const TextStyle(color: Colors.white70, fontSize: 12)),
        ],
      ),
    );
  }
}
