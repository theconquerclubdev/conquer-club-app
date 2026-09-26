import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../theme/app_theme.dart';
import '../providers/master_data_provider.dart';

class WorkoutDaySessionScreen extends StatefulWidget {
  final Map<String, dynamic> workout;
  final bool isViewOnly;

  const WorkoutDaySessionScreen({
    super.key,
    required this.workout,
    this.isViewOnly = false,
  });

  @override
  State<WorkoutDaySessionScreen> createState() =>
      _WorkoutDaySessionScreenState();
}

class _WorkoutDaySessionScreenState extends State<WorkoutDaySessionScreen>
    with WidgetsBindingObserver {
  bool isLoading = true;
  List<Map<String, dynamic>> exercises = [];
  bool isViewingDetails = false;

  String? sessionId;
  String sessionStatus = 'none'; // none | in_progress | completed
  int savedElapsedSeconds = 0;

  final Stopwatch stopwatch = Stopwatch();
  Timer? tickTimer;
  DateTime? runStartTime;
  static String? _persistentSessionId;
  static DateTime? _persistentRunStartTime;
  static int _persistentBaseSeconds = 0;

  bool _isLoadingWorkout = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    loadEverything();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (sessionStatus == 'in_progress' &&
        stopwatch.isRunning &&
        sessionId != null) {
      Supabase.instance.client
          .from('workout_sessions')
          .update({'elapsed_seconds': currentTotalSeconds})
          .eq('id', sessionId!)
          .catchError((_) {});
    }
    tickTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      setState(() {});
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      if (sessionStatus == 'in_progress' &&
          stopwatch.isRunning &&
          sessionId != null) {
        Supabase.instance.client
            .from('workout_sessions')
            .update({'elapsed_seconds': currentTotalSeconds})
            .eq('id', sessionId!)
            .catchError((_) {});
      }
    }
  }

  @override
  void deactivate() {
    // ✅ Timer keeps running even when phone is locked
    // Do NOT pause workout here - the workout timer should continue
    super.deactivate();
  }

  final Set<String> _expandedHistoryIds = {};
  Map<String, List<Map<String, dynamic>>>? _allHistory;
  bool _historyLoading = false;

  Future<void> _toggleHistory(String workoutExerciseId) async {
    if (_expandedHistoryIds.contains(workoutExerciseId)) {
      setState(() => _expandedHistoryIds.remove(workoutExerciseId));
      return;
    }
    setState(() => _expandedHistoryIds.add(workoutExerciseId));
    if (_allHistory != null) return; // whole workout already fetched once
    setState(() => _historyLoading = true);
    final data = await MasterDataProvider.instance
        .getWorkoutHistory(widget.workout['id']);
    if (!mounted) return;
    setState(() {
      _allHistory = data;
      _historyLoading = false;
    });
  }

  int get totalSetsCount =>
      exercises.fold(0, (sum, e) => sum + (e['sets'] as List).length);

  int get completedSetsCount => exercises.fold(
        0,
        (sum, e) =>
            sum +
            (e['sets'] as List).where((s) => s['completed'] == true).length,
      );

  bool get isFullyCompleted =>
      totalSetsCount > 0 && completedSetsCount == totalSetsCount;

  Future<void> loadEverything() async {
    // ✅ Guard against overlapping calls
    if (_isLoadingWorkout) return;
    _isLoadingWorkout = true;

    setState(() => isLoading = true);
    final memberId = Supabase.instance.client.auth.currentUser!.id;

    try {
      final weData = await Supabase.instance.client
          .from('workout_exercises')
          .select(
            'id, order_index, exercises(id, name, body_part, input_type), workout_sets(set_number, kg, reps, minutes, seconds)',
          )
          .eq('workout_id', widget.workout['id'])
          .order('order_index', ascending: true);

      final loadedExercises = <Map<String, dynamic>>[];
      for (final we in weData) {
        final rawSets = List<Map<String, dynamic>>.from(
          we['workout_sets'] ?? [],
        );
        rawSets.sort(
          (a, b) => (a['set_number'] as int).compareTo(b['set_number'] as int),
        );

        final inputType = we['exercises']['input_type'] ?? 'Reps';
        final sets = rawSets.map((s) {
          return {
            'set_number': s['set_number'],
            'coach_kg': s['kg'],
            'coach_reps': s['reps'],
            'actual_kg': s['kg'],
            'actual_reps': s['reps'],
            'actual_minutes': s['minutes'] ?? 0,
            'actual_seconds': s['seconds'] ?? 0,
            'completed': false,
          };
        }).toList();

        loadedExercises.add({
          'workout_exercise_id': we['id'],
          'name': we['exercises']['name'],
          'body_part': we['exercises']['body_part'],
          'input_type': inputType,
          'sets': sets,
        });
      }

      // Keep the member's completed workout records available for the
      // current weekly cycle. Sunday starts a new cycle, so sessions from
      // the previous week are not loaded after the Sunday reset.
      final now =
          DateTime.now().toUtc().add(const Duration(hours: 5, minutes: 30));
      final daysSinceSunday = now.weekday % 7;
      final weekStart = DateTime.utc(
        now.year,
        now.month,
        now.day,
      )
          .subtract(Duration(days: daysSinceSunday))
          .subtract(const Duration(hours: 5, minutes: 30));

      final existing = await Supabase.instance.client
          .from('workout_sessions')
          .select()
          .eq('workout_id', widget.workout['id'])
          .eq('member_id', memberId)
          .gte('started_at', weekStart.toIso8601String())
          .order('started_at', ascending: false)
          .limit(1)
          .maybeSingle();

      if (existing != null) {
        sessionId = existing['id'];
        sessionStatus = existing['status'] ?? 'none';
        savedElapsedSeconds = existing['elapsed_seconds'] ?? 0;

        final logs = await Supabase.instance.client
            .from('session_set_logs')
            .select(
                'workout_exercise_id, set_number, completed, actual_kg, actual_reps, actual_minutes, actual_seconds')
            .eq('session_id', sessionId!);

        for (final log in logs) {
          for (final ex in loadedExercises) {
            if (ex['workout_exercise_id'] != log['workout_exercise_id'])
              continue;
            for (final set in (ex['sets'] as List)) {
              if (set['set_number'] == log['set_number']) {
                set['actual_kg'] = log['actual_kg'] ?? set['actual_kg'];
                set['actual_reps'] = log['actual_reps'] ?? set['actual_reps'];
                set['actual_minutes'] =
                    log['actual_minutes'] ?? set['actual_minutes'];
                set['actual_seconds'] =
                    log['actual_seconds'] ?? set['actual_seconds'];
                set['completed'] = log['completed'] ?? false;
              }
            }
          }
        }
      }

      if (mounted) {
        setState(() {
          exercises = loadedExercises;
          isLoading = false;
        });
      }

      if (sessionStatus == 'in_progress') startTicking();
    } catch (e) {
      debugPrint('Error loading workout: $e');
      if (mounted) {
        setState(() => isLoading = false);
      }
    } finally {
      _isLoadingWorkout = false;
    }
  }

  void startTicking() {
    if (stopwatch.isRunning) return;
    if (_persistentSessionId == sessionId && _persistentRunStartTime != null) {
      runStartTime = _persistentRunStartTime;
    } else {
      runStartTime = DateTime.now();
      _persistentSessionId = sessionId;
      _persistentRunStartTime = runStartTime;
      _persistentBaseSeconds = savedElapsedSeconds;
    }
    stopwatch.start();
    tickTimer?.cancel();
    tickTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => setState(() {}),
    );
  }

  int get currentTotalSeconds =>
      (_persistentSessionId == sessionId && runStartTime != null
          ? _persistentBaseSeconds
          : savedElapsedSeconds) +
      (runStartTime != null
          ? DateTime.now().difference(runStartTime!).inSeconds
          : 0);

  String formatDuration(int totalSeconds) {
    final h = totalSeconds ~/ 3600;
    final m = (totalSeconds % 3600) ~/ 60;
    final s = totalSeconds % 60;
    if (h > 0) return '${h}h ${m}m ${s}s';
    if (m > 0) return '${m}m ${s}s';
    return '${s}s';
  }

  Future<void> startWorkout() async {
    if (widget.isViewOnly) return;

    try {
      final memberId = Supabase.instance.client.auth.currentUser!.id;
      final row = await Supabase.instance.client
          .from('workout_sessions')
          .insert({
            'workout_id': widget.workout['id'],
            'member_id': memberId,
            'day_of_week': widget.workout['day_of_week'],
            'status': 'in_progress',
            'started_at': DateTime.now().toUtc().toIso8601String(),
            'elapsed_seconds': 0,
          })
          .select()
          .single();

      setState(() {
        sessionId = row['id'];
        sessionStatus = 'in_progress';
        savedElapsedSeconds = 0;
      });
      startTicking();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to start workout')),
        );
      }
    }
  }

  Future<void> pauseWorkout() async {
    if (widget.isViewOnly) return;

    stopwatch.stop();
    tickTimer?.cancel();
    final total = currentTotalSeconds;
    runStartTime = null;
    _persistentRunStartTime = null;
    _persistentSessionId = null;
    await Supabase.instance.client
        .from('workout_sessions')
        .update({'elapsed_seconds': total}).eq('id', sessionId!);
    if (mounted) setState(() => savedElapsedSeconds = total);
    stopwatch.reset();
  }

  Future<void> resumeWorkout() async {
    if (widget.isViewOnly) return;
    startTicking();
  }

  void updateActualValue(
    String workoutExerciseId,
    int setIndex,
    String field,
    dynamic value,
  ) {
    if (widget.isViewOnly) return;

    final exercise = exercises.firstWhere(
      (e) => e['workout_exercise_id'] == workoutExerciseId,
    );
    final set = exercise['sets'][setIndex];
    if (set['completed'] == true) return;
    set[field] = value;
  }

  String getInputType(String workoutExerciseId) {
    final exercise = exercises.firstWhere(
      (e) => e['workout_exercise_id'] == workoutExerciseId,
    );
    return exercise['input_type'] ?? 'Reps';
  }

  Future<void> _upsertSetLogWithRetry(Map<String, dynamic> upsertData) async {
    const maxAttempts = 3;
    for (int attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        await Supabase.instance.client.from('session_set_logs').upsert(
              upsertData,
              onConflict: 'session_id,workout_exercise_id,set_number',
            );
        return;
      } catch (e) {
        if (attempt == maxAttempts) rethrow;
        await Future.delayed(Duration(seconds: attempt * 2));
      }
    }
  }

  Future<void> toggleSetDone(String workoutExerciseId, int setIndex) async {
    if (widget.isViewOnly) return;

    final exercise = exercises.firstWhere(
      (e) => e['workout_exercise_id'] == workoutExerciseId,
    );
    final set = exercise['sets'][setIndex];
    final nowCompleted = !(set['completed'] as bool);
    final inputType = exercise['input_type'] ?? 'Reps';

    final Map<String, dynamic> upsertData = {
      'session_id': sessionId,
      'workout_exercise_id': workoutExerciseId,
      'set_number': set['set_number'],
      'completed': nowCompleted,
      'completed_at':
          nowCompleted ? DateTime.now().toUtc().toIso8601String() : null,
    };
    if (inputType == 'kg × reps') {
      upsertData['actual_kg'] = set['actual_kg'];
      upsertData['actual_reps'] = set['actual_reps'];
    } else if (inputType == 'Min') {
      upsertData['actual_minutes'] = set['actual_minutes'];
      upsertData['actual_seconds'] = set['actual_seconds'];
    } else {
      // 'Reps'
      upsertData['actual_reps'] = set['actual_reps'];
    }

    try {
      await _upsertSetLogWithRetry(upsertData);

      if (mounted) setState(() => set['completed'] = nowCompleted);

      if (completedSetsCount == totalSetsCount && totalSetsCount > 0) {
        await finishWorkout();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
              'Connection issue — could not save this set. Check your internet and tap Retry.',
            ),
            action: SnackBarAction(
              label: 'Retry',
              onPressed: () => toggleSetDone(workoutExerciseId, setIndex),
            ),
          ),
        );
      }
    }
  }

  Future<void> finishWorkout() async {
    stopwatch.stop();
    tickTimer?.cancel();
    final total = currentTotalSeconds;
    runStartTime = null;
    _persistentRunStartTime = null;
    _persistentSessionId = null;

    await Supabase.instance.client.from('workout_sessions').update({
      'status': 'completed',
      'ended_at': DateTime.now().toUtc().toIso8601String(),
      'elapsed_seconds': total,
    }).eq('id', sessionId!);
    // Invalidate cache for the member
    final memberId = Supabase.instance.client.auth.currentUser?.id;
    if (memberId != null) {
      MasterDataProvider.instance.invalidateCache(memberId);
    }
    setState(() {
      sessionStatus = 'completed';
      savedElapsedSeconds = total;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(
          '${widget.workout['day_of_week']} · ${widget.workout['workout_name']}',
          style: const TextStyle(fontSize: 16),
        ),
        actions: [
          if (widget.isViewOnly)
            Container(
              margin: const EdgeInsets.only(right: 16),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.grey.withOpacity(0.2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Text(
                'VIEW ONLY',
                style: TextStyle(
                  color: Colors.grey,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
        ],
      ),
      body: isLoading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.gold),
            )
          : exercises.isEmpty
              ? _buildEmptyView()
              : widget.isViewOnly || isFullyCompleted
                  ? _buildViewOnlyView()
                  : sessionStatus == 'completed'
                      ? _buildCompletedView()
                      : sessionStatus == 'in_progress'
                          ? _buildActiveView()
                          : _buildStartView(),
    );
  }

  Widget _buildEmptyView() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline, size: 64, color: Colors.grey),
          const SizedBox(height: 16),
          const Text(
            'No exercises found for this workout',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey, fontSize: 16),
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('GO BACK'),
          ),
        ],
      ),
    );
  }

  Widget _buildStartView() {
    final screenWidth = MediaQuery.of(context).size.width;
    final scale = (screenWidth / 400).clamp(0.85, 1.2);

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 600),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
              child: Column(
                children: [
                  Icon(Icons.fitness_center,
                      size: 40 * scale, color: AppColors.gold),
                  SizedBox(height: 8 * scale),
                  Text(
                    widget.workout['workout_name'] ?? 'Workout',
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20 * scale,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  SizedBox(height: 4 * scale),
                  Text(
                    '${exercises.length} exercises · $totalSetsCount total sets',
                    style: TextStyle(color: Colors.grey, fontSize: 13 * scale),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: exercises.length,
                itemBuilder: (context, index) {
                  final ex = exercises[index];
                  final sets = ex['sets'] as List;
                  final inputType = ex['input_type'] ?? 'Reps';
                  return Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.cardDark,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.white.withOpacity(0.05)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          ex['name'] ?? 'Exercise',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 14 * scale,
                          ),
                        ),
                        Text(
                          ex['body_part'] ?? '',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: AppColors.gold.withOpacity(0.8),
                            fontSize: 11 * scale,
                          ),
                        ),
                        SizedBox(height: 6 * scale),
                        Wrap(
                          spacing: 8,
                          runSpacing: 4,
                          children: sets.map((s) {
                            final label = inputType == 'kg × reps'
                                ? '${s['coach_kg'] ?? '-'}kg × ${s['coach_reps'] ?? '-'}'
                                : inputType == 'Min'
                                    ? '${s['actual_minutes'] ?? 0}m ${s['actual_seconds'] ?? 0}s'
                                    : '${s['coach_reps'] ?? '-'} reps';
                            return Chip(
                              label: Text(
                                'Set ${s['set_number']}: $label',
                                style: TextStyle(fontSize: 11 * scale),
                              ),
                              backgroundColor: Colors.grey.withOpacity(0.15),
                              padding: EdgeInsets.zero,
                              visualDensity: VisualDensity.compact,
                              materialTapTargetSize:
                                  MaterialTapTargetSize.shrinkWrap,
                            );
                          }).toList(),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.play_arrow, color: Colors.black),
                      label: const Text('START WORKOUT'),
                      onPressed: startWorkout,
                    ),
                  ),
                  SizedBox(height: 16 * scale),
                  Text(
                    'Once you start, you can track your progress in real-time',
                    style: TextStyle(
                        color: Colors.grey.shade600, fontSize: 12 * scale),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActiveView() {
    final isRunning = stopwatch.isRunning;
    final total = totalSetsCount;
    final done = completedSetsCount;

    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          color: AppColors.cardDark,
          child: Row(
            children: [
              Text(
                formatDuration(currentTotalSeconds),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '$done / $total sets done',
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: AppColors.gold, fontSize: 11),
                    ),
                    const SizedBox(height: 4),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: LinearProgressIndicator(
                        value: total == 0 ? 0 : done / total,
                        minHeight: 5,
                        backgroundColor: Colors.white12,
                        color: AppColors.gold,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                width: 110,
                child: isRunning
                    ? OutlinedButton.icon(
                        icon: const Icon(
                          Icons.pause,
                          color: Colors.redAccent,
                          size: 16,
                        ),
                        label: const Text(
                          'PAUSE',
                          style:
                              TextStyle(color: Colors.redAccent, fontSize: 12),
                        ),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Colors.redAccent),
                          padding: const EdgeInsets.symmetric(vertical: 8),
                        ),
                        onPressed: pauseWorkout,
                      )
                    : ElevatedButton.icon(
                        icon: const Icon(
                          Icons.play_arrow,
                          color: Colors.black,
                          size: 16,
                        ),
                        label: const Text('RESUME',
                            style: TextStyle(fontSize: 12)),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                        ),
                        onPressed: resumeWorkout,
                      ),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: exercises.length,
            itemBuilder: (context, index) {
              final ex = exercises[index];
              final id = ex['workout_exercise_id'] as String;
              final sets = ex['sets'] as List;
              final exerciseDone = sets.every((s) => s['completed'] == true);

              Widget cell(String label, Widget child) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: 34,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          label,
                          style:
                              const TextStyle(color: Colors.grey, fontSize: 10),
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Expanded(child: child),
                  ],
                );
              }

              return Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.cardDark,
                  borderRadius: BorderRadius.circular(14),
                  border: exerciseDone
                      ? Border.all(color: Colors.green.withOpacity(0.5))
                      : null,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            ex['name'] ?? 'Exercise',
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: exerciseDone ? Colors.grey : Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                              decoration: exerciseDone
                                  ? TextDecoration.lineThrough
                                  : null,
                            ),
                          ),
                        ),
                        SizedBox(
                          width: 30,
                          height: 30,
                          child: IconButton(
                            padding: EdgeInsets.zero,
                            iconSize: 18,
                            icon: Icon(
                              _expandedHistoryIds.contains(id)
                                  ? Icons.remove_circle_outline
                                  : Icons.add_circle_outline,
                              color: AppColors.gold,
                            ),
                            onPressed: () => _toggleHistory(id),
                          ),
                        ),
                      ],
                    ),
                    Text(
                      ex['body_part'] ?? '',
                      style: TextStyle(
                        color: AppColors.gold.withOpacity(0.8),
                        fontSize: 11,
                      ),
                    ),
                    if (_expandedHistoryIds.contains(id))
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: _historyLoading
                            ? const Padding(
                                padding: EdgeInsets.symmetric(vertical: 8),
                                child: Center(
                                  child: SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: AppColors.gold,
                                    ),
                                  ),
                                ),
                              )
                            : Builder(builder: (context) {
                                final rows = _allHistory?[id] ?? [];
                                if (rows.isEmpty) {
                                  return const Text(
                                    'No workout history for this exercise',
                                    style: TextStyle(
                                        color: Colors.grey, fontSize: 12),
                                  );
                                }
                                final byDate =
                                    <String, List<Map<String, dynamic>>>{};
                                for (final r in rows) {
                                  final d = r['date'].toString();
                                  byDate.putIfAbsent(d, () => []).add(r);
                                }
                                final dates = byDate.keys.toList();
                                return SingleChildScrollView(
                                  scrollDirection: Axis.horizontal,
                                  child: Table(
                                    defaultColumnWidth:
                                        const IntrinsicColumnWidth(),
                                    border: TableBorder.all(
                                      color: Colors.white.withOpacity(0.08),
                                    ),
                                    children: [
                                      TableRow(children: [
                                        const Padding(
                                          padding: EdgeInsets.all(6),
                                          child: SizedBox(),
                                        ),
                                        for (final d in dates)
                                          Padding(
                                            padding: const EdgeInsets.all(6),
                                            child: Text(
                                              d,
                                              style: const TextStyle(
                                                  color: Colors.grey,
                                                  fontSize: 10),
                                            ),
                                          ),
                                      ]),
                                      for (var setNum = 1;
                                          setNum <=
                                              (byDate.values.first.length);
                                          setNum++)
                                        TableRow(children: [
                                          Padding(
                                            padding: const EdgeInsets.all(6),
                                            child: Text(
                                              'Set-$setNum',
                                              style: const TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 10),
                                            ),
                                          ),
                                          for (final d in dates)
                                            Padding(
                                              padding: const EdgeInsets.all(6),
                                              child: Builder(builder: (_) {
                                                final match =
                                                    byDate[d]!.firstWhere(
                                                  (s) =>
                                                      s['set_number'] == setNum,
                                                  orElse: () => {},
                                                );
                                                if (match.isEmpty) {
                                                  return const Text('-',
                                                      style: TextStyle(
                                                          color: Colors.grey,
                                                          fontSize: 10));
                                                }
                                                final label = match['kg'] !=
                                                        null
                                                    ? 'Kg-${match['kg']} reps-${match['reps'] ?? '-'}'
                                                    : match['minutes'] != null
                                                        ? '${match['minutes']}m ${match['seconds'] ?? 0}s'
                                                        : 'reps-${match['reps'] ?? '-'}';
                                                return Text(
                                                  label,
                                                  style: const TextStyle(
                                                      color: Colors.white,
                                                      fontSize: 10),
                                                );
                                              }),
                                            ),
                                        ]),
                                    ],
                                  ),
                                );
                              }),
                      ),
                    const SizedBox(height: 10),
                    ...sets.asMap().entries.map((entry) {
                      final setIdx = entry.key;
                      final set = entry.value;
                      final setDone = set['completed'] == true;
                      final inputType = ex['input_type'] ?? 'Reps';

                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            SizedBox(
                              width: 44,
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  'SET-${set['set_number']}',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              flex: 2,
                              child: Row(
                                children: [
                                  if (inputType == 'kg × reps')
                                    Expanded(
                                      child: cell(
                                        'KG',
                                        setDone
                                            ? Text(
                                                '${set['actual_kg'] ?? '-'}',
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(
                                                  color: Colors.white,
                                                ),
                                              )
                                            : TextFormField(
                                                initialValue: set['actual_kg']
                                                        ?.toString() ??
                                                    '',
                                                keyboardType:
                                                    const TextInputType
                                                        .numberWithOptions(
                                                  decimal: true,
                                                ),
                                                style: const TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 14,
                                                ),
                                                decoration:
                                                    const InputDecoration(
                                                  isDense: true,
                                                  contentPadding:
                                                      EdgeInsets.symmetric(
                                                    vertical: 8,
                                                    horizontal: 6,
                                                  ),
                                                  border: OutlineInputBorder(),
                                                ),
                                                onChanged: (v) =>
                                                    updateActualValue(
                                                  id,
                                                  setIdx,
                                                  'actual_kg',
                                                  double.tryParse(v),
                                                ),
                                              ),
                                      ),
                                    ),
                                  if (inputType == 'Min')
                                    Expanded(
                                      child: cell(
                                        'MIN',
                                        setDone
                                            ? Text(
                                                '${set['actual_minutes'] ?? 0}',
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(
                                                  color: Colors.white,
                                                ),
                                              )
                                            : TextFormField(
                                                initialValue:
                                                    set['actual_minutes']
                                                            ?.toString() ??
                                                        '',
                                                keyboardType:
                                                    TextInputType.number,
                                                style: const TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 14,
                                                ),
                                                decoration:
                                                    const InputDecoration(
                                                  isDense: true,
                                                  contentPadding:
                                                      EdgeInsets.symmetric(
                                                    vertical: 8,
                                                    horizontal: 6,
                                                  ),
                                                  border: OutlineInputBorder(),
                                                ),
                                                onChanged: (v) =>
                                                    updateActualValue(
                                                  id,
                                                  setIdx,
                                                  'actual_minutes',
                                                  int.tryParse(v) ?? 0,
                                                ),
                                              ),
                                      ),
                                    ),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: cell(
                                      inputType == 'Min' ? 'SEC' : 'REPS',
                                      setDone
                                          ? Text(
                                              inputType == 'Min'
                                                  ? '${set['actual_seconds'] ?? 0}'
                                                  : '${set['actual_reps'] ?? '-'}',
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                color: Colors.white,
                                              ),
                                            )
                                          : TextFormField(
                                              initialValue: inputType == 'Min'
                                                  ? (set['actual_seconds']
                                                          ?.toString() ??
                                                      '')
                                                  : (set['actual_reps']
                                                          ?.toString() ??
                                                      ''),
                                              keyboardType:
                                                  TextInputType.number,
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 14,
                                              ),
                                              decoration: const InputDecoration(
                                                isDense: true,
                                                contentPadding:
                                                    EdgeInsets.symmetric(
                                                  vertical: 8,
                                                  horizontal: 6,
                                                ),
                                                border: OutlineInputBorder(),
                                              ),
                                              onChanged: (v) =>
                                                  updateActualValue(
                                                id,
                                                setIdx,
                                                inputType == 'Min'
                                                    ? 'actual_seconds'
                                                    : 'actual_reps',
                                                inputType == 'Min'
                                                    ? (int.tryParse(v) ?? 0)
                                                    : int.tryParse(v),
                                              ),
                                            ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            SizedBox(
                              width: 36,
                              child: IconButton(
                                icon: Icon(
                                  setDone
                                      ? Icons.check_circle
                                      : Icons.check_circle_outline,
                                  color: setDone ? Colors.green : Colors.grey,
                                  size: 26,
                                ),
                                onPressed: () => toggleSetDone(id, setIdx),
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildCompletedView() {
    if (isViewingDetails) {
      return Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                IconButton(
                  icon: Icon(Icons.arrow_back, color: AppColors.gold),
                  onPressed: () => setState(() => isViewingDetails = false),
                ),
                const Text(
                  'Your Completed Plan',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: exercises.length,
              itemBuilder: (context, index) {
                final ex = exercises[index];
                final sets = ex['sets'] as List;
                return Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.cardDark,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        ex['name'],
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                      Text(
                        ex['body_part'],
                        style: TextStyle(
                          color: AppColors.gold.withOpacity(0.8),
                          fontSize: 11,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        children: sets.map<Widget>((s) {
                          final inputType = ex['input_type'] ?? 'Reps';
                          final kg = s['actual_kg'];
                          final reps = s['actual_reps'];
                          final minutes = s['actual_minutes'] ?? 0;
                          final seconds = s['actual_seconds'] ?? 0;

                          String displayText;
                          if (inputType == 'kg × reps') {
                            displayText = kg != null
                                ? '${kg}kg × $reps reps'
                                : '$reps reps';
                          } else if (inputType == 'Min') {
                            displayText = '${minutes}m ${seconds}s';
                          } else {
                            displayText = '$reps reps';
                          }

                          return Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.green.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              displayText,
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 11,
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      );
    }

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.emoji_events, size: 90, color: AppColors.gold),
          const SizedBox(height: 20),
          Text(
            '${widget.workout['day_of_week']} Workout Completed! 🎉',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Total time: ${formatDuration(savedElapsedSeconds)}',
            style: TextStyle(color: AppColors.gold, fontSize: 15),
          ),
          Text(
            '$totalSetsCount sets · ${exercises.length} exercises',
            style: const TextStyle(color: Colors.grey, fontSize: 13),
          ),
          const SizedBox(height: 32),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('BACK TO WEEK VIEW'),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: () => setState(() => isViewingDetails = true),
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: AppColors.gold),
              ),
              child: Text(
                'VIEW MY PLAN (READ-ONLY)',
                style: TextStyle(color: AppColors.gold),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildViewOnlyView() {
    return Column(
      children: [
        // Header with "View Only" badge and "Pay to Unlock" message if membership expired
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          color: AppColors.cardDark,
          child: Column(
            children: [
              const Text(
                '👁️ View Only Mode',
                style: TextStyle(
                  color: Colors.grey,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              if (!widget.isViewOnly)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.green.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    '✅ Workout Completed',
                    style: TextStyle(
                      color: Colors.green,
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              if (!widget.isViewOnly) const SizedBox(height: 8),
              Text(
                'Total time: ${formatDuration(savedElapsedSeconds)}',
                style: TextStyle(color: AppColors.gold, fontSize: 13),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: exercises.length,
            itemBuilder: (context, index) {
              final ex = exercises[index];
              final sets = ex['sets'] as List;

              return Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.cardDark,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.white.withOpacity(0.05)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            ex['name'] ?? 'Exercise',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.grey.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Text(
                            'VIEW ONLY',
                            style: TextStyle(
                              color: Colors.grey,
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                    Text(
                      ex['body_part'] ?? '',
                      style: TextStyle(
                        color: AppColors.gold.withOpacity(0.8),
                        fontSize: 11,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        const SizedBox(
                          width: 36,
                          child: Text(
                            'SET',
                            style: TextStyle(color: Colors.grey, fontSize: 11),
                          ),
                        ),
                        Expanded(
                          flex: 2,
                          child: Text(
                            ex['input_type'] == 'kg × reps'
                                ? 'ACTUAL (kg / reps)'
                                : ex['input_type'] == 'Min'
                                    ? 'ACTUAL (min / sec)'
                                    : 'ACTUAL (reps)',
                            style: const TextStyle(
                                color: Colors.grey, fontSize: 11),
                          ),
                        ),
                        const SizedBox(width: 36),
                      ],
                    ),
                    ...sets.asMap().entries.map((entry) {
                      final setIdx = entry.key;
                      final set = entry.value;
                      final setDone = set['completed'] == true;
                      final inputType = ex['input_type'] ?? 'Reps';

                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            SizedBox(
                              width: 36,
                              child: Text(
                                '${set['set_number']}',
                                style: const TextStyle(color: Colors.white),
                              ),
                            ),
                            Expanded(
                              flex: 2,
                              child: Row(
                                children: [
                                  if (inputType == 'kg × reps')
                                    Expanded(
                                      child: Text(
                                        '${set['actual_kg'] ?? '-'}',
                                        style: const TextStyle(
                                          color: Colors.white,
                                        ),
                                      ),
                                    ),
                                  if (inputType == 'Min')
                                    Expanded(
                                      child: Text(
                                        '${set['actual_minutes'] ?? 0}',
                                        style: const TextStyle(
                                          color: Colors.white,
                                        ),
                                      ),
                                    ),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      inputType == 'Min'
                                          ? '${set['actual_seconds'] ?? 0}'
                                          : '${set['actual_reps'] ?? '-'}',
                                      style: const TextStyle(
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            SizedBox(
                              width: 36,
                              child: Icon(
                                setDone
                                    ? Icons.check_circle
                                    : Icons.check_circle_outline,
                                color: setDone ? Colors.green : Colors.grey,
                                size: 26,
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
