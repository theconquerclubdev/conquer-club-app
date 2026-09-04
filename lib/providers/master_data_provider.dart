import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
// import 'package:realtime_client/realtime_client.dart';

// ============================================================
// DATA MODELS
// ============================================================

/// Represents all data for a member's dashboard
class MemberDashboardData {
  final String memberId;
  final int currentStreak;
  final int todaySteps;
  final int stepGoal;
  final double? currentWeight;
  final double? heightCm;
  final int daysLeft;
  final bool isMembershipActive;
  final Map<String, dynamic>? profile;
  final Map<String, dynamic>? measurements;
  final List<Map<String, dynamic>> measurementHistory;
  final Map<String, dynamic>? progressPhotos;
  final Map<String, dynamic>? tasksToday;
  final Map<String, dynamic>? latestDiet;
  final Map<String, dynamic>? latestWorkout;
  final DateTime? fetchedAt;

  const MemberDashboardData({
    required this.memberId,
    required this.currentStreak,
    required this.todaySteps,
    required this.stepGoal,
    required this.daysLeft,
    required this.isMembershipActive,
    this.currentWeight,
    this.heightCm,
    this.profile,
    this.measurements,
    this.measurementHistory = const [],
    this.progressPhotos,
    this.tasksToday,
    this.latestDiet,
    this.latestWorkout,
    this.fetchedAt,
  });

  factory MemberDashboardData.fromJson(
    String memberId,
    Map<String, dynamic> json,
  ) {
    final profileMap = json['profile'] as Map<String, dynamic>?;
    final tasksMap = json['tasks_today'] as Map<String, dynamic>?;

    // Get membership values from RPC response
    final daysLeft = (json['days_left'] as num?)?.toInt() ?? -1;
    final isMembershipActive = json['is_membership_active'] == true;

    // Ensure profile has membership fields for backward compatibility
    if (profileMap != null) {
      profileMap['days_left'] = daysLeft;
      profileMap['is_membership_active'] = isMembershipActive;
    }

    return MemberDashboardData(
      memberId: memberId,
      currentStreak: (json['current_streak'] as num?)?.toInt() ?? 0,
      todaySteps: (json['today_steps'] as num?)?.toInt() ?? 0,
      stepGoal: (json['step_goal'] as num?)?.toInt() ?? 10000,
      daysLeft: daysLeft,
      isMembershipActive: isMembershipActive,
      profile: profileMap,
      measurements: json['measurements'] as Map<String, dynamic>?,
      measurementHistory: List<Map<String, dynamic>>.from(
        json['measurement_history'] ?? [],
      ),
      progressPhotos: json['progress_photos'] as Map<String, dynamic>?,
      tasksToday: tasksMap,
      latestDiet: json['latest_diet'] as Map<String, dynamic>?,
      latestWorkout: json['latest_workout_plan'] as Map<String, dynamic>?,
      fetchedAt: DateTime.now(),
    );
  }

  bool isFresh() {
    if (fetchedAt == null) return false;
    return DateTime.now().difference(fetchedAt!) < const Duration(seconds: 30);
  }

  // Common Field Getters
  String get fullName => profile?['full_name'] ?? 'Member';
  String get email => profile?['email'] ?? '';

  // Task Status Getters
  bool get workoutCompletedToday => tasksToday?['workout_completed'] == true;
  bool get measurementUpdatedToday =>
      tasksToday?['measurement_updated'] == true;
  bool get photosUpdatedToday =>
      tasksToday?['after_front_updated_at'] != null &&
      tasksToday?['after_back_updated_at'] != null;
  bool get photoFrontUpdated => tasksToday?['after_front_updated_at'] != null;
  bool get photoBackUpdated => tasksToday?['after_back_updated_at'] != null;

  // 5 Member Types Category
  String get memberTypeCategory =>
      (profile?['member_type_category'] as String?) ?? 'signup_member';

  // True only for Active Member + Active Membership. Supabase RLS blocks
  // step/workout/measurement/photo writes when this is false.
  bool get canCollectData =>
      isMembershipActive && (profile?['is_active'] == true);
}

// ============================================================
// MASTER DATA PROVIDER
// ============================================================

class MasterDataProvider extends ChangeNotifier {
  static final MasterDataProvider _instance = MasterDataProvider._internal();
  factory MasterDataProvider() => _instance;
  static MasterDataProvider get instance => _instance;

  MasterDataProvider._internal() {
    _initRealtimeSubscription();
  }

  final Map<String, MemberDashboardData> _cache = {};
  final Map<String, DateTime> _cacheTimestamps = {};
  final Map<String, Future<MemberDashboardData>> _inFlight = {};
  final Map<String, bool> _loadingStates = {};
  final Map<String, String?> _errorStates = {};
  RealtimeChannel? _profilesChannel;
  RealtimeChannel? _paymentsChannel;

