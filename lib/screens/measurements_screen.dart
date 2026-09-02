import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../theme/app_theme.dart';
import 'member_home_screen.dart';
import '../providers/master_data_provider.dart';

class MeasurementsScreen extends StatefulWidget {
  final bool isOnboarding;
  final bool embedded;
  const MeasurementsScreen(
      {super.key, this.isOnboarding = false, this.embedded = false});

  @override
  State<MeasurementsScreen> createState() => _MeasurementsScreenState();
}

class _MeasurementsScreenState extends State<MeasurementsScreen> {
  // ✅ REMOVED height from fieldsMeta (height is managed in profile)
  final fieldsMeta = [
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

  final ranges = ['1W', '1M', '3M', '6M', '1Y', 'ALL'];
  String selectedRange = 'ALL';
  late String selectedMetric;

  List<Map<String, dynamic>> allHistory = [];
  bool isLoading = true;
  bool hasLoggedToday = false;

  bool _isLoadingHistory = false;

  @override
  void initState() {
    super.initState();
    selectedMetric = fieldsMeta[0]['key']!;
    loadHistory().then((_) {
      if (widget.isOnboarding && mounted) openNewEntryForm();
    });
  }

  bool _hasLoggedToday() {
    if (allHistory.isEmpty) return false;
    final today = DateTime.now();
    final todayStr = DateFormat('yyyy-MM-dd').format(today);

    for (final log in allHistory) {
      final logDate = DateTime.parse(log['recorded_at']);
      final logStr = DateFormat('yyyy-MM-dd').format(logDate);
      if (logStr == todayStr) {
        return true;
      }
    }
    return false;
  }

  bool get _isSunday => DateTime.now().weekday == DateTime.sunday;

  bool get _canAddMeasurement {
    if (allHistory.isEmpty) return true;
    if (_hasLoggedToday()) return false;
    return _isSunday;
  }

  String? get _addMeasurementBlockReason {
    if (allHistory.isEmpty) return null;
    if (_hasLoggedToday()) {
      return 'You have already logged measurements today.';
    }
    if (!_isSunday) {
      return 'Measurements can only be updated on Sundays.';
    }
    return null;
  }

  Future<void> loadHistory() async {
    // ✅ Guard against overlapping calls
    if (_isLoadingHistory) return;
    _isLoadingHistory = true;

    setState(() => isLoading = true);
    final userId = Supabase.instance.client.auth.currentUser!.id;
    final data = await Supabase.instance.client
        .from('measurement_logs')
        .select()
        .eq('member_id', userId)
        .order('recorded_at', ascending: true);
    if (mounted) {
      setState(() {
        allHistory = List<Map<String, dynamic>>.from(data);
        hasLoggedToday = _hasLoggedToday();
        isLoading = false;
      });
    }
    _isLoadingHistory = false;
  }

  List<Map<String, dynamic>> get filteredByRange {
    if (selectedRange == 'ALL' || allHistory.isEmpty) return allHistory;
    final now = DateTime.now();
    Duration cutoff;
    switch (selectedRange) {
      case '1W':
        cutoff = const Duration(days: 7);
        break;
      case '1M':
        cutoff = const Duration(days: 30);
        break;
      case '3M':
        cutoff = const Duration(days: 90);
        break;
      case '6M':
        cutoff = const Duration(days: 180);
        break;
      case '1Y':
        cutoff = const Duration(days: 365);
        break;
      default:
        cutoff = const Duration(days: 36500);
    }
    final cutoffDate = now.subtract(cutoff);
    final list = allHistory
        .where((h) => DateTime.parse(h['recorded_at']).isAfter(cutoffDate))
        .toList();
    return list.isEmpty ? [allHistory.last] : list;
  }

  Future<void> openNewEntryForm() async {
    if (!_canAddMeasurement) {
      final reason =
          _addMeasurementBlockReason ?? 'Measurements cannot be updated now.';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(reason),
          backgroundColor: Colors.orange,
          duration: const Duration(seconds: 3),
        ),
      );
      return;
    }

    final controllers = {
      for (var f in fieldsMeta) f['key']!: TextEditingController(),
    };

    if (allHistory.isNotEmpty) {
      for (var f in fieldsMeta) {
        final val = allHistory.last[f['key']];
        if (val != null) controllers[f['key']]!.text = val.toString();
      }
    }

