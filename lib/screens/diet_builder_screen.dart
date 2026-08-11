import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../theme/app_theme.dart';
import 'diet_preview_page.dart';

// Remove DietFoodItem and kDietSections from here
// They are now defined in diet_preview_page.dart

// A slightly darker, more muted green than Colors.green.shade400 so the
// white text/numbers overlaid on progress bars stay clearly readable.
const Color kBarDarkGreen = Color(0xFF1B6B33);

// Preset diet types: name -> {carbs%, protein%, fats%}.
// "Custom" is not in this list — it's the free-editing fallback state,
// selected whenever selectedDietType == kCustomDietType.
const List<Map<String, Object>> kDietTypePresets = [
  {'name': 'High Carb', 'carbs': 60, 'protein': 25, 'fats': 15},
  {'name': 'Moderate Carb', 'carbs': 50, 'protein': 30, 'fats': 20},
  {'name': 'Zone Diet', 'carbs': 40, 'protein': 30, 'fats': 30},
  {'name': 'Low Carb', 'carbs': 25, 'protein': 35, 'fats': 40},
  {'name': 'Ketogenic', 'carbs': 5, 'protein': 35, 'fats': 60},
];
const String kCustomDietType = 'Custom';

class DietBuilderScreen extends StatefulWidget {
  final Map<String, dynamic> member;
  const DietBuilderScreen({super.key, required this.member});

  @override
  State<DietBuilderScreen> createState() => _DietBuilderScreenState();
}

class _DietBuilderScreenState extends State<DietBuilderScreen> {
  int selectedDietIndex = 0;
  final GlobalKey<_DietSlotEditorState> vegKey =
      GlobalKey<_DietSlotEditorState>();
  final GlobalKey<_DietSlotEditorState> nonVegKey =
      GlobalKey<_DietSlotEditorState>();

  double vegCalories = 0;
  double vegPct = 0;
  double nonVegCalories = 0;
  double nonVegPct = 0;

  void _openPreviewForSelected() {
    final key = selectedDietIndex == 0 ? vegKey : nonVegKey;
    key.currentState?._openPreviewPage();
  }

  void _updateVegStats(double calories, double pct) {
    if (vegCalories == calories && vegPct == pct) return;
    setState(() {
      vegCalories = calories;
      vegPct = pct;
    });
  }

  void _updateNonVegStats(double calories, double pct) {
    if (nonVegCalories == calories && nonVegPct == pct) return;
    setState(() {
      nonVegCalories = calories;
      nonVegPct = pct;
    });
  }

  @override
  Widget build(BuildContext context) {
    final memberName = widget.member['full_name'] ?? 'Member';

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(
        children: [
          SafeArea(
            top: true,
            bottom: false,
            child: Container(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
            decoration: BoxDecoration(
              color: AppColors.cardDark,
              borderRadius: const BorderRadius.only(
                bottomLeft: Radius.circular(12),
                bottomRight: Radius.circular(12),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back,
                      color: Colors.white, size: 18),
                  onPressed: () => Navigator.pop(context),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 28,
                    minHeight: 28,
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.visibility, color: AppColors.gold, size: 18),
                  onPressed: _openPreviewForSelected,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 28,
                    minHeight: 28,
                  ),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Row(
                    children: [
                      _buildDietTab('Veg', 0, memberName),
                      const SizedBox(width: 4),
                      _buildDietTab('Non-Veg', 1, memberName),
                    ],
                  ),
                ),
              ],
              ),
            ),
          ),
          Expanded(
            child: IndexedStack(
              index: selectedDietIndex,
              children: [
                _DietSlotEditor(
                  key: vegKey,
                  memberId: widget.member['id'],
                  slot: 1,
                  memberName: memberName,
                  dietType: 'Veg',
                  member: widget.member,
                  onStatsChanged: _updateVegStats,
                ),
                _DietSlotEditor(
                  key: nonVegKey,
                  memberId: widget.member['id'],
                  slot: 2,
                  memberName: memberName,
                  dietType: 'Non-Veg',
                  member: widget.member,
                  onStatsChanged: _updateNonVegStats,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _shortName(String fullName) {
    final parts = fullName.trim().split(RegExp(r'\s+'));
    if (parts.length < 2) return fullName;
    return '${parts.first} ${parts.last[0]}';
  }

  Widget _buildDietTab(String label, int index, String memberName) {
    final isSelected = selectedDietIndex == index;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => selectedDietIndex = index),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 4),
          decoration: BoxDecoration(
            color: isSelected
                ? AppColors.gold.withOpacity(0.15)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color:
                  isSelected ? AppColors.gold : Colors.white.withOpacity(0.1),
              width: 1,
            ),
          ),
          child: Text(
            '${_shortName(memberName)} - $label',
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: isSelected ? AppColors.gold : Colors.grey,
              fontSize: 9,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ),
      ),
    );
  }
}

class _DietSlotEditor extends StatefulWidget {
  final String memberId;
  final int slot;
  final String memberName;
  final String dietType;
  final Map<String, dynamic> member;
  final void Function(double calories, double pct)? onStatsChanged;

  const _DietSlotEditor({
    super.key,
    required this.memberId,
    required this.slot,
    required this.memberName,
    required this.dietType,
    required this.member,
    this.onStatsChanged,
  });

