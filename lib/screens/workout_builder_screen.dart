import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../theme/app_theme.dart';
import '../providers/master_data_provider.dart';

class WorkoutBuilderScreen extends StatefulWidget {
  final Map<String, dynamic> member;
  const WorkoutBuilderScreen({super.key, required this.member});

  @override
  State<WorkoutBuilderScreen> createState() => _WorkoutBuilderScreenState();
}

class _WorkoutBuilderScreenState extends State<WorkoutBuilderScreen> {
  final days = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];
  List<Map<String, dynamic>> allExercises = [];
  bool isLoadingExercises = true;

  @override
  void initState() {
    super.initState();
    loadExercises();
  }

  Future<void> loadExercises() async {
    final data = await Supabase.instance.client
        .from('exercises')
        .select()
        .order('body_part');
    setState(() {
      allExercises = List<Map<String, dynamic>>.from(data);
      isLoadingExercises = false;
    });
  }

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
        body: isLoadingExercises
            ? const Center(
                child: CircularProgressIndicator(color: AppColors.gold),
              )
            : TabBarView(
                children: days
                    .map(
                      (day) => _DayWorkoutEditor(
                        memberId: widget.member['id'],
                        dayOfWeek: day,
                        allExercises: allExercises,
                      ),
                    )
                    .toList(),
              ),
      ),
    );
  }
}

class ExerciseEntry {
  String? exerciseId;
  String name;
  String bodyPart;
  String inputType; // 'Reps', 'kg × reps', or 'Min'
  List<Map<String, dynamic>> sets;
  int? savedOrderIndex;

  bool get isBodyweight => inputType == 'Reps';

  ExerciseEntry({
    this.exerciseId,
    required this.name,
    required this.bodyPart,
    required this.inputType,
    required this.sets,
    this.savedOrderIndex,
  });
}

String getInputType(Map<String, dynamic> exercise) {
  return exercise['input_type'] ?? 'Reps';
}

class _DayWorkoutEditor extends StatefulWidget {
  final String memberId;
  final String dayOfWeek;
  final List<Map<String, dynamic>> allExercises;
  const _DayWorkoutEditor({
    required this.memberId,
    required this.dayOfWeek,
    required this.allExercises,
  });

  @override
  State<_DayWorkoutEditor> createState() => _DayWorkoutEditorState();
}

class _DayWorkoutEditorState extends State<_DayWorkoutEditor> {
  final nameController = TextEditingController();
  List<ExerciseEntry> exercises = [];
  bool isLoading = true;
  bool isSaving = false;
  String? workoutId;

  @override
  void initState() {
    super.initState();
    loadWorkout();
  }

  @override
  void dispose() {
    nameController.dispose();
    super.dispose();
  }

  Future<void> loadWorkout() async {
    setState(() => isLoading = true);
    try {
      final workout = await Supabase.instance.client
          .from('workouts')
          .select()
          .eq('member_id', widget.memberId)
          .eq('day_of_week', widget.dayOfWeek)
          .maybeSingle();

      if (workout == null) {
        setState(() {
          workoutId = null;
          nameController.text = '';
          exercises = [];
          isLoading = false;
        });
        return;
      }

      workoutId = workout['id'];
      nameController.text = workout['workout_name'] ?? '';

      // ✅ Load exercises with order_index to preserve sequence
      final weData = await Supabase.instance.client
          .from('workout_exercises')
          .select(
            'id, order_index, exercises(id, name, body_part, input_type), workout_sets(id, set_number, kg, reps)',
          )
          .eq('workout_id', workoutId!)
          .order('order_index', ascending: true);

      final loaded = <ExerciseEntry>[];
      for (final we in weData) {
        final ex = we['exercises'];
        final exerciseName = ex['name'] ?? '';
        final inputType = ex['input_type'] ?? 'Reps';

        final sets = List<Map<String, dynamic>>.from(we['workout_sets'] ?? []);
        sets.sort(
          (a, b) => (a['set_number'] as int).compareTo(b['set_number'] as int),
        );
        loaded.add(
          ExerciseEntry(
            exerciseId: ex['id'],
            name: exerciseName,
            bodyPart: ex['body_part'],
            inputType: inputType,
            savedOrderIndex: we['order_index'] as int?,
            sets: sets
                .map(
                  (s) => {
                    'set_number': s['set_number'],
                    'kg': s['kg'],
                    'reps': s['reps'],
                    'minutes': s['minutes'] ?? 0,
                    'seconds': s['seconds'] ?? 0,
                  },
                )
                .toList(),
          ),
        );
      }

      setState(() {
        exercises = loaded;
        isLoading = false;
      });
    } catch (e) {
      print('Error loading workout: $e');
      setState(() => isLoading = false);
    }
  }