  void _initRealtimeSubscription() {
    // Realtime temporarily disabled - will re-enable after Flutter SDK upgrade
    // The app still works perfectly with 30-second cache + refresh on app open
    return;
  }

  void _handleProfileChange(Map<String, dynamic> payload) {
    final newRecord = payload['new'] as Map<String, dynamic>?;
    if (newRecord == null) return;

    final memberId = newRecord['id'] as String?;
    if (memberId == null) return;

    // Refresh this member's data
    _refreshMemberOnChange(memberId);
  }

  void _handlePaymentChange(Map<String, dynamic> payload) {
    final newRecord = payload['new'] as Map<String, dynamic>?;
    if (newRecord == null) return;

    final memberId = newRecord['member_id'] as String?;
    if (memberId == null) return;

    // Refresh this member's data (membership status may have changed)
    _refreshMemberOnChange(memberId);
  }

  void _refreshMemberOnChange(String memberId) {
    // Only refresh if we have this member cached
    if (_cache.containsKey(memberId)) {
      // Invalidate cache
      _cache.remove(memberId);
      _cacheTimestamps.remove(memberId);

      // Refresh in background
      fetchMemberData(memberId, force: true).catchError((e) {
        debugPrint('❌ Background refresh failed for $memberId: $e');
      });

      notifyListeners();
    }
  }

  void dispose() {
    // _profilesChannel?.unsubscribe();
    // _paymentsChannel?.unsubscribe();
    super.dispose();
  }

  MemberDashboardData? getData(String memberId) => _cache[memberId];
  bool isLoading(String memberId) => _loadingStates[memberId] ?? false;
  String? getError(String memberId) => _errorStates[memberId];
  bool isCached(String memberId) => _cache.containsKey(memberId);
  bool isFresh(String memberId) => _cache[memberId]?.isFresh() ?? false;

  Future<MemberDashboardData> fetchMemberData(
    String memberId, {
    bool force = false,
    bool skipCache = false,
  }) async {
    if (_inFlight.containsKey(memberId)) {
      return _inFlight[memberId]!;
    }

    if (!force && !skipCache && _cache.containsKey(memberId)) {
      final data = _cache[memberId]!;
      if (data.isFresh()) {
        return data;
      }
    }

    _loadingStates[memberId] = true;
    _errorStates[memberId] = null;
    notifyListeners();

    final future = _fetchFromSupabase(memberId);
    _inFlight[memberId] = future;

    try {
      final data = await future;
      // ✅ Check if membership status changed and notify
      final cachedData = _cache[memberId];
      if (cachedData != null &&
          cachedData.isMembershipActive != data.isMembershipActive) {
        debugPrint(
            '🔄 Membership status changed for $memberId: ${cachedData.isMembershipActive} -> ${data.isMembershipActive}');
        notifyListeners();
      }
      return data;
    } catch (e) {
      _errorStates[memberId] = e.toString();
      rethrow;
    } finally {
      _inFlight.remove(memberId);
      _loadingStates[memberId] = false;
      notifyListeners();
    }
  }

