import 'package:supabase_flutter/supabase_flutter.dart';
import 'master_data_provider.dart';

/// One tile popup list (names), kept in memory while it is still fresh.
class StaffNameList {
  final int version; // MasterDataProvider.listChangeNotifier value at creation
  final DateTime createdAt;
  final List<Map<String, dynamic>> items = [];
  int total = 0;
  bool loaded = false;

  StaffNameList(this.version) : createdAt = DateTime.now();

  bool get hasMore => items.length < total;
}

/// Dashboard numbers + tile name lists for head coach / coach.
/// The SERVER decides what the caller may see (head coach = all members,
/// coach = only his own), so nothing here can leak other coaches' members.
class StaffDashboardProvider {
  StaffDashboardProvider._();
  static final StaffDashboardProvider instance = StaffDashboardProvider._();

  static const int pageSize = 20;
  static const Duration _maxAge = Duration(minutes: 5);

  String? _uid; // whose data is cached
  Map<String, dynamic>? _stats;
  DateTime? _statsAt;
  int _statsVersion = -1;
  Future<Map<String, dynamic>>? _statsInFlight;
  final Map<String, StaffNameList> _names = {};

  int get _liveVersion => MasterDataProvider.instance.listChangeNotifier.value;

  // Different user logged in on this device -> forget everything.
  void _resetIfUserChanged() {
    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (uid == _uid) return;
    _uid = uid;
    _stats = null;
    _statsAt = null;
    _statsVersion = -1;
    _names.clear();
  }

  bool _fresh(DateTime? t) =>
      t != null && DateTime.now().difference(t) < _maxAge;

  /// All tile numbers in ONE call. Same call twice at once = one request.
  Future<Map<String, dynamic>> loadStats({bool force = false}) {
    _resetIfUserChanged();
    if (!force &&
        _stats != null &&
        _statsVersion == _liveVersion &&
        _fresh(_statsAt)) {
      return Future.value(_stats!);
    }
    return _statsInFlight ??=
        _fetchStats().whenComplete(() => _statsInFlight = null);
  }

  Future<Map<String, dynamic>> _fetchStats() async {
    final version = _liveVersion;
    final data =
        await Supabase.instance.client.rpc('get_staff_dashboard_stats');
    final stats = Map<String, dynamic>.from(data as Map);
    _stats = stats;
    _statsAt = DateTime.now();
    _statsVersion = version;
    _names.clear(); // numbers refreshed -> popup lists must refresh too
    return stats;
  }

  /// 20 names per call. kinds: total, in_membership, ended, new,
  /// no_diet, no_workout. Reopening a popup costs 0 calls while fresh.
  Future<StaffNameList> loadNames(String kind, {bool more = false}) async {
    _resetIfUserChanged();
    var list = _names[kind];
    if (list == null ||
        list.version != _liveVersion ||
        !_fresh(list.createdAt)) {
      list = StaffNameList(_liveVersion);
      _names[kind] = list;
    }
    if (more ? !list.hasMore : list.loaded) return list;

    final data = await Supabase.instance.client.rpc(
      'get_staff_member_names',
      params: {
        'p_kind': kind,
        'p_limit': pageSize,
        'p_offset': more ? list.items.length : 0,
      },
    );
    final rows = List<Map<String, dynamic>>.from(data);
    if (!more) list.items.clear();
    list.items.addAll(rows);
    list.total = rows.isNotEmpty
        ? (rows.first['total_count'] as num).toInt()
        : list.items.length;
    list.loaded = true;
    return list;
  }
}
