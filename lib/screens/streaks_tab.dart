import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../theme/app_theme.dart';

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