  void openExercisePicker() async {
    final picked = await showModalBottomSheet<List<Map<String, dynamic>>>(
      context: context,
      backgroundColor: AppColors.cardDark,
      isScrollControlled: true,
      builder: (context) =>
          _ExercisePickerSheet(allExercises: widget.allExercises),
    );

    if (picked != null && picked.isNotEmpty) {
      setState(() {
        for (final ex in picked) {
          exercises.add(
            ExerciseEntry(
              exerciseId: ex['id'],
              name: ex['name'] ?? '',
              bodyPart: ex['body_part'] ?? '',
              inputType: ex['input_type'] ?? 'Reps',
              savedOrderIndex: exercises.length,
              sets: [
                {
                  'set_number': 1,
                  'kg': null,
                  'reps': null,
                  'minutes': 0,
                  'seconds': 0
                },
              ],
            ),
          );
        }
      });
    }
  }

  void addSet(int exerciseIndex) {
    setState(() {
      final ex = exercises[exerciseIndex];
      final sets = ex.sets;
      sets.add({
        'set_number': sets.length + 1,
        'kg': null,
        'reps': null,
      });
    });
  }

  void removeSet(int exerciseIndex, int setIndex) {
    setState(() {
      exercises[exerciseIndex].sets.removeAt(setIndex);
      for (int i = 0; i < exercises[exerciseIndex].sets.length; i++) {
        exercises[exerciseIndex].sets[i]['set_number'] = i + 1;
      }
    });
  }

  void removeExercise(int index) {
    setState(() => exercises.removeAt(index));
  }

  Future<void> saveWorkout() async {
    if (nameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please give this workout a name')),
      );
      return;
    }
    if (exercises.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add at least one exercise')),
      );
      return;
    }

    setState(() => isSaving = true);

    try {
      final coachId = Supabase.instance.client.auth.currentUser!.id;

      final workoutRow = await Supabase.instance.client
          .from('workouts')
          .upsert({
            if (workoutId != null) 'id': workoutId,
            'member_id': widget.memberId,
            'coach_id': coachId,
            'day_of_week': widget.dayOfWeek,
            'workout_name': nameController.text.trim(),
            'updated_at': DateTime.now().toIso8601String(),
          }, onConflict: 'member_id,day_of_week')
          .select()
          .single();

      final newWorkoutId = workoutRow['id'];
      workoutId = newWorkoutId;

      // ✅ FIX: single atomic call (delete+insert done server-side in one
      // transaction via save_workout_exercises RPC). This prevents any
      // partial/half-written state between delete and insert, which was
      // the cause of order_index getting scrambled on reload.
      await Supabase.instance.client.rpc(
        'save_workout_exercises',
        params: {
          'p_workout_id': newWorkoutId,
          'p_exercises': exercises
              .map(
                (ex) => {
                  'exercise_id': ex.exerciseId,
                  'sets': ex.sets
                      .map(
                        (s) => {
                          'set_number': s['set_number'],
                          'kg': ex.isBodyweight ? null : s['kg'],
                          'reps': s['reps'] ?? 0,
                        },
                      )
                      .toList(),
                },
              )
              .toList(),
        },
      );

      if (mounted) {
        // Invalidate cache for the member
        MasterDataProvider.instance.invalidateCache(widget.memberId);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${widget.dayOfWeek} workout saved!')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Save failed: $e')),
        );
      }
    } finally {
      setState(() => isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.gold),
      );
    }

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              TextField(
                controller: nameController,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  labelText: '${widget.dayOfWeek} Workout Name',
                  hintText: 'e.g. Leg Day, Push Day...',
                ),
              ),
              const SizedBox(height: 20),
              ...exercises.asMap().entries.map((entry) {
                final idx = entry.key;
                final ex = entry.value;
                return _ExerciseCard(
                  exercise: ex,
                  onAddSet: () => addSet(idx),
                  onRemoveSet: (setIdx) => removeSet(idx, setIdx),
                  onRemoveExercise: () => removeExercise(idx),
                );
              }),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                icon: Icon(Icons.add, color: AppColors.gold),
                label: Text(
                  'ADD EXERCISE',
                  style: TextStyle(color: AppColors.gold),
                ),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  side: BorderSide(color: AppColors.gold),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  minimumSize: const Size(double.infinity, 0),
                ),
                onPressed: openExercisePicker,
              ),
              const SizedBox(height: 100),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: isSaving ? null : saveWorkout,
              child: isSaving
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.black,
                      ),
                    )
                  : Text('SAVE ${widget.dayOfWeek.toUpperCase()} WORKOUT'),
            ),
          ),
        ),
      ],
    );
  }
}

