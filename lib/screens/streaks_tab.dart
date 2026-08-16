import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../theme/app_theme.dart';
import 'package:share_plus/share_plus.dart';

// Simple StreakModel defined inline
class StreakModel {
  final String id;
  final String memberId;
  final DateTime date;
  final bool isWorkoutCompleted;
  final bool isPhotosUploaded;
  final bool isMeasurementsUpdated;
  final int workoutMinutes;
  final bool isSunday;
  final bool isStreakMet;

  StreakModel({
    required this.id,
    required this.memberId,
    required this.date,
    required this.isWorkoutCompleted,
    required this.isPhotosUploaded,
    required this.isMeasurementsUpdated,
    required this.workoutMinutes,
    required this.isSunday,
    required this.isStreakMet,
  });

  factory StreakModel.fromJson(Map<String, dynamic> json) {
    return StreakModel(
      id: json['id'],
      memberId: json['member_id'],
      date: DateTime.parse(json['date']),
      isWorkoutCompleted: json['is_workout_completed'] ?? false,
      isPhotosUploaded: json['is_photos_uploaded'] ?? false,
      isMeasurementsUpdated: json['is_measurements_updated'] ?? false,
      workoutMinutes: json['workout_minutes'] ?? 0,
      isSunday: json['is_sunday'] ?? false,
      isStreakMet: json['is_streak_met'] ?? false,
    );
  }
}

class StreaksTab extends StatefulWidget {
  const StreaksTab({super.key});

  @override
  State<StreaksTab> createState() => _StreaksTabState();
}

class _StreaksTabState extends State<StreaksTab> {
  List<StreakModel> _streaks = [];
  Map<String, dynamic> _stats = {};
  bool _isLoading = true;
  String _filter = 'all'; // all, streak, missed

  // Used to capture the composited share image (background + overlay text)
  final GlobalKey _shareImageKey = GlobalKey();

  // Native channel: opens directly into the Instagram Stories editor or
  // Snapchat's send flow with the image pre-loaded, instead of the
  // generic OS share sheet. See MainActivity.kt / AppDelegate.swift.
  static const MethodChannel _socialShareChannel = MethodChannel(
    'com.conquerclub.app/social_share',
  );

  static const String _fallbackQuote =
      'Consistency. Discipline. Results. Keep conquering.';

  // Fetches today's motivational quote from Supabase based on the
  // member's current streak day (day 1-100, cycling after day 100).
  Future<String> _fetchDailyQuote(int streakDay) async {
    final dayNumber = ((streakDay - 1) % 100) + 1;
    try {
      final row = await Supabase.instance.client
          .from('daily_quotes')
          .select('quote')
          .eq('day_number', dayNumber)
          .maybeSingle();
      return (row?['quote'] as String?) ?? _fallbackQuote;
    } catch (e) {
      return _fallbackQuote;
    }
  }

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final userId = Supabase.instance.client.auth.currentUser!.id;
      final today = DateTime.now();
      final todayStr = today.toIso8601String().substring(0, 10);
      final isSunday = today.weekday == DateTime.sunday;

      // 1. Update today's streak record
      final startOfDay = DateTime(today.year, today.month, today.day).toUtc();

      // Check workout completion (>= 45 minutes)
      final workoutSession = await Supabase.instance.client
          .from('workout_sessions')
          .select('elapsed_seconds')
          .eq('member_id', userId)
          .eq('status', 'completed')
          .gte('started_at', startOfDay.toIso8601String())
          .maybeSingle();

      bool workoutCompleted = false;
      int workoutMinutes = 0;
      if (workoutSession != null) {
        final elapsedSeconds =
            (workoutSession['elapsed_seconds'] as num?)?.toInt() ?? 0;
        workoutMinutes = (elapsedSeconds / 60).round();
        workoutCompleted = workoutMinutes >= 45;
      }

      // For Sunday, check photos and measurements
      bool photosUploaded = false;
      bool measurementsUpdated = false;