  @override
  State<_DietSlotEditor> createState() => _DietSlotEditorState();
}

class _DietSlotEditorState extends State<_DietSlotEditor> {
  final nameController = TextEditingController();
  final targetController = TextEditingController(text: '3000');

  final proteinTargetController = TextEditingController(text: '150');
  final carbsTargetController = TextEditingController(text: '300');
  final fatsTargetController = TextEditingController(text: '80');

  final Map<String, List<DietFoodItem>> sections = {
    for (var s in kDietSections) s: [],
  };

  bool isLoading = true;
  bool isSaving = false;
  String? dietId;
  DateTime? lastUpdated;
  String? coachOwnName;
  double calorieTarget = 3000;
  double proteinTarget = 150;
  double carbsTarget = 300;
  double fatsTarget = 80;
  String selectedDietType = kCustomDietType;
  String selectedDisplayOption = 'both';

  bool get macrosAreEditable => selectedDietType == kCustomDietType;

  @override
  void initState() {
    super.initState();
    nameController.text = '${widget.memberName} - ${widget.dietType}';
    loadDiet();
  }

  @override
  void dispose() {
    nameController.dispose();
    targetController.dispose();
    proteinTargetController.dispose();
    carbsTargetController.dispose();
    fatsTargetController.dispose();
    super.dispose();
  }

  Future<void> loadDiet() async {
    setState(() => isLoading = true);
    try {
      final coachId = Supabase.instance.client.auth.currentUser?.id;
      if (coachId != null) {
        final coachProfile = await Supabase.instance.client
            .from('profiles')
            .select('full_name, email')
            .eq('id', coachId)
            .maybeSingle();
        coachOwnName = coachProfile?['full_name'] ?? coachProfile?['email'];
      }

      final diet = await Supabase.instance.client
          .from('diets')
          .select(
              'id, name, calorie_target, protein_target, carbs_target, fats_target, diet_type_preset, updated_at')
          .eq('member_id', widget.memberId)
          .eq('slot', widget.slot)
          .maybeSingle();

      if (diet == null) {
        setState(() => isLoading = false);
        return;
      }

      dietId = diet['id'];
      lastUpdated = diet['updated_at'] != null
          ? DateTime.tryParse(diet['updated_at'])
          : null;
      nameController.text =
          diet['name'] ?? '${widget.memberName} - ${widget.dietType}';
      calorieTarget = (diet['calorie_target'] ?? 3000).toDouble();
      targetController.text = calorieTarget.toString();

      proteinTarget = (diet['protein_target'] ?? 150).toDouble();
      carbsTarget = (diet['carbs_target'] ?? 300).toDouble();
      fatsTarget = (diet['fats_target'] ?? 80).toDouble();
      selectedDietType =
          (diet['diet_type_preset'] as String?) ?? kCustomDietType;

      proteinTargetController.text = proteinTarget.toString();
      carbsTargetController.text = carbsTarget.toString();
      fatsTargetController.text = fatsTarget.toString();

      final items = await Supabase.instance.client
          .from('diet_items')
          .select(
              'id, section, quantity, order_index, foods(id, name, base_quantity, base_unit, calories, protein, carbs, fats)')
          .eq('diet_id', dietId!)
          .order('order_index');

      for (final s in kDietSections) {
        sections[s] = [];
      }

      for (final item in items) {
        final food = item['foods'];
        if (food == null) continue;
        final section = item['section'] as String;
        sections.putIfAbsent(section, () => []).add(DietFoodItem(
              foodId: food['id'],
              name: food['name'],
              unit: food['base_unit'],
              baseQuantity: (food['base_quantity'] as num).toDouble(),
              baseCalories: (food['calories'] as num).toDouble(),
              baseProtein: (food['protein'] as num).toDouble(),
              baseCarbs: (food['carbs'] as num).toDouble(),
              baseFats: (food['fats'] as num).toDouble(),
              quantity: (item['quantity'] as num).toDouble(),
            ));
      }

      setState(() => isLoading = false);
    } catch (e) {
      print('Error loading diet: $e');
      setState(() => isLoading = false);
    }
  }

  Map<String, double> get totals {
    double cal = 0, pro = 0, carb = 0, fat = 0;
    for (final list in sections.values) {
      for (final item in list) {
        cal += item.calories;
        pro += item.protein;
        carb += item.carbs;
        fat += item.fats;
      }
    }
    return {'calories': cal, 'protein': pro, 'carbs': carb, 'fats': fat};
  }

  double get progressPercentage {
    final t = totals;
    if (calorieTarget <= 0) return 0;
    return (t['calories']! / calorieTarget) * 100;
  }

  Color getMacroStatus(double current, double target) {
    if (target <= 0) return Colors.orange;
    final diff = current - target;
    if (diff.abs() < 0.5) return Colors.green;
    if (diff > 0) return Colors.redAccent;
    return Colors.orange;
  }

  String getMacroStatusLabel(double current, double target) {
    if (target <= 0) return 'Need More';
    final diff = current - target;
    if (diff.abs() < 0.5) return 'On Track';
    if (diff > 0) return 'Over';
    return 'Need More';
  }

  double _calculateCaloriesFromMacros() {
    final proteinCal = proteinTarget * 4;
    final carbsCal = carbsTarget * 4;
    final fatsCal = fatsTarget * 9;
    return proteinCal + carbsCal + fatsCal;
  }