// ============================================================
// EXERCISE CARD
// ============================================================
class _ExerciseCard extends StatelessWidget {
  final ExerciseEntry exercise;
  final VoidCallback onAddSet;
  final Function(int) onRemoveSet;
  final VoidCallback onRemoveExercise;

  const _ExerciseCard({
    required this.exercise,
    required this.onAddSet,
    required this.onRemoveSet,
    required this.onRemoveExercise,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.cardDark,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            exercise.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: exercise.isBodyweight
                                ? Colors.orange.withOpacity(0.2)
                                : Colors.blue.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(
                              color: exercise.isBodyweight
                                  ? Colors.orange.withOpacity(0.4)
                                  : Colors.blue.withOpacity(0.4),
                            ),
                          ),
                          child: Text(
                            exercise.isBodyweight ? 'FREE' : 'WEIGHT',
                            style: TextStyle(
                              color: exercise.isBodyweight
                                  ? Colors.orange
                                  : Colors.blue,
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                    Text(
                      exercise.bodyPart,
                      style: TextStyle(color: AppColors.gold, fontSize: 11),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(
                  Icons.delete_outline,
                  color: Colors.redAccent,
                  size: 20,
                ),
                onPressed: onRemoveExercise,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              const SizedBox(
                width: 50,
                child: Text(
                  'SET',
                  style: TextStyle(color: Colors.grey, fontSize: 11),
                ),
              ),
              if (exercise.inputType == 'kg × reps')
                const Expanded(
                  child: Text(
                    'KG',
                    style: TextStyle(color: Colors.grey, fontSize: 11),
                  ),
                ),
              if (exercise.inputType == 'Min')
                const Expanded(
                  child: Text(
                    'MIN',
                    style: TextStyle(color: Colors.grey, fontSize: 11),
                  ),
                ),
              Expanded(
                child: Text(
                  exercise.inputType == 'Reps'
                      ? 'REPS'
                      : exercise.inputType == 'Min'
                          ? 'SEC'
                          : 'REPS',
                  style: TextStyle(color: Colors.grey, fontSize: 11),
                ),
              ),
              const SizedBox(width: 36),
            ],
          ),
          ...exercise.sets.asMap().entries.map((entry) {
            final setIdx = entry.key;
            final set = entry.value;
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  SizedBox(
                    width: 50,
                    child: Text(
                      '${set['set_number']}',
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                  if (exercise.inputType == 'kg × reps')
                    Expanded(
                      child: TextFormField(
                        initialValue: set['kg']?.toString() ?? '',
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                        ),
                        decoration: const InputDecoration(
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(vertical: 8),
                        ),
                        onChanged: (v) => set['kg'] = double.tryParse(v),
                      ),
                    ),
                  if (exercise.inputType == 'Min')
                    Expanded(
                      child: TextFormField(
                        initialValue: set['minutes']?.toString() ?? '',
                        keyboardType: TextInputType.number,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                        ),
                        decoration: const InputDecoration(
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(vertical: 8),
                        ),
                        onChanged: (v) => set['minutes'] = int.tryParse(v) ?? 0,
                      ),
                    ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextFormField(
                      initialValue: exercise.inputType == 'Min'
                          ? (set['seconds']?.toString() ?? '')
                          : (set['reps']?.toString() ?? ''),
                      keyboardType: TextInputType.number,
                      style: const TextStyle(color: Colors.white, fontSize: 14),
                      decoration: const InputDecoration(
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(vertical: 8),
                      ),
                      onChanged: (v) {
                        if (exercise.inputType == 'Min') {
                          set['seconds'] = int.tryParse(v) ?? 0;
                        } else {
                          set['reps'] = int.tryParse(v);
                        }
                      },
                    ),
                  ),
                  SizedBox(
                    width: 36,
                    child: IconButton(
                      icon: const Icon(
                        Icons.close,
                        color: Colors.grey,
                        size: 16,
                      ),
                      onPressed: () => onRemoveSet(setIdx),
                    ),
                  ),
                ],
              ),
            );
          }),
          const SizedBox(height: 8),
          TextButton.icon(
            icon: Icon(Icons.add, size: 16, color: AppColors.gold),
            label: Text(
              'Add Set',
              style: TextStyle(color: AppColors.gold, fontSize: 13),
            ),
            onPressed: onAddSet,
          ),
        ],
      ),
    );
  }
}

// ============================================================
// EXERCISE PICKER SHEET
// ============================================================
class _ExercisePickerSheet extends StatefulWidget {
  final List<Map<String, dynamic>> allExercises;
  const _ExercisePickerSheet({required this.allExercises});

