import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../theme/app_theme.dart';
import 'diet_preview_page.dart';

/// Read-only diet preview for a coach who does NOT have edit-diet
/// permission. Shows whichever Veg/Non-Veg plan the head coach/admin has
/// assigned, using the same DietPreviewPage UI the builder uses — no
/// editing, no saving. Shows "No diet assigned" for any slot that hasn't
/// been set up yet.
class CoachDietPreviewScreen extends StatefulWidget {
  final Map<String, dynamic> member;
  const CoachDietPreviewScreen({super.key, required this.member});

  @override
  State<CoachDietPreviewScreen> createState() =>
      _CoachDietPreviewScreenState();
}

class _CoachDietPreviewScreenState extends State<CoachDietPreviewScreen> {
  int selectedIndex = 0;

  @override
  Widget build(BuildContext context) {
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
                    constraints:
                        const BoxConstraints(minWidth: 28, minHeight: 28),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Row(
                      children: [
                        _tab('Veg', 0),
                        const SizedBox(width: 4),
                        _tab('Non-Veg', 1),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: IndexedStack(
              index: selectedIndex,
              children: [
                _DietSlotPreview(
                  memberId: widget.member['id'],
                  member: widget.member,
                  slot: 1,
                  dietType: 'Veg',
                ),
                _DietSlotPreview(
                  memberId: widget.member['id'],
                  member: widget.member,
                  slot: 2,
                  dietType: 'Non-Veg',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _tab(String label, int index) {
    final isSelected = selectedIndex == index;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => selectedIndex = index),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
          decoration: BoxDecoration(
            color: isSelected
                ? AppColors.gold.withOpacity(0.15)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color:
                  isSelected ? AppColors.gold : Colors.white.withOpacity(0.1),
            ),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: isSelected ? AppColors.gold : Colors.grey,
              fontSize: 12,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ),
      ),
    );
  }
}

class _DietSlotPreview extends StatefulWidget {
  final String memberId;
  final Map<String, dynamic> member;
  final int slot;
  final String dietType;
  const _DietSlotPreview({
    required this.memberId,
    required this.member,
    required this.slot,
    required this.dietType,
  });

  @override
  State<_DietSlotPreview> createState() => _DietSlotPreviewState();
}

class _DietSlotPreviewState extends State<_DietSlotPreview> {
  bool isLoading = true;
  Map<String, dynamic>? diet;
  Map<String, List<DietFoodItem>> sections = {
    for (final s in kDietSections) s: <DietFoodItem>[],
  };

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => isLoading = true);
    try {
      final dietData = await Supabase.instance.client
          .from('diets')
          .select()
          .eq('member_id', widget.memberId)
          .eq('slot', widget.slot)
          .maybeSingle();

      if (dietData == null) {
        if (mounted) {
          setState(() {
            diet = null;
            isLoading = false;
          });
        }
        return;
      }

      final items = await Supabase.instance.client
          .from('diet_items')
          .select(
              'id, section, quantity, order_index, foods(id, name, base_quantity, base_unit, calories, protein, carbs, fats)')
          .eq('diet_id', dietData['id'])
          .order('order_index');

      final grouped = {for (final s in kDietSections) s: <DietFoodItem>[]};
      for (final item in items) {
        final food = item['foods'];
        if (food == null) continue;
        final section = item['section'] as String;
        grouped.putIfAbsent(section, () => []).add(DietFoodItem(
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

      if (mounted) {
        setState(() {
          diet = dietData;
          sections = grouped;
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

    if (diet == null) {
      return Center(
        child: Text(
          'No ${widget.dietType} diet assigned',
          style: const TextStyle(color: Colors.grey, fontSize: 14),
        ),
      );
    }

    return DietPreviewPage(
      member: widget.member,
      dietName:
          diet!['name'] ?? '${widget.member['full_name']} - ${widget.dietType}',
      dietType: widget.dietType,
      calorieTarget: (diet!['calorie_target'] ?? 0).toDouble(),
      proteinTarget: (diet!['protein_target'] ?? 0).toDouble(),
      carbsTarget: (diet!['carbs_target'] ?? 0).toDouble(),
      fatsTarget: (diet!['fats_target'] ?? 0).toDouble(),
      sections: sections,
      lastUpdated: diet!['updated_at'] != null
          ? DateTime.tryParse(diet!['updated_at'])
          : null,
    );
  }
}
