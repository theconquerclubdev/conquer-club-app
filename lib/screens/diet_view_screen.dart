import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../theme/app_theme.dart';

const kSections = ['Breakfast', 'Lunch', 'Dinner', 'Snacks'];

class DietViewScreen extends StatefulWidget {
  final String dietId;
  const DietViewScreen({super.key, required this.dietId});

  @override
  State<DietViewScreen> createState() => _DietViewScreenState();
}

class _DietViewScreenState extends State<DietViewScreen> {
  bool isLoading = true;
  Map<String, dynamic>? diet;
  List<Map<String, dynamic>> meals = [];
  Map<String, List<Map<String, dynamic>>> sections = {};

  @override
  void initState() {
    super.initState();
    loadDiet();
  }

  Future<void> loadDiet() async {
    setState(() => isLoading = true);
    try {
      final dietData = await Supabase.instance.client
          .from('diets')
          .select()
          .eq('id', widget.dietId)
          .maybeSingle();
      diet = dietData;

      final data = await Supabase.instance.client
          .from('diet_items')
          .select('*, foods(*)')
          .eq('diet_id', widget.dietId)
          .order('order_index');

      setState(() {
        meals = List<Map<String, dynamic>>.from(data);
        final grouped = {for (var s in kSections) s: <Map<String, dynamic>>[]};
        for (final meal in meals) {
          final section = meal['section'] ?? 'Other';
          if (grouped.containsKey(section)) {
            grouped[section]!.add(meal);
          } else {
            if (!grouped.containsKey('Other')) {
              grouped['Other'] = [];
            }
            grouped['Other']!.add(meal);
          }
        }
        sections = grouped;
        isLoading = false;
      });
    } catch (e) {
      print('Error loading diet: $e');
      setState(() => isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(diet?['name'] ?? 'Diet Plan'),
      ),
      body: isLoading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.gold),
            )
          : meals.isEmpty
              ? const Center(
                  child: Text(
                    'No meals in this diet yet.',
                    style: TextStyle(color: Colors.grey),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppColors.cardDark,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: AppColors.gold.withOpacity(0.2),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.restaurant,
                            color: AppColors.gold,
                            size: 24,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              diet?['name'] ?? 'Diet Plan',
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
                    if (diet?['updated_at'] != null) ...[
                      const SizedBox(height: 6),
                      Text(
                        'Last updated: ${DateFormat('MMM d, yyyy · h:mm a').format(DateTime.parse(diet!['updated_at']))}',
                        style:
                            const TextStyle(color: Colors.grey, fontSize: 12),
                      ),
                    ],
                    const SizedBox(height: 20),

                    // Meals by section
                    for (final section in kSections) ...[
                      if (sections[section]?.isNotEmpty ?? false) ...[
                        Text(
                          section.toUpperCase(),
                          style: TextStyle(
                            color: AppColors.gold,
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1,
                          ),
                        ),
                        const SizedBox(height: 8),
                        ...?sections[section]
                            ?.map((meal) => _MealCard(meal: meal)),
                        const SizedBox(height: 16),
                      ],
                    ],

                    // Other meals
                    if (sections['Other']?.isNotEmpty ?? false) ...[
                      Text(
                        'OTHER',
                        style: TextStyle(
                          color: AppColors.gold,
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1,
                        ),
                      ),
                      const SizedBox(height: 8),
                      ...?sections['Other']
                          ?.map((meal) => _MealCard(meal: meal)),
                      const SizedBox(height: 16),
                    ],
                  ],
                ),
    );
  }
}

class _MealCard extends StatelessWidget {
  final Map<String, dynamic> meal;

  const _MealCard({required this.meal});

  @override
  Widget build(BuildContext context) {
    final food = meal['foods'] as Map<String, dynamic>?;
    final quantity = meal['quantity'] as num? ?? 0;
    final foodName = food?['name'] ?? 'Unknown Food';

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.cardDark,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              foodName,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
          ),
          Text(
            '$quantity g',
            style: const TextStyle(
              color: Colors.grey,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}