  Map<String, double> get customMacroPercents {
    final totalCal = _calculateCaloriesFromMacros();
    if (totalCal <= 0) return {'carbs': 0, 'protein': 0, 'fats': 0};
    return {
      'carbs': (carbsTarget * 4 / totalCal) * 100,
      'protein': (proteinTarget * 4 / totalCal) * 100,
      'fats': (fatsTarget * 9 / totalCal) * 100,
    };
  }

  void _applyDietTypePreset(Map<String, Object> preset) {
    setState(() {
      selectedDietType = preset['name'] as String;
      final carbsPct = (preset['carbs'] as int) / 100;
      final proteinPct = (preset['protein'] as int) / 100;
      final fatsPct = (preset['fats'] as int) / 100;

      proteinTarget = (calorieTarget * proteinPct) / 4;
      carbsTarget = (calorieTarget * carbsPct) / 4;
      fatsTarget = (calorieTarget * fatsPct) / 9;

      proteinTargetController.text = proteinTarget.toStringAsFixed(0);
      carbsTargetController.text = carbsTarget.toStringAsFixed(0);
      fatsTargetController.text = fatsTarget.toStringAsFixed(0);
    });
  }

  void _selectCustomDietType() {
    setState(() => selectedDietType = kCustomDietType);
  }

