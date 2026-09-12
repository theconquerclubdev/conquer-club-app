import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../theme/app_theme.dart';
import '../providers/master_data_provider.dart';
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
  final GlobalKey _shareImageKey = GlobalKey();
  List<StreakModel> _streaks = [];
  Map<String, dynamic> _stats = {};
  bool _isLoading = true;
  String _filter = 'all'; // all, streak, missed

  bool _isLoadingData = false;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    // ✅ Guard against overlapping calls
    if (_isLoadingData) return;
    _isLoadingData = true;

    setState(() => _isLoading = true);
    try {
      final userId = Supabase.instance.client.auth.currentUser!.id;

      // ✅ Get current streak from MasterDataProvider (cached, no extra egress)
      final masterData = MasterDataProvider.instance;
      final dashboardData = await masterData.fetchMemberData(userId);
      final currentStreak = dashboardData.currentStreak;

      // Calculate start date for current streak
      DateTime? currentStreakStart;
      if (currentStreak > 0) {
        // Need to find when streak started from history
        // We still need history for the week view, so fetch it
      }

      // ✅ Always compute "today" in IST, regardless of device timezone,
      // so this matches the backend cron (which also runs on IST days).
      final nowUtc = DateTime.now().toUtc();
      final istNow = nowUtc.add(const Duration(hours: 5, minutes: 30));
      final today = DateTime(istNow.year, istNow.month, istNow.day);
      final todayStr =
          '${today.year.toString().padLeft(4, '0')}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
      final isSunday = today.weekday == DateTime.sunday;

      // IST day boundaries expressed as explicit UTC instants (unambiguous
      // when serialized), for querying timestamptz columns.
      final startOfDayUtc = DateTime.utc(today.year, today.month, today.day)
          .subtract(const Duration(hours: 5, minutes: 30));
      final endOfDayUtc = startOfDayUtc.add(const Duration(days: 1));

      // Check workout completion (>= 45 minutes) — bounded to today's IST
      // window, most recent session first, and capped to 1 row so multiple
      // completed sessions in a day can never throw.
      final workoutSessions = await Supabase.instance.client
          .from('workout_sessions')
          .select('elapsed_seconds')
          .eq('member_id', userId)
          .eq('status', 'completed')
          .gte('started_at', startOfDayUtc.toIso8601String())
          .lt('started_at', endOfDayUtc.toIso8601String())
          .order('started_at', ascending: false)
          .limit(1);

      bool workoutCompleted = false;
      int workoutMinutes = 0;
      if (workoutSessions.isNotEmpty) {
        final elapsedSeconds =
            (workoutSessions.first['elapsed_seconds'] as num?)?.toInt() ?? 0;
        workoutMinutes = (elapsedSeconds / 60).round();
        workoutCompleted = workoutMinutes >= 45;
      }

      // For Sunday, check photos and measurements
      bool photosUploaded = false;
      bool measurementsUpdated = false;

      if (isSunday) {
        // Check after photos — must be updated today (IST)
        final photos = await Supabase.instance.client
            .from('member_progress_photos')
            .select('after_front_updated_at, after_back_updated_at')
            .eq('member_id', userId)
            .limit(1)
            .maybeSingle();

        if (photos != null) {
          final frontDate = photos['after_front_updated_at'] != null
              ? DateTime.tryParse(photos['after_front_updated_at'])
              : null;
          final backDate = photos['after_back_updated_at'] != null
              ? DateTime.tryParse(photos['after_back_updated_at'])
              : null;

          photosUploaded = frontDate != null &&
              !frontDate.isBefore(startOfDayUtc) &&
              frontDate.isBefore(endOfDayUtc) &&
              backDate != null &&
              !backDate.isBefore(startOfDayUtc) &&
              backDate.isBefore(endOfDayUtc);
        }

        // Check measurements — bounded to today's IST window, capped to 1 row
        final measurements = await Supabase.instance.client
            .from('measurement_logs')
            .select('id')
            .eq('member_id', userId)
            .gte('recorded_at', startOfDayUtc.toIso8601String())
            .lt('recorded_at', endOfDayUtc.toIso8601String())
            .limit(1);

        measurementsUpdated = measurements.isNotEmpty;
      }

      // Determine if streak is met — same formula as the backend cron:
      // Sunday = photos + measurements; weekday = workout only.
      bool isStreakMet;
      if (isSunday) {
        isStreakMet = photosUploaded && measurementsUpdated;
      } else {
        isStreakMet = workoutCompleted;
      }

      // ✅ Skip the write entirely if today's row already matches what we
      // just computed — opening/reopening this tab shouldn't write to the
      // database unless something actually changed.
      final existingToday = await Supabase.instance.client
          .from('member_streaks')
          .select(
              'is_workout_completed, is_photos_uploaded, is_measurements_updated, workout_minutes, is_streak_met')
          .eq('member_id', userId)
          .eq('date', todayStr)
          .maybeSingle();

      final alreadyUpToDate = existingToday != null &&
          existingToday['is_workout_completed'] == workoutCompleted &&
          existingToday['is_photos_uploaded'] == photosUploaded &&
          existingToday['is_measurements_updated'] == measurementsUpdated &&
          existingToday['workout_minutes'] == workoutMinutes &&
          existingToday['is_streak_met'] == isStreakMet;

      if (!alreadyUpToDate) {
        // Upsert today's streak record (needed for history)
        await Supabase.instance.client.from('member_streaks').upsert({
          'member_id': userId,
          'date': todayStr,
          'is_workout_completed': workoutCompleted,
          'is_photos_uploaded': photosUploaded,
          'is_measurements_updated': measurementsUpdated,
          'workout_minutes': workoutMinutes,
          'is_sunday': isSunday,
          'is_streak_met': isStreakMet,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        }, onConflict: 'member_id,date');
      }
      // 2. Get history for UI cards & week view (limit to 90 days)
      final response = await Supabase.instance.client
          .from('member_streaks')
          .select(
              'id, member_id, date, is_workout_completed, is_photos_uploaded, is_measurements_updated, workout_minutes, is_sunday, is_streak_met')
          .eq('member_id', userId)
          .order('date', ascending: false)
          .limit(90);

      final List<StreakModel> history = [];
      for (var record in response) {
        history.add(StreakModel.fromJson(record));
      }

      // ✅ Calculate highest streak from history (still needed)
      final sortedHistory = List<StreakModel>.from(history)
        ..sort((a, b) => a.date.compareTo(b.date));

      int highestStreak = 0;
      int runningStreak = 0;
      DateTime? lastStreakDate;

      for (final streak in sortedHistory) {
        final sDate =
            DateTime(streak.date.year, streak.date.month, streak.date.day);
        if (streak.isStreakMet) {
          if (lastStreakDate != null &&
              sDate.difference(lastStreakDate).inDays == 1) {
            runningStreak++;
          } else {
            runningStreak = 1;
          }
          lastStreakDate = sDate;
          if (runningStreak > highestStreak) {
            highestStreak = runningStreak;
          }
        } else {
          runningStreak = 0;
          lastStreakDate = null;
        }
      }

      // ✅ Calculate streak start date from history
      if (currentStreak > 0 && history.isNotEmpty) {
        final sortedAsc = List<StreakModel>.from(history)
          ..sort((a, b) => a.date.compareTo(b.date));

        // Find the most recent streak break
        DateTime? breakDate;
        for (int i = sortedAsc.length - 1; i >= 0; i--) {
          if (!sortedAsc[i].isStreakMet) {
            breakDate = sortedAsc[i].date;
            break;
          }
        }

        if (breakDate != null) {
          // Start date is the day after the break
          currentStreakStart = breakDate.add(const Duration(days: 1));
        } else if (sortedAsc.isNotEmpty) {
          // No breaks found, streak started from the earliest record
          currentStreakStart = sortedAsc.first.date;
        }
      }

      final totalStreaks = history.where((s) => s.isStreakMet).length;
      final totalDays = history.length;
      final streakRate =
          totalDays > 0 ? (totalStreaks / totalDays * 100).round() : 0;

      if (mounted) {
        print('🔍 Current streak from MasterDataProvider: $currentStreak');
        print('🔍 Calculated highestStreak: $highestStreak');
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
      }
    } catch (e) {
      print('Error loading streak data: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    } finally {
      _isLoadingData = false;
    }
  }

  List<StreakModel> get _filteredStreaks {
    if (_filter == 'all') return _streaks.take(7).toList();
    if (_filter == 'streak') {
      return _streaks.where((s) => s.isStreakMet).take(7).toList();
    }
    return _streaks.where((s) => !s.isStreakMet).take(7).toList();
  }

  void _shareStreak(BuildContext context) {
    _postShare(context);
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
        Text(
          label,
          style: const TextStyle(
            color: Colors.grey,
            fontSize: 10,
          ),
        ),
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
      builder: (context) => Container(
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
                Navigator.pop(context);
                _shareWithImage(context, 'instagram_story', shareText);
              },
            ),
            const Divider(color: Colors.grey, height: 1),
            _shareOptionTile(
              icon: Icons.grid_on,
              title: 'Instagram Post',
              subtitle: 'Share as a feed post',
              onTap: () {
                Navigator.pop(context);
                _shareWithImage(context, 'instagram_post', shareText);
              },
            ),
            const Divider(color: Colors.grey, height: 1),
            _shareOptionTile(
              icon: Icons.chat_bubble_outline,
              title: 'Snapchat',
              subtitle: 'Send as a snap',
              onTap: () {
                Navigator.pop(context);
                _shareWithImage(context, 'snapchat', shareText);
              },
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => Navigator.pop(context),
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
        style: TextStyle(
          color: Colors.grey.shade500,
          fontSize: 12,
        ),
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

    // Preview is built entirely on-device (black background, no network
    // image, no database call), so it shows instantly.
    _showImagePreview(
      context,
      currentStreak,
      currentStreakStart,
      platform,
      shareText,
    );
  }

  void _showImagePreview(
    BuildContext context,
    int currentStreak,
    DateTime? currentStreakStart,
    String platform,
    String shareText,
  ) {
    // Make stats available to the image preview
    final highestStreak = _stats['highestStreak'] ?? 0;
    final streakRate = _stats['streakRate'] ?? 0;
    final totalStreaks = _stats['totalStreaks'] ?? 0;
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(16),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 340,
            maxHeight: MediaQuery.of(context).size.height - 32,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                RepaintBoundary(
                  key: _shareImageKey,
                  child: AspectRatio(
                    aspectRatio: platform == 'instagram_post' ? 1 : 9 / 16,
                    child: Container(
                      color: Colors.black,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          if (platform != 'instagram_post')
                            Image.asset(
                              'assets/images/reel_background.png',
                              fit: BoxFit.fill,
                            )
                          else
                            const ColoredBox(color: Colors.black),
                          if (platform != 'instagram_post')
                            Positioned(
                              top: 0,
                              left: 0,
                              right: 0,
                              bottom: 0,
                              child: Column(
                                children: [
                                  const Spacer(flex: 4),
                                  Text(
                                    currentStreak > 0
                                        ? '🔥 $currentStreak DAY${currentStreak > 1 ? 'S' : ''}'
                                        : '🔥 NO STREAK',
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 28,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 1.5,
                                    ),
                                  ),
                                  if (currentStreakStart != null &&
                                      currentStreak > 0) ...[
                                    const SizedBox(height: 8),
                                    Text(
                                      DateFormat('d-MMM-yyyy')
                                          .format(DateTime.now()),
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(
                                        color: Colors.white70,
                                        fontSize: 14,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      DateFormat('EEEE').format(DateTime.now()),
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(
                                        color: Colors.white70,
                                        fontSize: 14,
                                      ),
                                    ),
                                  ],
                                  const SizedBox(height: 16),
                                  const SizedBox(height: 16),
                                  const Spacer(flex: 5),
                                ],
                              ),
                            )
                          else
                            Positioned.fill(
                              child: Stack(
                                children: [
                                  const Positioned(
                                    top: 16,
                                    left: 0,
                                    right: 0,
                                    child: Text(
                                      'THE',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 25,
                                        fontWeight: FontWeight.normal,
                                        letterSpacing: 2,
                                      ),
                                    ),
                                  ),
                                  const Positioned(
                                    top: 50,
                                    left: 0,
                                    right: 0,
                                    child: Center(
                                      child: ColoredBox(
                                        color: Colors.black,
                                        child: Padding(
                                          padding: EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 12,
                                          ),
                                          child: Text(
                                            'CONQUER',
                                            textAlign: TextAlign.center,
                                            style: TextStyle(
                                              color: AppColors.gold,
                                              fontSize: 25,
                                              fontWeight: FontWeight.normal,
                                              letterSpacing: 2,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  const Positioned(
                                    top: 106,
                                    left: 0,
                                    right: 0,
                                    child: Text(
                                      'CLUB',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 25,
                                        fontWeight: FontWeight.normal,
                                        letterSpacing: 2,
                                      ),
                                    ),
                                  ),
                                  const Positioned(
                                    top: 135,
                                    left: 0,
                                    right: 0,
                                    child: Text(
                                      'BY ABHISHEK MOHITE',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        color:
                                            Color.fromRGBO(255, 255, 255, 0.7),
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                        letterSpacing: 1,
                                      ),
                                    ),
                                  ),
                                  Positioned(
                                    top: 170,
                                    left: 12,
                                    right: 12,
                                    child: Column(
                                      children: [
                                        Text(
                                          currentStreak > 0
                                              ? '🔥 ${currentStreak} DAY${currentStreak > 1 ? 'S' : ''}'
                                              : '🔥 NO STREAK',
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 28,
                                            fontWeight: FontWeight.bold,
                                            letterSpacing: 1.5,
                                          ),
                                        ),
                                        if (currentStreakStart != null &&
                                            currentStreak > 0) ...[
                                          const SizedBox(height: 8),
                                          Text(
                                            DateFormat('d-MMM-yyyy')
                                                .format(DateTime.now()),
                                            style: const TextStyle(
                                              color: Colors.white70,
                                              fontSize: 14,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            DateFormat('EEEE')
                                                .format(DateTime.now()),
                                            style: const TextStyle(
                                              color: Colors.white70,
                                              fontSize: 14,
                                            ),
                                          ),
                                        ],
                                        const SizedBox(height: 16),
                                        const SizedBox(height: 16),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(context),
                        style: OutlinedButton.styleFrom(
                          side:
                              BorderSide(color: Colors.white.withOpacity(0.3)),
                          foregroundColor: Colors.white,
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
                          _captureAndShare(context, platform, shareText);
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
                          'Share Now',
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
      ),
    );
  }

  Future<void> _captureAndShare(
    BuildContext context,
    String platform,
    String shareText,
  ) async {
    try {
      final boundary = _shareImageKey.currentContext!.findRenderObject()
          as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 3.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      final pngBytes = byteData!.buffer.asUint8List();

      if (!context.mounted) return;
      Navigator.pop(context);

      final xFile = XFile.fromData(
        pngBytes,
        mimeType: 'image/png',
        name: 'conquer_club_streak.png',
      );

      await Share.shareXFiles(
        [xFile],
        text: shareText,
        subject: 'My Conquer Club Streak',
      );
    } catch (e) {
      if (!context.mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('❌ Error sharing: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  double _calculateQuoteFontSize(String quote) {
    final length = quote.length;
    if (length <= 40) return 18;
    if (length <= 70) return 16;
    if (length <= 100) return 14;
    if (length <= 140) return 12;
    return 10;
  }

  Widget _imagePreviewStat(String icon, String value, String label) {
    return Column(
      children: [
        Text(icon, style: const TextStyle(fontSize: 18)),
        const SizedBox(height: 2),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.bold,
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
          label,
          style: TextStyle(
            color: Colors.white70,
            fontSize: 9,
            shadows: [
              const Shadow(
                offset: Offset(0, 1),
                blurRadius: 3,
                color: Colors.black,
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _confirmShare(BuildContext context, String platform, String shareText) {
    // Close any open dialogs
    Navigator.pop(context);

    // Show sharing progress
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('📤 Sharing to $platform...'),
        backgroundColor: AppColors.gold,
        duration: const Duration(seconds: 1),
      ),
    );

    // Share the text content
    // For Instagram/Snapchat, the user can choose the app from the share sheet
    Share.share(
      shareText,
      subject: 'My Conquer Club Streak',
    ).then((result) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('✅ Shared successfully!'),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 2),
        ),
      );
    }).catchError((error) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('❌ Error sharing: $error'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 2),
        ),
      );
    });
  }

  // Get this week's streaks (Mon-Sun)
  List<StreakModel> _getThisWeekStreaks() {
    final nowUtc = DateTime.now().toUtc();
    final istNow = nowUtc.add(const Duration(hours: 5, minutes: 30));

    // Get Monday of this week (IST)
    int daysFromMonday = istNow.weekday - DateTime.monday;
    if (daysFromMonday < 0) daysFromMonday += 7;
    final monday =
        DateTime(istNow.year, istNow.month, istNow.day - daysFromMonday);

    // Get Sunday of this week
    final sunday = monday.add(const Duration(days: 6));

    // Filter streaks that fall within this week
    return _streaks.where((s) {
      final sDate = DateTime(s.date.year, s.date.month, s.date.day);
      return !sDate.isBefore(monday) && !sDate.isAfter(sunday);
    }).toList();
  }

  // Build week days with 3D-like styling
  List<Widget> _buildWeekDays(List<StreakModel> weekStreaks) {
    final nowUtc = DateTime.now().toUtc();
    final istNow = nowUtc.add(const Duration(hours: 5, minutes: 30));
    final today = DateTime(istNow.year, istNow.month, istNow.day);

    // Build map of date -> isStreakMet
    final streakMap = <String, bool>{};
    for (final s in weekStreaks) {
      final key =
          '${s.date.year}-${s.date.month.toString().padLeft(2, '0')}-${s.date.day.toString().padLeft(2, '0')}';
      streakMap[key] = s.isStreakMet;
    }

    final weekDays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final List<Widget> dayWidgets = [];

    // Get Monday of this week
    int daysFromMonday = istNow.weekday - DateTime.monday;
    if (daysFromMonday < 0) daysFromMonday += 7;
    final monday =
        DateTime(istNow.year, istNow.month, istNow.day - daysFromMonday);

    for (int i = 0; i < 7; i++) {
      final date = monday.add(Duration(days: i));
      final dateKey =
          '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
      final isMet = streakMap[dateKey] ?? false;
      final isToday = date.year == today.year &&
          date.month == today.month &&
          date.day == today.day;
      final isFuture = date.isAfter(today);

      dayWidgets.add(
        _WeekDayChip(
          day: weekDays[i],
          isMet: isMet,
          isToday: isToday,
          isFuture: isFuture,
        ),
      );
    }

    return dayWidgets;
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
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadData,
          ),
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
                  SliverToBoxAdapter(
                    child: _buildStatsBanner(),
                  ),

                  // Filter Tabs
                  SliverToBoxAdapter(
                    child: Container(
                      margin: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        color: AppColors.cardDark,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        children: [
                          _buildFilterChip('All', 'all'),
                          _buildFilterChip('🔥 Streaks', 'streak'),
                          _buildFilterChip('⏳ Pending', 'missed'),
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

    // Get this week's streak data (Mon-Sun)
    final List<StreakModel> weekStreaks = _getThisWeekStreaks();

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
                        : '0 Day Streak',
                    style: TextStyle(
                      color: currentStreak > 0 ? AppColors.gold : Colors.grey,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (currentStreakStart != null)
                    Text(
                      'Since ${DateFormat('MMM d, yyyy').format(currentStreakStart)}',
                      style: const TextStyle(
                        color: Colors.grey,
                        fontSize: 12,
                      ),
                    ),
                ],
              ),
            ],
          ),

          const SizedBox(height: 16),

          // Week View - Mon to Sun
          Container(
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.2),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: _buildWeekDays(weekStreaks),
            ),
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
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
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
        Text(
          label,
          style: const TextStyle(
            color: Colors.grey,
            fontSize: 10,
          ),
        ),
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
    final istNow =
        DateTime.now().toUtc().add(const Duration(hours: 5, minutes: 30));
    final isToday = streak.date.year == istNow.year &&
        streak.date.month == istNow.month &&
        streak.date.day == istNow.day;

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
                  color: isSuccess
                      ? Colors.green
                      : (isToday
                          ? (isSunday
                              ? Colors.orange
                              : streak.workoutMinutes >= 45
                                  ? Colors.green
                                  : Colors.orange)
                          : Colors.red),
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
                      : (isToday
                          ? Colors.orange.withOpacity(0.15)
                          : Colors.red.withOpacity(0.15)),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  isSuccess
                      ? '✅ Streak!'
                      : (isToday
                          ? (isSunday
                              ? '⏳ Pending'
                              : streak.workoutMinutes >= 45
                                  ? '✅ Streak!'
                                  : '⏳ Pending')
                          : '❌ Missed'),
                  style: TextStyle(
                    color: isSuccess
                        ? Colors.green
                        : (isToday
                            ? (isSunday
                                ? Colors.orange
                                : streak.workoutMinutes >= 45
                                    ? Colors.green
                                    : Colors.orange)
                            : Colors.red),
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
              if (!isSunday)
                _detailChip(
                  '🏋️ ${streak.workoutMinutes} min',
                  streak.workoutMinutes >= 45,
                ),
              if (isSunday) ...[
                _detailChip(
                  '📸 Photos',
                  streak.isPhotosUploaded,
                ),
                _detailChip(
                  '📏 Measurements',
                  streak.isMeasurementsUpdated,
                ),
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

class _ConquerFramePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.gold
      ..strokeWidth = 5
      ..style = PaintingStyle.stroke;

    const sideInset = 36.0;

    final topY = 176.0;
    final bottomY = size.height - 121.0;

    canvas.drawRect(
      Rect.fromLTRB(
        sideInset,
        topY,
        size.width - sideInset,
        bottomY,
      ),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// Week Day Chip with 3D-like styling
class _WeekDayChip extends StatelessWidget {
  final String day;
  final bool isMet;
  final bool isToday;
  final bool isFuture;

  const _WeekDayChip({
    required this.day,
    required this.isMet,
    required this.isToday,
    required this.isFuture,
  });

  @override
  Widget build(BuildContext context) {
    final isSmall = MediaQuery.of(context).size.width < 360;
    final double size = isSmall ? 32 : 38;
    final double fontSize = isSmall ? 8 : 10;

    Color backgroundColor;
    Color borderColor;
    Color textColor;
    String icon = '';

    if (isFuture) {
      // Future days - greyed out
      backgroundColor = Colors.grey.withOpacity(0.15);
      borderColor = Colors.grey.withOpacity(0.1);
      textColor = Colors.grey.shade600;
      icon = '';
    } else if (isMet) {
      // Streak met - gold with glow
      backgroundColor = AppColors.gold.withOpacity(0.2);
      borderColor = AppColors.gold.withOpacity(0.5);
      textColor = AppColors.gold;
      icon = '✅';
    } else if (isToday) {
      // Today - pending (not yet completed)
      backgroundColor = Colors.orange.withOpacity(0.15);
      borderColor = Colors.orange.withOpacity(0.3);
      textColor = Colors.orange;
      icon = '⏳';
    } else {
      // Past day - missed (red)
      backgroundColor = Colors.red.withOpacity(0.15);
      borderColor = Colors.red.withOpacity(0.3);
      textColor = Colors.red;
      icon = '❌';
    }

    // Today indicator
    if (isToday && !isFuture) {
      borderColor = AppColors.gold;
      borderColor = AppColors.gold.withOpacity(0.8);
    }

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            backgroundColor.withOpacity(backgroundColor.opacity + 0.25),
            backgroundColor,
          ],
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: borderColor,
          width: isToday && !isFuture ? 2.2 : 1.5,
        ),
        boxShadow: isFuture
            ? []
            : [
                BoxShadow(
                  color: Colors.black.withOpacity(0.35),
                  blurRadius: 6,
                  offset: const Offset(0, 3),
                ),
                BoxShadow(
                  color: (isMet ? AppColors.gold : textColor).withOpacity(0.35),
                  blurRadius: 10,
                  spreadRadius: isMet ? 1.5 : 0.5,
                ),
                BoxShadow(
                  color: Colors.white.withOpacity(0.06),
                  blurRadius: 2,
                  offset: const Offset(-1, -1),
                ),
              ],
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              icon,
              style: TextStyle(
                fontSize: isSmall ? 13 : 15,
                shadows: isMet
                    ? [
                        Shadow(
                          color: AppColors.gold.withOpacity(0.6),
                          blurRadius: 6,
                        ),
                      ]
                    : null,
              ),
            ),
            Text(
              day,
              style: TextStyle(
                color: textColor,
                fontSize: fontSize,
                fontWeight: isToday ? FontWeight.bold : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