      if (isSunday) {
        // Check after photos
        final photos = await Supabase.instance.client
            .from('member_progress_photos')
            .select('after_front_updated_at, after_back_updated_at')
            .eq('member_id', userId)
            .maybeSingle();

        if (photos != null) {
          final frontDate = photos['after_front_updated_at'] != null
              ? DateTime.tryParse(photos['after_front_updated_at'])
              : null;
          final backDate = photos['after_back_updated_at'] != null
              ? DateTime.tryParse(photos['after_back_updated_at'])
              : null;

          photosUploaded = frontDate != null &&
              frontDate.year == today.year &&
              frontDate.month == today.month &&
              frontDate.day == today.day &&
              backDate != null &&
              backDate.year == today.year &&
              backDate.month == today.month &&
              backDate.day == today.day;
        }

        // Check measurements
        final measurement = await Supabase.instance.client
            .from('measurement_logs')
            .select('id')
            .eq('member_id', userId)
            .gte('recorded_at', startOfDay.toIso8601String())
            .maybeSingle();

        measurementsUpdated = measurement != null;
      }

      // Determine if streak is met
      bool isStreakMet;
      if (isSunday) {
        isStreakMet = photosUploaded && measurementsUpdated;
      } else {
        isStreakMet = workoutCompleted;
      }

      // Upsert today's streak record
      await Supabase.instance.client.from('member_streaks').upsert({
        'member_id': userId,
        'date': todayStr,
        'is_workout_completed': workoutCompleted,
        'is_steps_completed': false,
        'is_photos_uploaded': photosUploaded,
        'is_measurements_updated': measurementsUpdated,
        'workout_minutes': workoutMinutes,
        'steps_count': 0,
        'is_sunday': isSunday,
        'is_streak_met': isStreakMet,
        'updated_at': DateTime.now().toIso8601String(),
      }, onConflict: 'member_id,date');

      // 2. Get all streak history
      final response = await Supabase.instance.client
          .from('member_streaks')
          .select()
          .eq('member_id', userId)
          .order('date', ascending: false);

      final List<StreakModel> history = [];
      int currentStreak = 0;
      int highestStreak = 0;
      int totalStreaks = 0;
      int totalDays = 0;
      DateTime? currentStreakStart;

      for (var record in response) {
        final streak = StreakModel.fromJson(record);
        history.add(streak);

        if (streak.isStreakMet) {
          currentStreak++;
          currentStreakStart ??= streak.date;
        } else {
          break;
        }
      }

      // Calculate highest streak
      int tempStreak = 0;
      for (var streak in history) {
        if (streak.isStreakMet) {
          tempStreak++;
          highestStreak =
              highestStreak > tempStreak ? highestStreak : tempStreak;
        } else {
          tempStreak = 0;
        }
      }

      totalDays = history.length;
      for (var streak in history) {
        if (streak.isStreakMet) totalStreaks++;
      }
      final streakRate =
          totalDays > 0 ? (totalStreaks / totalDays * 100).round() : 0;

