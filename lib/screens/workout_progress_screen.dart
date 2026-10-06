// lib/screens/member/workout_progress_screen.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../theme/app_theme.dart';
import '../providers/master_data_provider.dart';

class WorkoutProgressScreen extends StatefulWidget {
  // Optional: pass this when a coach/admin is viewing a specific
  // member's progress. If omitted, defaults to the logged-in user
  // (unchanged behaviour for the member's own "My Progress" screen).
  final String? memberId;

  const WorkoutProgressScreen({super.key, this.memberId});

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

  bool _isLoadingRecords = false;

  // ✅ Weekly Workout Plan preview (added — does NOT touch the table below)
  final List<String> _weekDays = const [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];
  String _todayName = '';
  String? _selectedDay;
  bool _weeklyLoading = true;
  Map<String, Map<String, dynamic>> _weeklyWorkouts = {};
  final Map<String, String> _todayStatus = {};
  final Map<String, List<Map<String, dynamic>>> _dayExercisesCache = {};
  bool _dayExLoading = false;
  final Set<String> _expandedHistoryIds = {};
  final Set<String> _historyLoadingWorkoutIds = {};
  final Map<String, Map<String, List<Map<String, dynamic>>>> _historyCache = {};

  @override
  void initState() {
    super.initState();
    _loadData();
    _loadWeeklyPlan();
  }

