import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../theme/app_theme.dart';
import '../providers/master_data_provider.dart';
import '../utils/cache_manager.dart';
import 'workout_builder_screen.dart';

const List<String> _kDays = [
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];

// ============================================================
// STORAGE (Supabase table: head_coach_workout_templates)
// Plans live in the cloud, so new phone / web login = same plans.
// ============================================================
class HeadCoachTemplateStore {
  static const _table = 'head_coach_workout_templates';
  static SupabaseClient get _db => Supabase.instance.client;

  // Old phone-only key (used once to move old plans to the cloud)
  static String get _legacyKey =>
      'head_coach_workout_templates_${_db.auth.currentUser?.id ?? 'unknown'}';

  // Cache: kept in memory + saved on the phone. Supabase is only called
  // when there is no cache yet, or after the coach changes a plan.
  static List<Map<String, dynamic>>? _memoryCache;

  static String get _cacheKey =>
      'head_coach_workout_templates_cache_${_db.auth.currentUser?.id ?? 'unknown'}';

  static Future<void> _saveCache(List<Map<String, dynamic>> list) async {
    _memoryCache = list;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_cacheKey, jsonEncode(list));
  }

  static Future<List<Map<String, dynamic>>> load() async {
    // 1. memory cache (fastest)
    if (_memoryCache != null) {
      return List<Map<String, dynamic>>.from(_memoryCache!);
    }

    // 2. phone cache
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_cacheKey);
    if (raw != null) {
      try {
        _memoryCache = (jsonDecode(raw) as List<dynamic>)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        return List<Map<String, dynamic>>.from(_memoryCache!);
      } catch (_) {
        // bad cache -> fall through and fetch from Supabase
      }
    }

    // 3. no cache -> ask Supabase (first time / new phone)
    await _migrateLegacy();
    final rows = await _db
        .from(_table)
        .select('id, name, days')
        .order('created_at', ascending: true);
    final list = List<Map<String, dynamic>>.from(rows);
    await _saveCache(list);
    return List<Map<String, dynamic>>.from(list);
  }

  // Insert (id == null) or update (id given). Returns saved row.
  static Future<Map<String, dynamic>> upsert({
    String? id,
    required String name,
    required Map<String, dynamic> days,
  }) async {
    final row = <String, dynamic>{
      if (id != null) 'id': id,
      'name': name,
      'days': days,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    };
    // coach_id is filled by DB default auth.uid()
    final saved =
        await _db.from(_table).upsert(row).select('id, name, days').single();

    // keep cache in sync (replace if same id, else add)
    final list = await load();
    final idx = list.indexWhere((t) => t['id'] == saved['id']);
    if (idx == -1) {
      list.add(Map<String, dynamic>.from(saved));
    } else {
      list[idx] = Map<String, dynamic>.from(saved);
    }
    await _saveCache(list);
    return saved;
  }

  static Future<void> delete(String id) async {
    await _db.from(_table).delete().eq('id', id);

    // keep cache in sync
    final list = await load();
    list.removeWhere((t) => t['id'] == id);
    await _saveCache(list);
  }

  // One time: copy plans saved on this phone into the database,
  // then remove them from the phone. Safe to call every time.
  static Future<void> _migrateLegacy() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_legacyKey);
      if (raw == null) return;
      final old = (jsonDecode(raw) as List<dynamic>)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      if (old.isNotEmpty) {
        await _db.from(_table).insert(
              old
                  .map((t) => {'name': t['name'], 'days': t['days'] ?? {}})
                  .toList(),
            );
      }
      await prefs.remove(_legacyKey); // only after insert worked
    } catch (_) {
      // keep local copy, try again next time
    }
  }

  // Copies the plan into the member's normal workouts, using the SAME
  // calls WorkoutBuilderScreen uses when it saves. Only days that have
  // exercises in the plan are written; other days are left untouched.
  static Future<void> assignToMember(
    Map<String, dynamic> template,
    String memberId,
  ) async {
    final client = Supabase.instance.client;
    final coachId = client.auth.currentUser!.id;
    final days = Map<String, dynamic>.from(template['days'] ?? {});

    for (final day in _kDays) {
      final d = days[day];
      if (d == null) continue;
      final exercises =
          List<Map<String, dynamic>>.from((d['exercises'] as List?) ?? []);
      if (exercises.isEmpty) continue;

      final workoutRow = await client
          .from('workouts')
          .upsert({
            'member_id': memberId,
            'coach_id': coachId,
            'day_of_week': day,
            'workout_name': d['workout_name'],
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          }, onConflict: 'member_id,day_of_week')
          .select()
          .single();

      await client.rpc(
        'save_workout_exercises',
        params: {
          'p_workout_id': workoutRow['id'],
          'p_exercises': exercises.map((ex) {
            final isBodyweight = ex['input_type'] == 'Reps';
            final sets = List<Map<String, dynamic>>.from(ex['sets'] ?? []);
            return {
              'exercise_id': ex['exercise_id'],
              'sets': sets
                  .map(
                    (s) => {
                      'set_number': s['set_number'],
                      'kg': isBodyweight ? null : s['kg'],
                      'reps': s['reps'] ?? 0,
                    },
                  )
                  .toList(),
            };
          }).toList(),
        },
      );
    }

    MasterDataProvider.instance.invalidateCache(memberId);
  }
}

