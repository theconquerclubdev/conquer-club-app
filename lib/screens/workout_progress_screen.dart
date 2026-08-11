// lib/screens/member/workout_progress_screen.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../theme/app_theme.dart';

class WorkoutProgressScreen extends StatefulWidget {
  const WorkoutProgressScreen({super.key});

  @override
  State<WorkoutProgressScreen> createState() => _WorkoutProgressScreenState();
}

class _WorkoutProgressScreenState extends State<WorkoutProgressScreen> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _strengthRecords = [];

  // ✅ Exercise mapping for Strength Records
  final List<Map<String, dynamic>> _trackedExercises = [
    {
      'displayName': 'Deadlift',
      'dbNames': ['Deadlift'],
    },
    {
      'displayName': 'Squats',
      'dbNames': ['Barbell Squat'],
    },
    {
      'displayName': 'Flat Bench Press',
      'dbNames': ['Flat Bench Press', 'Flat Dumbbell Press'],
    },
    {
      'displayName': 'Pull Ups',
      'dbNames': ['Pull Ups'],
    },
    {
      'displayName': 'Push Ups',
      'dbNames': ['Push Ups'],
    },
  ];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final userId = Supabase.instance.client.auth.currentUser!.id;
      final records = await _getStrengthRecords(userId);
      setState(() {
        _strengthRecords = records;
        _isLoading = false;
      });
    } catch (e) {
      print('Error loading strength records: $e');
      setState(() => _isLoading = false);
    }
  }

  Future<List<Map<String, dynamic>>> _getStrengthRecords(String userId) async {
    final List<Map<String, dynamic>> records = [];

    for (final exerciseConfig in _trackedExercises) {
      final displayName = exerciseConfig['displayName'] as String;
      final dbNames = exerciseConfig['dbNames'] as List<String>;

      // Get all exercise IDs for this exercise
      final exerciseIds = <String>[];
      for (final name in dbNames) {
        try {
          final exData = await Supabase.instance.client
              .from('exercises')
              .select('id')
              .eq('name', name)
              .maybeSingle();
          if (exData != null) {
            exerciseIds.add(exData['id']);
          }
        } catch (e) {
          // Skip if exercise not found
        }
      }

      if (exerciseIds.isEmpty) {
        records.add({
          'displayName': displayName,
          'hasData': false,
          'lastDate': null,
          'lastKg': null,
          'lastReps': null,
          'highestDate': null,
          'highestKg': null,
          'highestReps': null,
        });
        continue;
      }

      // Get all workout_exercises for these exercise IDs
      final workoutExercises = await Supabase.instance.client
          .from('workout_exercises')
          .select('id, workout_id')
          .inFilter('exercise_id', exerciseIds);

      if (workoutExercises.isEmpty) {
        records.add({
          'displayName': displayName,
          'hasData': false,
          'lastDate': null,
          'lastKg': null,
          'lastReps': null,
          'highestDate': null,
          'highestKg': null,
          'highestReps': null,
        });
        continue;
      }

      final workoutExerciseIds =
          workoutExercises.map((we) => we['id'] as String).toList();

      // Get all sets for these workout_exercises
      final allSets =
          await Supabase.instance.client.from('workout_sets').select('''
            id, kg, reps, 
            workout_exercise_id,
            workout_exercises!inner(workout_id)
          ''').inFilter('workout_exercise_id', workoutExerciseIds);

      if (allSets.isEmpty) {
        records.add({
          'displayName': displayName,
          'hasData': false,
          'lastDate': null,
          'lastKg': null,
          'lastReps': null,
          'highestDate': null,
          'highestKg': null,
          'highestReps': null,
        });
        continue;
      }

      // Get workout session dates for these sets
      final workoutIds = allSets
          .map((s) => s['workout_exercises']['workout_id'] as String)
          .toSet()
          .toList();

      final sessions = await Supabase.instance.client
          .from('workout_sessions')
          .select('id, workout_id, started_at')
          .eq('member_id', userId)
          .eq('status', 'completed')
          .inFilter('workout_id', workoutIds);

      // Build a map of workout_id -> started_at
      final sessionDates = <String, DateTime>{};
      for (final session in sessions) {
        final startedAt = DateTime.tryParse(session['started_at'] as String);
        if (startedAt != null) {
          sessionDates[session['workout_id']] = startedAt;
        }
      }

      // For each set, get its session date
      final setsWithDates = <Map<String, dynamic>>[];
      for (final set in allSets) {
        final workoutId = set['workout_exercises']['workout_id'] as String;
        final date = sessionDates[workoutId];
        if (date != null) {
          setsWithDates.add({
            'kg': (set['kg'] as num?)?.toDouble() ?? 0,
            'reps': (set['reps'] as num?)?.toInt() ?? 0,
            'date': date,
          });
        }
      }

      if (setsWithDates.isEmpty) {
        records.add({
          'displayName': displayName,
          'hasData': false,
          'lastDate': null,
          'lastKg': null,
          'lastReps': null,
          'highestDate': null,
          'highestKg': null,
          'highestReps': null,
        });
        continue;
      }

      // ✅ Find the LATEST set (by date)
      setsWithDates.sort((a, b) => b['date'].compareTo(a['date']));
      final latestSet = setsWithDates.first;
      final latestKg = latestSet['kg'];
      final latestReps = latestSet['reps'];
      final latestDate = latestSet['date'];

      // ✅ Find the HIGHEST kg set (all time)
      Map<String, dynamic>? highestSet;
      double maxKg = 0;
      for (final set in setsWithDates) {
        final kg = set['kg'] as double;
        if (kg > maxKg) {
          maxKg = kg;
          highestSet = set;
        }
      }

      records.add({
        'displayName': displayName,
        'hasData': true,
        'lastDate': latestDate,
        'lastKg': latestKg,
        'lastReps': latestReps,
        'highestDate': highestSet?['date'],
        'highestKg': highestSet?['kg'],
        'highestReps': highestSet?['reps'],
      });
    }

    return records;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          'Strength Records',
          style: TextStyle(
            color: Colors.white,
            fontSize: 22,
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: AppColors.gold),
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
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: _buildStrengthRecordsTable(),
              ),
            ),
    );
  }

  // ============================================================
  // Strength Records Table
  // ============================================================
  Widget _buildStrengthRecordsTable() {
    final hasData = _strengthRecords.any((r) => r['hasData'] == true);

    if (!hasData) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.fitness_center_outlined,
              color: Colors.grey.shade600,
              size: 64,
            ),
            const SizedBox(height: 16),
            Text(
              'No strength records yet',
              style: TextStyle(
                color: Colors.grey.shade500,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Complete workouts to track your best lifts! 💪',
              style: TextStyle(
                color: Colors.grey.shade400,
                fontSize: 14,
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.cardDark,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: Colors.white.withOpacity(0.06),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Table Header
          Container(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
            decoration: BoxDecoration(
              color: AppColors.gold.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 90,
                  child: Text(
                    'Exercise',
                    style: TextStyle(
                      color: AppColors.gold,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Expanded(
                  flex: 1,
                  child: Text(
                    'Last Date',
                    style: TextStyle(
                      color: AppColors.gold,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
                Expanded(
                  flex: 1,
                  child: Text(
                    'Last (kg×reps)',
                    style: TextStyle(
                      color: AppColors.gold,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
                Expanded(
                  flex: 1,
                  child: Text(
                    'Best Date',
                    style: TextStyle(
                      color: AppColors.gold,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
                Expanded(
                  flex: 1,
                  child: Text(
                    'Best (kg×reps)',
                    style: TextStyle(
                      color: AppColors.gold,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          ..._strengthRecords.map((record) {
            final hasData = record['hasData'] == true;
            final isFlatBench = record['displayName'] == 'Flat Bench Press';

            return Container(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: Colors.white.withOpacity(0.05),
                  ),
                ),
              ),
              child: Row(
                children: [
                  SizedBox(
                    width: 90,
                    child: Row(
                      children: [
                        Text(
                          record['displayName'],
                          style: TextStyle(
                            color:
                                hasData ? Colors.white : Colors.grey.shade500,
                            fontSize: 12,
                            fontWeight:
                                hasData ? FontWeight.w600 : FontWeight.normal,
                          ),
                        ),
                        if (isFlatBench && hasData)
                          Container(
                            margin: const EdgeInsets.only(left: 4),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 3,
                              vertical: 1,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.gold.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(3),
                            ),
                            child: Text(
                              '🏆',
                              style: TextStyle(
                                fontSize: 8,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  Expanded(
                    flex: 1,
                    child: Text(
                      hasData
                          ? DateFormat('dd/MM/yy').format(record['lastDate'])
                          : '-',
                      style: TextStyle(
                        color: hasData ? Colors.white70 : Colors.grey.shade500,
                        fontSize: 11,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  Expanded(
                    flex: 1,
                    child: Text(
                      hasData
                          ? '${record['lastKg']}×${record['lastReps']}'
                          : '-',
                      style: TextStyle(
                        color: hasData ? Colors.white : Colors.grey.shade500,
                        fontSize: 11,
                        fontWeight:
                            hasData ? FontWeight.w500 : FontWeight.normal,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  Expanded(
                    flex: 1,
                    child: Text(
                      hasData
                          ? DateFormat('dd/MM/yy').format(record['highestDate'])
                          : '-',
                      style: TextStyle(
                        color: hasData ? Colors.white70 : Colors.grey.shade500,
                        fontSize: 11,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  Expanded(
                    flex: 1,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          hasData
                              ? '${record['highestKg']}×${record['highestReps']}'
                              : '-',
                          style: TextStyle(
                            color:
                                hasData ? AppColors.gold : Colors.grey.shade500,
                            fontSize: 12,
                            fontWeight:
                                hasData ? FontWeight.bold : FontWeight.normal,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        if (hasData && isFlatBench)
                          Container(
                            margin: const EdgeInsets.only(left: 4),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 4,
                              vertical: 1,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.green.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              'BEST',
                              style: TextStyle(
                                color: Colors.green,
                                fontSize: 7,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          }),
          // Note for Flat Bench Press
          if (_strengthRecords.any((r) =>
              r['displayName'] == 'Flat Bench Press' && r['hasData'] == true))
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                '🏆 Flat Bench Press = Best of Barbell + Dumbbell',
                style: TextStyle(
                  color: Colors.grey.shade500,
                  fontSize: 10,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
