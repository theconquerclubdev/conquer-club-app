// lib/screens/member/workout_progress_screen.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../theme/app_theme.dart';

class WorkoutProgressScreen extends StatefulWidget {
  // Optional: pass this when a coach/admin is viewing a specific
  // member's progress. If omitted, defaults to the logged-in user
  // (unchanged behaviour for the member's own "My Progress" screen).
  final String? memberId;

  const WorkoutProgressScreen({super.key, this.memberId});

  @override
  State<WorkoutProgressScreen> createState() => _WorkoutProgressScreenState();
}

class _WorkoutProgressScreenState extends State<WorkoutProgressScreen> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _strengthRecords = [];
  String? _errorMessage;

  // ✅ Exercise mapping for Strength Records (Optimized)
  // Simplified to only Barbell exercises for faster loading
  final List<Map<String, dynamic>> _trackedExercises = [
    {
      'displayName': 'Barbell Squats',
      'dbNames': [
        {'name': 'Barbell Squats', 'tag': 'BB'},
      ],
    },
    {
      'displayName': 'Flat Barbell Press',
      'dbNames': [
        {'name': 'Flat Barbell Press', 'tag': 'BB'},
      ],
    },
    {
      'displayName': 'Barbell Shoulder Press',
      'dbNames': [
        {'name': 'Barbell Shoulder Press', 'tag': 'BB'},
      ],
    },
    {
      'displayName': 'Barbell Deadlift',
      'dbNames': [
        {'name': 'Barbell Deadlift', 'tag': 'BB'},
      ],
    },
  ];

  bool _isLoadingRecords = false;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    // ✅ Guard against overlapping calls
    if (_isLoadingRecords) return;
    _isLoadingRecords = true;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final userId =
          widget.memberId ?? Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) {
        if (mounted) {
          setState(() {
            _isLoading = false;
            _errorMessage = 'Please login to view progress';
          });
        }
        _isLoadingRecords = false;
        return;
      }
      final records = await _getStrengthRecords(userId);
      if (mounted) {
        setState(() {
          _strengthRecords = records;
          _isLoading = false;
        });
      }
    } catch (e) {
      print('Error loading strength records: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = e.toString();
        });
      }
    } finally {
      _isLoadingRecords = false;
    }
  }

  Future<List<Map<String, dynamic>>> _getStrengthRecords(String userId) async {
    final List<Map<String, dynamic>> records = [];

    // Flatten every tracked exercise's db name variants (today there's
    // exactly one variant per exercise, but this keeps working if more
    // are added later) and remember which displayName + tag each name
    // belongs to.
    final dbNameToDisplayName = <String, String>{};
    final dbNameToTag = <String, String>{};
    final allDbNames = <String>[];
    for (final config in _trackedExercises) {
      final displayName = config['displayName'] as String;
      final dbNames = config['dbNames'] as List<Map<String, String>>;
      for (final variant in dbNames) {
        final name = variant['name']!;
        allDbNames.add(name);
        dbNameToDisplayName[name] = displayName;
        dbNameToTag[name] = variant['tag']!;
      }
    }

    // ✅ Single RPC call — server aggregates and filters by this member
    // only, instead of pulling every member's logged sets to the client.
    final result = await Supabase.instance.client.rpc(
      'get_member_strength_records',
      params: {
        'p_member_id': userId,
        'p_exercise_names': allDbNames,
      },
    );

    final rows = List<Map<String, dynamic>>.from(result as List);

    // Group rows back by displayName, since a displayName can (in
    // theory) map to more than one db exercise name/variant.
    final rowsByDisplayName = <String, List<Map<String, dynamic>>>{};
    for (final row in rows) {
      if (row['has_data'] != true) continue;
      final dbName = row['exercise_name'] as String;
      final displayName = dbNameToDisplayName[dbName];
      if (displayName == null) continue;
      rowsByDisplayName.putIfAbsent(displayName, () => []).add(row);
    }

    for (final config in _trackedExercises) {
      final displayName = config['displayName'] as String;
      final variantRows = rowsByDisplayName[displayName];

      if (variantRows == null || variantRows.isEmpty) {
        records.add(_emptyRecord(displayName));
        continue;
      }

      // Pick the variant with the most recent lastDate, and the
      // variant with the highest highestKg/highestReps — same
      // "best across variants" behaviour as before.
      Map<String, dynamic> latestRow = variantRows.first;
      Map<String, dynamic> bestRow = variantRows.first;
      for (final row in variantRows) {
        final rowLastDate = DateTime.tryParse(row['last_date'] as String? ?? '');
        final latestDate =
            DateTime.tryParse(latestRow['last_date'] as String? ?? '');
        if (rowLastDate != null &&
            (latestDate == null || rowLastDate.isAfter(latestDate))) {
          latestRow = row;
        }

        final rowKg = (row['highest_kg'] as num?)?.toDouble() ?? 0;
        final rowReps = (row['highest_reps'] as num?)?.toInt() ?? 0;
        final bestKg = (bestRow['highest_kg'] as num?)?.toDouble() ?? 0;
        final bestReps = (bestRow['highest_reps'] as num?)?.toInt() ?? 0;
        if (rowKg > bestKg || (rowKg == bestKg && rowReps > bestReps)) {
          bestRow = row;
        }
      }

      records.add({
        'displayName': displayName,
        'hasData': true,
        'lastDate': DateTime.tryParse(latestRow['last_date'] as String),
        'lastKg': (latestRow['last_kg'] as num?)?.toDouble(),
        'lastReps': (latestRow['last_reps'] as num?)?.toInt(),
        'lastTag': dbNameToTag[latestRow['exercise_name']] ?? '',
        'highestDate': DateTime.tryParse(bestRow['highest_date'] as String),
        'highestKg': (bestRow['highest_kg'] as num?)?.toDouble(),
        'highestReps': (bestRow['highest_reps'] as num?)?.toInt(),
        'highestTag': dbNameToTag[bestRow['exercise_name']] ?? '',
      });
    }

    return records;
  }


  Map<String, dynamic> _emptyRecord(String displayName) {
    return {
      'displayName': displayName,
      'hasData': false,
      'lastDate': null,
      'lastKg': null,
      'lastReps': null,
      'lastTag': null,
      'highestDate': null,
      'highestKg': null,
      'highestReps': null,
      'highestTag': null,
    };
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          'Strength Records',
          style: TextStyle(
            color: Colors.white,
            fontSize: 22,
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: AppColors.gold),
            onPressed: _loadData,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.gold),
            )
          : _errorMessage != null
              ? _buildErrorView()
              : RefreshIndicator(
                  onRefresh: _loadData,
                  color: AppColors.gold,
                  backgroundColor: AppColors.cardDark,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: _buildStrengthRecordsTable(),
                  ),
                ),
    );
  }

  Widget _buildErrorView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.error_outline,
            color: Colors.grey.shade600,
            size: 64,
          ),
          const SizedBox(height: 16),
          Text(
            'Something went wrong',
            style: TextStyle(
              color: Colors.grey.shade500,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              _errorMessage ?? 'Unable to load strength records',
              style: TextStyle(
                color: Colors.grey.shade400,
                fontSize: 14,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: _loadData,
            child: const Text('RETRY'),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // Strength Records Table
  // ============================================================
  Widget _buildStrengthRecordsTable() {
    final hasData = _strengthRecords.any((r) => r['hasData'] == true);

    if (!hasData) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.fitness_center_outlined,
              color: Colors.grey.shade600,
              size: 64,
            ),
            const SizedBox(height: 16),
            Text(
              'No strength records yet',
              style: TextStyle(
                color: Colors.grey.shade500,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Complete workouts to track your best lifts! 💪',
              style: TextStyle(
                color: Colors.grey.shade400,
                fontSize: 14,
              ),
            ),
          ],
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final tableWidth =
            constraints.maxWidth < 560 ? 560.0 : constraints.maxWidth;

        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          physics: constraints.maxWidth < 560
              ? const AlwaysScrollableScrollPhysics()
              : const NeverScrollableScrollPhysics(),
          child: SizedBox(
            width: tableWidth,
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.cardDark,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: Colors.white.withOpacity(0.06),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Table Header
                  Container(
                    padding:
                        const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
                    decoration: BoxDecoration(
                      color: AppColors.gold.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 90,
                          child: Text(
                            'Exercise',
                            style: TextStyle(
                              color: AppColors.gold,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        Expanded(
                          flex: 1,
                          child: Text(
                            'Last Date',
                            style: TextStyle(
                              color: AppColors.gold,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                        Expanded(
                          flex: 1,
                          child: Text(
                            'Last (kg×reps)',
                            style: TextStyle(
                              color: AppColors.gold,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                        Expanded(
                          flex: 1,
                          child: Text(
                            'Best Date',
                            style: TextStyle(
                              color: AppColors.gold,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                        Expanded(
                          flex: 1,
                          child: Text(
                            'Best (kg×reps)',
                            style: TextStyle(
                              color: AppColors.gold,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  ..._strengthRecords.map((record) {
                    final hasData = record['hasData'] == true;
                    final isFlatBench = false;

                    // Safe date formatting - FIXED: handle null dates
                    String formatDate(dynamic date) {
                      if (date == null) return '-';
                      if (date is DateTime) {
                        return DateFormat('dd/MM/yy').format(date);
                      }
                      return '-';
                    }

                    return Container(
                      padding: const EdgeInsets.symmetric(
                          vertical: 8, horizontal: 8),
                      decoration: BoxDecoration(
                        border: Border(
                          bottom: BorderSide(
                            color: Colors.white.withOpacity(0.05),
                          ),
                        ),
                      ),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 90,
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    record['displayName'],
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: hasData
                                          ? Colors.white
                                          : Colors.grey.shade500,
                                      fontSize: 12,
                                      fontWeight: hasData
                                          ? FontWeight.w600
                                          : FontWeight.normal,
                                    ),
                                  ),
                                ),
                                if (isFlatBench && hasData)
                                  Container(
                                    margin: const EdgeInsets.only(left: 4),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 3,
                                      vertical: 1,
                                    ),
                                    decoration: BoxDecoration(
                                      color: AppColors.gold.withOpacity(0.2),
                                      borderRadius: BorderRadius.circular(3),
                                    ),
                                    child: Text(
                                      '🏆',
                                      style: TextStyle(
                                        fontSize: 8,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          Expanded(
                            flex: 1,
                            child: Text(
                              hasData ? formatDate(record['lastDate']) : '-',
                              style: TextStyle(
                                color: hasData
                                    ? Colors.white70
                                    : Colors.grey.shade500,
                                fontSize: 11,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                          Expanded(
                            flex: 1,
                            child: Text(
                              hasData
                                  ? '${record['lastKg']}×${record['lastReps']}'
                                      '${record['lastTag'] != null && record['lastTag'] != '' ? ' ${record['lastTag']}' : ''}'
                                  : '-',
                              style: TextStyle(
                                color: hasData
                                    ? Colors.white
                                    : Colors.grey.shade500,
                                fontSize: 11,
                                fontWeight: hasData
                                    ? FontWeight.w500
                                    : FontWeight.normal,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                          Expanded(
                            flex: 1,
                            child: Text(
                              hasData ? formatDate(record['highestDate']) : '-',
                              style: TextStyle(
                                color: hasData
                                    ? Colors.white70
                                    : Colors.grey.shade500,
                                fontSize: 11,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                          Expanded(
                            flex: 1,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  hasData
                                      ? '${record['highestKg']}×${record['highestReps']}'
                                          '${record['highestTag'] != null && record['highestTag'] != '' ? ' ${record['highestTag']}' : ''}'
                                      : '-',
                                  style: TextStyle(
                                    color: hasData
                                        ? AppColors.gold
                                        : Colors.grey.shade500,
                                    fontSize: 12,
                                    fontWeight: hasData
                                        ? FontWeight.bold
                                        : FontWeight.normal,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                                if (hasData && isFlatBench)
                                  Container(
                                    margin: const EdgeInsets.only(left: 4),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 4,
                                      vertical: 1,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.green.withOpacity(0.2),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      'BEST',
                                      style: TextStyle(
                                        color: Colors.green,
                                        fontSize: 7,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                  // Note for best lift
                  if (_strengthRecords.any((r) =>
                      r['displayName'] == 'Barbell Deadlift' &&
                      r['hasData'] == true))
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        '💪 Track your best Barbell lifts here',
                        style: TextStyle(
                          color: Colors.grey.shade500,
                          fontSize: 10,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