// ============================================================
// LIST SCREEN
// assignTo == null  -> manage mode (create / edit / delete plans)
// assignTo != null  -> pick a plan to assign to that member
// ============================================================
class HeadCoachWorkoutTemplatesScreen extends StatefulWidget {
  final Map<String, dynamic>? assignTo;
  const HeadCoachWorkoutTemplatesScreen({super.key, this.assignTo});

  @override
  State<HeadCoachWorkoutTemplatesScreen> createState() =>
      _HeadCoachWorkoutTemplatesScreenState();
}

class _HeadCoachWorkoutTemplatesScreenState
    extends State<HeadCoachWorkoutTemplatesScreen> {
  List<Map<String, dynamic>> templates = [];
  bool isLoading = true;
  bool isAssigning = false;

  bool get _isAssignMode => widget.assignTo != null;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final data = await HeadCoachTemplateStore.load();
      if (!mounted) return;
      setState(() {
        templates = data;
        isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not load plans: $e')),
      );
    }
  }

  Future<void> _openEditor([Map<String, dynamic>? template]) async {
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => _TemplateEditorScreen(template: template),
      ),
    );
    if (saved == true) _load();
  }

  Future<void> _deleteTemplate(Map<String, dynamic> t) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.cardDark,
        title: const Text(
          'Delete workout plan?',
          style: TextStyle(color: Colors.white),
        ),
        content: Text(
          '"${t['name']}" will be removed from your saved plans. '
          'Members who already have it keep their workouts.',
          style: const TextStyle(color: Colors.grey),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('CANCEL'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'DELETE',
              style: TextStyle(color: Colors.redAccent),
            ),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await HeadCoachTemplateStore.delete(t['id'] as String);
      templates.removeWhere((x) => x['id'] == t['id']);
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Delete failed: $e')),
        );
      }
    }
  }

  Future<void> _assign(Map<String, dynamic> t) async {
    final member = widget.assignTo!;
    final memberName = member['full_name'] ?? 'this member';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.cardDark,
        title: const Text(
          'Assign workout plan?',
          style: TextStyle(color: Colors.white),
        ),
        content: Text(
          'Assign "${t['name']}" to $memberName? Days that have exercises '
          'in this plan will replace the member\'s current workout on '
          'those days.',
          style: const TextStyle(color: Colors.grey),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('CANCEL'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('ASSIGN', style: TextStyle(color: AppColors.gold)),
          ),
        ],
      ),
    );
    if (ok != true) return;

    setState(() => isAssigning = true);
    try {
      await HeadCoachTemplateStore.assignToMember(t, member['id']);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('"${t['name']}" assigned to $memberName')),
      );
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Assign failed: $e')),
        );
        setState(() => isAssigning = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(
          _isAssignMode
              ? 'Assign to ${widget.assignTo!['full_name'] ?? 'Member'}'
              : 'My Workout Plans',
        ),
      ),
      body: isLoading
          ? Center(child: CircularProgressIndicator(color: AppColors.gold))
          : Column(
              children: [
                Expanded(
                  child: templates.isEmpty
                      ? const Center(
                          child: Padding(
                            padding: EdgeInsets.all(24),
                            child: Text(
                              'No workout plans yet.\nCreate one below.',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: Colors.grey),
                            ),
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: templates.length,
                          itemBuilder: (context, index) {
                            final t = templates[index];
                            final days =
                                Map<String, dynamic>.from(t['days'] ?? {});
                            int exerciseCount = 0;
                            for (final d in days.values) {
                              exerciseCount +=
                                  ((d['exercises'] as List?) ?? []).length;
                            }
                            final dayLabels = _kDays
                                .where((d) => days.containsKey(d))
                                .map((d) => d.substring(0, 3))
                                .join(' · ');
                            return Container(
                              margin: const EdgeInsets.only(bottom: 12),
                              decoration: BoxDecoration(
                                color: AppColors.cardDark,
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: Colors.white.withOpacity(0.06),
                                ),
                              ),
                              child: ListTile(
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 6,
                                ),
                                title: Text(
                                  '${t['name']}',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                subtitle: Text(
                                  '${days.length} days · $exerciseCount exercises\n$dayLabels',
                                  style: TextStyle(
                                    color: AppColors.gold,
                                    fontSize: 12,
                                  ),
                                ),
                                isThreeLine: true,
                                trailing: _isAssignMode
                                    ? Icon(
                                        Icons.chevron_right,
                                        color: AppColors.gold,
                                      )
                                    : Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          IconButton(
                                            icon: const Icon(
                                              Icons.edit_outlined,
                                              color: Colors.grey,
                                              size: 20,
                                            ),
                                            onPressed: () => _openEditor(t),
                                          ),
                                          IconButton(
                                            icon: const Icon(
                                              Icons.delete_outline,
                                              color: Colors.redAccent,
                                              size: 20,
                                            ),
                                            onPressed: () => _deleteTemplate(t),
                                          ),
                                        ],
                                      ),
                                onTap: isAssigning
                                    ? null
                                    : () => _isAssignMode
                                        ? _assign(t)
                                        : _openEditor(t),
                              ),
                            );
                          },
                        ),
                ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.add, color: Colors.black),
                      label: const Text('CREATE NEW WORKOUT PLAN'),
                      onPressed: isAssigning ? null : () => _openEditor(),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

