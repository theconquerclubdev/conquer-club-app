// lib/services/streak_service.dart
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/streak_model.dart';

class StreakService {
  static const String _table = 'member_streaks';

  Future<void> checkAndUpdateStreak(String memberId) async {
    final today = DateTime.now();
    final isSunday = today.weekday == DateTime.sunday;
    final dateStr = today.toIso8601String().split('T').first;

    // Check if today's streak already exists
    final existing = await Supabase.instance.client
        .from(_table)
        .select()
        .eq('member_id', memberId)
        .eq('date', dateStr)
        .maybeSingle();

    // Get today's data
    final isWorkoutCompleted = await _checkWorkoutCompleted(memberId, today);
    final workoutMinutes = await _getWorkoutMinutes(memberId, today);
    final stepsCount = await _getStepsCount(memberId, today);
    final stepGoal = await _getStepGoal(memberId);
    final isStepsCompleted = stepsCount >= stepGoal;
    final isPhotosUploaded = await _checkPhotosUploaded(memberId);
    final isMeasurementsUpdated =
        await _checkMeasurementsUpdated(memberId, today);

    // Determine if streak is met
    bool isStreakMet;
    if (isSunday) {
      isStreakMet =
          isStepsCompleted && isPhotosUploaded && isMeasurementsUpdated;
    } else {
      isStreakMet = isWorkoutCompleted && isStepsCompleted;
    }

    final streakData = {
      'member_id': memberId,
      'date': dateStr,
      'is_workout_completed': isWorkoutCompleted,
      'is_steps_completed': isStepsCompleted,
      'is_photos_uploaded': isPhotosUploaded,
      'is_measurements_updated': isMeasurementsUpdated,
      'workout_minutes': workoutMinutes,
      'steps_count': stepsCount,
      'is_sunday': isSunday,
      'is_streak_met': isStreakMet,
      'updated_at': DateTime.now().toIso8601String(),
    };

    if (existing != null) {
      await Supabase.instance.client
          .from(_table)
          .update(streakData)
          .eq('id', existing['id']);
    } else {
      await Supabase.instance.client.from(_table).insert({
        ...streakData,
        'created_at': DateTime.now().toIso8601String(),
      });
    }
  }

  Future<bool> _checkWorkoutCompleted(String memberId, DateTime date) async {
    final startOfDay = DateTime(date.year, date.month, date.day);
    final endOfDay = startOfDay.add(const Duration(days: 1));

    final session = await Supabase.instance.client
        .from('workout_sessions')
        .select('elapsed_seconds, status')
        .eq('member_id', memberId)
        .eq('status', 'completed')
        .gte('started_at', startOfDay.toIso8601String())
        .lt('started_at', endOfDay.toIso8601String())
        .maybeSingle();

    if (session == null) return false;
    final minutes = (session['elapsed_seconds'] ?? 0) ~/ 60;
    return minutes >= 45;
  }

  Future<int> _getWorkoutMinutes(String memberId, DateTime date) async {
    final startOfDay = DateTime(date.year, date.month, date.day);
    final endOfDay = startOfDay.add(const Duration(days: 1));

    final session = await Supabase.instance.client
        .from('workout_sessions')
        .select('elapsed_seconds')
        .eq('member_id', memberId)
        .eq('status', 'completed')
        .gte('started_at', startOfDay.toIso8601String())
        .lt('started_at', endOfDay.toIso8601String())
        .maybeSingle();

    if (session == null) return 0;
    return (session['elapsed_seconds'] ?? 0) ~/ 60;
  }

  Future<int> _getStepsCount(String memberId, DateTime date) async {
    final dateStr = date.toIso8601String().split('T').first;
    final result = await Supabase.instance.client
        .from('step_logs')
        .select('steps')
        .eq('member_id', memberId)
        .eq('log_date', dateStr)
        .maybeSingle();

    return result?['steps'] ?? 0;
  }

