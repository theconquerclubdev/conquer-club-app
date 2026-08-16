// lib/screens/member/workout_progress_screen.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../theme/app_theme.dart';

class WorkoutProgressScreen extends StatefulWidget {
  const WorkoutProgressScreen({super.key});

  @override
  State<WorkoutProgressScreen> createState() => _WorkoutProgressScreenState();
}

class _WorkoutProgressScreenState extends State<WorkoutProgressScreen> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _strengthRecords = [];
  String? _errorMessage;

  // ✅ Exercise mapping for Strength Records (Optimized)
  // Simplified to only Barbell exercises for faster loading
  final List<Map<String, dynamic>> _trackedExercises = [
    {
      'displayName': 'Barbell Squats',
      'dbNames': [
        {'name': 'Barbell Squats', 'tag': 'BB'},
      ],
    },
    {
      'displayName': 'Flat Barbell Press',
      'dbNames': [
        {'name': 'Flat Barbell Press', 'tag': 'BB'},
      ],
    },
    {
      'displayName': 'Barbell Shoulder Press',
      'dbNames': [
        {'name': 'Barbell Shoulder Press', 'tag': 'BB'},
      ],
    },
    {
      'displayName': 'Barbell Deadlift',
      'dbNames': [
        {'name': 'Barbell Deadlift', 'tag': 'BB'},
      ],
    },
  ];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Please login to view progress';
        });
        return;
      }
      final records = await _getStrengthRecords(userId);
      setState(() {
        _strengthRecords = records;
        _isLoading = false;
      });
    } catch (e) {
      print('Error loading strength records: $e');
      setState(() {
        _isLoading = false;
        _errorMessage = e.toString();
      });
    }
  }

  Future<List<Map<String, dynamic>>> _getStrengthRecords(String userId) async {
    final List<Map<String, dynamic>> records = [];

    // OPTIMIZATION: Get all exercise names we need in one query
    final allExerciseNames = _trackedExercises
        .expand((e) => (e['dbNames'] as List).map((v) => v['name'] as String))
        .toList();

    // Single query to get all exercise IDs
    final allExercises = await Supabase.instance.client
        .from('exercises')
        .select('id, name')
        .inFilter('name', allExerciseNames);

    final exerciseIdMap = <String, String>{}; // name -> id
    for (final ex in allExercises) {
      exerciseIdMap[ex['name'] as String] = ex['id'] as String;
    }

    // Build a map of exercise name -> tag for each tracked exercise
    final exerciseConfigs = <String, List<Map<String, String>>>{};
    for (final config in _trackedExercises) {
      final displayName = config['displayName'] as String;
      final dbNames = config['dbNames'] as List<Map<String, String>>;
      exerciseConfigs[displayName] = dbNames;
    }

    // Get ALL workout_exercises for ALL tracked exercises in one query
    final allExerciseIds = allExercises.map((e) => e['id'] as String).toList();

    if (allExerciseIds.isEmpty) {
      // No exercises found in database
      for (final config in _trackedExercises) {
        records.add(_emptyRecord(config['displayName'] as String));
      }
      return records;
    }

    final allWorkoutExercises = await Supabase.instance.client
        .from('workout_exercises')
        .select('id, workout_id, exercise_id')
        .inFilter('exercise_id', allExerciseIds);

    if (allWorkoutExercises.isEmpty) {
      for (final config in _trackedExercises) {
        records.add(_emptyRecord(config['displayName'] as String));
      }
      return records;
    }

    // Get ALL sets from session_set_logs (actual member logged data)
    final allWorkoutExerciseIds =
        allWorkoutExercises.map((we) => we['id'] as String).toList();
    final allSets = await Supabase.instance.client
        .from('session_set_logs')
        .select(
            'id, kg:actual_kg, reps:actual_reps, workout_exercise_id, session_id')
        .inFilter('workout_exercise_id', allWorkoutExerciseIds)
        .eq('completed', true);

    if (allSets.isEmpty) {
      for (final config in _trackedExercises) {
        records.add(_emptyRecord(config['displayName'] as String));
      }
      return records;
    }

    // Build lookup maps
    final workoutIdMap = <String, String>{}; // workoutExerciseId -> workoutId
    final exerciseIdForWE =
        <String, String>{}; // workoutExerciseId -> exerciseId
    for (final we in allWorkoutExercises) {
      final weId = we['id'] as String;
      workoutIdMap[weId] = we['workout_id'] as String;
      exerciseIdForWE[weId] = we['exercise_id'] as String;
    }

    // Get session IDs from session_set_logs (filter out null)
    final sessionIds = allSets
        .map((s) => s['session_id'] as String?)
        .where((id) => id != null)
        .cast<String>()
        .toSet()
        .toList();

    // Get all completed sessions for these session IDs
    final sessions = <Map<String, dynamic>>[];
    if (sessionIds.isNotEmpty) {
      final result = await Supabase.instance.client
          .from('workout_sessions')
          .select('id, started_at, workout_id')
          .inFilter('id', sessionIds)
          .eq('status', 'completed');
      sessions.addAll(result);
    }

    final sessionDates = <String, DateTime>{};
    final sessionWorkoutMap = <String, String>{}; // sessionId -> workoutId
    for (final session in sessions) {
      final startedAt = DateTime.tryParse(session['started_at'] as String);
      final workoutId = session['workout_id'] as String?;
      final sessionId = session['id'] as String?;
      if (startedAt != null && workoutId != null && sessionId != null) {
        sessionDates[workoutId] = startedAt;
        sessionWorkoutMap[sessionId] = workoutId;
      }
    }

    // Build exercise name -> exercise id mapping for lookup
    final exerciseNameToId = <String, String>{};
    for (final ex in allExercises) {
      exerciseNameToId[ex['name'] as String] = ex['id'] as String;
    }

    // Process each tracked exercise
    for (final config in _trackedExercises) {
      final displayName = config['displayName'] as String;
      final dbNames = config['dbNames'] as List<Map<String, String>>;

      // Get exercise IDs for this exercise
      final exerciseIds = <String>[];
      final tagMap = <String, String>{}; // exerciseId -> tag
      for (final variant in dbNames) {
        final exId = exerciseNameToId[variant['name']!];
        if (exId != null) {
          exerciseIds.add(exId);
          tagMap[exId] = variant['tag']!;
        }
      }

      if (exerciseIds.isEmpty) {
        records.add(_emptyRecord(displayName));
        continue;
      }

      // Filter workout_exercises for this exercise
      final relevantWEs = allWorkoutExercises
          .where((we) => exerciseIds.contains(we['exercise_id'] as String))
          .toList();

      if (relevantWEs.isEmpty) {
        records.add(_emptyRecord(displayName));
        continue;
      }

      final relevantWEIds =
          relevantWEs.map((we) => we['id'] as String).toList();

      // Filter sets for this exercise
      final relevantSets = allSets
          .where((set) =>
              relevantWEIds.contains(set['workout_exercise_id'] as String))
          .toList();

      if (relevantSets.isEmpty) {
        records.add(_emptyRecord(displayName));
        continue;
      }

      // Build tag map for workout_exercise_id
      final weTagMap = <String, String>{};
      for (final we in relevantWEs) {
        final weId = we['id'] as String;
        final exId = we['exercise_id'] as String;
        weTagMap[weId] = tagMap[exId] ?? '';
      }

      // Build sets with dates
      final setsWithDates = <Map<String, dynamic>>[];
      for (final set in relevantSets) {
        final weId = set['workout_exercise_id'] as String;
        final sessionId = set['session_id'] as String?;
        if (sessionId == null) continue;
        final workoutId = sessionWorkoutMap[sessionId];
        if (workoutId == null) continue;
        final date = sessionDates[workoutId];
        if (date == null) continue;

        final kg = (set['kg'] as num?)?.toDouble() ?? 0;
        final reps = (set['reps'] as num?)?.toInt() ?? 0;

        // Skip sets where both kg and reps are 0 (invalid/empty logs)
        if (kg == 0 && reps == 0) continue;

        setsWithDates.add({
          'kg': kg,
          'reps': reps,
          'date': date,
          'tag': weTagMap[weId] ?? '',
        });
      }

      if (setsWithDates.isEmpty) {
        records.add(_emptyRecord(displayName));
        continue;
      }

      // Compare function
      int compareSets(Map<String, dynamic> a, Map<String, dynamic> b) {
        final kgCompare = (a['kg'] as double).compareTo(b['kg'] as double);
        if (kgCompare != 0) return kgCompare;
        return (a['reps'] as int).compareTo(b['reps'] as int);
      }

      final highestSet =
          setsWithDates.reduce((a, b) => compareSets(a, b) >= 0 ? a : b);

      final latestDate = setsWithDates
          .map((s) => s['date'] as DateTime)
          .reduce((a, b) => a.isAfter(b) ? a : b);
      final latestSessionSets =
          setsWithDates.where((s) => s['date'] == latestDate).toList();
      final lastSet =
          latestSessionSets.reduce((a, b) => compareSets(a, b) >= 0 ? a : b);

      records.add({
        'displayName': displayName,
        'hasData': true,
        'lastDate': lastSet['date'],
        'lastKg': lastSet['kg'],
        'lastReps': lastSet['reps'],
        'lastTag': lastSet['tag'],
        'highestDate': highestSet['date'],
        'highestKg': highestSet['kg'],
        'highestReps': highestSet['reps'],
        'highestTag': highestSet['tag'],
      });
    }

    return records;
  }

  Map<String, dynamic> _emptyRecord(String displayName) {
    return {
      'displayName': displayName,
      'hasData': false,
      'lastDate': null,
      'lastKg': null,
      'lastReps': null,
      'lastTag': null,
      'highestDate': null,
      'highestKg': null,
      'highestReps': null,
      'highestTag': null,
    };
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
          : _errorMessage != null
              ? _buildErrorView()
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

  Widget _buildErrorView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.error_outline,
            color: Colors.grey.shade600,
            size: 64,
          ),
          const SizedBox(height: 16),
          Text(
            'Something went wrong',
            style: TextStyle(
              color: Colors.grey.shade500,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              _errorMessage ?? 'Unable to load strength records',
              style: TextStyle(
                color: Colors.grey.shade400,
                fontSize: 14,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: _loadData,
            child: const Text('RETRY'),
          ),
        ],
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

    return LayoutBuilder(
      builder: (context, constraints) {
        final tableWidth =
            constraints.maxWidth < 560 ? 560.0 : constraints.maxWidth;

        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          physics: constraints.maxWidth < 560
              ? const AlwaysScrollableScrollPhysics()
              : const NeverScrollableScrollPhysics(),
          child: SizedBox(
            width: tableWidth,
            child: Container(
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
                    padding:
                        const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
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
                    final isFlatBench = false;

                    // Safe date formatting - FIXED: handle null dates
                    String formatDate(dynamic date) {
                      if (date == null) return '-';
                      if (date is DateTime) {
                        return DateFormat('dd/MM/yy').format(date);
                      }
                      return '-';
                    }

                    return Container(
                      padding: const EdgeInsets.symmetric(
                          vertical: 8, horizontal: 8),
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
                                Expanded(
                                  child: Text(
                                    record['displayName'],
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: hasData
                                          ? Colors.white
                                          : Colors.grey.shade500,
                                      fontSize: 12,
                                      fontWeight: hasData
                                          ? FontWeight.w600
                                          : FontWeight.normal,
                                    ),
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
                              hasData ? formatDate(record['lastDate']) : '-',
                              style: TextStyle(
                                color: hasData
                                    ? Colors.white70
                                    : Colors.grey.shade500,
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
                                      '${record['lastTag'] != null && record['lastTag'] != '' ? ' ${record['lastTag']}' : ''}'
                                  : '-',
                              style: TextStyle(
                                color: hasData
                                    ? Colors.white
                                    : Colors.grey.shade500,
                                fontSize: 11,
                                fontWeight: hasData
                                    ? FontWeight.w500
                                    : FontWeight.normal,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                          Expanded(
                            flex: 1,
                            child: Text(
                              hasData ? formatDate(record['highestDate']) : '-',
                              style: TextStyle(
                                color: hasData
                                    ? Colors.white70
                                    : Colors.grey.shade500,
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
                                          '${record['highestTag'] != null && record['highestTag'] != '' ? ' ${record['highestTag']}' : ''}'
                                      : '-',
                                  style: TextStyle(
                                    color: hasData
                                        ? AppColors.gold
                                        : Colors.grey.shade500,
                                    fontSize: 12,
                                    fontWeight: hasData
                                        ? FontWeight.bold
                                        : FontWeight.normal,
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
                  // Note for best lift
                  if (_strengthRecords.any((r) =>
                      r['displayName'] == 'Barbell Deadlift' &&
                      r['hasData'] == true))
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        '💪 Track your best Barbell lifts here',
                        style: TextStyle(
                          color: Colors.grey.shade500,
                          fontSize: 10,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