    final saved = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: AppColors.cardDark,
      isScrollControlled: true,
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: DraggableScrollableSheet(
          initialChildSize: 0.85,
          maxChildSize: 0.95,
          expand: false,
          builder: (context, scrollController) => Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Text(
                      'LOG NEW MEASUREMENT',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: _isSunday
                            ? Colors.green.withOpacity(0.2)
                            : Colors.orange.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: _isSunday
                              ? Colors.green.withOpacity(0.3)
                              : Colors.orange.withOpacity(0.3),
                        ),
                      ),
                      child: Text(
                        _isSunday ? '✅ Sunday Update' : '⏳ Sunday Only',
                        style: TextStyle(
                          color: _isSunday ? Colors.green : Colors.orange,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                if (allHistory.isNotEmpty)
                  Text(
                    '📝 You can update measurements on Sundays only.',
                    style: TextStyle(
                      color: Colors.grey.shade500,
                      fontSize: 12,
                    ),
                  ),
                const SizedBox(height: 16),
                Expanded(
                  child: ListView(
                    controller: scrollController,
                    children: fieldsMeta
                        .map(
                          (f) => Padding(
                            padding: const EdgeInsets.only(
                              bottom: 12,
                            ),
                            child: TextField(
                              controller: controllers[f['key']],
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                decimal: true,
                              ),
                              style: const TextStyle(
                                color: Colors.white,
                              ),
                              decoration: InputDecoration(
                                labelText: '${f['label']} (${f['unit']}) *',
                                labelStyle: const TextStyle(
                                  color: Colors.grey,
                                ),
                              ),
                            ),
                          ),
                        )
                        .toList(),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '⚠️ All fields are required.',
                  style: TextStyle(
                    color: Colors.grey.shade500,
                    fontSize: 11,
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () async {
                      // ✅ VALIDATION: Check all fields are filled
                      bool allFilled = true;
                      String? firstEmptyField;

                      for (final f in fieldsMeta) {
                        final value = controllers[f['key']]!.text.trim();
                        if (value.isEmpty) {
                          allFilled = false;
                          firstEmptyField = f['label'];
                          break;
                        }
                        if (double.tryParse(value) == null) {
                          allFilled = false;
                          firstEmptyField = f['label'];
                          break;
                        }
                      }

                      if (!allFilled) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              'Please fill all fields (${firstEmptyField ?? ''} is empty or invalid)',
                            ),
                            backgroundColor: Colors.red,
                          ),
                        );
                        return;
                      }

                      final userId =
                          Supabase.instance.client.auth.currentUser!.id;
                      final values = <String, dynamic>{
                        'member_id': userId,
                      };
                      for (var f in fieldsMeta) {
                        values[f['key']!] = double.tryParse(
                          controllers[f['key']]!.text.trim(),
                        );
                      }
                      await Supabase.instance.client
                          .from('measurement_logs')
                          .insert(values);
                      if (context.mounted) Navigator.pop(context, true);
                    },
                    child: const Text('SAVE ENTRY'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    if (saved == true) {
      await loadHistory();
      // Invalidate cache for the current user
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId != null) {
        MasterDataProvider.instance.invalidateCache(userId);
      }
      if (widget.isOnboarding && mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const MemberHomeScreen()),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final rangeData = filteredByRange;
    final metricMeta = fieldsMeta.firstWhere((f) => f['key'] == selectedMetric);

    final points = <FlSpot>[];
    for (int i = 0; i < rangeData.length; i++) {
      final val = rangeData[i][selectedMetric];
      if (val != null)
        points.add(FlSpot(i.toDouble(), (val as num).toDouble()));
    }

    final latestValue =
        rangeData.isNotEmpty ? rangeData.last[selectedMetric] : null;
    final firstValue =
        rangeData.isNotEmpty ? rangeData.first[selectedMetric] : null;
    final delta = (latestValue != null && firstValue != null)
        ? (latestValue - firstValue)
        : null;

    final body = isLoading
        ? const Center(child: CircularProgressIndicator(color: AppColors.gold))
        : allHistory.isEmpty
            ? const Center(
                child: Text(
                  'No measurements logged yet.\nTap + to add your first entry.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey),
                ),
              )
            : ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  if (widget.embedded)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('BODY MEASUREMENTS',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w900)),
                          Tooltip(
                            message: _addMeasurementBlockReason ??
                                'Add new measurement',
                            child: IconButton(
                              icon: Icon(
                                Icons.add_circle,
                                color: _canAddMeasurement
                                    ? AppColors.gold
                                    : Colors.grey,
                              ),
                              onPressed:
                                  _canAddMeasurement ? openNewEntryForm : null,
                            ),
                          ),
                        ],
                      ),
                    ),
                  // Body Guide Card - REMOVED Male/Female toggle
                  const _BodyGuideCard(),

                  // Metric selector chips
                  SizedBox(
                    height: 40,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      children: fieldsMeta.map((f) {
                        final selected = f['key'] == selectedMetric;
                        return Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ChoiceChip(
                            label: Text(f['label']!),
                            selected: selected,
                            onSelected: (_) => setState(
                              () => selectedMetric = f['key']!,
                            ),
                            selectedColor: AppColors.gold,
                            backgroundColor: AppColors.cardDark,
                            labelStyle: TextStyle(
                              color: selected ? Colors.black : Colors.white,
                              fontSize: 12,
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Big frozen "latest" number, like stock price
                  Text(
                    metricMeta['label']!.toUpperCase(),
                    style: TextStyle(
                      color: AppColors.gold,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Flexible(
                        child: Text(
                          latestValue != null ? '$latestValue' : '--',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 36,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Text(
                          metricMeta['unit']!,
                          style: const TextStyle(
                            color: Colors.grey,
                            fontSize: 16,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      if (delta != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: (delta == 0
                                      ? Colors.grey
                                      : (delta > 0
                                          ? Colors.green
                                          : Colors.redAccent))
                                  .withOpacity(0.15),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              '${delta > 0 ? '+' : ''}${delta.toStringAsFixed(1)} ${metricMeta['unit']}',
                              style: TextStyle(
                                color: delta == 0
                                    ? Colors.grey
                                    : (delta > 0
                                        ? Colors.green
                                        : Colors.redAccent),
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),

                  const SizedBox(height: 20),

                  // Chart
                  SizedBox(
                    height: 220,
                    child: points.length < 2
                        ? const Center(
                            child: Text(
                              'Add another entry to see your trend line',
                              style: TextStyle(
                                color: Colors.grey,
                                fontSize: 13,
                              ),
                            ),
                          )
                        : LineChart(
                            LineChartData(
                              gridData: const FlGridData(show: false),
                              titlesData: FlTitlesData(
                                leftTitles: const AxisTitles(
                                  sideTitles: SideTitles(showTitles: false),
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
                                    reservedSize: 24,
                                    interval: (rangeData.length / 4)
                                        .clamp(1, rangeData.length)
                                        .toDouble(),
                                    getTitlesWidget: (value, meta) {
                                      final idx = value.toInt();
                                      if (idx < 0 || idx >= rangeData.length)
                                        return const SizedBox.shrink();
                                      final date = DateTime.parse(
                                        rangeData[idx]['recorded_at'],
                                      );
                                      return Padding(
                                        padding: const EdgeInsets.only(
                                          top: 6,
                                        ),
                                        child: Text(
                                          DateFormat('MMM d').format(date),
                                          style: const TextStyle(
                                            color: Colors.grey,
                                            fontSize: 10,
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
                                  barWidth: 3,
                                  dotData: const FlDotData(show: true),
                                  belowBarData: BarAreaData(
                                    show: true,
                                    gradient: LinearGradient(
                                      colors: [
                                        AppColors.gold.withOpacity(0.25),
                                        Colors.transparent,
                                      ],
                                      begin: Alignment.topCenter,
                                      end: Alignment.bottomCenter,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                  ),

                  const SizedBox(height: 16),

                  // Range selector chips
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: ranges.map((r) {
                      final selected = r == selectedRange;
                      return GestureDetector(
                        onTap: () => setState(() => selectedRange = r),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color:
                                selected ? AppColors.gold : Colors.transparent,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            r,
                            style: TextStyle(
                              color: selected ? Colors.black : Colors.grey,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),

                  const SizedBox(height: 28),
                  const Divider(color: Colors.white12),
                  const SizedBox(height: 12),

                  Text(
                    'ALL ENTRIES',
                    style: TextStyle(
                      color: AppColors.gold,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1,
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Reversed (latest first) simple log list below chart
                  ...allHistory.reversed.toList().asMap().entries.map((entry) {
                    final log = entry.value;
                    final date = DateFormat(
                      'MMM d, yyyy',
                    ).format(DateTime.parse(log['recorded_at']));
                    final value = log[selectedMetric];
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            date,
                            style: const TextStyle(
                              color: Colors.grey,
                              fontSize: 13,
                            ),
                          ),
                          Text(
                            value != null
                                ? '$value ${metricMeta['unit']}'
                                : '--',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                ],
              );

    if (widget.embedded) return body;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Body Progress'),
        actions: [
          Tooltip(
            message: _addMeasurementBlockReason ?? 'Add new measurement',
            child: IconButton(
              icon: Icon(
                Icons.add,
                color: _canAddMeasurement ? Colors.white : Colors.grey,
              ),
              onPressed: _canAddMeasurement ? openNewEntryForm : null,
            ),
          ),
        ],
      ),
      body: body,
    );
  }
}

// Body Guide Card - REMOVED Male/Female toggle
class _BodyGuideCard extends StatelessWidget {
  const _BodyGuideCard();

  final guidePoints = const [
    '1. Chest / Bust — measure around the fullest part',
    '2. Left / Right Arm — measure around the bicep, flexed',
    '3. Abdomen — measure around the navel',
    '4. Waist — measure at the narrowest point',
    '5. Hips — measure around the fullest part',
    '6. Left / Right Thigh — measure around the fullest part',
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.cardDark,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'HOW TO MEASURE',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 16),
          Center(
            child: Icon(
              Icons.accessibility_new,
              size: 90,
              color: AppColors.gold.withOpacity(0.8),
            ),
          ),
          const SizedBox(height: 12),
          ...guidePoints.map(
            (p) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Text(
                p,
                style: const TextStyle(color: Colors.grey, fontSize: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
