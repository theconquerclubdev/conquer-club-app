import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../theme/app_theme.dart';

enum _StepView { day, week, month }

class StepCounterScreen extends StatefulWidget {
  final int liveTodaySteps;
  final int initialGoal;
  final DateTime signupDate;
  const StepCounterScreen({
    super.key,
    required this.liveTodaySteps,
    required this.initialGoal,
    required this.signupDate,
  });

  @override
  State<StepCounterScreen> createState() => _StepCounterScreenState();
}

class _StepCounterScreenState extends State<StepCounterScreen> {
  _StepView view = _StepView.day;
  late int stepGoal;
  bool isLoading = true;
  Map<String, int> dailySteps = {};
  Map<String, int> dailyGoals = {};
  DateTime today = DateTime.now();
  late DateTime monthCursor;
  late DateTime signupMonth;
  DateTime? _loadedStart;

  // ✅ Week view state - renamed to avoid conflict with getter
  late DateTime _weekStartDate;

  @override
  void initState() {
    super.initState();
    stepGoal = widget.initialGoal;
    monthCursor = DateTime(today.year, today.month, 1);
    signupMonth = DateTime(widget.signupDate.year, widget.signupDate.month, 1);
    _weekStartDate = today.subtract(Duration(days: today.weekday % 7));
    _loadHistory();
  }

  String _fmt(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> _loadHistory() async {
    setState(() => isLoading = true);
    final yearBack = DateTime(today.year - 1, today.month, today.day);
    final start = yearBack.isBefore(signupMonth) ? signupMonth : yearBack;
    await _fetchRange(start);
    if (mounted) setState(() => isLoading = false);
  }

  Future<void> _fetchRange(DateTime start) async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;
    try {
      final rows = await Supabase.instance.client
          .from('step_logs')
          .select('log_date, steps, goal')
          .eq('member_id', userId)
          .gte('log_date', _fmt(start));
      final map = Map<String, int>.from(dailySteps);
      final goalMap = Map<String, int>.from(dailyGoals);
      for (final r in List<Map<String, dynamic>>.from(rows)) {
        final key = r['log_date'].toString().substring(0, 10);
        map[key] = (r['steps'] as num?)?.toInt() ?? 0;
        final g = (r['goal'] as num?)?.toInt();
        if (g != null) goalMap[key] = g;
      }
      final todayKey = _fmt(today);
      if (widget.liveTodaySteps > (map[todayKey] ?? 0)) {
        map[todayKey] = widget.liveTodaySteps;
        // ✅ Save today's steps to database when viewing step counter
        try {
          await Supabase.instance.client.from('step_logs').upsert({
            'member_id': userId,
            'log_date': todayKey,
            'steps': widget.liveTodaySteps,
            'updated_at': DateTime.now().toIso8601String(),
          }, onConflict: 'member_id,log_date');
          print('✅ StepCounterScreen: Saved $widget.liveTodaySteps steps');
        } catch (e) {
          print('❌ StepCounterScreen: Failed to save steps: $e');
        }
      }
      if (mounted) {
        setState(() {
          dailySteps = map;
          dailyGoals = goalMap;
          if (_loadedStart == null || start.isBefore(_loadedStart!)) {
            _loadedStart = start;
          }
        });
      }
    } catch (_) {}
  }

  Future<void> _ensureLoadedThrough(DateTime neededStart) async {
    if (_loadedStart == null || neededStart.isBefore(_loadedStart!)) {
      await _fetchRange(neededStart);
    }
  }

  bool get _atCurrentMonth =>
      monthCursor.year == today.year && monthCursor.month == today.month;

  bool get _atSignupMonth =>
      monthCursor.year == signupMonth.year &&
      monthCursor.month == signupMonth.month;