// ============================================================
// EDITOR - one plan, all 7 days, saved together
// ============================================================
class _TemplateEditorScreen extends StatefulWidget {
  final Map<String, dynamic>? template;
  const _TemplateEditorScreen({this.template});

  @override
  State<_TemplateEditorScreen> createState() => _TemplateEditorScreenState();
}

class _TemplateEditorScreenState extends State<_TemplateEditorScreen> {
  final nameController = TextEditingController();
  final Map<String, TextEditingController> dayNameControllers = {};
  final Map<String, List<ExerciseEntry>> dayExercises = {};
  List<Map<String, dynamic>> allExercises = [];
  bool isLoadingExercises = true;
  bool isSaving = false;

  @override
  void initState() {
    super.initState();
    for (final day in _kDays) {
      dayNameControllers[day] = TextEditingController();
      dayExercises[day] = [];
    }

    final tpl = widget.template;
    if (tpl != null) {
      nameController.text = tpl['name'] ?? '';
      final days = Map<String, dynamic>.from(tpl['days'] ?? {});
      for (final day in _kDays) {
        final d = days[day];
        if (d == null) continue;
        dayNameControllers[day]!.text = d['workout_name'] ?? '';
        for (final e in ((d['exercises'] as List?) ?? [])) {
          dayExercises[day]!.add(
            ExerciseEntry(
              exerciseId: e['exercise_id'],
              name: e['name'] ?? '',
              bodyPart: e['body_part'] ?? '',
              inputType: e['input_type'] ?? 'Reps',
              sets: ((e['sets'] as List?) ?? [])
                  .map((s) => Map<String, dynamic>.from(s as Map))
                  .toList(),
            ),
          );
        }
      }
    }

    loadExercises();
  }

