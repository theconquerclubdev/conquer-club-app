import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
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
      final startOfDay = DateTime(today.year, today.month, today.day);

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
          if (currentStreak > 0) break;
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
      builder: (context) => Dialog(
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
              Container(
                height: 1,
                color: Colors.white.withOpacity(0.1),
              ),

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
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: AppColors.gold.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.gold.withOpacity(0.2)),
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
                      onPressed: () => Navigator.pop(context),
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
                        Navigator.pop(context);
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
      // Fetch background image from Supabase storage
      // You need to upload a background image to your Supabase storage bucket
      // The image should be in a bucket named 'streak_share' or similar
      final String imageUrl =
          'https://dafbinwvwxuekdomdmro.supabase.co/storage/v1/object/public/streak_share/background.jpg';

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
  ) {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(16),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            image: DecorationImage(
              image: NetworkImage(imageUrl),
              fit: BoxFit.cover,
            ),
          ),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.transparent,
                  Colors.black.withOpacity(0.4),
                  Colors.black.withOpacity(0.7),
                ],
                stops: const [0.4, 0.7, 1.0],
              ),
            ),
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Streak counter
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text('🔥', style: TextStyle(fontSize: 40)),
                    const SizedBox(width: 16),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          currentStreak > 0
                              ? '$currentStreak DAYS'
                              : 'NO ACTIVE STREAK',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                            shadows: [
                              Shadow(
                                offset: Offset(0, 2),
                                blurRadius: 4,
                                color: Colors.black,
                              ),
                            ],
                          ),
                        ),
                        if (currentStreakStart != null && currentStreak > 0)
                          Text(
                            'Started: ${DateFormat('MMM d, yyyy').format(currentStreakStart)}',
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 13,
                              shadows: [
                                Shadow(
                                  offset: Offset(0, 1),
                                  blurRadius: 3,
                                  color: Colors.black,
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ],
                ),

                const SizedBox(height: 24),

                // Stats row
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _imagePreviewStat('🏆', '$highestStreak', 'Best Streak'),
                    _imagePreviewStat('📊', '$streakRate%', 'Success Rate'),
                    _imagePreviewStat('✅', '$totalStreaks', 'Total Streaks'),
                  ],
                ),

                const SizedBox(height: 20),

                // Tagline
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.gold.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: AppColors.gold.withOpacity(0.3),
                    ),
                  ),
                  child: const Text(
                    'CONSISTENCY. DISCIPLINE. RESULTS.',
                    style: TextStyle(
                      color: AppColors.gold,
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
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
                ),

                const SizedBox(height: 8),

                // Gym name
                const Text(
                  'THE CONQUER CLUB',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1.5,
                    shadows: [
                      Shadow(
                        offset: Offset(0, 1),
                        blurRadius: 3,
                        color: Colors.black,
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                // Platform badge
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.5),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    'Sharing to: $platform',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 11,
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                // Action buttons
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
                          Navigator.pop(context);
                          _confirmShare(context, platform, shareText);
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

  Widget _imagePreviewStat(String icon, String value, String label) {
    return Column(
      children: [
        Text(icon, style: const TextStyle(fontSize: 22)),
        const SizedBox(height: 2),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 18,
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
            fontSize: 10,
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

          // Stats Row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _statItem(
                '🏆',
                '$highestStreak',
                'Best Streak',
              ),
              _statItem(
                '📊',
                '$streakRate%',
                'Success Rate',
              ),
              _statItem(
                '✅',
                '$totalStreaks',
                'Total Streaks',
              ),
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
