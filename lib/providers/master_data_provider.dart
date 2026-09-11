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

  MasterDataProvider._internal() {
    _initRealtimeSubscription();
    // ✅ Narrow the global channels to just this device's own rows once we
    // know the signed-in account is a 'member' (the overwhelming majority
    // at scale). Coaches/admins/head-coaches are left on the untouched
    // global channels above — they still need to see other members'
    // changes. Any failure here just leaves the global subscription from
    // _initRealtimeSubscription() running, so there's no broken state.
    Supabase.instance.client.auth.onAuthStateChange.listen((_) {
      _refineRealtimeForCurrentUser();
    });
    _refineRealtimeForCurrentUser();
  }

  Future<void> _refineRealtimeForCurrentUser() async {
    try {
      final uid = Supabase.instance.client.auth.currentUser?.id;
      if (uid == null) return;
      final profile =
          await Supabase.instance.client
              .from('profiles')
              .select('role')
              .eq('id', uid)
              .maybeSingle();
      if (profile?['role'] != 'member') return;

      await _profilesChannel?.unsubscribe();
      _profilesChannel =
          Supabase.instance.client
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
      _paymentsChannel =
          Supabase.instance.client
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
      _dietsChannel =
          Supabase.instance.client
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
                callback:
                    (payload) => _handleMemberTableChange(payload.newRecord),
              )
              .subscribe();

      await _workoutsChannel?.unsubscribe();
      _workoutsChannel =
          Supabase.instance.client
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
                callback:
                    (payload) => _handleMemberTableChange(payload.newRecord),
              )
              .subscribe();

      await _measurementsChannel?.unsubscribe();
      _measurementsChannel =
          Supabase.instance.client
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
                callback:
                    (payload) => _handleMemberTableChange(payload.newRecord),
              )
              .subscribe();
    } catch (e) {
      debugPrint(
        '⚠️ Realtime refine skipped, global channels still active: $e',
      );
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

    _profilesChannel =
        client
            .channel('public:profiles')
            .onPostgresChanges(
              event: PostgresChangeEvent.update,
              schema: 'public',
              table: 'profiles',
              callback: (payload) => _handleProfileChange(payload.newRecord),
            )
            .subscribe();

    _paymentsChannel =
        client
            .channel('public:payments')
            .onPostgresChanges(
              event: PostgresChangeEvent.all,
              schema: 'public',
              table: 'payments',
              callback: (payload) => _handlePaymentChange(payload.newRecord),
            )
            .subscribe();

    _dietsChannel =
        client
            .channel('public:diets')
            .onPostgresChanges(
              event: PostgresChangeEvent.all,
              schema: 'public',
              table: 'diets',
              callback:
                  (payload) => _handleMemberTableChange(payload.newRecord),
            )
            .subscribe();

    _workoutsChannel =
        client
            .channel('public:workouts')
            .onPostgresChanges(
              event: PostgresChangeEvent.all,
              schema: 'public',
              table: 'workouts',
              callback:
                  (payload) => _handleMemberTableChange(payload.newRecord),
            )
            .subscribe();

    _measurementsChannel =
        client
            .channel('public:measurement_logs')
            .onPostgresChanges(
              event: PostgresChangeEvent.all,
              schema: 'public',
              table: 'measurement_logs',
              callback:
                  (payload) => _handleMemberTableChange(payload.newRecord),
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
      final profileFuture =
          Supabase.instance.client
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
        final extra =
            await Supabase.instance.client.rpc(
                  'get_member_dashboard_extra',
                  params: {'p_member_id': memberId},
                )
                as Map<String, dynamic>;

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
        todaySteps: todaySteps,
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

  void pruneCache({int maxEntries = 50}) {
    if (_cache.length <= maxEntries) return;

    final sortedKeys =
        _cacheTimestamps.keys.toList()..sort(
          (a, b) => _cacheTimestamps[a]!.compareTo(_cacheTimestamps[b]!),
        );

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