  Future<int> _getStepGoal(String memberId) async {
    final profile = await Supabase.instance.client
        .from('profiles')
        .select('step_goal')
        .eq('id', memberId)
        .maybeSingle();

    return profile?['step_goal'] ?? 10000;
  }

  Future<bool> _checkPhotosUploaded(String memberId) async {
    final photos = await Supabase.instance.client
        .from('member_progress_photos')
        .select('after_front, after_back')
        .eq('member_id', memberId)
        .maybeSingle();

    if (photos == null) return false;
    return photos['after_front'] != null && photos['after_back'] != null;
  }

  Future<bool> _checkMeasurementsUpdated(String memberId, DateTime date) async {
    final startOfDay = DateTime(date.year, date.month, date.day);
    final endOfDay = startOfDay.add(const Duration(days: 1));

    final measurement = await Supabase.instance.client
        .from('measurement_logs')
        .select('recorded_at')
        .eq('member_id', memberId)
        .gte('recorded_at', startOfDay.toIso8601String())
        .lt('recorded_at', endOfDay.toIso8601String())
        .maybeSingle();

    return measurement != null;
  }

  Future<int> getCurrentStreak(String memberId) async {
    final today = DateTime.now();
    var streakCount = 0;
    var currentDate = today;

    while (true) {
      final dateStr = currentDate.toIso8601String().split('T').first;
      final result = await Supabase.instance.client
          .from(_table)
          .select('is_streak_met')
          .eq('member_id', memberId)
          .eq('date', dateStr)
          .maybeSingle();

      if (result == null || result['is_streak_met'] != true) {
        break;
      }

      streakCount++;
      currentDate = currentDate.subtract(const Duration(days: 1));
    }

    return streakCount;
  }

  Future<List<StreakModel>> getStreakHistory(String memberId) async {
    final result = await Supabase.instance.client
        .from(_table)
        .select()
        .eq('member_id', memberId)
        .order('date', ascending: false);

    return (result as List).map((e) => StreakModel.fromJson(e)).toList();
  }

  Future<int> getHighestStreak(String memberId) async {
    final history = await getStreakHistory(memberId);
    int highest = 0;
    int current = 0;

    // Process from oldest to newest
    final reversed = history.reversed.toList();
    for (final entry in reversed) {
      if (entry.isStreakMet) {
        current++;
        if (current > highest) highest = current;
      } else {
        current = 0;
      }
    }

    return highest;
  }

  Future<Map<String, dynamic>> getStreakStats(String memberId) async {
    final currentStreak = await getCurrentStreak(memberId);
    final highestStreak = await getHighestStreak(memberId);
    final history = await getStreakHistory(memberId);

    final totalStreaks = history.where((e) => e.isStreakMet).length;
    final totalDays = history.length;
    final streakRate =
        totalDays > 0 ? (totalStreaks / totalDays * 100).round() : 0;

    // Find current streak start date
    DateTime? currentStreakStart;
    if (currentStreak > 0) {
      final sortedHistory = List.from(history)
        ..sort((a, b) => a.date.compareTo(b.date));
      for (int i = 0; i < sortedHistory.length; i++) {
        if (sortedHistory[i].isStreakMet) {
          // Check if this is the start of the current streak
          bool isStart = true;
          if (i > 0) {
            // Check if previous day was not a streak
            final prevDay = sortedHistory[i - 1];
            if (prevDay.date.difference(sortedHistory[i].date).inDays.abs() ==
                    1 &&
                prevDay.isStreakMet) {
              isStart = false;
            }
          }
          if (isStart &&
              sortedHistory[i]
                  .date
                  .isBefore(DateTime.now().add(const Duration(days: 1)))) {
            currentStreakStart = sortedHistory[i].date;
            break;
          }
        }
      }
    }

    return {
      'currentStreak': currentStreak,
      'highestStreak': highestStreak,
      'totalStreaks': totalStreaks,
      'totalDays': totalDays,
      'streakRate': streakRate,
      'currentStreakStart': currentStreakStart,
      'history': history,
    };
  }
}