  void _openDietTypePicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _DietTypePickerSheet(
        selectedDietType: selectedDietType,
        customPercents: customMacroPercents,
        onSelectPreset: _applyDietTypePreset,
        onSelectCustom: _selectCustomDietType,
      ),
    );
  }

  Future<void> openFoodPicker(String section) async {
    final picked = await showModalBottomSheet<List<Map<String, dynamic>>>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      isDismissible: true,
      enableDrag: true,
      builder: (context) => _FoodPickerSheet(dietType: widget.dietType),
    );
    if (picked != null && picked.isNotEmpty) {
      setState(() {
        for (final food in picked) {
          final userQuantity = (food['base_quantity'] as num).toDouble();
          final originalBaseQty =
              (food['original_base_quantity'] as num).toDouble();

          sections[section]!.add(DietFoodItem(
            foodId: food['id'],
            name: food['name'],
            unit: food['base_unit'],
            baseQuantity: originalBaseQty,
            baseCalories: (food['calories'] as num).toDouble(),
            baseProtein: (food['protein'] as num).toDouble(),
            baseCarbs: (food['carbs'] as num).toDouble(),
            baseFats: (food['fats'] as num).toDouble(),
            quantity: userQuantity,
          ));
        }
      });
    }
  }

  Future<void> saveDiet() async {
    setState(() => isSaving = true);
    try {
      final coachId = Supabase.instance.client.auth.currentUser!.id;
      final target = double.tryParse(targetController.text) ?? 3000;
      calorieTarget = target;

      proteinTarget = double.tryParse(proteinTargetController.text) ?? 150;
      carbsTarget = double.tryParse(carbsTargetController.text) ?? 300;
      fatsTarget = double.tryParse(fatsTargetController.text) ?? 80;

      final dietRow = await Supabase.instance.client
          .from('diets')
          .upsert({
            if (dietId != null) 'id': dietId,
            'member_id': widget.memberId,
            'coach_id': coachId,
            'slot': widget.slot,
            'name': nameController.text.trim().isEmpty
                ? '${widget.memberName} - ${widget.dietType}'
                : nameController.text.trim(),
            'calorie_target': target,
            'protein_target': proteinTarget,
            'carbs_target': carbsTarget,
            'fats_target': fatsTarget,
            'diet_type_preset': selectedDietType,
            'updated_at': DateTime.now().toIso8601String(),
          }, onConflict: 'member_id,slot')
          .select()
          .single();

      final newDietId = dietRow['id'];
      dietId = newDietId;

      await Supabase.instance.client
          .from('diet_items')
          .delete()
          .eq('diet_id', newDietId);

      final rowsToInsert = <Map<String, dynamic>>[];
      int orderIndex = 0;
      for (final section in kDietSections) {
        for (final item in sections[section]!) {
          rowsToInsert.add({
            'diet_id': newDietId,
            'section': section,
            'food_id': item.foodId,
            'quantity': item.quantity,
            'order_index': orderIndex++,
          });
        }
      }
      if (rowsToInsert.isNotEmpty) {
        await Supabase.instance.client.from('diet_items').insert(rowsToInsert);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('${widget.dietType} Diet saved successfully!')),
        );
        await loadDiet();
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

  void quitDiet() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.cardDark,
        title: const Text('Discard Changes?',
            style: TextStyle(color: Colors.white)),
        content: const Text(
          'Are you sure you want to quit? Your changes will not be saved.',
          style: TextStyle(color: Colors.grey),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.pop(context);
            },
            child:
                const Text('Quit', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
  }

  void _openPreviewPage() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => DietPreviewPage(
          member: widget.member,
          dietName: nameController.text,
          dietType: widget.dietType,
          calorieTarget: calorieTarget,
          proteinTarget: proteinTarget,
          carbsTarget: carbsTarget,
          fatsTarget: fatsTarget,
          sections: sections,
          lastUpdated: lastUpdated,
          coachNameOverride: coachOwnName,
          onSave: saveDiet,
          onQuit: quitDiet,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.gold),
      );
    }

    final t = totals;
    final pct = progressPercentage;
    final remaining = calorieTarget - t['calories']!;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.onStatsChanged?.call(t['calories']!, pct);
    });

    return Column(
      children: [
        // ✅ Compact header
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: AppColors.cardDark,
            borderRadius: const BorderRadius.only(
              bottomLeft: Radius.circular(10),
              bottomRight: Radius.circular(10),
            ),
            border: Border(
              bottom: BorderSide(
                color: Colors.white.withOpacity(0.05),
              ),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ✅ Row 1: Target + Progress Bar + Stats
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // TARGET
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'TARGET',
                        style: TextStyle(
                          color: Colors.grey,
                          fontSize: 7,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.5,
                        ),
                      ),
                      SizedBox(
                        width: 40,
                        child: TextField(
                          controller: targetController,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                          keyboardType: TextInputType.number,
                          textAlign: TextAlign.left,
                          decoration: const InputDecoration(
                            isDense: true,
                            contentPadding: EdgeInsets.zero,
                            border: InputBorder.none,
                          ),
                          onChanged: (v) {
                            final val = double.tryParse(v) ?? 3000;
                            setState(() {
                              calorieTarget = val;
                              if (selectedDietType != kCustomDietType) {
                                final preset = kDietTypePresets.firstWhere(
                                  (p) => p['name'] == selectedDietType,
                                  orElse: () => kDietTypePresets.first,
                                );
                                final carbsPct = (preset['carbs'] as int) / 100;
                                final proteinPct =
                                    (preset['protein'] as int) / 100;
                                final fatsPct = (preset['fats'] as int) / 100;
                                proteinTarget =
                                    (calorieTarget * proteinPct) / 4;
                                carbsTarget = (calorieTarget * carbsPct) / 4;
                                fatsTarget = (calorieTarget * fatsPct) / 9;
                                proteinTargetController.text =
                                    proteinTarget.toStringAsFixed(0);
                                carbsTargetController.text =
                                    carbsTarget.toStringAsFixed(0);
                                fatsTargetController.text =
                                    fatsTarget.toStringAsFixed(0);
                              }
                            });
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(width: 4),
                  // Progress bar
                  Expanded(
                    child: SizedBox(
                      height: 16,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(3),
                            child: LinearProgressIndicator(
                              value: (pct / 100).clamp(0.0, 1.0),
                              backgroundColor: Colors.grey.shade800,
                              color: (pct - 100).abs() < 0.5
                                  ? Colors.green
                                  : pct < 100
                                      ? Colors.orange
                                      : Colors.redAccent,
                              minHeight: 16,
                            ),
                          ),
                          Text(
                            '${t['calories']!.toStringAsFixed(0)} kcal (${pct.toStringAsFixed(0)}%)',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 8,
                              fontWeight: FontWeight.bold,
                              shadows: [
                                Shadow(color: Colors.black54, blurRadius: 2)
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  // REMAINING stat - Compact
                  _buildMiniStatCompact(
                    remaining.abs() < 1
                        ? 'ACHIEVED'
                        : remaining > 0
                            ? 'REMAIN'
                            : 'OVER',
                    remaining.abs() < 1
                        ? '0'
                        : remaining.abs().toStringAsFixed(0),
                    remaining.abs() < 1
                        ? Colors.green
                        : remaining > 0
                            ? Colors.orange
                            : Colors.redAccent,
                  ),
                  const SizedBox(width: 2),
                  // CALORIE stat - Compact
                  _buildMiniStatCompact(
                    'CAL',
                    '${_calculateCaloriesFromMacros().toStringAsFixed(0)}',
                    calorieTarget == _calculateCaloriesFromMacros()
                        ? Colors.green
                        : _calculateCaloriesFromMacros() < calorieTarget
                            ? Colors.orange
                            : Colors.redAccent,
                  ),
                ],
              ),
              const SizedBox(height: 4),
              // ✅ Row 2: Diet Type Picker
              GestureDetector(
                onTap: _openDietTypePicker,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.gold.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: AppColors.gold.withOpacity(0.3)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        selectedDietType == kCustomDietType
                            ? Icons.edit
                            : Icons.lock_outline,
                        size: 9,
                        color: AppColors.gold,
                      ),
                      const SizedBox(width: 3),
                      Text(
                        selectedDietType,
                        style: const TextStyle(
                          color: AppColors.gold,
                          fontSize: 8,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(width: 2),
                      Icon(Icons.arrow_drop_down,
                          size: 12, color: AppColors.gold),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 4),
              // ✅ Row 3: Macro Rows - Compact
              _buildMacroRow('Protein', t['protein']!, proteinTarget,
                  proteinTargetController),
              const SizedBox(height: 2),
              _buildMacroRow(
                  'Carbs', t['carbs']!, carbsTarget, carbsTargetController),
              const SizedBox(height: 2),
              _buildMacroRow(
                  'Fats', t['fats']!, fatsTarget, fatsTargetController),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(6, 4, 6, 8),
            children: [
              _SectionBlock(
                section: 'Breakfast',
                items: sections['Breakfast'] ?? [],
                onAdd: () => openFoodPicker('Breakfast'),
                onRemove: (item) =>
                    setState(() => sections['Breakfast']!.remove(item)),
                onQuantityChanged: (item, value) =>
                    setState(() => item.quantity = value),
              ),
              const SizedBox(height: 4),
              _SectionBlock(
                section: 'Lunch',
                items: sections['Lunch'] ?? [],
                onAdd: () => openFoodPicker('Lunch'),
                onRemove: (item) =>
                    setState(() => sections['Lunch']!.remove(item)),
                onQuantityChanged: (item, value) =>
                    setState(() => item.quantity = value),
              ),
              const SizedBox(height: 4),
              _SectionBlock(
                section: 'Snacks',
                items: sections['Snacks'] ?? [],
                onAdd: () => openFoodPicker('Snacks'),
                onRemove: (item) =>
                    setState(() => sections['Snacks']!.remove(item)),
                onQuantityChanged: (item, value) =>
                    setState(() => item.quantity = value),
              ),
              const SizedBox(height: 4),
              _SectionBlock(
                section: 'Dinner',
                items: sections['Dinner'] ?? [],
                onAdd: () => openFoodPicker('Dinner'),
                onRemove: (item) =>
                    setState(() => sections['Dinner']!.remove(item)),
                onQuantityChanged: (item, value) =>
                    setState(() => item.quantity = value),
              ),
              const SizedBox(height: 8),
              _buildRadioButtons(),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: quitDiet,
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: Colors.grey.shade600),
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                      child: Text(
                        'QUIT',
                        style: TextStyle(
                          color: Colors.grey.shade400,
                          fontWeight: FontWeight.bold,
                          fontSize: 10,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton(
                      onPressed: isSaving ? null : saveDiet,
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                      child: isSaving
                          ? const SizedBox(
                              height: 16,
                              width: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.black,
                              ),
                            )
                          : Text(
                              'SAVE ${widget.dietType.toUpperCase()}',
                              style: const TextStyle(fontSize: 10),
                            ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildRadioButtons() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.04),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        children: [
          _buildRadioOption('Veg', 'veg'),
          _buildRadioOption('Non-Veg', 'nonveg'),
          _buildRadioOption('Both', 'both'),
        ],
      ),
    );
  }

  Widget _buildRadioOption(String label, String value) {
    final isSelected = selectedDisplayOption == value;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => selectedDisplayOption = value),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 2),
          decoration: BoxDecoration(
            color: isSelected
                ? AppColors.gold.withOpacity(0.12)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isSelected ? AppColors.gold : Colors.grey.shade600,
                    width: 1.5,
                  ),
                ),
                child: isSelected
                    ? Center(
                        child: Container(
                          width: 4,
                          height: 4,
                          decoration: const BoxDecoration(
                            color: AppColors.gold,
                            shape: BoxShape.circle,
                          ),
                        ),
                      )
                    : null,
              ),
              const SizedBox(width: 3),
              Text(
                label,
                style: TextStyle(
                  color: isSelected ? Colors.white : Colors.grey.shade500,
                  fontSize: 8,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMiniStatCompact(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 4),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.03),
        borderRadius: BorderRadius.circular(3),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            label,
            style: TextStyle(
              color: Colors.grey.shade500,
              fontSize: 5,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.3,
            ),
          ),
          const SizedBox(height: 1),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 8,
              fontWeight: FontWeight.bold,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildMacroRow(String label, double actual, double target,
      TextEditingController controller) {
    final progress = target > 0 ? (actual / target).clamp(0.0, 1.0) : 0.0;
    final statusColor = getMacroStatus(actual, target);
    final statusLabel = getMacroStatusLabel(actual, target);
    final realPct = target > 0 ? (actual / target) * 100 : 0.0;
    final pct = realPct.toStringAsFixed(0);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.02),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: statusColor.withOpacity(0.15), width: 0.5),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 32,
            child: Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 8,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          Expanded(
            child: SizedBox(
              height: 12,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: LinearProgressIndicator(
                      value: progress,
                      backgroundColor: Colors.grey.shade800,
                      color: statusColor,
                      minHeight: 12,
                    ),
                  ),
                  Text(
                    '${actual.toStringAsFixed(0)}g ($pct%)',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 7,
                      fontWeight: FontWeight.bold,
                      shadows: [Shadow(color: Colors.black54, blurRadius: 2)],
                    ),
                  ),
                ],
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
            decoration: BoxDecoration(
              color: statusColor.withOpacity(0.15),
              borderRadius: BorderRadius.circular(3),
            ),
            child: Text(
              statusLabel,
              style: TextStyle(
                color: statusColor,
                fontSize: 6,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 2),
          const Text(
            '/',
            style: TextStyle(
              color: Colors.white,
              fontSize: 7,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 2),
          SizedBox(
            width: 22,
            child: TextField(
              controller: controller,
              readOnly: !macrosAreEditable,
              style: TextStyle(
                color: macrosAreEditable ? Colors.white : Colors.grey.shade500,
                fontSize: 7,
                fontWeight: FontWeight.bold,
              ),
              keyboardType: TextInputType.number,
              textAlign: TextAlign.right,
              decoration: const InputDecoration(
                isDense: true,
                contentPadding: EdgeInsets.zero,
                border: InputBorder.none,
              ),
              onChanged: !macrosAreEditable
                  ? null
                  : (v) {
                      final val = double.tryParse(v) ?? 0;
                      setState(() {
                        if (label == 'Protein') proteinTarget = val;
                        if (label == 'Carbs') carbsTarget = val;
                        if (label == 'Fats') fatsTarget = val;
                      });
                    },
            ),
          ),
          const Text(
            'g',
            style: TextStyle(
              color: Colors.white70,
              fontSize: 6,
            ),
          ),
        ],
      ),
    );
  }
}

