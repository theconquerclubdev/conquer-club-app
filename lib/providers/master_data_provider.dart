import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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

    return MemberDashboardData(
      memberId: memberId,
      currentStreak: (json['current_streak'] as num?)?.toInt() ?? 0,
      todaySteps: (json['today_steps'] as num?)?.toInt() ?? 0,
      stepGoal: (json['step_goal'] ?? profileMap?['step_goal'] ?? 10000) as int,
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
  int get daysLeft => (profile?['days_left'] as num?)?.toInt() ?? -1;
  bool get isMembershipActive =>
      profile?['is_membership_active'] == true || daysLeft >= 0;

  // Task Status Getters
  bool get workoutCompletedToday => tasksToday?['workout_completed'] == true;
  bool get measurementUpdatedToday =>
      tasksToday?['measurement_updated'] == true;
  bool get photosUpdatedToday => tasksToday?['photos_updated'] == true;
  bool get photoFrontUpdated => tasksToday?['after_front_updated_at'] != null;
  bool get photoBackUpdated => tasksToday?['after_back_updated_at'] != null;

  // 5 Member Types Category
  String get memberTypeCategory =>
      (profile?['member_type_category'] as String?) ?? 'signup_member';
}

// ============================================================
// MASTER DATA PROVIDER
// ============================================================

class MasterDataProvider extends ChangeNotifier {
  static final MasterDataProvider _instance = MasterDataProvider._internal();
  factory MasterDataProvider() => _instance;
  static MasterDataProvider get instance => _instance;

  MasterDataProvider._internal();

  final Map<String, MemberDashboardData> _cache = {};
  final Map<String, DateTime> _cacheTimestamps = {};
  final Map<String, Future<MemberDashboardData>> _inFlight = {};
  final Map<String, bool> _loadingStates = {};
  final Map<String, String?> _errorStates = {};

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
      final response = await Supabase.instance.client.rpc(
        'get_member_full_profile',
        params: {'p_member_id': memberId},
      );

      if (response == null) {
        throw Exception('No data returned for member: $memberId');
      }

      final data = Map<String, dynamic>.from(response as Map);
      final dashboardData = MemberDashboardData.fromJson(memberId, data);

      _cache[memberId] = dashboardData;
      _cacheTimestamps[memberId] = DateTime.now();
      pruneCache();

      return dashboardData;
    } catch (e) {
      if (_cache.containsKey(memberId)) {
        return _cache[memberId]!;
      }
      rethrow;
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