  Future<void> _changeMonth(int delta) async {
    final target = DateTime(monthCursor.year, monthCursor.month + delta, 1);
    if (target.isAfter(DateTime(today.year, today.month, 1))) return;
    if (target.isBefore(signupMonth)) return;
    setState(() => monthCursor = target);
    final wanted = DateTime(target.year - 1, target.month, 1);
    await _ensureLoadedThrough(
        wanted.isBefore(signupMonth) ? signupMonth : wanted);
  }

  Future<void> _selectMonth(DateTime target) async {
    var clamped = target.isAfter(DateTime(today.year, today.month, 1))
        ? DateTime(today.year, today.month, 1)
        : DateTime(target.year, target.month, 1);
    if (clamped.isBefore(signupMonth)) clamped = signupMonth;
    setState(() => monthCursor = clamped);
    final wanted = DateTime(clamped.year - 1, clamped.month, 1);
    await _ensureLoadedThrough(
        wanted.isBefore(signupMonth) ? signupMonth : wanted);
  }

  Future<void> _pickMonthYear() async {
    var pickYear = monthCursor.year;
    const monthNames = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec'
    ];
    final result = await showDialog<DateTime>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: AppColors.cardDark,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          contentPadding: const EdgeInsets.fromLTRB(12, 16, 12, 8),
          title: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                icon: const Icon(Icons.chevron_left, color: AppColors.gold),
                onPressed: pickYear <= signupMonth.year
                    ? null
                    : () => setDialogState(() => pickYear--),
              ),
              Text('$pickYear',
                  style: const TextStyle(color: Colors.white, fontSize: 16)),
              IconButton(
                icon: const Icon(Icons.chevron_right, color: AppColors.gold),
                onPressed: pickYear >= today.year
                    ? null
                    : () => setDialogState(() => pickYear++),
              ),
            ],
          ),
          content: SizedBox(
            width: MediaQuery.sizeOf(context).width < 360
                ? MediaQuery.sizeOf(context).width - 88
                : 260,
            child: GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: 12,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                childAspectRatio: 1.8,
              ),
              itemBuilder: (context, i) {
                final isFuture = DateTime(pickYear, i + 1, 1)
                    .isAfter(DateTime(today.year, today.month, 1));
                final isBeforeSignup =
                    DateTime(pickYear, i + 1, 1).isBefore(signupMonth);
                final isDisabled = isFuture || isBeforeSignup;
                final isSelected =
                    pickYear == monthCursor.year && i + 1 == monthCursor.month;
                return GestureDetector(
                  onTap: isDisabled
                      ? null
                      : () =>
                          Navigator.pop(context, DateTime(pickYear, i + 1, 1)),
                  child: Container(
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: isSelected
                          ? AppColors.gold
                          : Colors.white.withOpacity(0.05),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      monthNames[i],
                      style: TextStyle(
                        color: isDisabled
                            ? Colors.grey.shade700
                            : isSelected
                                ? Colors.black
                                : Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 12.5,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
    if (result != null) await _selectMonth(result);
  }

  int stepsOn(DateTime d) => dailySteps[_fmt(d)] ?? 0;

  // ✅ Per-day goal: use that day's stored goal if we have one (once the
  // write side starts saving it), else fall back to current profile target.
  int goalOn(DateTime d) => dailyGoals[_fmt(d)] ?? stepGoal;

  // ✅ Achieved = steps met or exceeded that day's goal.
  bool isAchieved(DateTime d) {
    final g = goalOn(d);
    return g > 0 && stepsOn(d) >= g;
  }

  // ============================================================
  // ✅ SHOW DAY STATS POPUP - When tapping on a date in month view
  // ============================================================
  void _showDayStats(DateTime date) {
    final steps = stepsOn(date);
    if (steps == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No steps recorded for this day')),
      );
      return;
    }

    final kcal = (steps * 0.04).round();
    final km = (steps * 0.000762);
    final mins = (steps / 100).round();
    final achieved = isAchieved(date);
    final dayGoal = goalOn(date);

    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.cardDark,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => Container(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade600,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              DateFormat('EEEE, MMM d, yyyy').format(date),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              achieved
                  ? '✅ Goal achieved ($steps / $dayGoal)'
                  : '$steps / $dayGoal steps',
              style: TextStyle(
                color: achieved ? Colors.green : Colors.grey,
                fontSize: 12.5,
                fontWeight: achieved ? FontWeight.bold : FontWeight.normal,
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                _buildStatCard('👟', '$steps', 'Steps', AppColors.gold),
                _buildStatCard('🔥', '$kcal', 'Calories', Colors.orange),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                _buildStatCard(
                    '📏', '${km.toStringAsFixed(1)}', 'km', Colors.blue),
                _buildStatCard('⏱️', '$mins', 'mins', Colors.green),
              ],
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('CLOSE'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatCard(String icon, String value, String label, Color color) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 4),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withOpacity(0.2)),
        ),
        child: Column(
          children: [
            Text(icon, style: const TextStyle(fontSize: 20)),
            const SizedBox(height: 4),
            Text(
              value,
              style: TextStyle(
                color: color,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              label,
              style: const TextStyle(
                color: Colors.grey,
                fontSize: 10,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _editTarget() async {
    final controller = TextEditingController(text: stepGoal.toString());
    final result = await showDialog<int>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.cardDark,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: const Text('Daily Step Target',
            style: TextStyle(color: Colors.white, fontSize: 17)),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          style: const TextStyle(color: Colors.white, fontSize: 18),
          decoration: InputDecoration(
            hintText: 'e.g. 10000',
            hintStyle: TextStyle(color: Colors.grey.shade600),
            suffixText: 'steps',
            suffixStyle: const TextStyle(color: Colors.grey),
            enabledBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: AppColors.gold.withOpacity(0.3)),
            ),
            focusedBorder: const UnderlineInputBorder(
              borderSide: BorderSide(color: AppColors.gold),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () =>
                Navigator.pop(context, int.tryParse(controller.text.trim())),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (result != null && result > 0 && mounted) {
      setState(() => stepGoal = result);
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId != null) {
        try {
          await Supabase.instance.client
              .from('profiles')
              .update({'step_goal': result}).eq('id', userId);
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Target save failed: $e')),
            );
          }
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        title: const Text('Step Counter',
            style: TextStyle(color: Colors.white, fontSize: 17)),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: const Icon(Icons.flag_outlined, color: AppColors.gold),
            tooltip: 'Set target',
            onPressed: _editTarget,
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: isLoading
            ? const Center(
                child: CircularProgressIndicator(color: AppColors.gold))
            : Column(
                children: [
                  _buildViewToggle(),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
                      child: Column(
                        children: [
                          if (view == _StepView.day) _buildDayView(),
                          if (view == _StepView.week) _buildWeekView(),
                          if (view == _StepView.month) _buildMonthView(),
                          const SizedBox(height: 18),
                          _buildStatsRow(),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  // ---- D / W / M toggle ----
  Widget _buildViewToggle() {
    Widget seg(String label, _StepView v) {
      final selected = view == v;
      return Expanded(
        child: GestureDetector(
          onTap: () => setState(() => view = v),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            margin: const EdgeInsets.symmetric(horizontal: 2),
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: selected ? AppColors.gold : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
            ),
            alignment: Alignment.center,
            child: Text(
              label,
              style: TextStyle(
                color: selected ? Colors.black : Colors.grey,
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.cardDark,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          seg('Day', _StepView.day),
          seg('Week', _StepView.week),
          seg('Month', _StepView.month),
        ],
      ),
    );
  }

  // ---- DAY: circular ring ----
  Widget _buildDayView() {
    final steps = stepsOn(today);
    final todayGoal = goalOn(today);
    final progress = (steps / todayGoal).clamp(0.0, 1.0);
    final achieved = isAchieved(today);
    return Column(
      children: [
        const SizedBox(height: 8),
        SizedBox(
          width: 220,
          height: 220,
          child: Stack(
            alignment: Alignment.center,
            children: [
              SizedBox(
                width: 220,
                height: 220,
                child: CircularProgressIndicator(
                  value: 1,
                  strokeWidth: 14,
                  color: Colors.white.withOpacity(0.06),
                ),
              ),
              SizedBox(
                width: 220,
                height: 220,
                child: CircularProgressIndicator(
                  value: progress,
                  strokeWidth: 14,
                  backgroundColor: Colors.transparent,
                  valueColor:
                      const AlwaysStoppedAnimation<Color>(AppColors.gold),
                  strokeCap: StrokeCap.round,
                ),
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Today',
                      style: TextStyle(color: AppColors.gold, fontSize: 15)),
                  const SizedBox(height: 6),
                  Text(
                    '$steps',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 40,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  Text(
                    'of $todayGoal steps',
                    style: const TextStyle(color: Colors.grey, fontSize: 12.5),
                  ),
                  if (achieved) ...[
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.green.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(20),
                        border:
                            Border.all(color: Colors.green.withOpacity(0.4)),
                      ),
                      child: const Text(
                        '✅ Achieved',
                        style: TextStyle(
                          color: Colors.green,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ---- WEEK: bars per day, Sun-Sat with swipe and labels ----
  Widget _buildWeekView() {
    final weekDays =
        List.generate(7, (i) => _weekStartDate.add(Duration(days: i)));
    final weekTotal = weekDays.fold<int>(0, (sum, d) => sum + stepsOn(d));
    const labels = ['S', 'M', 'T', 'W', 'T', 'F', 'S'];

    // Check if we can go forward
    final canGoForward =
        _weekStartDate.add(const Duration(days: 7)).isBefore(today) ||
            _weekStartDate.add(const Duration(days: 7)).isAtSameMomentAs(today);

    return GestureDetector(
      onHorizontalDragEnd: (details) {
        final velocity = details.primaryVelocity ?? 0;
        if (velocity < -200) {
          // Swipe left → Next week
          final nextWeek = _weekStartDate.add(const Duration(days: 7));
          if (nextWeek.isBefore(today) || nextWeek.isAtSameMomentAs(today)) {
            setState(() {
              _weekStartDate = nextWeek;
            });
          }
        } else if (velocity > 200) {
          // Swipe right → Previous week
          setState(() {
            _weekStartDate = _weekStartDate.subtract(const Duration(days: 7));
          });
        }
      },
      child: Column(
        children: [
          // Week navigation header
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                icon: const Icon(Icons.chevron_left, color: AppColors.gold),
                onPressed: () {
                  setState(() {
                    _weekStartDate =
                        _weekStartDate.subtract(const Duration(days: 7));
                  });
                },
                padding: const EdgeInsets.all(4),
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              ),
              Text(
                '${DateFormat('MMM d').format(weekDays.first)} - ${DateFormat('MMM d, yyyy').format(weekDays.last)}',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
              IconButton(
                icon: Icon(
                  Icons.chevron_right,
                  color: canGoForward ? AppColors.gold : Colors.grey.shade700,
                ),
                onPressed: canGoForward
                    ? () {
                        setState(() {
                          _weekStartDate =
                              _weekStartDate.add(const Duration(days: 7));
                        });
                      }
                    : null,
                padding: const EdgeInsets.all(4),
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '$weekTotal steps this week',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 200,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: List.generate(7, (i) {
                final d = weekDays[i];
                final steps = stepsOn(d);
                final ratio = (steps / stepGoal).clamp(0.0, 1.0);
                final isToday = _fmt(d) == _fmt(today);
                final isFuture = d.isAfter(today);

                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        // ✅ Data Label (Step count on top of bar)
                        if (steps > 0)
                          Text(
                            '$steps',
                            style: TextStyle(
                              color: isFuture
                                  ? Colors.grey.shade600
                                  : Colors.grey.shade400,
                              fontSize: 8,
                              fontWeight: FontWeight.w500,
                            ),
                          )
                        else
                          const SizedBox(height: 12),
                        // Bar
                        Expanded(
                          child: Align(
                            alignment: Alignment.bottomCenter,
                            child: FractionallySizedBox(
                              heightFactor: isFuture
                                  ? 0.02
                                  : (ratio == 0
                                      ? 0.02
                                      : ratio.clamp(0.01, 1.0)),
                              child: Container(
                                decoration: BoxDecoration(
                                  color: isFuture
                                      ? Colors.white.withOpacity(0.05)
                                      : AppColors.gold
                                          .withOpacity(isToday ? 1 : 0.5),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        // Day label
                        Container(
                          width: 26,
                          height: 26,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: isToday
                                ? AppColors.gold
                                : Colors.white.withOpacity(0.06),
                          ),
                          child: Text(
                            labels[i],
                            style: TextStyle(
                              color: isToday ? Colors.black : Colors.grey,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }),
            ),
          ),
        ],
      ),
    );
  }

  // ---- MONTH: calendar grid (swipeable) + trailing 12-month trend ----
  Widget _buildMonthView() {
    final daysInMonth =
        DateTime(monthCursor.year, monthCursor.month + 1, 0).day;
    final leadingBlanks = monthCursor.weekday % 7;
    final monthTotal = List.generate(
      daysInMonth,
      (i) => stepsOn(DateTime(monthCursor.year, monthCursor.month, i + 1)),
    ).fold<int>(0, (a, b) => a + b);

    const labels = ['S', 'M', 'T', 'W', 'T', 'F', 'S'];
    const monthNames = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec'
    ];

    return GestureDetector(
      onHorizontalDragEnd: (details) {
        final v = details.primaryVelocity ?? 0;
        if (v < -200) {
          _changeMonth(1);
        } else if (v > 200) {
          _changeMonth(-1);
        }
      },
      child: Column(
        children: [
          Text(
            '$monthTotal steps',
            style: const TextStyle(
                color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                icon: const Icon(Icons.chevron_left,
                    color: AppColors.gold, size: 20),
                onPressed: _atSignupMonth ? null : () => _changeMonth(-1),
              ),
              GestureDetector(
                onTap: _pickMonthYear,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.cardDark,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.gold.withOpacity(0.25)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '${monthNames[monthCursor.month - 1]} ${monthCursor.year}',
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(width: 4),
                      const Icon(Icons.calendar_month,
                          color: AppColors.gold, size: 13),
                    ],
                  ),
                ),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                icon: Icon(Icons.chevron_right,
                    size: 20,
                    color: _atCurrentMonth
                        ? Colors.grey.shade800
                        : AppColors.gold),
                onPressed: _atCurrentMonth ? null : () => _changeMonth(1),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: labels
                .map((l) => Expanded(
                      child: Center(
                        child: Text(l,
                            style: const TextStyle(
                                color: Colors.grey,
                                fontSize: 10.5,
                                fontWeight: FontWeight.bold)),
                      ),
                    ))
                .toList(),
          ),
          const SizedBox(height: 4),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: leadingBlanks + daysInMonth,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              mainAxisSpacing: 4,
              crossAxisSpacing: 4,
            ),
            itemBuilder: (context, index) {
              if (index < leadingBlanks) return const SizedBox.shrink();
              final day = index - leadingBlanks + 1;
              final date = DateTime(monthCursor.year, monthCursor.month, day);
              final steps = stepsOn(date);
              final ratio = (steps / stepGoal).clamp(0.0, 1.0);
              final isToday = _fmt(date) == _fmt(today);
              final isFuture = date.isAfter(today);

              return GestureDetector(
                onTap: () => _showDayStats(date),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    SizedBox(
                      width: 28,
                      height: 28,
                      child: CircularProgressIndicator(
                        value: isFuture ? 0 : (ratio == 0 ? 1 : ratio),
                        strokeWidth: 2.5,
                        backgroundColor: Colors.white.withOpacity(0.08),
                        valueColor: AlwaysStoppedAnimation<Color>(
                          ratio == 0 || isFuture
                              ? Colors.white.withOpacity(0.08)
                              : AppColors.gold,
                        ),
                      ),
                    ),
                    Container(
                      width: 21,
                      height: 21,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: isToday ? AppColors.gold : Colors.transparent,
                      ),
                      child: Text(
                        '$day',
                        style: TextStyle(
                          color: isToday ? Colors.black : Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: 18),
          _buildYearlyTrendChart(),
        ],
      ),
    );
  }

  // ---- Compact bar chart: total steps per month, trailing 12 months ----
  Widget _buildYearlyTrendChart() {
    const monthNames = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec'
    ];
    final months = List.generate(12, (i) {
      final m = DateTime(monthCursor.year, monthCursor.month - 11 + i, 1);
      final daysIn = DateTime(m.year, m.month + 1, 0).day;
      final total = List.generate(
        daysIn,
        (d) => stepsOn(DateTime(m.year, m.month, d + 1)),
      ).fold<int>(0, (a, b) => a + b);
      return MapEntry(m, total);
    });
    final maxVal =
        months.map((e) => e.value).fold<int>(1, (a, b) => a > b ? a : b);

    return Container(
      padding: const EdgeInsets.fromLTRB(10, 12, 10, 8),
      decoration: BoxDecoration(
        color: AppColors.cardDark,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Yearly trend',
              style: TextStyle(
                  color: Colors.grey,
                  fontSize: 11,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          SizedBox(
            height: 72,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: months.map((e) {
                final ratio = maxVal == 0 ? 0.0 : e.value / maxVal;
                final isCurrent = e.key.year == monthCursor.year &&
                    e.key.month == monthCursor.month;
                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 1.5),
                    child: FractionallySizedBox(
                      heightFactor: ratio < 0.03 ? 0.03 : ratio,
                      alignment: Alignment.bottomCenter,
                      child: Container(
                        decoration: BoxDecoration(
                          color:
                              AppColors.gold.withOpacity(isCurrent ? 1 : 0.45),
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 4),
          Row(
            children: months.asMap().entries.map((entry) {
              final show = entry.key.isEven;
              return Expanded(
                child: Center(
                  child: Text(
                    show ? monthNames[entry.value.key.month - 1] : '',
                    style: const TextStyle(color: Colors.grey, fontSize: 8.5),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  // ---- Stats row: kcal / distance / active mins ----
  Widget _buildStatsRow() {
    int steps;
    if (view == _StepView.day) {
      steps = stepsOn(today);
    } else if (view == _StepView.week) {
      final start = _weekStartDate;
      steps = List.generate(7, (i) => start.add(Duration(days: i)))
          .fold<int>(0, (sum, d) => sum + stepsOn(d));
    } else {
      final daysInMonth =
          DateTime(monthCursor.year, monthCursor.month + 1, 0).day;
      steps = List.generate(
        daysInMonth,
        (i) => stepsOn(DateTime(monthCursor.year, monthCursor.month, i + 1)),
      ).fold<int>(0, (a, b) => a + b);
    }

    final kcal = (steps * 0.04).round();
    final km = (steps * 0.000762);
    final mins = (steps / 100).round();

    Widget stat(String value, String label) => Expanded(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 4),
            padding: const EdgeInsets.symmetric(vertical: 14),
            decoration: BoxDecoration(
              color: AppColors.cardDark,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white.withOpacity(0.05)),
            ),
            child: Column(
              children: [
                Text(value,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.bold)),
                const SizedBox(height: 2),
                Text(label,
                    style: const TextStyle(color: Colors.grey, fontSize: 11)),
              ],
            ),
          ),
        );

    return Row(
      children: [
        stat('$kcal', 'kcal'),
        stat(km.toStringAsFixed(1), 'km'),
        stat('$mins', 'mins'),
      ],
    );
  }
}