class _DietTypePickerSheet extends StatelessWidget {
  final String selectedDietType;
  final Map<String, double> customPercents;
  final void Function(Map<String, Object> preset) onSelectPreset;
  final VoidCallback onSelectCustom;

  const _DietTypePickerSheet({
    required this.selectedDietType,
    required this.customPercents,
    required this.onSelectPreset,
    required this.onSelectCustom,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
        decoration: const BoxDecoration(
          color: AppColors.cardDark,
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Diet type',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 14),
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 2.1,
              children: [
                ...kDietTypePresets.map((preset) => _DietTypeCard(
                      title: preset['name'] as String,
                      carbs: preset['carbs'] as int,
                      protein: preset['protein'] as int,
                      fats: preset['fats'] as int,
                      isSelected: selectedDietType == preset['name'],
                      onTap: () {
                        onSelectPreset(preset);
                        Navigator.pop(context);
                      },
                    )),
                _DietTypeCard(
                  title: kCustomDietType,
                  carbs: customPercents['carbs']!.round(),
                  protein: customPercents['protein']!.round(),
                  fats: customPercents['fats']!.round(),
                  isSelected: selectedDietType == kCustomDietType,
                  isCustom: true,
                  onTap: () {
                    onSelectCustom();
                    Navigator.pop(context);
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _DietTypeCard extends StatelessWidget {
  final String title;
  final int carbs;
  final int protein;
  final int fats;
  final bool isSelected;
  final bool isCustom;
  final VoidCallback onTap;

  const _DietTypeCard({
    required this.title,
    required this.carbs,
    required this.protein,
    required this.fats,
    required this.isSelected,
    required this.onTap,
    this.isCustom = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.03),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected ? AppColors.gold : Colors.white.withOpacity(0.1),
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Row(
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (isCustom) ...[
                      const SizedBox(width: 4),
                      Icon(Icons.edit, size: 12, color: Colors.grey.shade400),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'C:$carbs% \u2022 P:$protein% \u2022 F:$fats%',
                  style: TextStyle(
                    color: Colors.grey.shade400,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
            if (isSelected)
              Positioned(
                top: 0,
                right: 0,
                child: Container(
                  width: 18,
                  height: 18,
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.check, size: 12, color: Colors.black),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _SectionBlock extends StatelessWidget {
  final String section;
  final List<DietFoodItem> items;
  final VoidCallback onAdd;
  final void Function(DietFoodItem) onRemove;
  final void Function(DietFoodItem, double) onQuantityChanged;

  const _SectionBlock({
    required this.section,
    required this.items,
    required this.onAdd,
    required this.onRemove,
    required this.onQuantityChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.cardDark,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.white.withOpacity(0.04)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                section.toUpperCase(),
                style: TextStyle(
                  color: AppColors.gold,
                  fontWeight: FontWeight.bold,
                  fontSize: 8,
                  letterSpacing: 0.5,
                ),
              ),
              TextButton.icon(
                onPressed: onAdd,
                icon: Icon(Icons.add, size: 12, color: AppColors.gold),
                label: Text(
                  'Add',
                  style: TextStyle(
                    color: AppColors.gold,
                    fontSize: 9,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                style: TextButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  backgroundColor: Colors.white.withOpacity(0.05),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(4),
                    side: BorderSide(color: AppColors.gold.withOpacity(0.3)),
                  ),
                ),
              ),
            ],
          ),
          if (items.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 2),
              child: Center(
                child: Text(
                  'No items',
                  style: TextStyle(color: Colors.grey, fontSize: 8),
                ),
              ),
            ),
          ...items.map((item) => _FoodItemRow(
                item: item,
                onRemove: () => onRemove(item),
                onQuantityChanged: (v) => onQuantityChanged(item, v),
              )),
        ],
      ),
    );
  }
}

class _FoodItemRow extends StatefulWidget {
  final DietFoodItem item;
  final VoidCallback onRemove;
  final void Function(double) onQuantityChanged;

  const _FoodItemRow({
    required this.item,
    required this.onRemove,
    required this.onQuantityChanged,
  });

  @override
  State<_FoodItemRow> createState() => _FoodItemRowState();
}

class _FoodItemRowState extends State<_FoodItemRow> {
  final TextEditingController _controller = TextEditingController();

  @override
  void initState() {
    super.initState();
    _controller.text = widget.item.quantity.toString();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final multiplier = widget.item.quantity / widget.item.baseQuantity;
    final calories = (widget.item.baseCalories * multiplier);
    final protein = (widget.item.baseProtein * multiplier);
    final carbs = (widget.item.baseCarbs * multiplier);
    final fats = (widget.item.baseFats * multiplier);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                flex: 2,
                child: Text(
                  widget.item.name,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                  ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
              ),
              const SizedBox(width: 2),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 24,
                    child: TextField(
                      controller: _controller,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                      decoration: const InputDecoration(
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(vertical: 1),
                        border: InputBorder.none,
                      ),
                      onChanged: (value) {
                        final newValue = double.tryParse(value);
                        if (newValue != null && newValue >= 0) {
                          widget.onQuantityChanged(newValue);
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: 2),
                  Text(
                    widget.item.unit,
                    style: const TextStyle(
                      color: Colors.grey,
                      fontSize: 8,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(width: 2),
                  IconButton(
                    icon: const Icon(Icons.close, size: 12, color: Colors.grey),
                    onPressed: widget.onRemove,
                    padding: EdgeInsets.zero,
                    constraints:
                        const BoxConstraints(minWidth: 16, minHeight: 16),
                  ),
                ],
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(left: 2),
            child: Text(
              '${calories.toStringAsFixed(0)} kcal · '
              'P${protein.toStringAsFixed(0)}g '
              'C${carbs.toStringAsFixed(0)}g '
              'F${fats.toStringAsFixed(0)}g',
              style: const TextStyle(
                color: Colors.grey,
                fontSize: 7,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// _FoodPickerSheet - Mobile friendly, compact, editable
// ============================================================
class _FoodPickerSheet extends StatefulWidget {
  final String dietType;
  const _FoodPickerSheet({required this.dietType});

  @override
  State<_FoodPickerSheet> createState() => _FoodPickerSheetState();
}

class _FoodPickerSheetState extends State<_FoodPickerSheet> {
  String query = '';
  late String selectedCategory;
  late bool isLocked;
  List<Map<String, dynamic>> allFoods = [];
  bool isLoading = true;
  final TextEditingController searchController = TextEditingController();
  final Map<String, TextEditingController> quantityControllers = {};
  final Map<String, double> selectedQuantities = {};
  final Set<String> selectedIds = {};
  final Map<String, Map<String, dynamic>> foodById = {};

  @override
  void initState() {
    super.initState();
    isLocked = widget.dietType == 'Veg';
    selectedCategory = widget.dietType;
    load();
  }

  @override
  void dispose() {
    searchController.dispose();
    for (var controller in quantityControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Widget _categoryChip(String label,
      {required bool active, bool tappable = true}) {
    final chip = Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: active ? AppColors.gold : Colors.grey.shade800,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: active ? Colors.black : Colors.grey.shade300,
          fontSize: 8,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
    if (!tappable) return chip;
    return GestureDetector(
      onTap: () => setState(() => selectedCategory = label),
      child: chip,
    );
  }

  Future<void> load() async {
    final data =
        await Supabase.instance.client.from('foods').select().order('name');
    setState(() {
      allFoods = List<Map<String, dynamic>>.from(data);
      for (final f in allFoods) {
        foodById[f['id']] = f;
        final baseQty = (f['base_quantity'] as num).toDouble();
        selectedQuantities[f['id']] = baseQty;
        quantityControllers[f['id']] =
            TextEditingController(text: baseQty.toString());
      }
      isLoading = false;
    });
  }

  void _updateQuantity(String foodId, double value) {
    setState(() {
      selectedQuantities[foodId] = value;
    });
  }

  double _calculateMacro(
      double baseValue, double quantity, double baseQuantity) {
    return (baseValue * quantity / baseQuantity);
  }

  @override
  Widget build(BuildContext context) {
    final byCategory = selectedCategory == 'All'
        ? allFoods
        : allFoods.where((f) => f['category'] == selectedCategory).toList();

    final filtered = query.isEmpty
        ? byCategory
        : byCategory.where((f) {
            final name = (f['name'] as String).toLowerCase();
            return name.contains(query.toLowerCase());
          }).toList();

    return Container(
      height: MediaQuery.of(context).size.height * 0.92,
      decoration: const BoxDecoration(
        color: AppColors.cardDark,
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(20),
        ),
      ),
      child: Column(
        children: [
          Container(
            margin: const EdgeInsets.only(top: 10),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.shade600,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  selectedIds.isEmpty
                      ? 'Add Food'
                      : 'Add Food (${selectedIds.length})',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (isLocked)
                      _categoryChip('Veg', active: true, tappable: false)
                    else ...[
                      _categoryChip('Veg', active: selectedCategory == 'Veg'),
                      const SizedBox(width: 2),
                      _categoryChip('Non-Veg',
                          active: selectedCategory == 'Non-Veg'),
                      const SizedBox(width: 2),
                      _categoryChip('All', active: selectedCategory == 'All'),
                    ],
                    const SizedBox(width: 4),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white70),
                      onPressed: () => Navigator.pop(context),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 28,
                        minHeight: 28,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const Divider(color: Colors.white12, height: 1),
          Padding(
            padding: const EdgeInsets.all(8),
            child: TextField(
              controller: searchController,
              autofocus: true,
              style: const TextStyle(color: Colors.white, fontSize: 13),
              decoration: InputDecoration(
                hintText: 'Search...',
                hintStyle: const TextStyle(color: Colors.grey, fontSize: 11),
                prefixIcon:
                    const Icon(Icons.search, color: Colors.grey, size: 18),
                suffixIcon: query.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.close, color: Colors.grey),
                        onPressed: () {
                          setState(() {
                            query = '';
                            searchController.clear();
                          });
                        },
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                          minWidth: 24,
                          minHeight: 24,
                        ),
                      )
                    : null,
                filled: true,
                fillColor: Colors.grey.shade900,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
              ),
              onChanged: (v) => setState(() => query = v.trim()),
            ),
          ),
          Expanded(
            child: isLoading
                ? const Center(
                    child: CircularProgressIndicator(color: AppColors.gold),
                  )
                : filtered.isEmpty
                    ? const Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.search_off,
                                color: Colors.grey, size: 36),
                            SizedBox(height: 4),
                            Text(
                              'No foods found',
                              style:
                                  TextStyle(color: Colors.grey, fontSize: 12),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        itemCount: filtered.length,
                        itemBuilder: (context, index) {
                          final f = filtered[index];
                          final isSelected = selectedIds.contains(f['id']);
                          final controller = quantityControllers[f['id']]!;
                          final currentQty = selectedQuantities[f['id']] ??
                              (f['base_quantity'] as num).toDouble();
                          final baseQty =
                              (f['base_quantity'] as num).toDouble();

                          final calories = _calculateMacro(
                              (f['calories'] as num).toDouble(),
                              currentQty,
                              baseQty);
                          final protein = _calculateMacro(
                              (f['protein'] as num).toDouble(),
                              currentQty,
                              baseQty);
                          final carbs = _calculateMacro(
                              (f['carbs'] as num).toDouble(),
                              currentQty,
                              baseQty);
                          final fats = _calculateMacro(
                              (f['fats'] as num).toDouble(),
                              currentQty,
                              baseQty);

                          return Container(
                            margin: const EdgeInsets.only(bottom: 4),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? AppColors.gold.withOpacity(0.12)
                                  : Colors.grey.shade900,
                              borderRadius: BorderRadius.circular(8),
                              border: isSelected
                                  ? Border.all(
                                      color: AppColors.gold.withOpacity(0.5))
                                  : null,
                            ),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  Expanded(
                                    flex: 3,
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          f['name'],
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 10,
                                            fontWeight: FontWeight.w500,
                                          ),
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        const SizedBox(height: 1),
                                        Text(
                                          '${calories.toStringAsFixed(0)} kcal · P${protein.toStringAsFixed(0)}g C${carbs.toStringAsFixed(0)}g F${fats.toStringAsFixed(0)}g',
                                          style: const TextStyle(
                                            color: Colors.grey,
                                            fontSize: 7,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Container(
                                        width: 32,
                                        height: 22,
                                        decoration: BoxDecoration(
                                          color: Colors.grey.shade800,
                                          borderRadius:
                                              BorderRadius.circular(4),
                                        ),
                                        child: TextField(
                                          controller: controller,
                                          keyboardType: const TextInputType
                                              .numberWithOptions(decimal: true),
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                          ),
                                          textAlign: TextAlign.center,
                                          decoration: const InputDecoration(
                                            isDense: true,
                                            contentPadding: EdgeInsets.zero,
                                            border: InputBorder.none,
                                          ),
                                          onChanged: (value) {
                                            final newValue =
                                                double.tryParse(value);
                                            if (newValue != null &&
                                                newValue >= 0) {
                                              _updateQuantity(
                                                  f['id'], newValue);
                                            }
                                          },
                                        ),
                                      ),
                                      const SizedBox(width: 2),
                                      SizedBox(
                                        width: 20,
                                        child: Text(
                                          f['base_unit'],
                                          style: const TextStyle(
                                            color: Colors.grey,
                                            fontSize: 7,
                                            fontWeight: FontWeight.w500,
                                          ),
                                          textAlign: TextAlign.center,
                                        ),
                                      ),
                                      const SizedBox(width: 2),
                                      GestureDetector(
                                        onTap: () {
                                          setState(() {
                                            if (isSelected) {
                                              selectedIds.remove(f['id']);
                                            } else {
                                              selectedIds.add(f['id']);
                                            }
                                          });
                                        },
                                        child: Container(
                                          width: 22,
                                          height: 22,
                                          decoration: BoxDecoration(
                                            color: isSelected
                                                ? AppColors.gold
                                                : Colors.grey.shade700,
                                            shape: BoxShape.circle,
                                          ),
                                          child: Icon(
                                            isSelected
                                                ? Icons.check
                                                : Icons.add,
                                            color: isSelected
                                                ? Colors.black
                                                : Colors.white,
                                            size: 14,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
          ),
          if (selectedIds.isNotEmpty)
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.gold,
                      padding: const EdgeInsets.symmetric(vertical: 8),
                    ),
                    onPressed: () {
                      final selectedFoods = selectedIds.map((id) {
                        final food = foodById[id]!;
                        final qty = selectedQuantities[id] ??
                            (food['base_quantity'] as num).toDouble();
                        return {
                          ...food,
                          'base_quantity': qty,
                          'original_base_quantity': food['base_quantity'],
                        };
                      }).toList();
                      Navigator.pop(context, selectedFoods);
                    },
                    child: Text(
                      'ADD ${selectedIds.length} FOOD${selectedIds.length > 1 ? 'S' : ''}',
                      style: const TextStyle(
                          color: Colors.black,
                          fontWeight: FontWeight.bold,
                          fontSize: 10),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