  Future<void> _loadData() async {
    // ✅ Guard against overlapping calls
    if (_isLoadingRecords) return;
    _isLoadingRecords = true;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final userId =
          widget.memberId ?? Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) {
        if (mounted) {
          setState(() {
            _isLoading = false;
            _errorMessage = 'Please login to view progress';
          });
        }
        _isLoadingRecords = false;
        return;
      }
      final records = await _getStrengthRecords(userId);
      if (mounted) {
        setState(() {
          _strengthRecords = records;
          _isLoading = false;
        });
      }
    } on PostgrestException catch (e) {
      debugPrint('Error loading strength records: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage =
              'Unable to load strength records. Please check your internet connection and try again.';
        });
      }
    } catch (e) {
      debugPrint('Error loading strength records: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage =
              'Unable to connect. Please check your internet connection and try again.';
        });
      }
    } finally {
      _isLoadingRecords = false;
    }
  }

  Future<List<Map<String, dynamic>>> _getStrengthRecords(String userId) async {
    final List<Map<String, dynamic>> records = [];

    // Flatten every tracked exercise's db name variants (today there's
    // exactly one variant per exercise, but this keeps working if more
    // are added later) and remember which displayName + tag each name
    // belongs to.
    final dbNameToDisplayName = <String, String>{};
    final dbNameToTag = <String, String>{};
    final allDbNames = <String>[];
    for (final config in _trackedExercises) {
      final displayName = config['displayName'] as String;
      final dbNames = config['dbNames'] as List<Map<String, String>>;
      for (final variant in dbNames) {
        final name = variant['name']!;
        allDbNames.add(name);
        dbNameToDisplayName[name] = displayName;
        dbNameToTag[name] = variant['tag']!;
      }
    }

    // ✅ Single RPC call — server aggregates and filters by this member
    // only, instead of pulling every member's logged sets to the client.
    final result = await Supabase.instance.client.rpc(
      'get_member_strength_records',
      params: {
        'p_member_id': userId,
        'p_exercise_names': allDbNames,
      },
    );

    final rows = List<Map<String, dynamic>>.from(result as List);

    // Group rows back by displayName, since a displayName can (in
    // theory) map to more than one db exercise name/variant.
    final rowsByDisplayName = <String, List<Map<String, dynamic>>>{};
    for (final row in rows) {
      if (row['has_data'] != true) continue;
      final dbName = row['exercise_name'] as String;
      final displayName = dbNameToDisplayName[dbName];
      if (displayName == null) continue;
      rowsByDisplayName.putIfAbsent(displayName, () => []).add(row);
    }

    for (final config in _trackedExercises) {
      final displayName = config['displayName'] as String;
      final variantRows = rowsByDisplayName[displayName];

      if (variantRows == null || variantRows.isEmpty) {
        records.add(_emptyRecord(displayName));
        continue;
      }

      // Pick the variant with the most recent lastDate, and the
      // variant with the highest highestKg/highestReps — same
      // "best across variants" behaviour as before.
      Map<String, dynamic> latestRow = variantRows.first;
      Map<String, dynamic> bestRow = variantRows.first;
      for (final row in variantRows) {
        final rowLastDate =
            DateTime.tryParse(row['last_date'] as String? ?? '');
        final latestDate =
            DateTime.tryParse(latestRow['last_date'] as String? ?? '');
        if (rowLastDate != null &&
            (latestDate == null || rowLastDate.isAfter(latestDate))) {
          latestRow = row;
        }

        final rowKg = (row['highest_kg'] as num?)?.toDouble() ?? 0;
        final rowReps = (row['highest_reps'] as num?)?.toInt() ?? 0;
        final bestKg = (bestRow['highest_kg'] as num?)?.toDouble() ?? 0;
        final bestReps = (bestRow['highest_reps'] as num?)?.toInt() ?? 0;
        if (rowKg > bestKg || (rowKg == bestKg && rowReps > bestReps)) {
          bestRow = row;
        }
      }

      records.add({
        'displayName': displayName,
        'hasData': true,
        'lastDate': DateTime.tryParse(latestRow['last_date'] as String),
        'lastKg': (latestRow['last_kg'] as num?)?.toDouble(),
        'lastReps': (latestRow['last_reps'] as num?)?.toInt(),
        'lastTag': dbNameToTag[latestRow['exercise_name']] ?? '',
        'highestDate': DateTime.tryParse(bestRow['highest_date'] as String),
        'highestKg': (bestRow['highest_kg'] as num?)?.toDouble(),
        'highestReps': (bestRow['highest_reps'] as num?)?.toInt(),
        'highestTag': dbNameToTag[bestRow['exercise_name']] ?? '',
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

  // ============================================================
  // Weekly Workout Plan — data loading (new, additive only)
  // ============================================================
  Future<void> _loadWeeklyPlan() async {
    debugPrint('DEBUG _loadWeeklyPlan() called from:\n${StackTrace.current}');
    setState(() => _weeklyLoading = true);
    try {
      final userId =
          widget.memberId ?? Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) {
        if (mounted) setState(() => _weeklyLoading = false);
        return;
      }

      final istNow =
          DateTime.now().toUtc().add(const Duration(hours: 5, minutes: 30));
      _todayName = _weekDays[istNow.weekday - 1];

      final data = await Supabase.instance.client
          .from('workouts')
          .select()
          .eq('member_id', userId);

      final map = <String, Map<String, dynamic>>{};
      for (final w in List<Map<String, dynamic>>.from(data)) {
        map[w['day_of_week'] as String] = w;
      }

      final todayWorkout = map[_todayName];
      if (todayWorkout != null) {
        final startOfDay = DateTime.utc(
          istNow.year,
          istNow.month,
          istNow.day,
        ).subtract(const Duration(hours: 5, minutes: 30));

        final session = await Supabase.instance.client
            .from('workout_sessions')
            .select()
            .eq('workout_id', todayWorkout['id'])
            .eq('member_id', userId)
            .gte('started_at', startOfDay.toIso8601String())
            .order('started_at', ascending: false)
            .limit(1)
            .maybeSingle();

        if (session != null) {
          _todayStatus[todayWorkout['id'] as String] =
              session['status'] ?? 'none';
        }
      }

      if (!mounted) return;
      setState(() {
        _weeklyWorkouts = map;
        _selectedDay ??= _todayName;
        _weeklyLoading = false;
      });

      final day = _selectedDay;
      if (day != null) await _loadDayExercises(day);
    } catch (e) {
      debugPrint('⚠️ Error loading weekly plan: $e');
      if (mounted) setState(() => _weeklyLoading = false);
    }
  }

  Future<void> _selectDay(String day) async {
    setState(() => _selectedDay = day);
    await _loadDayExercises(day);
  }

  Future<void> _loadDayExercises(String day) async {
    final workout = _weeklyWorkouts[day];
    if (workout == null) return;
    final workoutId = workout['id'] as String;
    if (_dayExercisesCache.containsKey(workoutId)) return;

    setState(() => _dayExLoading = true);
    try {
      final weData = await Supabase.instance.client
          .from('workout_exercises')
          .select(
            'id, order_index, exercises(id, name, body_part, input_type), workout_sets(id, set_number, kg, reps, minutes, seconds)',
          )
          .eq('workout_id', workoutId)
          .order('order_index', ascending: true);

      final loaded = List<Map<String, dynamic>>.from(weData);
      for (final we in loaded) {
        final sets = List<Map<String, dynamic>>.from(we['workout_sets'] ?? []);
        sets.sort((a, b) =>
            (a['set_number'] as int).compareTo(b['set_number'] as int));
        we['workout_sets'] = sets;
      }

      if (!mounted) return;
      setState(() {
        _dayExercisesCache[workoutId] = loaded;
        _dayExLoading = false;
      });
    } catch (e) {
      debugPrint('⚠️ Error loading day exercises: $e');
      if (mounted) setState(() => _dayExLoading = false);
    }
  }

  Future<void> _toggleExerciseHistory(String workoutId, String weId) async {
    final key = '$workoutId|$weId';
    if (_expandedHistoryIds.contains(key)) {
      setState(() => _expandedHistoryIds.remove(key));
      return;
    }
    setState(() => _expandedHistoryIds.add(key));
    if (_historyCache.containsKey(workoutId)) return;

    setState(() => _historyLoadingWorkoutIds.add(workoutId));
    final data = await MasterDataProvider.instance.getWorkoutHistory(
      workoutId,
      memberId: widget.memberId,
    );
    if (!mounted) return;
    setState(() {
      _historyCache[workoutId] = data;
      _historyLoadingWorkoutIds.remove(workoutId);
    });
  }

  Future<void> _refreshAll() async {
    await Future.wait([_loadData(), _loadWeeklyPlan()]);
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
            onPressed: _refreshAll,
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
                  onRefresh: _refreshAll,
                  color: AppColors.gold,
                  backgroundColor: AppColors.cardDark,
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildWeeklyPlanSection(),
                      ],
                    ),
                  ),
                ),
    );
  }

  // ============================================================
  // Weekly Workout Plan — UI (new, additive only)
  // ============================================================
  Widget _buildWeeklyPlanSection() {
    if (_weeklyLoading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(
          child: CircularProgressIndicator(color: AppColors.gold),
        ),
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.cardDark,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '📅 WEEKLY WORKOUT PLAN',
            style: TextStyle(
              color: AppColors.gold,
              fontSize: 12,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 42,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _weekDays.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, i) {
                final day = _weekDays[i];
                final isToday = day == _todayName;
                final isSelected = day == _selectedDay;
                final workout = _weeklyWorkouts[day];
                final status =
                    workout != null ? _todayStatus[workout['id']] : null;
                final isCompletedToday = isToday && status == 'completed';
                final isInProgressToday = isToday && status == 'in_progress';

                return GestureDetector(
                  onTap: () => _selectDay(day),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? AppColors.gold.withOpacity(0.18)
                          : Colors.white.withOpacity(0.03),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: isSelected
                            ? AppColors.gold
                            : (isToday
                                ? AppColors.gold.withOpacity(0.5)
                                : Colors.white.withOpacity(0.08)),
                        width: isSelected ? 1.4 : 1,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (isCompletedToday)
                          const Padding(
                            padding: EdgeInsets.only(right: 4),
                            child: Icon(
                              Icons.check_circle,
                              color: Colors.green,
                              size: 14,
                            ),
                          ),
                        if (isInProgressToday)
                          const Padding(
                            padding: EdgeInsets.only(right: 4),
                            child: Icon(
                              Icons.play_circle,
                              color: AppColors.gold,
                              size: 14,
                            ),
                          ),
                        Text(
                          day.substring(0, 3).toUpperCase(),
                          style: TextStyle(
                            color: isSelected
                                ? AppColors.gold
                                : (isToday ? Colors.white : Colors.grey),
                            fontWeight: (isSelected || isToday)
                                ? FontWeight.bold
                                : FontWeight.normal,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 12),
          _buildSelectedDayWorkout(),
        ],
      ),
    );
  }

  Widget _buildSelectedDayWorkout() {
    final day = _selectedDay;
    if (day == null) return const SizedBox.shrink();
    final workout = _weeklyWorkouts[day];
    final isToday = day == _todayName;
    final status = workout != null ? _todayStatus[workout['id']] : null;

    if (workout == null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Text(
          'No workout assigned for $day',
          style: TextStyle(color: Colors.grey.shade500, fontSize: 13),
        ),
      );
    }

    final exercises = _dayExercisesCache[workout['id']] ?? [];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                workout['workout_name'] ?? 'Workout',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                ),
              ),
            ),
            if (isToday && status == 'completed')
              _statusBadge('Completed', Colors.green)
            else if (isToday && status == 'in_progress')
              _statusBadge('In Progress', AppColors.gold)
            else if (isToday)
              _statusBadge('Not started', Colors.grey)
            else
              _statusBadge('Preview', Colors.grey),
          ],
        ),
        const SizedBox(height: 10),
        if (_dayExLoading && exercises.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Center(
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppColors.gold,
                ),
              ),
            ),
          )
        else if (exercises.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(
              'No exercises added yet.',
              style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
            ),
          )
        else
          ...exercises.map(
            (we) => _buildExerciseWithHistory(workout['id'] as String, we),
          ),
      ],
    );
  }

  Widget _statusBadge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildExerciseWithHistory(
    String workoutId,
    Map<String, dynamic> we,
  ) {
    final ex = we['exercises'] as Map<String, dynamic>? ?? {};
    final weId = we['id'] as String;
    final key = '$workoutId|$weId';
    final inputType = ex['input_type'] ?? 'Reps';
    final sets = List<Map<String, dynamic>>.from(we['workout_sets'] ?? []);
    final expanded = _expandedHistoryIds.contains(key);
    final historyLoading = _historyLoadingWorkoutIds.contains(workoutId);
    final rows = _historyCache[workoutId]?[weId] ?? [];

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.03),
        borderRadius: BorderRadius.circular(10),
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
                    fontSize: 13,
                  ),
                ),
              ),
              SizedBox(
                width: 28,
                height: 28,
                child: IconButton(
                  padding: EdgeInsets.zero,
                  iconSize: 16,
                  icon: Icon(
                    expanded
                        ? Icons.remove_circle_outline
                        : Icons.add_circle_outline,
                    color: AppColors.gold,
                  ),
                  onPressed: () => _toggleExerciseHistory(workoutId, weId),
                ),
              ),
            ],
          ),
          Text(
            ex['body_part'] ?? '',
            style: TextStyle(
              color: AppColors.gold.withOpacity(0.8),
              fontSize: 10,
            ),
          ),
          const SizedBox(height: 4),
          ...sets.map((s) {
            String label;
            if (inputType == 'kg × reps') {
              label = '${s['kg'] ?? '-'} kg × ${s['reps'] ?? '-'} reps';
            } else if (inputType == 'Min') {
              label = '${s['minutes'] ?? 0}m ${s['seconds'] ?? 0}s';
            } else {
              label = '${s['reps'] ?? '-'} reps';
            }
            return Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                'Set ${s['set_number']}: $label',
                style: const TextStyle(color: Colors.grey, fontSize: 11),
              ),
            );
          }),
          if (expanded)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: historyLoading
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
                  : rows.isEmpty
                      ? const Text(
                          'No workout history for this exercise',
                          style: TextStyle(color: Colors.grey, fontSize: 11),
                        )
                      : _buildHistoryTable(rows),
            ),
        ],
      ),
    );
  }

  Widget _buildHistoryTable(List<Map<String, dynamic>> rows) {
    final byDate = <String, List<Map<String, dynamic>>>{};
    for (final r in rows) {
      final d = r['date'].toString();
      byDate.putIfAbsent(d, () => []).add(r);
    }
    final dates = byDate.keys.toList();
    final maxSets =
        byDate.values.fold<int>(0, (m, l) => l.length > m ? l.length : m);

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Table(
        defaultColumnWidth: const IntrinsicColumnWidth(),
        border: TableBorder.all(color: Colors.white.withOpacity(0.08)),
        children: [
          TableRow(children: [
            const Padding(padding: EdgeInsets.all(6), child: SizedBox()),
            for (final d in dates)
              Padding(
                padding: const EdgeInsets.all(6),
                child: Text(
                  DateTime.tryParse(d) != null
                      ? DateFormat('dd/MM/yy').format(DateTime.parse(d))
                      : d,
                  style: const TextStyle(color: Colors.grey, fontSize: 10),
                ),
              ),
          ]),
          for (var setNum = 1; setNum <= maxSets; setNum++)
            TableRow(children: [
              Padding(
                padding: const EdgeInsets.all(6),
                child: Text(
                  'Set-$setNum',
                  style: const TextStyle(color: Colors.white, fontSize: 10),
                ),
              ),
              for (final d in dates)
                Padding(
                  padding: const EdgeInsets.all(6),
                  child: Builder(builder: (_) {
                    final match = byDate[d]!.firstWhere(
                      (s) => s['set_number'] == setNum,
                      orElse: () => {},
                    );
                    if (match.isEmpty) {
                      return const Text(
                        '-',
                        style: TextStyle(color: Colors.grey, fontSize: 10),
                      );
                    }
                    final kg = match['kg'];
                    final reps = match['reps'];
                    final minutes = match['minutes'];
                    final seconds = match['seconds'];
                    String txt;
                    if (kg != null && (kg != 0 || (reps ?? 0) != 0)) {
                      txt = '$kg×${reps ?? '-'}';
                    } else if ((minutes ?? 0) != 0 || (seconds ?? 0) != 0) {
                      txt = '${minutes ?? 0}m${seconds ?? 0}s';
                    } else if (reps != null) {
                      txt = '$reps';
                    } else {
                      txt = '-';
                    }
                    return Text(
                      txt,
                      style: const TextStyle(color: Colors.white, fontSize: 10),
                    );
                  }),
                ),
            ]),
        ],
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