      setState(() {
        _streaks = history;
        _stats = {
          'history': history,
          'currentStreak': currentStreak,
          'currentStreakStart': currentStreakStart,
          'highestStreak': highestStreak,
          'totalStreaks': totalStreaks,
          'streakRate': streakRate,
        };
        _isLoading = false;
      });
    } catch (e) {
      print('Error loading streak data: $e');
      setState(() => _isLoading = false);
    }
  }

  List<StreakModel> get _filteredStreaks {
    if (_filter == 'all') return _streaks;
    if (_filter == 'streak') {
      return _streaks.where((s) => s.isStreakMet).toList();
    }
    return _streaks.where((s) => !s.isStreakMet).toList();
  }

  void _shareStreak(BuildContext context) {
    final currentStreak = _stats['currentStreak'] ?? 0;
    final currentStreakStart = _stats['currentStreakStart'] as DateTime?;
    final highestStreak = _stats['highestStreak'] ?? 0;
    final streakRate = _stats['streakRate'] ?? 0;
    final totalStreaks = _stats['totalStreaks'] ?? 0;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(16),
        child: Container(
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF1a1a1a), Color(0xFF0d0d0d)],
            ),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColors.gold.withOpacity(0.3)),
            boxShadow: [
              BoxShadow(
                color: AppColors.gold.withOpacity(0.1),
                blurRadius: 20,
                spreadRadius: 5,
              ),
            ],
          ),
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text('🔥', style: TextStyle(fontSize: 32)),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        currentStreak > 0
                            ? '$currentStreak DAYS'
                            : 'NO ACTIVE STREAK',
                        style: const TextStyle(
                          color: AppColors.gold,
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.2,
                        ),
                      ),
                      if (currentStreakStart != null && currentStreak > 0)
                        Text(
                          'Started: ${DateFormat('MMM d, yyyy').format(currentStreakStart)}',
                          style: const TextStyle(
                            color: Colors.grey,
                            fontSize: 12,
                          ),
                        ),
                    ],
                  ),
                ],
              ),

              const SizedBox(height: 20),

              // Divider
              Container(height: 1, color: Colors.white.withOpacity(0.1)),

              const SizedBox(height: 20),

              // Stats Grid
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _shareStatItem('🏆', '$highestStreak', 'Best Streak'),
                  _shareStatItem('📊', '$streakRate%', 'Success Rate'),
                  _shareStatItem('✅', '$totalStreaks', 'Total Streaks'),
                ],
              ),

              const SizedBox(height: 20),

              // Tagline
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: AppColors.gold.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: AppColors.gold.withOpacity(0.2),
                  ),
                ),
                child: const Text(
                  'CONSISTENCY. DISCIPLINE. RESULTS.',
                  style: TextStyle(
                    color: AppColors.gold,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 2,
                  ),
                ),
              ),

              const SizedBox(height: 12),

              // Gym Name
              const Text(
                'THE CONQUER CLUB',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1.5,
                ),
              ),

              const SizedBox(height: 20),

              // Action Buttons
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(dialogContext),
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: Colors.grey.shade700),
                        foregroundColor: Colors.grey,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.pop(dialogContext);
                        _postShare(context);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.gold,
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: const Text(
                        'Post',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _shareStatItem(String icon, String value, String label) {
    return Column(
      children: [
        Text(icon, style: const TextStyle(fontSize: 22)),
        const SizedBox(height: 2),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(label, style: const TextStyle(color: Colors.grey, fontSize: 10)),
      ],
    );
  }

  void _postShare(BuildContext context) {
    _showShareOptions(context);
  }

  void _showShareOptions(BuildContext context) {
    final currentStreak = _stats['currentStreak'] ?? 0;
    final currentStreakStart = _stats['currentStreakStart'] as DateTime?;
    final highestStreak = _stats['highestStreak'] ?? 0;
    final streakRate = _stats['streakRate'] ?? 0;
    final totalStreaks = _stats['totalStreaks'] ?? 0;

    final String shareText = '''
🔥 MY CONQUER STREAK

${currentStreak > 0 ? '$currentStreak DAYS' : 'NO ACTIVE STREAK'}${currentStreakStart != null && currentStreak > 0 ? '\nStarted: ${DateFormat('MMM d, yyyy').format(currentStreakStart)}' : ''}

🏆 Best Streak: $highestStreak
📊 Success Rate: $streakRate%
✅ Total Streaks: $totalStreaks

CONSISTENCY. DISCIPLINE. RESULTS.

THE CONQUER CLUB
''';

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => Container(
        decoration: const BoxDecoration(
          color: Color(0xFF1a1a1a),
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(20),
            topRight: Radius.circular(20),
          ),
        ),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade600,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Share Your Streak',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            _shareOptionTile(
              icon: Icons.photo_library,
              title: 'Instagram Story',
              subtitle: 'Share as a story with background image',
              onTap: () {
                Navigator.pop(sheetContext);
                _shareWithImage(context, 'instagram_story', shareText);
              },
            ),
            const Divider(color: Colors.grey, height: 1),
            _shareOptionTile(
              icon: Icons.grid_on,
              title: 'Instagram Post',
              subtitle: 'Share as a feed post',
              onTap: () {
                Navigator.pop(sheetContext);
                _shareWithImage(context, 'instagram_post', shareText);
              },
            ),
            const Divider(color: Colors.grey, height: 1),
            _shareOptionTile(
              icon: Icons.chat_bubble_outline,
              title: 'Snapchat',
              subtitle: 'Send as a snap',
              onTap: () {
                Navigator.pop(sheetContext);
                _shareWithImage(context, 'snapchat', shareText);
              },
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => Navigator.pop(sheetContext),
              child: const Text(
                'Cancel',
                style: TextStyle(color: Colors.grey),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _shareOptionTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: AppColors.gold.withOpacity(0.1),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: AppColors.gold),
      ),
      title: Text(
        title,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w600,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
      ),
      trailing: const Icon(
        Icons.arrow_forward_ios,
        color: Colors.grey,
        size: 16,
      ),
      onTap: onTap,
    );
  }

  Future<void> _shareWithImage(
    BuildContext context,
    String platform,
    String shareText,
  ) async {
    final currentStreak = _stats['currentStreak'] ?? 0;
    final currentStreakStart = _stats['currentStreakStart'] as DateTime?;
    final highestStreak = _stats['highestStreak'] ?? 0;
    final streakRate = _stats['streakRate'] ?? 0;
    final totalStreaks = _stats['totalStreaks'] ?? 0;

    // Show loading
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Preparing for $platform...'),
        backgroundColor: AppColors.gold,
      ),
    );

    try {
      // Background image from Supabase storage (public bucket: streak_share)
      final String imageUrl =
          'https://dafbinwvwxuekdomdmro.supabase.co/storage/v1/object/public/streak_share/background.jpg';

      // Fetch the motivational quote for the current streak day from Supabase
      final dayNumber = currentStreak > 0 ? currentStreak : 1;
      final quote = await _fetchDailyQuote(dayNumber);

      if (!context.mounted) return;

      // Force full decode before showing — avoids RepaintBoundary
      // capturing/painting a partial/stale frame of the network image.
      await precacheImage(NetworkImage(imageUrl), context);

      if (!context.mounted) return;

      // Show preview with image
      _showImagePreview(
        context,
        imageUrl,
        currentStreak,
        currentStreakStart,
        highestStreak,
        streakRate,
        totalStreaks,
        platform,
        shareText,
        quote,
      );
    } catch (e) {
      // Fallback to text share
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Unable to load image. Sharing text instead.'),
          backgroundColor: Colors.orange,
        ),
      );
      // Share text directly
      await Share.share(shareText);
    }
  }

  void _showImagePreview(
    BuildContext context,
    String imageUrl,
    int currentStreak,
    DateTime? currentStreakStart,
    int highestStreak,
    int streakRate,
    int totalStreaks,
    String platform,
    String shareText,
    String quote,
  ) {
    final int dayNumber =
        currentStreak > 0 ? (((currentStreak - 1) % 100) + 1) : 1;
    final String todayStr = DateFormat(
      'EEEE, MMM d, yyyy',
    ).format(DateTime.now());

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(16),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400, maxHeight: 640),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // The composited card below is exactly what gets captured and
              // shared as an image, so nothing outside RepaintBoundary
              // (buttons, platform badge) ends up in the shared file.
              Flexible(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: RepaintBoundary(
                    key: _shareImageKey,
                    child: AspectRatio(
                      // Matches the exact 1024x1536 background image so the
                      // fractional frame coordinates below line up with the
                      // yellow box printed on the image.
                      aspectRatio: 1024 / 1536,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          Image.network(
                            imageUrl,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) =>
                                Container(color: Colors.black),
                          ),
                          LayoutBuilder(
                            builder: (context, constraints) {
                              final w = constraints.maxWidth;
                              final h = constraints.maxHeight;
                              // Measured empty interior of the yellow frame
                              // on background.jpg, as fractions of the
                              // full 1024x1536 image. Top pushed down to
                              // clear "BY ABHISHEK MOHITE" baked into image.
                              return Positioned(
                                left: w * 0.127,
                                top: h * 0.306,
                                width: w * 0.718,
                                height: h * 0.488,
                                child: Container(
                                  color: Colors.red.withOpacity(
                                    0.3,
                                  ), // TEMP DEBUG — remove after test
                                  child: _buildFrameContent(
                                    currentStreak: currentStreak,
                                    currentStreakStart: currentStreakStart,
                                    todayStr: todayStr,
                                    dayNumber: dayNumber,
                                    quote: quote,
                                  ),
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 14),

              // Platform badge
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.6),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.white.withOpacity(0.1)),
                ),
                child: Text(
                  'Sharing to: $platform',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.8),
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),

              const SizedBox(height: 12),

              // Action buttons
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(
                          color: Colors.white.withOpacity(0.4),
                          width: 1.5,
                        ),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        backgroundColor: Colors.black.withOpacity(0.3),
                      ),
                      child: const Text(
                        'Cancel',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () =>
                          _confirmShare(context, platform, shareText),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.gold,
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 4,
                      ),
                      child: const Text(
                        'Share Now',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 14,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Everything the member's streak card shows, laid out to fit entirely
  // inside the yellow frame printed on background.jpg.
  Widget _buildFrameContent({
    required int currentStreak,
    required DateTime? currentStreakStart,
    required String todayStr,
    required int dayNumber,
    required String quote,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisSize: MainAxisSize.max,
        children: [
          const Text('🔥', style: TextStyle(fontSize: 40)),
          const SizedBox(height: 4),
          Text(
            currentStreak > 0 ? '$currentStreak' : '0',
            style: const TextStyle(
              color: AppColors.gold,
              fontSize: 56,
              fontWeight: FontWeight.w900,
              height: 1.0,
              shadows: [
                Shadow(
                  offset: Offset(0, 3),
                  blurRadius: 8,
                  color: Colors.black,
                ),
                Shadow(
                  offset: Offset(0, 6),
                  blurRadius: 14,
                  color: Colors.black54,
                ),
              ],
            ),
          ),
          const Text(
            'DAY STREAK',
            style: TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w800,
              letterSpacing: 3,
              shadows: [
                Shadow(
                  offset: Offset(0, 2),
                  blurRadius: 6,
                  color: Colors.black,
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          if (currentStreakStart != null && currentStreak > 0)
            Text(
              'Since ${DateFormat('MMM d, yyyy').format(currentStreakStart)}',
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 13,
                fontWeight: FontWeight.w500,
                shadows: [
                  Shadow(
                    offset: Offset(0, 1),
                    blurRadius: 3,
                    color: Colors.black,
                  ),
                ],
              ),
            ),
          Text(
            todayStr,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 13,
              fontWeight: FontWeight.w500,
              shadows: [
                Shadow(
                  offset: Offset(0, 1),
                  blurRadius: 3,
                  color: Colors.black,
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          Container(
            width: 50,
            height: 2,
            color: AppColors.gold.withOpacity(0.8),
          ),
          const SizedBox(height: 18),
          Text(
            'DAY $dayNumber OF 100',
            style: const TextStyle(
              color: AppColors.gold,
              fontSize: 12,
              fontWeight: FontWeight.w800,
              letterSpacing: 2,
              shadows: [
                Shadow(
                  offset: Offset(0, 1),
                  blurRadius: 3,
                  color: Colors.black,
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Flexible(
            child: Text(
              '"$quote"',
              textAlign: TextAlign.center,
              maxLines: 6,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Colors.white,
                fontSize: quote.length <= 45
                    ? 17
                    : quote.length <= 75
                        ? 15
                        : quote.length <= 105
                            ? 13
                            : 11.5,
                fontStyle: FontStyle.italic,
                fontWeight: FontWeight.w500,
                height: 1.35,
                shadows: const [
                  Shadow(
                    offset: Offset(0, 2),
                    blurRadius: 6,
                    color: Colors.black,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmShare(
    BuildContext context,
    String platform,
    String shareText,
  ) async {
    // Capture the composited image WHILE the preview dialog is still
    // mounted — the RepaintBoundary is disposed as soon as we pop it.
    Uint8List? pngBytes;
    try {
      final boundary = _shareImageKey.currentContext?.findRenderObject()
          as RenderRepaintBoundary?;
      if (boundary != null) {
        final image = await boundary.toImage(pixelRatio: 3.0);
        final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
        pngBytes = byteData?.buffer.asUint8List();
      }
    } catch (e) {
      debugPrint('Failed to capture streak image: $e');
    }

    Navigator.pop(context); // close the preview dialog

    if (pngBytes == null) {
      // Couldn't capture the image at all — fall back to text-only share.
      await Share.share(shareText, subject: 'My Conquer Club Streak');
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('📤 Sharing to $platform...'),
        backgroundColor: AppColors.gold,
        duration: const Duration(seconds: 1),
      ),
    );

    try {
      final tempDir = await getTemporaryDirectory();
      final file = File(
        '${tempDir.path}/conquer_club_streak_${DateTime.now().millisecondsSinceEpoch}.png',
      );
      await file.writeAsBytes(pngBytes);

      bool openedNatively = false;

      if (platform == 'instagram_story') {
        openedNatively = await _shareToInstagramStoryNative(file.path);
      } else if (platform == 'snapchat') {
        openedNatively = await _shareToSnapchatNative(file.path);
      }

      if (!openedNatively) {
        // Native deep-link into the app wasn't available (app not
        // installed, iOS Snapchat has no such API, or the platform
        // channel isn't set up) — fall back to the generic OS share
        // sheet. Instagram/Snapchat only consume the media itself, so
        // for these two we share the image alone (no caption text),
        // otherwise both apps tend to surface the text and drop the
        // image entirely.
        final bool isStoryPlatform =
            platform == 'instagram_story' || platform == 'snapchat';
        if (isStoryPlatform) {
          await Share.shareXFiles([XFile(file.path)]);
        } else {
          await Share.shareXFiles(
            [XFile(file.path)],
            text: shareText,
            subject: 'My Conquer Club Streak',
          );
        }
      }

      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ Shared successfully!'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 2),
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('❌ Error sharing: $e'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  // Returns true if Instagram's Story editor was actually opened with the
  // image loaded. Returns false (never throws) if Instagram isn't
  // installed or the native channel isn't wired up yet, so the caller can
  // fall back to the generic share sheet.
  Future<bool> _shareToInstagramStoryNative(String imagePath) async {
    try {
      final result = await _socialShareChannel.invokeMethod<bool>(
        'shareToInstagramStory',
        {'imagePath': imagePath},
      );
      return result ?? false;
    } on MissingPluginException {
      return false; // native side not implemented for this platform yet
    } catch (e) {
      debugPrint('Instagram native share failed: $e');
      return false;
    }
  }

  // Returns true if Snapchat was actually opened with the image loaded
  // (Android only — iOS has no non-SDK way to do this, see
  // AppDelegate.swift). Returns false otherwise so the caller falls back
  // to the generic share sheet.
  Future<bool> _shareToSnapchatNative(String imagePath) async {
    try {
      final result = await _socialShareChannel.invokeMethod<bool>(
        'shareToSnapchat',
        {'imagePath': imagePath},
      );
      return result ?? false;
    } on MissingPluginException {
      return false;
    } catch (e) {
      debugPrint('Snapchat native share failed: $e');
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'My Streaks',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _loadData),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.gold),
            )
          : RefreshIndicator(
              onRefresh: _loadData,
              color: AppColors.gold,
              backgroundColor: AppColors.cardDark,
              child: CustomScrollView(
                slivers: [
                  // Stats Banner
                  SliverToBoxAdapter(child: _buildStatsBanner()),

                  // Filter Tabs
                  SliverToBoxAdapter(
                    child: Container(
                      margin: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.cardDark,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        children: [
                          _buildFilterChip('All', 'all'),
                          _buildFilterChip('🔥 Streaks', 'streak'),
                          _buildFilterChip('❌ Missed', 'missed'),
                        ],
                      ),
                    ),
                  ),

                  // Streak List
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                    sliver: _filteredStreaks.isEmpty
                        ? SliverFillRemaining(
                            child: Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.calendar_today,
                                    color: Colors.grey.shade600,
                                    size: 48,
                                  ),
                                  const SizedBox(height: 12),
                                  Text(
                                    'No streak data yet',
                                    style: TextStyle(
                                      color: Colors.grey.shade500,
                                      fontSize: 16,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Complete your workouts to start building streaks!',
                                    style: TextStyle(
                                      color: Colors.grey.shade400,
                                      fontSize: 12,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                ],
                              ),
                            ),
                          )
                        : SliverList(
                            delegate: SliverChildBuilderDelegate(
                              (context, index) => _StreakCard(
                                streak: _filteredStreaks[index],
                              ),
                              childCount: _filteredStreaks.length,
                            ),
                          ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildStatsBanner() {
    final currentStreak = _stats['currentStreak'] ?? 0;
    final highestStreak = _stats['highestStreak'] ?? 0;
    final streakRate = _stats['streakRate'] ?? 0;
    final totalStreaks = _stats['totalStreaks'] ?? 0;
    final currentStreakStart = _stats['currentStreakStart'] as DateTime?;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            currentStreak > 0
                ? AppColors.gold.withOpacity(0.2)
                : AppColors.cardDark,
            AppColors.cardDark,
          ],
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: currentStreak > 0
              ? AppColors.gold.withOpacity(0.3)
              : Colors.white.withOpacity(0.05),
        ),
      ),
      child: Column(
        children: [
          // Current Streak - Big Display
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                currentStreak > 0 ? '🔥' : '⏳',
                style: const TextStyle(fontSize: 32),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    currentStreak > 0
                        ? '$currentStreak Day Streak'
                        : 'No Active Streak',
                    style: TextStyle(
                      color: currentStreak > 0 ? AppColors.gold : Colors.grey,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (currentStreakStart != null)
                    Text(
                      'Since ${DateFormat('MMM d, yyyy').format(currentStreakStart)}',
                      style: const TextStyle(color: Colors.grey, fontSize: 12),
                    ),
                ],
              ),
            ],
          ),

          const SizedBox(height: 16),

          // Stats Row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _statItem('🏆', '$highestStreak', 'Best Streak'),
              _statItem('📊', '$streakRate%', 'Success Rate'),
              _statItem('✅', '$totalStreaks', 'Total Streaks'),
            ],
          ),

          const SizedBox(height: 12),

          // Share Button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () => _shareStreak(context),
              icon: const Icon(Icons.share, size: 18),
              label: const Text(
                'Share Your Streak',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.gold,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _statItem(String icon, String value, String label) {
    return Column(
      children: [
        Text(icon, style: const TextStyle(fontSize: 20)),
        const SizedBox(height: 2),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(label, style: const TextStyle(color: Colors.grey, fontSize: 10)),
      ],
    );
  }

  Widget _buildFilterChip(String label, String value) {
    final isSelected = _filter == value;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _filter = value),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isSelected
                ? AppColors.gold.withOpacity(0.15)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: isSelected ? AppColors.gold : Colors.grey,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              fontSize: 13,
            ),
          ),
        ),
      ),
    );
  }
}

class _StreakCard extends StatelessWidget {
  final StreakModel streak;

  const _StreakCard({required this.streak});

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('EEEE, MMM d, yyyy');
    final isSuccess = streak.isStreakMet;
    final isSunday = streak.isSunday;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.cardDark,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isSuccess
              ? Colors.green.withOpacity(0.2)
              : Colors.red.withOpacity(0.1),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: isSuccess ? Colors.green : Colors.red,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  dateFormat.format(streak.date),
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
              ),
              if (isSunday)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.gold.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'Sunday',
                    style: TextStyle(
                      color: AppColors.gold,
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: isSuccess
                      ? Colors.green.withOpacity(0.15)
                      : Colors.red.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  isSuccess ? '✅ Streak!' : '❌ Missed',
                  style: TextStyle(
                    color: isSuccess ? Colors.green : Colors.red,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 10),

          // Details - Only show workout for weekdays, photos+measurements for Sunday
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _detailChip(
                '🏋️ ${streak.workoutMinutes} min',
                streak.isWorkoutCompleted,
              ),
              if (isSunday) ...[
                _detailChip('📸 Photos', streak.isPhotosUploaded),
                _detailChip('📏 Measurements', streak.isMeasurementsUpdated),
              ],
            ],
          ),

          // Sunday Requirement Note
          if (isSunday) ...[
            const SizedBox(height: 6),
            Text(
              'Sunday requirements: 2 After Photos + Measurements',
              style: TextStyle(
                color: Colors.grey.shade600,
                fontSize: 10,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _detailChip(String label, bool isCompleted) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: isCompleted
            ? Colors.green.withOpacity(0.1)
            : Colors.red.withOpacity(0.08),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: isCompleted
              ? Colors.green.withOpacity(0.2)
              : Colors.red.withOpacity(0.15),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isCompleted ? Icons.check_circle : Icons.cancel,
            size: 12,
            color: isCompleted ? Colors.green : Colors.red,
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: isCompleted ? Colors.green : Colors.red,
              fontSize: 10,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
