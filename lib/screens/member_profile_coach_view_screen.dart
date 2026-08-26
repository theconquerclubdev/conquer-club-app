import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import '../theme/app_theme.dart';
import 'workout_builder_screen.dart';
import 'diet_builder_screen.dart';
import 'workout_progress_screen.dart';
import 'streaks_tab.dart';
import 'step_counter_screen.dart';
import 'member_progress_screen.dart';

class MemberProfileCoachViewScreen extends StatefulWidget {
  final Map<String, dynamic> member;
  final bool canEditDiet;
  final bool canEditWorkout;

  const MemberProfileCoachViewScreen({
    super.key,
    required this.member,
    this.canEditDiet = false,
    this.canEditWorkout = false,
  });

  @override
  State<MemberProfileCoachViewScreen> createState() =>
      _MemberProfileCoachViewScreenState();
}

class _MemberProfileCoachViewScreenState
    extends State<MemberProfileCoachViewScreen> {
  Map<String, dynamic>? measurements;
  List<Map<String, dynamic>> measurementHistory = [];
  List<Map<String, dynamic>> payments = [];
  bool isLoading = true;
  int currentStreak = 0;
  String? streakMissedReason;
  int daysLeft = 0;
  bool isMembershipActive = false;
  bool isDietUpdateRequired = false;
  int dietDaysSinceUpdate = 0;

  // Step Counter Data
  int todaySteps = 0;
  int stepGoal = 10000;
  double stepProgress = 0.0;

  // Current Weight (from measurements)
  double? currentWeight;
  // Height from profile
  String height = '--';

  // Measurement Graph
  String selectedMetric = 'weight_kg';
  List<Map<String, dynamic>> measurementFields = [
    {'key': 'weight_kg', 'label': 'Weight', 'unit': 'kg'},
    {'key': 'chest', 'label': 'Chest', 'unit': 'in'},
    {'key': 'left_arm', 'label': 'Left Arm', 'unit': 'in'},
    {'key': 'right_arm', 'label': 'Right Arm', 'unit': 'in'},
    {'key': 'abdomen', 'label': 'Abdomen', 'unit': 'in'},
    {'key': 'waist', 'label': 'Waist', 'unit': 'in'},
    {'key': 'hips', 'label': 'Hips', 'unit': 'in'},
    {'key': 'left_thigh', 'label': 'Left Thigh', 'unit': 'in'},
    {'key': 'right_thigh', 'label': 'Right Thigh', 'unit': 'in'},
  ];

  @override
  void initState() {
    super.initState();
    loadData();
  }

  Future<void> loadData() async {
    try {
      final memberId = widget.member['id'];

      // 1. Fetch profile info directly from Supabase to guarantee fresh data
      final profileData = await Supabase.instance.client
          .from('profiles')
          .select('height_cm, membership_end_date, step_goal')
          .eq('id', memberId)
          .maybeSingle();

      // 2. Fetch RPC for remaining calculations
      Map<String, dynamic> data = {};
      try {
        final response = await Supabase.instance.client.rpc(
          'get_member_full_profile',
          params: {'p_member_id': memberId},
        );
        if (response != null && response is Map<String, dynamic>) {
          data = response;
        }
      } catch (e) {
        debugPrint('RPC error: $e');
      }

      final profile =
          (data['profile'] as Map<String, dynamic>?) ?? profileData ?? {};

      // Current Weight (safe cast)
      currentWeight = (data['current_weight'] as num?)?.toDouble();

      // Height (checks direct profile first, then RPC)
      final hVal = profileData?['height_cm'] ??
          data['height_cm'] ??
          profile['height_cm'];
      height = (hVal != null) ? '$hVal cm' : '-- cm';

      // Latest Measurements
      measurements = data['measurements'] as Map<String, dynamic>?;

      // Measurement History
      measurementHistory =
          List<Map<String, dynamic>>.from(data['measurement_history'] ?? []);

      // Current Streak - Use RPC function (same as member_home_screen)
      try {
        final streakResult = await Supabase.instance.client
            .rpc('get_current_streak', params: {'p_member_id': memberId});
        currentStreak = (streakResult as int?) ?? 0;
      } catch (e) {
        debugPrint('Error fetching streak: $e');
        currentStreak = 0;
      }

      // Today's Steps - Direct query from step_logs
      try {
        final todayStr = DateTime.now().toIso8601String().substring(0, 10);
        final stepLog = await Supabase.instance.client
            .from('step_logs')
            .select('steps')
            .eq('member_id', memberId)
            .eq('log_date', todayStr)
            .maybeSingle();
        todaySteps = (stepLog?['steps'] as num?)?.toInt() ?? 0;
      } catch (e) {
        debugPrint('Error fetching steps: $e');
        todaySteps = 0;
      }

      // Step Goal (prioritize direct profile query)
      final rawStepGoal = profileData?['step_goal'] ??
          profile['step_goal'] ??
          widget.member['step_goal'];
      stepGoal = (rawStepGoal as num?)?.toInt() ?? 10000;
      stepProgress =
          stepGoal > 0 ? (todaySteps / stepGoal).clamp(0.0, 1.0) : 0.0;

      // ✅ Membership Status: checks direct profile first, then RPC profile, then widget.member
      final endDateStr = (profileData?['membership_end_date'] ??
          profile['membership_end_date'] ??
          widget.member['membership_end_date']) as String?;

      if (endDateStr != null && endDateStr.isNotEmpty) {
        try {
          final endDate = DateTime.parse(endDateStr);
          final now = DateTime.now();
          final todayDate = DateTime(now.year, now.month, now.day);
          final cleanEndDate =
              DateTime(endDate.year, endDate.month, endDate.day);
          daysLeft = cleanEndDate.difference(todayDate).inDays;
          isMembershipActive = daysLeft >= 0;
        } catch (e) {
          debugPrint('Error parsing membership date: $e');
          isMembershipActive = false;
        }
      } else {
        isMembershipActive = false;
      }

      // Diet Update Check
      final latestDiet = data['latest_diet'] as Map<String, dynamic>?;
      if (latestDiet != null && latestDiet['updated_at'] != null) {
        try {
          final dietDate = DateTime.parse(latestDiet['updated_at']);
          dietDaysSinceUpdate = DateTime.now().difference(dietDate).inDays;
          isDietUpdateRequired = dietDaysSinceUpdate >= 7;
        } catch (_) {}
      }

      if (mounted) {
        setState(() {
          isLoading = false;
        });
      }
    } catch (err, stack) {
      debugPrint('Error in loadData(): $err\n$stack');
      if (mounted) {
        setState(() => isLoading = false);
      }
    }
  }

  Future<void> _resetPassword() async {
    final controller = TextEditingController();
    final newPassword = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.cardDark,
        title: const Text(
          'Set New Password',
          style: TextStyle(color: Colors.white),
        ),
        content: TextField(
          controller: controller,
          style: const TextStyle(color: Colors.white),
          obscureText: true,
          decoration: const InputDecoration(
            labelText: 'New password (min 6 chars)',
            labelStyle: TextStyle(color: Colors.grey),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Set'),
          ),
        ],
      ),
    );

    if (newPassword == null || newPassword.length < 6) return;

    try {
      await Supabase.instance.client.functions.invoke(
        'reset-password',
        body: {'targetUserId': widget.member['id'], 'newPassword': newPassword},
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Password updated!'),
              backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _showMeasurementHistory() {
    if (measurementHistory.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No measurement history available')),
      );
      return;
    }

    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.cardDark,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => StatefulBuilder(
        builder: (context, setSheetState) {
          final metricMeta = measurementFields.firstWhere(
            (f) => f['key'] == selectedMetric,
            orElse: () => measurementFields.first,
          );

          final points = <FlSpot>[];
          for (int i = 0; i < measurementHistory.length; i++) {
            final val = measurementHistory[i][selectedMetric];
            if (val != null) {
              points.add(FlSpot(i.toDouble(), (val as num).toDouble()));
            }
          }

          final latestValue = measurementHistory.isNotEmpty
              ? measurementHistory.last[selectedMetric]
              : null;
          final firstValue = measurementHistory.isNotEmpty
              ? measurementHistory.first[selectedMetric]
              : null;
          final delta = (latestValue != null && firstValue != null)
              ? (latestValue - firstValue)
              : null;

          return Container(
            height: MediaQuery.of(context).size.height * 0.7,
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      '📊 Measurement History',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.grey),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'Latest: ${latestValue != null ? latestValue : '--'} ${metricMeta['unit']}',
                  style: TextStyle(color: Colors.grey, fontSize: 13),
                ),
                if (delta != null)
                  Text(
                    'Change: ${delta > 0 ? '+' : ''}${delta.toStringAsFixed(1)} ${metricMeta['unit']}',
                    style: TextStyle(
                      color: delta == 0
                          ? Colors.grey
                          : delta > 0
                              ? Colors.green
                              : Colors.red,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                const SizedBox(height: 12),
                SizedBox(
                  height: 32,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: measurementFields.map((f) {
                      final selected = f['key'] == selectedMetric;
                      return Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: ChoiceChip(
                          label: Text(
                            f['label']!,
                            style: TextStyle(
                              fontSize: selected ? 10 : 9,
                              color: selected ? Colors.black : Colors.white,
                            ),
                          ),
                          selected: selected,
                          onSelected: (_) => setSheetState(() {
                            selectedMetric = f['key']!;
                          }),
                          selectedColor: AppColors.gold,
                          backgroundColor: AppColors.cardDark,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                        ),
                      );
                    }).toList(),
                  ),
                ),
                const SizedBox(height: 12),
                points.length < 2
                    ? Expanded(
                        child: Center(
                          child: Text(
                            'Need at least 2 measurements for a graph',
                            style: TextStyle(color: Colors.grey.shade500),
                          ),
                        ),
                      )
                    : Expanded(
                        child: LineChart(
                          LineChartData(
                            gridData: const FlGridData(show: false),
                            titlesData: FlTitlesData(
                              leftTitles: AxisTitles(
                                sideTitles: SideTitles(
                                  showTitles: true,
                                  reservedSize: 30,
                                  getTitlesWidget: (value, meta) {
                                    return Text(
                                      value.toInt().toString(),
                                      style: const TextStyle(
                                        color: Colors.grey,
                                        fontSize: 8,
                                      ),
                                    );
                                  },
                                ),
                              ),
                              topTitles: const AxisTitles(
                                sideTitles: SideTitles(showTitles: false),
                              ),
                              rightTitles: const AxisTitles(
                                sideTitles: SideTitles(showTitles: false),
                              ),
                              bottomTitles: AxisTitles(
                                sideTitles: SideTitles(
                                  showTitles: true,
                                  reservedSize: 20,
                                  interval: (points.length / 4)
                                      .clamp(1, points.length)
                                      .toDouble(),
                                  getTitlesWidget: (value, meta) {
                                    final idx = value.toInt();
                                    if (idx < 0 ||
                                        idx >= measurementHistory.length) {
                                      return const SizedBox.shrink();
                                    }
                                    final date = DateTime.parse(
                                      measurementHistory[idx]['recorded_at'],
                                    );
                                    return Padding(
                                      padding: const EdgeInsets.only(top: 4),
                                      child: Text(
                                        DateFormat('MMM d').format(date),
                                        style: const TextStyle(
                                          color: Colors.grey,
                                          fontSize: 8,
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ),
                            borderData: FlBorderData(show: false),
                            lineBarsData: [
                              LineChartBarData(
                                spots: points,
                                isCurved: true,
                                color: AppColors.gold,
                                barWidth: 2,
                                dotData: const FlDotData(show: true),
                                belowBarData: BarAreaData(
                                  show: true,
                                  gradient: LinearGradient(
                                    colors: [
                                      AppColors.gold.withOpacity(0.2),
                                      Colors.transparent,
                                    ],
                                    begin: Alignment.topCenter,
                                    end: Alignment.bottomCenter,
                                  ),
                                ),
                              ),
                            ],
                            minY: 0,
                          ),
                        ),
                      ),
                const SizedBox(height: 8),
                Container(
                  height: 80,
                  decoration: BoxDecoration(
                    color: AppColors.background,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: measurementHistory.length,
                    itemBuilder: (context, index) {
                      final log = measurementHistory[index];
                      final date = DateTime.parse(log['recorded_at']);
                      final value = log[selectedMetric];
                      return Container(
                        width: 80,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          border: Border(
                            right: BorderSide(
                              color: Colors.white.withOpacity(0.05),
                            ),
                          ),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              value != null ? value.toString() : '--',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              DateFormat('dd/MM').format(date),
                              style: const TextStyle(
                                color: Colors.grey,
                                fontSize: 8,
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.member;
    final name = m['full_name'] ?? 'Member';
    final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';
    final canEdit = widget.canEditDiet || widget.canEditWorkout;

    final membershipStatus =
        isMembershipActive ? '$daysLeft days left' : 'Expired';
    final membershipColor = isMembershipActive
        ? (daysLeft <= 7 ? Colors.orange : Colors.green)
        : Colors.red;

    final phone = m['phone'] ?? 'Not provided';

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        title: Text(
          name,
          style: const TextStyle(color: Colors.white),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.lock_reset, color: Colors.white70),
            onPressed: _resetPassword,
            tooltip: 'Reset Password',
          ),
        ],
      ),
      body: isLoading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.gold),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Column(
                      children: [
                        Container(
                          width: 80,
                          height: 80,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                AppColors.gold,
                                AppColors.gold.withOpacity(0.6),
                              ],
                            ),
                            shape: BoxShape.circle,
                          ),
                          child: Center(
                            child: Text(
                              initial,
                              style: const TextStyle(
                                color: Colors.black,
                                fontSize: 30,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          name,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          m['email'] ?? '',
                          style: const TextStyle(
                            color: Colors.grey,
                            fontSize: 13,
                          ),
                        ),
                        Text(
                          '📱 $phone',
                          style: const TextStyle(
                            color: Colors.grey,
                            fontSize: 12,
                          ),
                        ),
                        if (currentWeight != null)
                          Text(
                            '⚖️ Current Weight: ${currentWeight!.toStringAsFixed(1)} kg',
                            style: const TextStyle(
                              color: AppColors.gold,
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: membershipColor.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: membershipColor.withOpacity(0.3),
                            ),
                          ),
                          child: Text(
                            'Membership: $membershipStatus',
                            style: TextStyle(
                              color: membershipColor,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        if (isDietUpdateRequired)
                          Container(
                            margin: const EdgeInsets.only(top: 4),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.red.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: Colors.red.withOpacity(0.3),
                              ),
                            ),
                            child: Text(
                              '⚠️ Diet Update Required ($dietDaysSinceUpdate days ago)',
                              style: const TextStyle(
                                color: Colors.red,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        if (!canEdit)
                          Container(
                            margin: const EdgeInsets.only(top: 4),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade800,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Text(
                              'VIEW ONLY',
                              style: TextStyle(
                                color: Colors.grey,
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 1,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),

                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: AppColors.cardDark,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: AppColors.gold.withOpacity(0.15),
                      ),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: InkWell(
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const StreaksTab(),
                                ),
                              );
                            },
                            child: Row(
                              children: [
                                Text(
                                  currentStreak > 0 ? '🔥' : '⏳',
                                  style: const TextStyle(fontSize: 18),
                                ),
                                const SizedBox(width: 8),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      'Streak',
                                      style: TextStyle(
                                        color: Colors.grey.shade500,
                                        fontSize: 9,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                    Text(
                                      '$currentStreak d',
                                      style: TextStyle(
                                        color: currentStreak > 0
                                            ? AppColors.gold
                                            : Colors.grey,
                                        fontSize: 14,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                                if (streakMissedReason != null &&
                                    currentStreak == 0)
                                  Padding(
                                    padding: const EdgeInsets.only(left: 6),
                                    child: Text(
                                      '⚠️',
                                      style: TextStyle(
                                        color: Colors.red,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                        Container(
                          width: 1,
                          height: 30,
                          color: Colors.white.withOpacity(0.1),
                        ),
                        Expanded(
                          child: InkWell(
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => StepCounterScreen(
                                    liveTodaySteps: todaySteps,
                                    initialGoal: stepGoal,
                                    signupDate: DateTime.now(),
                                  ),
                                ),
                              );
                            },
                            child: Row(
                              children: [
                                Icon(
                                  Icons.directions_walk,
                                  color: AppColors.gold,
                                  size: 18,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        'Steps',
                                        style: TextStyle(
                                          color: Colors.grey.shade500,
                                          fontSize: 9,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                      Row(
                                        children: [
                                          Text(
                                            '$todaySteps',
                                            style: TextStyle(
                                              color: Colors.white,
                                              fontSize: 14,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                          const SizedBox(width: 4),
                                          Text(
                                            '/ $stepGoal',
                                            style: TextStyle(
                                              color: Colors.grey,
                                              fontSize: 11,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),

                  Row(
                    children: [
                      _StatBox(
                        label: 'HEIGHT',
                        value: height,
                      ),
                      const SizedBox(width: 10),
                      _StatBox(
                        label: 'WEIGHT',
                        value: currentWeight != null
                            ? '${currentWeight!.toStringAsFixed(1)} kg'
                            : '-- kg',
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  _StatBox(
                    label: 'GOAL',
                    value: m['goal'] ?? 'Not set',
                    fullWidth: true,
                  ),

                  const SizedBox(height: 16),

                  GestureDetector(
                    onTap: _showMeasurementHistory,
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.cardDark,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: AppColors.gold.withOpacity(0.15),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Text(
                                '📏 BODY MEASUREMENTS (inches)',
                                style: TextStyle(
                                  color: AppColors.gold,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 0.5,
                                ),
                              ),
                              const Spacer(),
                              const Icon(
                                Icons.chevron_right,
                                color: Colors.grey,
                                size: 18,
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          measurements == null
                              ? const Text(
                                  'No measurements recorded yet.',
                                  style: TextStyle(
                                      color: Colors.grey, fontSize: 12),
                                )
                              : Wrap(
                                  spacing: 8,
                                  runSpacing: 6,
                                  children: [
                                    _MiniStat('Chest', measurements!['chest']),
                                    _MiniStat(
                                        'L Arm', measurements!['left_arm']),
                                    _MiniStat(
                                        'R Arm', measurements!['right_arm']),
                                    _MiniStat(
                                        'Abdomen', measurements!['abdomen']),
                                    _MiniStat('Waist', measurements!['waist']),
                                    _MiniStat('Hips', measurements!['hips']),
                                    _MiniStat(
                                        'L Thigh', measurements!['left_thigh']),
                                    _MiniStat('R Thigh',
                                        measurements!['right_thigh']),
                                  ],
                                ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  GestureDetector(
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const WorkoutProgressScreen(),
                        ),
                      );
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.cardDark,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: AppColors.gold.withOpacity(0.2),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.fitness_center,
                            color: AppColors.gold,
                            size: 20,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'VIEW WORKOUT PROGRESS',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                          ),
                          const Icon(
                            Icons.chevron_right,
                            color: Colors.grey,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),

                  // ✅ Progress Photos Button - Fixed with memberId and readOnly
                  GestureDetector(
                    onTap: () {
                      final memberId = widget.member['id']?.toString();
                      if (memberId == null) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Member ID not found')),
                        );
                        return;
                      }
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => MemberProgressScreen(
                              memberId: memberId, readOnly: true),
                        ),
                      );
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.cardDark,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: Colors.purple.withOpacity(0.2),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.camera_alt,
                            color: Colors.purple.shade300,
                            size: 20,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'VIEW PROGRESS PHOTOS',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                          ),
                          const Icon(
                            Icons.chevron_right,
                            color: Colors.grey,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),

                  if (widget.canEditWorkout)
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        icon: const Icon(
                          Icons.fitness_center,
                          color: Colors.black,
                          size: 18,
                        ),
                        label: const Text('MANAGE WORKOUT PLAN'),
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => WorkoutBuilderScreen(member: m),
                            ),
                          );
                        },
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                        ),
                      ),
                    )
                  else
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        icon: Icon(
                          Icons.visibility,
                          color: AppColors.gold,
                          size: 18,
                        ),
                        label: Text(
                          'VIEW WORKOUT PLAN',
                          style: TextStyle(color: AppColors.gold),
                        ),
                        onPressed: () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content:
                                  Text('Workout plan preview coming soon!'),
                              backgroundColor: Colors.orange,
                            ),
                          );
                        },
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          side: BorderSide(color: AppColors.gold),
                        ),
                      ),
                    ),
                  const SizedBox(height: 8),

                  if (widget.canEditDiet)
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        icon: const Icon(
                          Icons.restaurant,
                          color: Colors.black,
                          size: 18,
                        ),
                        label: const Text('MANAGE DIET PLAN'),
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => DietBuilderScreen(member: m),
                            ),
                          );
                        },
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                        ),
                      ),
                    )
                  else
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        icon: Icon(
                          Icons.visibility,
                          color: AppColors.gold,
                          size: 18,
                        ),
                        label: Text(
                          'VIEW DIET PLAN',
                          style: TextStyle(color: AppColors.gold),
                        ),
                        onPressed: () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Diet plan preview coming soon!'),
                              backgroundColor: Colors.orange,
                            ),
                          );
                        },
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          side: BorderSide(color: AppColors.gold),
                        ),
                      ),
                    ),

                  const SizedBox(height: 10),

                  if (payments.isNotEmpty) ...[
                    const Divider(color: Colors.white12),
                    const SizedBox(height: 10),
                    Text(
                      '💳 RECENT PAYMENTS',
                      style: TextStyle(
                        color: AppColors.gold,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 6),
                    ...payments.map((p) {
                      final amount = (p['amount'] as num?)?.toDouble() ?? 0;
                      final status = p['status'] ?? 'pending';
                      final isCompleted = status == 'completed';
                      final date = p['payment_date'] != null
                          ? DateTime.parse(p['payment_date'])
                          : DateTime.now();

                      return Container(
                        margin: const EdgeInsets.only(bottom: 4),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.cardDark,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: isCompleted
                                ? Colors.green.withOpacity(0.2)
                                : Colors.orange.withOpacity(0.2),
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              isCompleted ? Icons.check_circle : Icons.pending,
                              color: isCompleted ? Colors.green : Colors.orange,
                              size: 14,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                '₹${amount.toStringAsFixed(0)} - ${p['plan_key'] ?? 'N/A'}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                ),
                              ),
                            ),
                            Text(
                              '${date.day}/${date.month}/${date.year}',
                              style: const TextStyle(
                                color: Colors.grey,
                                fontSize: 9,
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                  ],

                  if (!widget.canEditWorkout && !widget.canEditDiet)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.grey.withOpacity(0.05),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: Colors.grey.withOpacity(0.1),
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.info_outline,
                              color: Colors.grey.shade500,
                              size: 14,
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                'View-only mode. Contact admin for edit permissions.',
                                style: TextStyle(
                                  color: Colors.grey.shade500,
                                  fontSize: 11,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  const SizedBox(height: 20),
                ],
              ),
            ),
    );
  }
}

class _StatBox extends StatelessWidget {
  final String label;
  final String value;
  final bool fullWidth;

  const _StatBox({
    required this.label,
    required this.value,
    this.fullWidth = false,
  });

  @override
  Widget build(BuildContext context) {
    final child = Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
      decoration: BoxDecoration(
        color: AppColors.cardDark,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Colors.grey,
              fontSize: 9,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
    return fullWidth
        ? SizedBox(width: double.infinity, child: child)
        : Expanded(child: child);
  }
}

class _MiniStat extends StatelessWidget {
  final String label;
  final dynamic value;

  const _MiniStat(this.label, this.value);

  String get displayValue {
    if (value == null) return '--';
    if (value is String) return value;
    if (value is num) return value.toString();
    return '--';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.cardDark,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: Text(
        '$label: ${displayValue}"',
        style: const TextStyle(color: Colors.white, fontSize: 10),
      ),
    );
  }
}