  @override
  void dispose() {
    nameController.dispose();
    for (final c in dayNameControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  // Same exercise list + same cache the WorkoutBuilderScreen uses
  Future<void> loadExercises() async {
    List<Map<String, dynamic>> data;
    final cached = await CacheManager.getGeneric('cached_exercises');
    if (cached != null) {
      data = cached;
    } else {
      final fresh = await Supabase.instance.client
          .from('exercises')
          .select()
          .order('body_part');
      data = List<Map<String, dynamic>>.from(fresh);
      await CacheManager.saveGeneric('cached_exercises', data,
          duration: const Duration(hours: 1));
    }
    if (!mounted) return;
    setState(() {
      allExercises = data;
      isLoadingExercises = false;
    });
  }

  void openExercisePicker(String day) async {
    final picked = await showModalBottomSheet<List<Map<String, dynamic>>>(
      context: context,
      backgroundColor: AppColors.cardDark,
      isScrollControlled: true,
      builder: (context) => ExercisePickerSheet(allExercises: allExercises),
    );

    if (picked != null && picked.isNotEmpty) {
      setState(() {
        for (final ex in picked) {
          dayExercises[day]!.add(
            ExerciseEntry(
              exerciseId: ex['id'],
              name: ex['name'] ?? '',
              bodyPart: ex['body_part'] ?? '',
              inputType: ex['input_type'] ?? 'Reps',
              savedOrderIndex: dayExercises[day]!.length,
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

  void addSet(String day, int exerciseIndex) {
    setState(() {
      final sets = dayExercises[day]![exerciseIndex].sets;
      sets.add({
        'set_number': sets.length + 1,
        'kg': null,
        'reps': null,
      });
    });
  }

  void removeSet(String day, int exerciseIndex, int setIndex) {
    setState(() {
      final sets = dayExercises[day]![exerciseIndex].sets;
      sets.removeAt(setIndex);
      for (int i = 0; i < sets.length; i++) {
        sets[i]['set_number'] = i + 1;
      }
    });
  }

  void removeExercise(String day, int index) {
    setState(() => dayExercises[day]!.removeAt(index));
  }

  Future<void> saveTemplate() async {
    final name = nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please give this workout plan a name')),
      );
      return;
    }

    final days = <String, dynamic>{};
    for (final day in _kDays) {
      final list = dayExercises[day]!;
      if (list.isEmpty) continue;
      final dayName = dayNameControllers[day]!.text.trim();
      days[day] = {
        'workout_name': dayName.isEmpty ? '$day Workout' : dayName,
        'exercises': list
            .map(
              (ex) => {
                'exercise_id': ex.exerciseId,
                'name': ex.name,
                'body_part': ex.bodyPart,
                'input_type': ex.inputType,
                'sets':
                    ex.sets.map((s) => Map<String, dynamic>.from(s)).toList(),
              },
            )
            .toList(),
      };
    }

    if (days.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add at least one exercise on any day')),
      );
      return;
    }

    setState(() => isSaving = true);
    try {
      await HeadCoachTemplateStore.upsert(
        id: widget.template?['id'] as String?,
        name: name,
        days: days,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Save failed: $e')),
        );
        setState(() => isSaving = false);
      }
    }
  }

  Widget _buildDay(String day) {
    final exercises = dayExercises[day]!;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        TextField(
          controller: dayNameControllers[day],
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            labelText: '$day Workout Name',
            hintText: 'e.g. Leg Day, Push Day... (leave empty for rest day)',
          ),
        ),
        const SizedBox(height: 20),
        ...exercises.asMap().entries.map((entry) {
          final idx = entry.key;
          final ex = entry.value;
          return KeyedSubtree(
            key: ObjectKey(ex),
            child: ExerciseCard(
              exercise: ex,
              onAddSet: () => addSet(day, idx),
              onRemoveSet: (setIdx) => removeSet(day, idx, setIdx),
              onRemoveExercise: () => removeExercise(day, idx),
            ),
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
          onPressed: () => openExercisePicker(day),
        ),
        const SizedBox(height: 100),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: _kDays.length,
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          title: Text(
            widget.template == null ? 'New Workout Plan' : 'Edit Workout Plan',
          ),
          bottom: TabBar(
            isScrollable: true,
            indicatorColor: AppColors.gold,
            labelColor: AppColors.gold,
            unselectedLabelColor: Colors.grey,
            tabs: _kDays
                .map((d) => Tab(text: d.substring(0, 3).toUpperCase()))
                .toList(),
          ),
        ),
        body: isLoadingExercises
            ? Center(child: CircularProgressIndicator(color: AppColors.gold))
            : Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                    child: TextField(
                      controller: nameController,
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                        labelText: 'Workout Plan Name',
                        hintText: 'e.g. Fat Loss, Muscle Gain...',
                      ),
                    ),
                  ),
                  Expanded(
                    child: TabBarView(
                      children: _kDays.map((day) => _buildDay(day)).toList(),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: isSaving ? null : saveTemplate,
                        child: isSaving
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.black,
                                ),
                              )
                            : const Text('SAVE WORKOUT PLAN'),
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