  @override
  State<_ExercisePickerSheet> createState() => _ExercisePickerSheetState();
}

class _ExercisePickerSheetState extends State<_ExercisePickerSheet> {
  String query = '';
  final List<String> _selectedIds = [];

  @override
  Widget build(BuildContext context) {
    final filtered = query.isEmpty
        ? widget.allExercises
        : widget.allExercises.where((e) {
            final name = (e['name'] ?? '').toString().toLowerCase();
            final part = (e['body_part'] ?? '').toString().toLowerCase();
            final q = query.toLowerCase();
            return name.contains(q) || part.contains(q);
          }).toList();

    final Map<String, List<Map<String, dynamic>>> grouped = {};
    for (final e in filtered) {
      grouped.putIfAbsent(e['body_part'], () => []).add(e);
    }

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: DraggableScrollableSheet(
        initialChildSize: 0.75,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) {
          return Column(
            children: [
              Container(
                margin: const EdgeInsets.symmetric(vertical: 10),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: TextField(
                  autofocus: true,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    hintText: 'Search body part or exercise...',
                    hintStyle: TextStyle(color: Colors.grey),
                    prefixIcon: Icon(Icons.search, color: Colors.grey),
                  ),
                  onChanged: (v) => setState(() => query = v.trim()),
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: filtered.isEmpty
                    ? const Center(
                        child: Text(
                          'No exercises found',
                          style: TextStyle(color: Colors.grey),
                        ),
                      )
                    : ListView(
                        controller: scrollController,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        children: grouped.entries.map((groupEntry) {
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Padding(
                                padding: const EdgeInsets.only(
                                  top: 12,
                                  bottom: 4,
                                ),
                                child: Text(
                                  groupEntry.key,
                                  style: TextStyle(
                                    color: AppColors.gold,
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 1,
                                  ),
                                ),
                              ),
                              ...groupEntry.value.map(
                                (ex) {
                                  final name = ex['name'] ?? '';
                                  final inputType = ex['input_type'] ?? 'Reps';
                                  final displayType = inputType == 'Reps'
                                      ? 'Free'
                                      : inputType == 'kg × reps'
                                          ? 'Weighted'
                                          : 'Min';
                                  final isSelected =
                                      _selectedIds.contains(ex['id']);
                                  return ListTile(
                                    contentPadding: EdgeInsets.zero,
                                    leading: Icon(
                                      isSelected
                                          ? Icons.check_box
                                          : Icons.check_box_outline_blank,
                                      color: isSelected
                                          ? AppColors.gold
                                          : Colors.grey,
                                      size: 22,
                                    ),
                                    title: Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            name,
                                            style: const TextStyle(
                                              color: Colors.white,
                                            ),
                                          ),
                                        ),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 6,
                                            vertical: 2,
                                          ),
                                          decoration: BoxDecoration(
                                            color: inputType == 'Reps'
                                                ? Colors.orange.withOpacity(0.2)
                                                : inputType == 'kg × reps'
                                                    ? Colors.blue
                                                        .withOpacity(0.2)
                                                    : Colors.green
                                                        .withOpacity(0.2),
                                            borderRadius:
                                                BorderRadius.circular(4),
                                          ),
                                          child: Text(
                                            inputType == 'Reps'
                                                ? 'FREE'
                                                : inputType == 'kg × reps'
                                                    ? 'WEIGHT'
                                                    : 'MIN',
                                            style: TextStyle(
                                              color: inputType == 'Reps'
                                                  ? Colors.orange
                                                  : inputType == 'kg × reps'
                                                      ? Colors.blue
                                                      : Colors.green,
                                              fontSize: 8,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    subtitle: Text(
                                      '${ex['body_part']} · ${inputType == 'Reps' ? 'Bodyweight only' : inputType == 'kg × reps' ? 'Kg + Reps' : 'Minutes + Seconds'}',
                                      style: const TextStyle(
                                        color: Colors.grey,
                                        fontSize: 11,
                                      ),
                                    ),
                                    onTap: () {
                                      setState(() {
                                        if (isSelected) {
                                          _selectedIds.remove(ex['id']);
                                        } else {
                                          _selectedIds.add(ex['id']);
                                        }
                                      });
                                    },
                                  );
                                },
                              ),
                            ],
                          );
                        }).toList(),
                      ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _selectedIds.isEmpty
                        ? null
                        : () {
                            final selectedExercises = _selectedIds
                                .map((id) => widget.allExercises
                                    .firstWhere((e) => e['id'] == id))
                                .toList();
                            Navigator.pop(context, selectedExercises);
                          },
                    child: Text(
                      'ADD SELECTED (${_selectedIds.length})',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