  Future<MemberDashboardData> _fetchFromSupabase(String memberId) async {
    try {
      // Ensure memberId is a valid UUID format
      final uuidRegex = RegExp(
        r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
        caseSensitive: false,
      );
      if (!uuidRegex.hasMatch(memberId)) {
        throw Exception('Invalid UUID format for member ID: $memberId');
      }

      // Fetch profile directly
      final profile = await Supabase.instance.client
          .from('profiles')
          .select('*')
          .eq('id', memberId)
          .maybeSingle();

      if (profile == null) {
        debugPrint('⚠️ Profile not found for member: $memberId');
        final fallback = MemberDashboardData(
          memberId: memberId,
          currentStreak: 0,
          todaySteps: 0,
          stepGoal: 10000,
          daysLeft: -1,
          isMembershipActive: false,
          profile: {
            'id': memberId,
            'full_name': 'Unknown',
            'email': '',
            'is_active': true,
            'days_left': -1,
            'is_membership_active': false,
            'membership_end_date': null,
          },
          fetchedAt: DateTime.now(),
        );
        _cache[memberId] = fallback;
        _cacheTimestamps[memberId] = DateTime.now();
        return fallback;
      }

      // Fetch streak history and calculate streak
      int currentStreak = 0;
      int highestStreak = 0;

      final streakResponse = await Supabase.instance.client
          .from('member_streaks')
          .select('date, is_streak_met')
          .eq('member_id', memberId)
          .order('date', ascending: false)
          .limit(90);

      if (streakResponse.isNotEmpty) {
        final history = List<Map<String, dynamic>>.from(streakResponse);

        // Calculate current streak using IST date
        final nowUtc = DateTime.now().toUtc();
        final today = nowUtc.add(const Duration(hours: 5, minutes: 30));
        final todayStr =
            '${today.year.toString().padLeft(4, '0')}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';

        // Check today's streak
        bool todayStreakMet = false;
        for (final record in history) {
          if (record['date'] == todayStr) {
            todayStreakMet = record['is_streak_met'] as bool;
            break;
          }
        }

        if (todayStreakMet) {
          currentStreak = 1;
          DateTime checkDate = today.subtract(const Duration(days: 1));
          while (true) {
            final dateStr =
                '${checkDate.year}-${checkDate.month.toString().padLeft(2, '0')}-${checkDate.day.toString().padLeft(2, '0')}';
            bool found = false;
            for (final record in history) {
              if (record['date'] == dateStr) {
                if (record['is_streak_met'] as bool) {
                  currentStreak++;
                  checkDate = checkDate.subtract(const Duration(days: 1));
                  found = true;
                }
                break;
              }
            }
            if (!found) break;
          }
        } else {
          // Check yesterday
          final yesterday = today.subtract(const Duration(days: 1));
          final yesterdayStr =
              '${yesterday.year}-${yesterday.month.toString().padLeft(2, '0')}-${yesterday.day.toString().padLeft(2, '0')}';
          bool yesterdayStreakMet = false;
          for (final record in history) {
            if (record['date'] == yesterdayStr) {
              yesterdayStreakMet = record['is_streak_met'] as bool;
              break;
            }
          }
          if (yesterdayStreakMet) {
            currentStreak = 1;
            DateTime checkDate = yesterday.subtract(const Duration(days: 1));
            while (true) {
              final dateStr =
                  '${checkDate.year}-${checkDate.month.toString().padLeft(2, '0')}-${checkDate.day.toString().padLeft(2, '0')}';
              bool found = false;
              for (final record in history) {
                if (record['date'] == dateStr) {
                  if (record['is_streak_met'] as bool) {
                    currentStreak++;
                    checkDate = checkDate.subtract(const Duration(days: 1));
                    found = true;
                  }
                  break;
                }
              }
              if (!found) break;
            }
          }
        }

        // Calculate highest streak
        final sortedHistory = List<Map<String, dynamic>>.from(history)
          ..sort(
              (a, b) => (a['date'] as String).compareTo(b['date'] as String));

        int running = 0;
        for (final record in sortedHistory) {
          if (record['is_streak_met'] as bool) {
            running++;
            if (running > highestStreak) {
              highestStreak = running;
            }
          } else {
            running = 0;
          }
        }
      }

      // Fetch other data using IST date
      final nowUtc = DateTime.now().toUtc();
      final today = nowUtc.add(const Duration(hours: 5, minutes: 30));
      final todayStr =
          '${today.year.toString().padLeft(4, '0')}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';

      final stepLog = await Supabase.instance.client
          .from('step_logs')
          .select('steps')
          .eq('member_id', memberId)
          .eq('log_date', todayStr)
          .maybeSingle();

      final todaySteps = (stepLog?['steps'] as num?)?.toInt() ?? 0;
      final stepGoal = (profile?['step_goal'] as num?)?.toInt() ?? 10000;

      // Calculate days left
      int daysLeft = -1;
      bool isMembershipActive = false;
      if (profile != null && profile['membership_end_date'] != null) {
        try {
          final endDate = DateTime.parse(profile['membership_end_date']);
          final now = DateTime.now();
          daysLeft = endDate.difference(now).inDays;
          isMembershipActive = daysLeft >= 0;
        } catch (_) {}
      }

      // Fetch measurements
      final measurements = await Supabase.instance.client
          .from('measurement_logs')
          .select('*')
          .eq('member_id', memberId)
          .order('recorded_at', ascending: false)
          .limit(1)
          .maybeSingle();

      final measurementHistory = await Supabase.instance.client
          .from('measurement_logs')
          .select('*')
          .eq('member_id', memberId)
          .order('recorded_at', ascending: false);

      // Fetch workout status for today using IST boundaries
      // Convert IST midnight to UTC for querying timestamptz columns
      final startOfDay = DateTime.utc(today.year, today.month, today.day)
          .subtract(const Duration(hours: 5, minutes: 30));
      final endOfDay = startOfDay.add(const Duration(days: 1));

      final workoutSession = await Supabase.instance.client
          .from('workout_sessions')
          .select('status')
          .eq('member_id', memberId)
          .eq('status', 'completed')
          .gte('started_at', startOfDay.toIso8601String())
          .lt('started_at', endOfDay.toIso8601String())
          .maybeSingle();

      final dashboardData = MemberDashboardData(
        memberId: memberId,
        currentStreak: currentStreak,
        todaySteps: todaySteps,
        stepGoal: stepGoal,
        daysLeft: daysLeft,
        isMembershipActive: isMembershipActive,
        currentWeight: (measurements?['weight_kg'] as num?)?.toDouble(),
        heightCm: (profile?['height_cm'] as num?)?.toDouble(),
        profile: profile,
        measurements: measurements,
        measurementHistory: List<Map<String, dynamic>>.from(measurementHistory),
        progressPhotos: null,
        tasksToday: {
          'workout_completed': workoutSession != null,
          'after_front_updated_at': null,
          'after_back_updated_at': null,
        },
        latestDiet: null,
        latestWorkout: null,
        fetchedAt: DateTime.now(),
      );

      _cache[memberId] = dashboardData;
      _cacheTimestamps[memberId] = DateTime.now();
      pruneCache();

      return dashboardData;
    } catch (e) {
      debugPrint(
          '❌ Error in _fetchFromSupabase: $e'); // If cache exists, return it
      if (_cache.containsKey(memberId)) {
        debugPrint('📦 Returning cached data for: $memberId');
        return _cache[memberId]!;
      }

      // Return a fallback with expired membership
      final fallback = MemberDashboardData(
        memberId: memberId,
        currentStreak: 0,
        todaySteps: 0,
        stepGoal: 10000,
        daysLeft: -1,
        isMembershipActive: false,
        profile: {
          'id': memberId,
          'full_name': 'Unknown',
          'email': '',
          'is_active': true,
          'days_left': -1,
          'is_membership_active': false,
        },
        fetchedAt: DateTime.now(),
      );
      _cache[memberId] = fallback;
      _cacheTimestamps[memberId] = DateTime.now();
      return fallback;
    }
  }

