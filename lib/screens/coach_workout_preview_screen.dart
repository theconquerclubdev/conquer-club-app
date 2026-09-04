import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../theme/app_theme.dart';

/// Read-only workout preview for a coach who does NOT have edit-workout
/// permission. Shows whichever plan the head coach/admin has assigned,
/// one tab per day of week — no editing, no saving. Shows "No workout
/// assigned" for any day that hasn't been set up yet.
class CoachWorkoutPreviewScreen extends StatefulWidget {
  final Map<String, dynamic> member;
  const CoachWorkoutPreviewScreen({super.key, required this.member});

  @override
  State<CoachWorkoutPreviewScreen> createState() =>
      _CoachWorkoutPreviewScreenState();
}

class _CoachWorkoutPreviewScreenState
    extends State<CoachWorkoutPreviewScreen> {
  final days = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: days.length,
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          title: Text('${widget.member['full_name'] ?? 'Member'}'),
          bottom: TabBar(
            isScrollable: true,
            indicatorColor: AppColors.gold,
            labelColor: AppColors.gold,
            unselectedLabelColor: Colors.grey,
            tabs: days
                .map((d) => Tab(text: d.substring(0, 3).toUpperCase()))
                .toList(),
          ),
        ),
        body: TabBarView(
          children: days
              .map((day) => _DayWorkoutPreview(
                    memberId: widget.member['id'],
                    dayOfWeek: day,
                  ))
              .toList(),
        ),
      ),
    );
  }
}

class _DayWorkoutPreview extends StatefulWidget {
  final String memberId;
  final String dayOfWeek;
  const _DayWorkoutPreview({
    required this.memberId,
    required this.dayOfWeek,
  });

  @override
  State<_DayWorkoutPreview> createState() => _DayWorkoutPreviewState();
}

class _DayWorkoutPreviewState extends State<_DayWorkoutPreview> {
  bool isLoading = true;
  Map<String, dynamic>? workout;
  List<Map<String, dynamic>> exercises = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => isLoading = true);
    try {
      final workoutData = await Supabase.instance.client
          .from('workouts')
          .select()
          .eq('member_id', widget.memberId)
          .eq('day_of_week', widget.dayOfWeek)
          .maybeSingle();

      if (workoutData == null) {
        if (mounted) {
          setState(() {
            workout = null;
            isLoading = false;
          });
        }
        return;
      }

      final weData = await Supabase.instance.client
          .from('workout_exercises')
          .select(
            'id, order_index, exercises(id, name, body_part, input_type), workout_sets(id, set_number, kg, reps, minutes, seconds)',
          )
          .eq('workout_id', workoutData['id'])
          .order('order_index', ascending: true);

      final loaded = List<Map<String, dynamic>>.from(weData);
      for (final we in loaded) {
        final sets =
            List<Map<String, dynamic>>.from(we['workout_sets'] ?? []);
        sets.sort((a, b) =>
            (a['set_number'] as int).compareTo(b['set_number'] as int));
        we['workout_sets'] = sets;
      }

      if (mounted) {
        setState(() {
          workout = workoutData;
          exercises = loaded;
          isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.gold),
      );
    }

    if (workout == null) {
      return const Center(
        child: Text(
          'No workout assigned',
          style: TextStyle(color: Colors.grey, fontSize: 14),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.cardDark,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.gold.withOpacity(0.2)),
          ),
          child: Row(
            children: [
              Icon(Icons.fitness_center, color: AppColors.gold, size: 24),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  workout!['workout_name'] ?? 'Workout',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        if (exercises.isEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 20),
            child: Center(
              child: Text(
                'No exercises added yet.',
                style: TextStyle(color: Colors.grey),
              ),
            ),
          )
        else
          ...exercises.map((we) => _ExerciseCard(we: we)),
      ],
    );
  }
}

class _ExerciseCard extends StatelessWidget {
  final Map<String, dynamic> we;
  const _ExerciseCard({required this.we});

  @override
  Widget build(BuildContext context) {
    final ex = we['exercises'] as Map<String, dynamic>? ?? {};
    final inputType = ex['input_type'] ?? 'Reps';
    final sets = List<Map<String, dynamic>>.from(we['workout_sets'] ?? []);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.cardDark,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            ex['name'] ?? 'Exercise',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 6),
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
                style: const TextStyle(color: Colors.grey, fontSize: 12),
              ),
            );
          }),
        ],
      ),
    );
  }
}
