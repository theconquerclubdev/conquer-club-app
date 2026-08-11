import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../theme/app_theme.dart';
import 'diet_preview_page.dart';
import 'payments_screen.dart';

/// Loads everything DietPreviewPage needs for a given diet, then shows
/// it — this is how a member views their own diet plan, using the exact
/// same preview UI (table, watermark, PDF download) the coach sees when
/// building it. Coach/Save/Quit actions are simply omitted since a
/// member is only ever viewing, never editing.
class MemberDietPreviewLoader extends StatefulWidget {
  final String dietId;
  const MemberDietPreviewLoader({super.key, required this.dietId});

  @override
  State<MemberDietPreviewLoader> createState() =>
      _MemberDietPreviewLoaderState();
}

class _MemberDietPreviewLoaderState extends State<MemberDietPreviewLoader> {
  bool isLoading = true;
  String? error;

  Map<String, dynamic>? diet;
  Map<String, dynamic>? member;
  String coachName = 'Coach';
  Map<String, List<DietFoodItem>> sections = {
    for (final s in kDietSections) s: <DietFoodItem>[],
  };
  bool isMembershipActive = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => isLoading = true);
    try {
      final userId = Supabase.instance.client.auth.currentUser!.id;

      // Check membership status
      final profile = await Supabase.instance.client
          .from('profiles')
          .select('membership_end_date')
          .eq('id', userId)
          .maybeSingle();

      if (profile != null) {
        final endDate = profile['membership_end_date'] as String?;
        if (endDate != null) {
          final daysLeft =
              DateTime.parse(endDate).difference(DateTime.now()).inDays;
          isMembershipActive = daysLeft > 0;
        } else {
          isMembershipActive = false;
        }
      }

      final dietData = await Supabase.instance.client
          .from('diets')
          .select()
          .eq('id', widget.dietId)
          .single();

      final memberData = await Supabase.instance.client
          .from('profiles')
          .select('id, full_name, weight_kg, height_cm, assigned_coach_id')
          .eq('id', dietData['member_id'])
          .single();

      String resolvedCoachName = 'No coach assigned';
      final coachId = memberData['assigned_coach_id'];
      if (coachId != null) {
        final coachData = await Supabase.instance.client
            .from('profiles')
            .select('full_name, email')
            .eq('id', coachId)
            .maybeSingle();
        resolvedCoachName =
            coachData?['full_name'] ?? coachData?['email'] ?? 'Coach';
      }

      final items = await Supabase.instance.client
          .from('diet_items')
          .select(
              'id, section, quantity, order_index, foods(id, name, base_quantity, base_unit, calories, protein, carbs, fats)')
          .eq('diet_id', widget.dietId)
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

      setState(() {
        diet = dietData;
        member = memberData;
        coachName = resolvedCoachName;
        sections = grouped;
        isLoading = false;
      });
    } catch (e) {
      setState(() {
        error = e.toString();
        isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Scaffold(
        backgroundColor: Colors.white,
        body: Center(
          child: CircularProgressIndicator(color: AppColors.gold),
        ),
      );
    }

    if (error != null || diet == null || member == null) {
      return Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.black),
            onPressed: () => Navigator.pop(context),
          ),
        ),
        body: Center(
          child: Text(
            error != null ? 'Failed to load diet: $error' : 'Diet not found.',
            style: const TextStyle(color: Colors.black54),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    final slot = diet!['slot'];
    final dietType = slot == 1 ? 'Veg' : 'Non-Veg';

    // If membership is not active, show a locked message
    if (!isMembershipActive) {
      return Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.black),
            onPressed: () => Navigator.pop(context),
          ),
          title: const Text(
            'Diet Plan',
            style: TextStyle(color: Colors.black),
          ),
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.lock_outline, color: Colors.grey.shade600, size: 80),
              const SizedBox(height: 24),
              Text(
                '🔒 Diet Plan Locked',
                style: TextStyle(
                  color: Colors.grey.shade700,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 40),
                child: Text(
                  'Subscribe to unlock your personalized diet plan and get full access to all features.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.grey.shade500,
                    fontSize: 15,
                  ),
                ),
              ),
              const SizedBox(height: 32),
              ElevatedButton.icon(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const PaymentsScreen()),
                  );
                },
                icon: const Icon(Icons.lock_open, color: Colors.black),
                label: const Text('UNLOCK NOW'),
                style: ElevatedButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
                  backgroundColor: AppColors.gold,
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return DietPreviewPage(
      member: member!,
      dietName: diet!['name'] ?? '${member!['full_name']} - $dietType',
      dietType: dietType,
      calorieTarget: (diet!['calorie_target'] ?? 0).toDouble(),
      proteinTarget: (diet!['protein_target'] ?? 0).toDouble(),
      carbsTarget: (diet!['carbs_target'] ?? 0).toDouble(),
      fatsTarget: (diet!['fats_target'] ?? 0).toDouble(),
      sections: sections,
      lastUpdated: diet!['updated_at'] != null
          ? DateTime.tryParse(diet!['updated_at'])
          : null,
      coachNameOverride: coachName,
    );
  }
}