  void invalidateCache(String memberId) {
    _cache.remove(memberId);
    _cacheTimestamps.remove(memberId);
    _errorStates.remove(memberId);
    notifyListeners();
  }

  void invalidateAllCache() {
    _cache.clear();
    _cacheTimestamps.clear();
    _errorStates.clear();
    notifyListeners();
  }

  Future<MemberDashboardData> refreshMember(String memberId) async {
    invalidateCache(memberId);
    return fetchMemberData(memberId, force: true);
  }

  void pruneCache({int maxEntries = 50}) {
    if (_cache.length <= maxEntries) return;

    final sortedKeys = _cacheTimestamps.keys.toList()
      ..sort((a, b) => _cacheTimestamps[a]!.compareTo(_cacheTimestamps[b]!));

    final toRemove = sortedKeys.sublist(0, _cache.length - maxEntries);
    for (final key in toRemove) {
      _cache.remove(key);
      _cacheTimestamps.remove(key);
      _errorStates.remove(key);
    }
  }

  Future<int> getStreak(String memberId, {bool force = false}) async {
    final data = await fetchMemberData(memberId, force: force);
    return data.currentStreak;
  }

  Future<int> getSteps(String memberId, {bool force = false}) async {
    final data = await fetchMemberData(memberId, force: force);
    return data.todaySteps;
  }

  Future<Map<String, dynamic>> getTasks(String memberId,
      {bool force = false}) async {
    final data = await fetchMemberData(memberId, force: force);
    return data.tasksToday ?? {};
  }

  Future<Map<String, dynamic>> getProfile(String memberId,
      {bool force = false}) async {
    final data = await fetchMemberData(memberId, force: force);
    return data.profile ?? {};
  }

  bool get hasCacheData => _cache.isNotEmpty;
  int get cacheSize => _cache.length;
  List<String> get cachedMemberIds => _cache.keys.toList();

  // Debug method to check membership status
  void debugMembership(String memberId) {
    final data = _cache[memberId];
    if (data == null) {
      debugPrint('🔍 No cached data for member: $memberId');
      return;
    }
    debugPrint('🔍 Member: ${data.fullName}');
    debugPrint('🔍 Days Left: ${data.daysLeft}');
    debugPrint('🔍 Is Active: ${data.isMembershipActive}');
    debugPrint('🔍 End Date: ${data.profile?['membership_end_date']}');
  }
}

extension MasterDataProviderExtension on BuildContext {
  MasterDataProvider get masterData => MasterDataProvider.instance;
  MemberDashboardData? watchMemberData(String memberId) =>
      MasterDataProvider.instance.getData(memberId);
  void invalidateMemberCache(String memberId) =>
      MasterDataProvider.instance.invalidateCache(memberId);
  Future<MemberDashboardData> refreshMemberData(String memberId) =>
      MasterDataProvider.instance.refreshMember(memberId);
}
