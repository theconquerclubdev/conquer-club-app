import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pedometer/pedometer.dart';
import 'package:health/health.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'step_task_handler.dart';
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
    return DateTime.now().difference(fetchedAt!) < const Duration(minutes: 3);
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

  StreamSubscription<AuthState>? _authStateSub;

  MasterDataProvider._internal() {
    // ✅ One deterministic lifecycle for every auth change: always tear
    // down whatever channels/cache exist first, then rebuild only what
    // the CURRENT user/role needs. Fixes a gap where logging out (or
    // switching role on the same device) could leave a previous
    // member's filtered channels and cached data still active.
    _authStateSub = Supabase.instance.client.auth.onAuthStateChange.listen((_) {
      _refineRealtimeForCurrentUser();
    });
    _refineRealtimeForCurrentUser();
  }

  Future<void> _refineRealtimeForCurrentUser() async {
    try {
      // Always start from a clean slate so logout/role-switch never
      // leaves a stale subscription or another user's cached data behind.
      await _profilesChannel?.unsubscribe();
      await _paymentsChannel?.unsubscribe();
      await _dietsChannel?.unsubscribe();
      await _workoutsChannel?.unsubscribe();
      await _measurementsChannel?.unsubscribe();
      invalidateAllCache();

      final uid = Supabase.instance.client.auth.currentUser?.id;
      if (uid == null) {
        // Logged out — no channels, no cache. Done.
        return;
      }
      final profile = await Supabase.instance.client
          .from('profiles')
          .select('role')
          .eq('id', uid)
          .maybeSingle();
      if (profile?['role'] != 'member') {
        // Coach/admin/head_coach — restore the original global channels
        // (they need visibility across members, not just their own row).
        _initRealtimeSubscription();
        return;
      }

      await _profilesChannel?.unsubscribe();
      _profilesChannel = Supabase.instance.client
          .channel('public:profiles:$uid')
          .onPostgresChanges(
            event: PostgresChangeEvent.update,
            schema: 'public',
            table: 'profiles',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'id',
              value: uid,
            ),
            callback: (payload) => _handleProfileChange(payload.newRecord),
          )
          .subscribe();

      await _paymentsChannel?.unsubscribe();
      _paymentsChannel = Supabase.instance.client
          .channel('public:payments:$uid')
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'payments',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'member_id',
              value: uid,
            ),
            callback: (payload) => _handlePaymentChange(payload.newRecord),
          )
          .subscribe();

      await _dietsChannel?.unsubscribe();
      _dietsChannel = Supabase.instance.client
          .channel('public:diets:$uid')
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'diets',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'member_id',
              value: uid,
            ),
            callback: (payload) => _handleMemberTableChange(payload.newRecord),
          )
          .subscribe();

      await _workoutsChannel?.unsubscribe();
      _workoutsChannel = Supabase.instance.client
          .channel('public:workouts:$uid')
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'workouts',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'member_id',
              value: uid,
            ),
            callback: (payload) => _handleMemberTableChange(payload.newRecord),
          )
          .subscribe();

      await _measurementsChannel?.unsubscribe();
      _measurementsChannel = Supabase.instance.client
          .channel('public:measurement_logs:$uid')
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'measurement_logs',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'member_id',
              value: uid,
            ),
            callback: (payload) => _handleMemberTableChange(payload.newRecord),
          )
          .subscribe();
    } catch (e) {
      debugPrint(
        '⚠️ Realtime refine failed, falling back to global channels: $e',
      );
      _initRealtimeSubscription();
    }
  }

  final Map<String, MemberDashboardData> _cache = {};
  final Map<String, DateTime> _cacheTimestamps = {};
  final Map<String, Future<MemberDashboardData>> _inFlight = {};
  final Map<String, bool> _loadingStates = {};
  final Map<String, String?> _errorStates = {};
  RealtimeChannel? _profilesChannel;
  RealtimeChannel? _paymentsChannel;
  RealtimeChannel? _dietsChannel;
  RealtimeChannel? _workoutsChannel;
  RealtimeChannel? _measurementsChannel;

  void _initRealtimeSubscription() {
    final client = Supabase.instance.client;

    _profilesChannel = client
        .channel('public:profiles')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'profiles',
          callback: (payload) => _handleProfileChange(payload.newRecord),
        )
        .subscribe();

    _paymentsChannel = client
        .channel('public:payments')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'payments',
          callback: (payload) => _handlePaymentChange(payload.newRecord),
        )
        .subscribe();

    _dietsChannel = client
        .channel('public:diets')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'diets',
          callback: (payload) => _handleMemberTableChange(payload.newRecord),
        )
        .subscribe();

    _workoutsChannel = client
        .channel('public:workouts')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'workouts',
          callback: (payload) => _handleMemberTableChange(payload.newRecord),
        )
        .subscribe();

    _measurementsChannel = client
        .channel('public:measurement_logs')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'measurement_logs',
          callback: (payload) => _handleMemberTableChange(payload.newRecord),
        )
        .subscribe();
  }

  void _handleProfileChange(Map<String, dynamic> newRecord) {
    final memberId = newRecord['id'] as String?;
    if (memberId == null) return;

    // Refresh this member's data
    _refreshMemberOnChange(memberId);
  }

  void _handlePaymentChange(Map<String, dynamic> newRecord) {
    final memberId = newRecord['member_id'] as String?;
    if (memberId == null) return;

    // Refresh this member's data (membership status may have changed)
    _refreshMemberOnChange(memberId);
  }

  void _handleMemberTableChange(Map<String, dynamic> newRecord) {
    final memberId = newRecord['member_id'] as String?;
    if (memberId == null) return;

    // Diet / workout / measurement changed — refresh this member's cache
    // so any screen watching MasterDataProvider updates within seconds.
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
    _authStateSub?.cancel();
    _profilesChannel?.unsubscribe();
    _paymentsChannel?.unsubscribe();
    _dietsChannel?.unsubscribe();
    _workoutsChannel?.unsubscribe();
    _measurementsChannel?.unsubscribe();
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
          '🔄 Membership status changed for $memberId: ${cachedData.isMembershipActive} -> ${data.isMembershipActive}',
        );
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

      // 🚀 Fetch profile and streak in parallel instead of one-after-another —
      // they don't depend on each other, so this cuts one full round trip.
      final profileFuture = Supabase.instance.client
          .from('profiles')
          .select(
            'id, full_name, email, is_active, membership_end_date, step_goal, height_cm, weight_kg, created_at, assigned_coach_id, goal, date_of_birth, gender',
          )
          .eq('id', memberId)
          .maybeSingle();
      final streakRpcFuture = Supabase.instance.client.rpc(
        'get_current_streak',
        params: {'p_member_id': memberId},
      );

      final profileAndStreak = await Future.wait<dynamic>([
        profileFuture,
        streakRpcFuture,
      ]);
      final profile = profileAndStreak[0] as Map<String, dynamic>?;
      final streakRpcResponse = profileAndStreak[1];

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

      // Fetch current streak from the single source-of-truth RPC — computes
      // live off workout_sessions / measurement_logs / member_progress_photos.
      // No member_streaks table read, no client-side recalculation.
      int currentStreak = 0;

      if (streakRpcResponse != null) {
        currentStreak =
            (streakRpcResponse['current_streak'] as num?)?.toInt() ?? 0;
      }
      // Fetch other data using IST date
      final nowUtc = DateTime.now().toUtc();
      final today = nowUtc.add(const Duration(hours: 5, minutes: 30));
      final todayStr =
          '${today.year.toString().padLeft(4, '0')}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';

      // Calculate days left using IST "today" (the same Asia/Kolkata date the
      // streak RPC uses) instead of the device's local DateTime.now().
      int daysLeft = -1;
      bool isMembershipActive = false;
      if (profile != null && profile['membership_end_date'] != null) {
        try {
          final endDate = DateTime.parse(profile['membership_end_date']);
          daysLeft = endDate.difference(today).inDays;
          isMembershipActive = daysLeft >= 0;
        } catch (_) {}
      }

      // ✅ Everything below is wrapped so that if ANY of these queries fail,
      // it can NEVER wipe out the currentStreak we already fetched above.
      int todaySteps = 0;
      final stepGoal = (profile?['step_goal'] as num?)?.toInt() ?? 10000;
      Map<String, dynamic>? measurements;
      List<Map<String, dynamic>> measurementHistory = [];
      bool workoutCompletedToday = false;
      Map<String, dynamic>? latestDiet;
      Map<String, dynamic>? latestWorkout;
      String? photoFrontUpdatedAt;
      String? photoBackUpdatedAt;

      try {
        // Fetch workout status for today using IST boundaries
        // Convert IST midnight to UTC for querying timestamptz columns
        final startOfDay = DateTime.utc(
          today.year,
          today.month,
          today.day,
        ).subtract(const Duration(hours: 5, minutes: 30));
        final endOfDay = startOfDay.add(const Duration(days: 1));

        // 🚀 Single RPC round trip instead of 7 separate REST calls —
        // same data, ~85% fewer requests per dashboard load.
        final extra = await Supabase.instance.client.rpc(
          'get_member_dashboard_extra',
          params: {'p_member_id': memberId},
        ) as Map<String, dynamic>;

        todaySteps = (extra['today_steps'] as num?)?.toInt() ?? 0;

        measurements = extra['latest_measurement'] as Map<String, dynamic>?;

        measurementHistory = List<Map<String, dynamic>>.from(
          (extra['measurement_history'] as List?) ?? const [],
        );

        workoutCompletedToday = extra['workout_completed_today'] == true;

        // Fetch latest diet so coach's "diet needs update" check has real data.
        latestDiet = extra['latest_diet'] as Map<String, dynamic>?;

        // Fetch latest workout the same way, so the member-side popup can
        // detect a new/updated workout plan too.
        latestWorkout = extra['latest_workout'] as Map<String, dynamic>?;

        // Fetch today's photo-upload timestamps (IST-bounded) for Sunday task card.
        final photoFrontRaw = extra['photo_front_updated_at'] as String?;
        final photoBackRaw = extra['photo_back_updated_at'] as String?;

        if (photoFrontRaw != null) {
          final frontDate = DateTime.tryParse(photoFrontRaw);
          if (frontDate != null &&
              !frontDate.isBefore(startOfDay) &&
              frontDate.isBefore(endOfDay)) {
            photoFrontUpdatedAt = photoFrontRaw;
          }
        }
        if (photoBackRaw != null) {
          final backDate = DateTime.tryParse(photoBackRaw);
          if (backDate != null &&
              !backDate.isBefore(startOfDay) &&
              backDate.isBefore(endOfDay)) {
            photoBackUpdatedAt = photoBackRaw;
          }
        }
      } catch (e) {
        debugPrint(
          '⚠️ Non-streak data fetch failed for $memberId (streak kept intact): $e',
        );
      }

      final dashboardData = MemberDashboardData(
        memberId: memberId,
        currentStreak: currentStreak,
        todaySteps:
            todaySteps > MasterDataProvider.instance.getLocalTodaySteps()
                ? todaySteps
                : MasterDataProvider.instance.getLocalTodaySteps(),
        stepGoal: stepGoal,
        daysLeft: daysLeft,
        isMembershipActive: isMembershipActive,
        currentWeight: (measurements?['weight_kg'] as num?)?.toDouble(),
        heightCm: (profile?['height_cm'] as num?)?.toDouble(),
        profile: profile,
        measurements: measurements,
        measurementHistory: measurementHistory,
        progressPhotos: null,
        tasksToday: {
          'workout_completed': workoutCompletedToday,
          'after_front_updated_at': photoFrontUpdatedAt,
          'after_back_updated_at': photoBackUpdatedAt,
        },
        latestDiet: latestDiet,
        latestWorkout: latestWorkout,
        fetchedAt: DateTime.now(),
      );

      _cache[memberId] = dashboardData;
      _cacheTimestamps[memberId] = DateTime.now();
      pruneCache();

      return dashboardData;
    } catch (e) {
      debugPrint(
        '❌ Error in _fetchFromSupabase: $e',
      ); // If cache exists, return it
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

  /// Pure math for cache pruning, pulled out so it can be tested directly
  /// without needing a real MasterDataProvider/Supabase instance.
  static List<String> keysToPrune(
      List<String> sortedKeys, int entryCount, int maxEntries) {
    final removeCount =
        (sortedKeys.length - maxEntries).clamp(0, sortedKeys.length);
    return sortedKeys.sublist(0, removeCount);
  }

  void pruneCache({int maxEntries = 50}) {
    if (_cache.length <= maxEntries) return;

    final sortedKeys = _cacheTimestamps.keys.toList()
      ..sort(
        (a, b) => _cacheTimestamps[a]!.compareTo(_cacheTimestamps[b]!),
      );

    final toRemove = keysToPrune(sortedKeys, _cache.length, maxEntries);
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

  Future<Map<String, dynamic>> getTasks(
    String memberId, {
    bool force = false,
  }) async {
    final data = await fetchMemberData(memberId, force: force);
    return data.tasksToday ?? {};
  }

  Future<Map<String, dynamic>> getProfile(
    String memberId, {
    bool force = false,
  }) async {
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
    debugPrint('🔍 Days Left: ${data.daysLeft}');
    debugPrint('🔍 Is Active: ${data.isMembershipActive}');
    debugPrint('🔍 End Date: ${data.profile?['membership_end_date']}');
  }

  // ============================================================
  // OFFLINE-FIRST STEP TRACKING — single source of truth, app-wide.
  // No background service, no persistent notification (by design —
  // keeps the app light and avoids unnecessary battery/review flags).
  // Health Connect / HealthKit is primary (works even when app is
  // closed, OS tracks it). Raw sensor is fallback (works only while
  // app is open). Everything syncs in ONE batched request, capped to
  // 30 rolling days or membership end — whichever comes first.
  // ============================================================
  static const _pendingStepsKey = 'pending_step_days_v1';
  static const _stepSyncWindowDays = 30;

  Map<String, int> _localSteps = {}; // dateKey -> steps, unsynced only
  bool _stepEngineStarted = false;
  bool _usingHealthSource = false;
  StreamSubscription<StepCount>? _pedometerSub;
  Timer? _healthPollTimer;
  Timer? _stepSyncTimer;
  int? _pedoBaseline;
  String? _pedoBaselineDate;
  DateTime? _membershipEndDate;

  String _todayKeyIst() {
    final now =
        DateTime.now().toUtc().add(const Duration(hours: 5, minutes: 30));
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }

  /// Instant, no-network read — call this for the UI, never shows a blank 0.
  int getLocalTodaySteps() => _localSteps[_todayKeyIst()] ?? 0;

  bool get usingHealthSource => _usingHealthSource;

  /// Call once per app session (member_home_screen initState). Safe to call
  /// repeatedly — does nothing after the first successful start.
  Future<void> initStepTracking() async {
    if (kIsWeb || _stepEngineStarted) return;
    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (uid == null) return;
    final data = _cache[uid];
    if (data != null && !data.isMembershipActive)
      return; // inactive membership — skip
    if (data?.profile?['membership_end_date'] != null) {
      _membershipEndDate =
          DateTime.tryParse(data!.profile!['membership_end_date'].toString());
    }
    _stepEngineStarted = true;
    await _loadLocalSteps();
    _pruneExpiredLocal(); // keep phone storage minimal — drop anything already outside the window
    await _startHealthSource();
    _stepSyncTimer?.cancel();
    _stepSyncTimer =
        Timer.periodic(const Duration(minutes: 20), (_) => syncPendingSteps());
    syncPendingSteps(); // catch up immediately too — covers offline days since last open
  }

  Future<void> _loadLocalSteps() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_pendingStepsKey);
    if (raw == null) return;
    try {
      final map = Map<String, dynamic>.from(jsonDecode(raw));
      _localSteps = map.map((k, v) => MapEntry(k, (v as num).toInt()));
    } catch (_) {
      _localSteps = {};
    }
  }

  Future<void> _saveLocalSteps() async {
    final prefs = await SharedPreferences.getInstance();
    if (_localSteps.isEmpty) {
      await prefs.remove(
          _pendingStepsKey); // nothing pending — don't even keep an empty key
    } else {
      await prefs.setString(_pendingStepsKey, jsonEncode(_localSteps));
    }
  }

  /// Drops anything already outside the 30-day/membership window before it
  /// ever gets synced — keeps local storage to only what's actually usable.
  void _pruneExpiredLocal() {
    final today =
        DateTime.now().toUtc().add(const Duration(hours: 5, minutes: 30));
    final earliest = today.subtract(const Duration(days: _stepSyncWindowDays));
    final cap = _membershipEndDate;
    _localSteps.removeWhere((key, _) {
      final p = key.split('-');
      final d = DateTime.utc(int.parse(p[0]), int.parse(p[1]), int.parse(p[2]));
      return d.isBefore(
              DateTime.utc(earliest.year, earliest.month, earliest.day)) ||
          (cap != null && d.isAfter(cap));
    });
  }

  /// Never lowers a day's count (guards against a sensor reboot dip).
  Future<void> _recordSteps(String dateKey, int steps) async {
    final existing = _localSteps[dateKey] ?? 0;
    if (steps <= existing) return;
    _localSteps[dateKey] = steps;
    await _saveLocalSteps();
    notifyListeners(); // any open screen redraws instantly, no network wait
  }

  Future<void> _startHealthSource() async {
    try {
      final health = Health();
      await health.configure();
      const types = [HealthDataType.STEPS];
      const perms = [HealthDataAccess.READ];
      final has =
          await health.hasPermissions(types, permissions: perms) ?? false;
      final granted =
          has || await health.requestAuthorization(types, permissions: perms);
      if (!granted) {
        _usingHealthSource = false;
        await _startPedometerFallback(); // keeps app-open UI live too
        await _startAndroidBackgroundStepService(); // + counts all day, app closed or not
        return;
      }
      _usingHealthSource = true;
      await _pollHealthSteps();
      _healthPollTimer?.cancel();
      // 60s is plenty — Health Connect/HealthKit themselves only update every
      // few minutes internally, polling faster wastes battery for no gain.
      _healthPollTimer = Timer.periodic(
          const Duration(seconds: 60), (_) => _pollHealthSteps());
    } catch (_) {
      _usingHealthSource = false;
      await _startPedometerFallback();
    }
  }

  Future<void> _pollHealthSteps() async {
    try {
      final nowUtc = DateTime.now().toUtc();
      final now = nowUtc.add(const Duration(hours: 5, minutes: 30));
      final istMidnightUtc = DateTime.utc(now.year, now.month, now.day)
          .subtract(const Duration(hours: 5, minutes: 30));
      final steps =
          await Health().getTotalStepsInInterval(istMidnightUtc, nowUtc) ?? 0;
      await _recordSteps(_todayKeyIst(), steps);
    } catch (_) {
      if (_usingHealthSource) {
        _usingHealthSource = false;
        _healthPollTimer?.cancel();
        await _startPedometerFallback(); // Health hiccup — fall back live, don't show 0
      }
    }
  }

  Future<void> _startPedometerFallback() async {
    await _pedometerSub?.cancel();
    _pedometerSub = Pedometer.stepCountStream.listen((event) async {
      final todayKey = _todayKeyIst();
      final prefs = await SharedPreferences.getInstance();
      if (_pedoBaselineDate != todayKey) {
        final storedDate = prefs.getString('pedo_baseline_date');
        final storedBase = prefs.getInt('pedo_baseline_value');
        _pedoBaseline = (storedDate == todayKey &&
                storedBase != null &&
                event.steps >= storedBase)
            ? storedBase
            : event.steps;
        _pedoBaselineDate = todayKey;
        await prefs.setString('pedo_baseline_date', todayKey);
        await prefs.setInt('pedo_baseline_value', _pedoBaseline!);
      }
      final delta =
          (event.steps - (_pedoBaseline ?? event.steps)).clamp(0, 1000000);
      await _recordSteps(todayKey, delta);
    }, onError: (_) {});
  }

  /// Android-only: keeps counting steps all day even with the app fully
  /// closed, for phones without Health Connect. iOS never needs this —
  /// Apple Health is always present. Only starts when Plan A (Health) fails.
  Future<void> _startAndroidBackgroundStepService() async {
    if (kIsWeb) return;
    try {
      FlutterForegroundTask.init(
        androidNotificationOptions: AndroidNotificationOptions(
          channelId: 'step_tracking_channel',
          channelName: 'Step Tracking',
          channelDescription: 'Keeps counting your steps in the background.',
          priority: NotificationPriority.LOW,
        ),
        iosNotificationOptions: const IOSNotificationOptions(),
        foregroundTaskOptions: ForegroundTaskOptions(
          eventAction: ForegroundTaskEventAction.repeat(60000),
          autoRunOnBoot: true,
          allowWakeLock: true,
        ),
      );
      await FlutterForegroundTask.startService(
        notificationTitle: 'Conquer Club',
        notificationText: 'Tracking your steps',
        callback: startCallback,
      );
    } catch (_) {
      // Service failed to start — Plan B (foreground-only pedometer) still works.
    }
  }

  /// One batched request for everything pending — this is what keeps
  /// Supabase usage low no matter how often steps change locally.
  Future<void> syncPendingSteps() async {
    if (_localSteps.isEmpty) return;
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;

    _pruneExpiredLocal();
    if (_localSteps.isEmpty) {
      await _saveLocalSteps();
      return;
    }

    final toSync = _localSteps.entries
        .map((e) => {
              'member_id': userId,
              'log_date': e.key,
              'steps': e.value,
              'updated_at': DateTime.now().toUtc().toIso8601String(),
            })
        .toList();

    try {
      await Supabase.instance.client
          .from('step_logs')
          .upsert(toSync, onConflict: 'member_id,log_date');
      _localSteps
          .clear(); // confirmed saved server-side — clear local, storage stays minimal
      await _saveLocalSteps();
    } catch (e) {
      debugPrint('⚠️ Step sync deferred, will retry next tick: $e');
      // Offline/error — keep everything local exactly as-is, nothing lost.
    }
  }

  void disposeStepTracking() {
    _pedometerSub?.cancel();
    _healthPollTimer?.cancel();
    _stepSyncTimer?.cancel();
    _stepEngineStarted = false;
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

@pragma('vm:entry-point')
void startCallback() {
  FlutterForegroundTask.setTaskHandler(StepTaskHandler());
}
