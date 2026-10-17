import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../theme/app_theme.dart';
import 'login_screen.dart';
import 'member_profile_coach_view_screen.dart';
import '../providers/master_data_provider.dart';
import 'head_coach_workout_templates_screen.dart';
import '../providers/staff_dashboard_provider.dart';
import '../widgets/staff_member_names_sheet.dart';

class CoachHomeScreen extends StatefulWidget {
  const CoachHomeScreen({super.key});

  @override
  State<CoachHomeScreen> createState() => _CoachHomeScreenState();
}

class _CoachHomeScreenState extends State<CoachHomeScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final searchController = TextEditingController();
  String search = '';
  String filterType = 'all'; // all, active, inactive, new, no_diet, no_workout
  String sortType = 'name';
  bool sortAscending = true;

  List<Map<String, dynamic>> allMembers = [];
  List<Map<String, dynamic>> filteredMembers = [];
  bool isLoading = true;
  final MasterDataProvider _dataProvider = MasterDataProvider.instance;

  // ✅ Pagination variables — now backed by real server-side LIMIT/OFFSET
  bool isLoadingMore = false;
  final int pageSize = 20;
  bool hasMoreData = true;
  int totalCount = 0;
  final ScrollController _scrollController = ScrollController();
  Timer? _searchDebounce;

  // Saved member-list pages per filter/sort. Reused while nothing changed.
  final Map<String, Map<String, dynamic>> _listCache = {};
  Timer? _listChangeDebounce;
  int _listRequestId = 0; // newest list request wins; older answers are dropped

  // Role — fetched once, not on every page load
  bool isHeadCoach = false;

  // Dashboard Stats
  int activeCount = 0;
  int inactiveCount = 0;
  int totalMembers = 0;
  int inMembership = 0;
  int membersEnded = 0;
  int newMembersCount = 0;
  int noDietCount = 0;
  int noWorkoutCount = 0;
  int dietDueToday = 0;
  int dietDueTomorrow = 0;
  int dietOverdue = 0;
  int expiredToday = 0;
  int expiredYesterday = 0;
  int expiredLastWeek = 0;
  int expiringTomorrow = 0;
  int expiringIn7Days = 0;
  // Not used in UI but kept for potential future use
  int activeWithStreakCount = 0;

  // Coach permissions
  bool canEditDiet = false;
  bool canEditWorkout = false;
  bool isLoadingPermissions = true;

  // Account deletion request status (coach)
  bool _checkingDeletionRequest = true;
  bool _hasPendingDeletionRequest = false;
  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _dataProvider.listChangeNotifier.addListener(_onListChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _loadPermissionsAndMembers();
      }
    });
  }

  @override
  void dispose() {
    _dataProvider.listChangeNotifier.removeListener(_onListChanged);
    _listChangeDebounce?.cancel();
    _tabController.dispose();
    searchController.dispose();
    _searchDebounce?.cancel();
    super.dispose();
  }

  // Something the list shows changed (realtime / long sleep): reload once,
  // after a short pause so a burst of changes = 1 call.
  void _onListChanged() {
    _listChangeDebounce?.cancel();
    _listChangeDebounce = Timer(const Duration(milliseconds: 1500), () {
      if (!mounted || isLoading) return;
      loadMembers(reset: true, refreshStats: true);
    });
  }

  Future<void> _loadPermissionsAndMembers() async {
    await _loadPermissions();
    await loadMembers(refreshStats: true);
  }

  Future<void> _checkExistingDeletionRequest() async {
    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) return;
      final existing = await Supabase.instance.client
          .from('account_deletion_requests')
          .select('id')
          .eq('member_id', userId)
          .eq('status', 'pending')
          .maybeSingle();
      if (mounted) {
        setState(() {
          _hasPendingDeletionRequest = existing != null;
          _checkingDeletionRequest = false;
        });
      }
    } catch (e) {
      debugPrint('Error checking deletion request: $e');
      if (mounted) setState(() => _checkingDeletionRequest = false);
    }
  }

  Future<void> _confirmAndRequestCoachDeletion() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.cardDark,
        title: const Text('Delete your account?',
            style: TextStyle(color: Colors.white)),
        content: const Text(
          'This will permanently delete your coach account and all your '
          'data. This cannot be undone.\n\n'
          'Your account will be deleted within 48 hours after your request '
          'is reviewed.',
          style: TextStyle(color: Colors.grey),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete My Account'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) return;

      final profile = await Supabase.instance.client
          .from('profiles')
          .select('email, full_name')
          .eq('id', user.id)
          .maybeSingle();

      await Supabase.instance.client.from('account_deletion_requests').insert({
        'member_id': user.id,
        'email': profile?['email'] ?? user.email ?? '',
        'full_name': profile?['full_name'],
      });

      if (mounted) {
        setState(() => _hasPendingDeletionRequest = true);
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            backgroundColor: AppColors.cardDark,
            title: const Text('Request received',
                style: TextStyle(color: Colors.white)),
            content: const Text(
              'Your account will be deleted within 48 hours. You can keep '
              'using the app until then.',
              style: TextStyle(color: Colors.grey),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      debugPrint('Error requesting account deletion: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Something went wrong. Please try again.')),
        );
      }
    }
  }

  Future<void> _loadPermissions() async {
    if (!mounted) return;
    setState(() => isLoadingPermissions = true);
    try {
      final coachId = Supabase.instance.client.auth.currentUser!.id;

      final results = await Future.wait([
        Supabase.instance.client
            .from('coach_permissions')
            .select('can_edit_diet, can_edit_workout')
            .eq('coach_id', coachId)
            .maybeSingle(),
        Supabase.instance.client
            .from('profiles')
            .select('role')
            .eq('id', coachId)
            .maybeSingle(),
      ]);

      final data = results[0];
      final profile = results[1];

      if (mounted) {
        setState(() {
          canEditDiet = data?['can_edit_diet'] ?? false;
          canEditWorkout = data?['can_edit_workout'] ?? false;
          isHeadCoach = profile?['role'] == 'head_coach';
          isLoadingPermissions = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading permissions: $e');
      if (mounted) {
        setState(() {
          canEditDiet = false;
          canEditWorkout = false;
          isLoadingPermissions = false;
        });
      }
    }
  }

  // ============================================================
  // Real server-side pagination, search, filter and sort.
  // Every param is sent to the get_members_with_latest_data RPC,
  // which does the LIMIT/OFFSET, ILIKE search, filter and ORDER BY
  // in Postgres. The client never downloads more rows than it
  // displays, and search works across ALL members — not just the
  // ones already paged in.
  // ============================================================
  Future<void> loadMembers(
      {bool reset = true, bool refreshStats = false}) async {
    if (!mounted) return;

    final cacheKey = '$filterType|$sortType|$sortAscending|$search';
    final startVersion = _dataProvider.listChangeNotifier.value;
    final requestSearch = search;
    if (reset) _listRequestId++;
    final requestId = _listRequestId;
    if (reset && !refreshStats) {
      final hit = _listCache[cacheKey];
      if (hit != null && hit['v'] == startVersion) {
        setState(() {
          allMembers = List<Map<String, dynamic>>.from(hit['members'] as List);
          filteredMembers = allMembers;
          totalCount = hit['total'] as int;
          hasMoreData = hit['hasMore'] as bool;
          isLoading = false;
          isLoadingMore = false;
        });
        return;
      }
    }

    if (reset) {
      setState(() {
        isLoading = allMembers.isEmpty;
        hasMoreData = true;
      });
    } else {
      if (isLoadingMore || !hasMoreData) return;
      setState(() => isLoadingMore = true);
    }

    try {
      final currentUser = Supabase.instance.client.auth.currentUser!;
      final offset = reset ? 0 : allMembers.length;

      // ⚠️ IMPORTANT: The RPC MUST return current_streak for each member.
      // If current_streak is not in the response, check the database RPC definition.
      // The RPC should include: (SELECT COALESCE((SELECT current_streak FROM get_current_streak(p.id)), 0)) as current_streak
      final data = await Supabase.instance.client.rpc(
        'get_members_with_latest_data',
        params: {
          'p_coach_id': isHeadCoach ? null : currentUser.id,
          'p_is_head_coach': isHeadCoach,
          'p_search': search.isEmpty ? null : search,
          'p_filter_type': filterType,
          'p_sort_type': sortType,
          'p_sort_ascending': sortAscending,
          'p_limit': pageSize,
          'p_offset': offset,
        },
      );

      if (requestId != _listRequestId) return;

      final results = List<Map<String, dynamic>>.from(data);
      final total = results.isNotEmpty
          ? (results.first['total_count'] as num).toInt()
          : (reset ? 0 : totalCount);

      // ✅ DEBUG: Check if current_streak is in the data
      if (results.isNotEmpty) {
        final firstMember = results.first;
        debugPrint('🔍 First member keys: ${firstMember.keys}');
        debugPrint('🔍 current_streak value: ${firstMember['current_streak']}');
        debugPrint('🔍 days_left: ${firstMember['days_left']}');
        debugPrint('🔍 is_active: ${firstMember['is_active']}');
      }

      if (mounted) {
        setState(() {
          if (reset) {
            allMembers = results;
          } else {
            allMembers = [...allMembers, ...results];
          }
          filteredMembers = allMembers;
          totalCount = total;
          hasMoreData = allMembers.length < total;
          isLoading = false;
          isLoadingMore = false;
        });
        {
          final old = _listCache[cacheKey];
          if (reset || (old != null && old['v'] == startVersion)) {
            _listCache[cacheKey] = {
              'members': List<Map<String, dynamic>>.from(allMembers),
              'total': totalCount,
              'hasMore': hasMoreData,
              'v': startVersion,
            };
          } else {
            _listCache.remove(cacheKey);
          }
        }
      }

      // Dashboard stat tiles are computed server-side too, so they stay
      // correct across the whole member set instead of only the loaded page.
      if (reset && refreshStats) {
        unawaited(_loadStats());
      }
    } on PostgrestException catch (e) {
      debugPrint('Error loading members: $e');
      if (mounted) {
        setState(() {
          isLoading = false;
          isLoadingMore = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content:
                Text('Unable to load members. Please check your connection.'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } catch (e) {
      debugPrint('Error loading members: $e');
      if (mounted) {
        setState(() {
          isLoading = false;
          isLoadingMore = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content:
                Text('Network error. Please check your internet connection.'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    }
  }

  Future<void> _loadStats() async {
    try {
      // One call for every tile. Server decides: head coach = all members,
      // coach = only his own. Result is cached in StaffDashboardProvider.
      final stats =
          await StaffDashboardProvider.instance.loadStats(force: true);

      if (!mounted) return;
      setState(() {
        totalMembers = (stats['total_members'] as num?)?.toInt() ?? 0;
        inMembership = (stats['in_membership'] as num?)?.toInt() ?? 0;
        membersEnded = (stats['members_ended'] as num?)?.toInt() ?? 0;
        newMembersCount = (stats['new_members'] as num?)?.toInt() ?? 0;
        noDietCount = (stats['no_diet'] as num?)?.toInt() ?? 0;
        noWorkoutCount = (stats['no_workout'] as num?)?.toInt() ?? 0;
        dietDueToday = (stats['diet_due_today'] as num?)?.toInt() ?? 0;
        dietDueTomorrow = (stats['diet_due_tomorrow'] as num?)?.toInt() ?? 0;
        dietOverdue = (stats['diet_overdue'] as num?)?.toInt() ?? 0;
        expiredToday = (stats['expired_today'] as num?)?.toInt() ?? 0;
        expiredYesterday = (stats['expired_yesterday'] as num?)?.toInt() ?? 0;
        expiredLastWeek = (stats['expired_last_week'] as num?)?.toInt() ?? 0;
        expiringTomorrow = (stats['expiring_tomorrow'] as num?)?.toInt() ?? 0;
        expiringIn7Days = (stats['expiring_in_7_days'] as num?)?.toInt() ?? 0;
      });
    } catch (e) {
      debugPrint('Error loading stats: $e');
    }
  }

  // Debounced search — waits for the user to pause typing before hitting
  // the server, instead of filtering an incomplete in-memory list.
  void onSearchChanged(String value) {
    _listRequestId++;
    setState(() => search = value.trim());
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 700), () {
      loadMembers(reset: true);
    });
  }

  void onFilterChanged(String value) {
    setState(() => filterType = value);
    loadMembers(reset: true);
  }

  void onSortToggled() {
    setState(() => sortAscending = !sortAscending);
    loadMembers(reset: true);
  }

  String formatDate(String? dateTime) {
    if (dateTime == null) return '—';
    try {
      final date = DateTime.parse(dateTime);
      return '${date.day}/${date.month} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
    } catch (e) {
      return '—';
    }
  }

  void _navigateToMembersWithFilter(String filter) {
    setState(() => filterType = filter);
    loadMembers(reset: true);
    _tabController.animateTo(1);
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    // Huge system fonts must not break the layout.
    return MediaQuery(
        data: mq.copyWith(textScaler: mq.textScaler.clamp(maxScaleFactor: 1.2)),
        child: Scaffold(
          backgroundColor: AppColors.background,
          body: SafeArea(
            child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 900),
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Flexible(
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: AppColors.gold.withOpacity(0.12),
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(
                                      color: AppColors.gold.withOpacity(0.2),
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.people_alt_rounded,
                                        color: AppColors.gold,
                                        size: 16,
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        '$totalCount',
                                        style: TextStyle(
                                          color: AppColors.gold,
                                          fontSize: 14,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Flexible(
                                  child: Text(
                                    'Athletes',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (isHeadCoach)
                            Container(
                              margin: const EdgeInsets.only(right: 8),
                              decoration: BoxDecoration(
                                color: AppColors.cardDark,
                                shape: BoxShape.circle,
                              ),
                              child: IconButton(
                                tooltip: 'Workout Plans',
                                icon: Icon(
                                  Icons.fitness_center,
                                  color: AppColors.gold,
                                  size: 20,
                                ),
                                onPressed: () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        const HeadCoachWorkoutTemplatesScreen(),
                                  ),
                                ),
                              ),
                            ),
                          Container(
                            margin: const EdgeInsets.only(right: 8),
                            decoration: BoxDecoration(
                              color: AppColors.cardDark,
                              shape: BoxShape.circle,
                            ),
                            child: IconButton(
                              icon: Icon(
                                Icons.delete_outline,
                                color: _hasPendingDeletionRequest
                                    ? Colors.white24
                                    : Colors.redAccent,
                                size: 20,
                              ),
                              onPressed: _checkingDeletionRequest ||
                                      _hasPendingDeletionRequest
                                  ? null
                                  : _confirmAndRequestCoachDeletion,
                            ),
                          ),
                          Container(
                            decoration: BoxDecoration(
                              color: AppColors.cardDark,
                              shape: BoxShape.circle,
                            ),
                            child: IconButton(
                              icon: const Icon(
                                Icons.logout_rounded,
                                color: Colors.white60,
                                size: 20,
                              ),
                              onPressed: () async {
                                await Supabase.instance.client.auth.signOut();
                                if (context.mounted) {
                                  Navigator.pushReplacement(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => const LoginScreen(),
                                    ),
                                  );
                                }
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      margin: const EdgeInsets.symmetric(horizontal: 16),
                      decoration: BoxDecoration(
                        color: AppColors.cardDark,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: TabBar(
                        controller: _tabController,
                        indicator: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              AppColors.gold,
                              AppColors.gold.withOpacity(0.75)
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        indicatorSize: TabBarIndicatorSize.tab,
                        labelColor: Colors.black,
                        unselectedLabelColor: Colors.grey,
                        labelStyle: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                        unselectedLabelStyle: const TextStyle(
                          fontWeight: FontWeight.w500,
                          fontSize: 11,
                        ),
                        tabs: const [
                          Tab(
                            height: 40,
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.dashboard, size: 14),
                                  SizedBox(width: 4),
                                  Text('DASHBOARD'),
                                ],
                              ),
                            ),
                          ),
                          Tab(
                            height: 40,
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.people, size: 14),
                                  SizedBox(width: 4),
                                  Text('MEMBERS'),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: TabBarView(
                        controller: _tabController,
                        children: [
                          _buildDashboardTab(),
                          _buildMembersTab(),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ));
  }

  // ============================================================
  // DASHBOARD TAB
  // ============================================================
  Widget _buildDashboardTab() {
    if (isLoading || isLoadingPermissions) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.gold),
      );
    }

    return RefreshIndicator(
      onRefresh: () => loadMembers(reset: true, refreshStats: true),
      color: AppColors.gold,
      backgroundColor: AppColors.cardDark,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(12),
        physics: const AlwaysScrollableScrollPhysics(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LayoutBuilder(
              builder: (context, c) {
                final w = c.maxWidth;
                final cols = w >= 760 ? 6 : (w >= 520 ? 3 : 2);
                const gap = 8.0;
                final cardW = (w - gap * (cols - 1)) / cols;
                Widget card(Widget child) =>
                    SizedBox(width: cardW, child: child);
                return Wrap(
                  spacing: gap,
                  runSpacing: gap,
                  children: [
                    card(_DashboardStatCard(
                      label: 'Total Members',
                      count: totalMembers,
                      color: Colors.purple,
                      icon: Icons.groups,
                      onTap: () {},
                    )),
                    card(_DashboardStatCard(
                      label: 'In Membership',
                      count: inMembership,
                      color: Colors.green,
                      icon: Icons.people,
                      onTap: () {},
                    )),
                    card(_DashboardStatCard(
                      label: 'Membership Ended',
                      count: membersEnded,
                      color: Colors.red,
                      icon: Icons.person_off,
                      onTap: () => showStaffMemberNamesSheet(
                          context, 'ended', 'Membership Ended'),
                    )),
                    card(_DashboardStatCard(
                      label: 'New Members',
                      count: newMembersCount,
                      color: AppColors.gold,
                      icon: Icons.person_add,
                      onTap: () => showStaffMemberNamesSheet(
                          context, 'new', 'New Members'),
                    )),
                    card(_DashboardStatCard(
                      label: 'No Diet',
                      count: noDietCount,
                      color: Colors.orange,
                      icon: Icons.restaurant,
                      onTap: () => showStaffMemberNamesSheet(
                          context, 'no_diet', 'No Diet'),
                    )),
                    card(_DashboardStatCard(
                      label: 'No Workout',
                      count: noWorkoutCount,
                      color: Colors.blue,
                      icon: Icons.fitness_center,
                      onTap: () => showStaffMemberNamesSheet(
                          context, 'no_workout', 'No Workout'),
                    )),
                  ],
                );
              },
            ),
            const SizedBox(height: 16),

            // ✅ Membership Expiry Alerts
            if (expiredLastWeek > 0 ||
                expiredYesterday > 0 ||
                expiredToday > 0 ||
                expiringTomorrow > 0 ||
                expiringIn7Days > 0)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '📅 MEMBERSHIP EXPIRY ALERTS',
                    style: TextStyle(
                      color: AppColors.gold,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1,
                    ),
                  ),
                  const SizedBox(height: 6),
                  if (expiredLastWeek > 0)
                    _AlertChip(
                      label: '⏰ Expired 7+ days ago',
                      count: expiredLastWeek,
                      color: Colors.red.shade700,
                      onTap: () => showStaffMemberNamesSheet(
                          context, 'alert_expired_7d', 'Expired 7+ days ago'),
                    ),
                  if (expiredYesterday > 0)
                    _AlertChip(
                      label: '⚠️ Expired Yesterday',
                      count: expiredYesterday,
                      color: Colors.deepOrange,
                      onTap: () => showStaffMemberNamesSheet(context,
                          'alert_expired_yesterday', 'Expired Yesterday'),
                    ),
                  if (expiredToday > 0)
                    _AlertChip(
                      label: '🔥 Expires Today',
                      count: expiredToday,
                      color: Colors.orange,
                      onTap: () => showStaffMemberNamesSheet(
                          context, 'alert_expired_today', 'Expires Today'),
                    ),
                  if (expiringTomorrow > 0)
                    _AlertChip(
                      label: '📋 Expires Tomorrow',
                      count: expiringTomorrow,
                      color: Colors.blue,
                      onTap: () => showStaffMemberNamesSheet(context,
                          'alert_expiring_tomorrow', 'Expires Tomorrow'),
                    ),
                  if (expiringIn7Days > 0)
                    _AlertChip(
                      label: '📅 Expires in 7 days',
                      count: expiringIn7Days,
                      color: Colors.green,
                      onTap: () => showStaffMemberNamesSheet(
                          context, 'alert_expiring_7d', 'Expires in 7 days'),
                    ),
                  const SizedBox(height: 8),
                ],
              ),

            // ✅ Diet Update Alerts
            if (dietDueToday > 0 || dietDueTomorrow > 0 || dietOverdue > 0)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '🍽️ DIET UPDATE ALERTS',
                    style: TextStyle(
                      color: AppColors.gold,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1,
                    ),
                  ),
                  const SizedBox(height: 6),
                  if (dietDueToday > 0)
                    _AlertChip(
                      label: '📋 Diet Due Today',
                      count: dietDueToday,
                      color: Colors.orange,
                      onTap: () => showStaffMemberNamesSheet(
                          context, 'alert_diet_today', 'Diet Due Today'),
                    ),
                  if (dietDueTomorrow > 0)
                    _AlertChip(
                      label: '📋 Diet Due Tomorrow',
                      count: dietDueTomorrow,
                      color: Colors.blue,
                      onTap: () => showStaffMemberNamesSheet(
                          context, 'alert_diet_tomorrow', 'Diet Due Tomorrow'),
                    ),
                  if (dietOverdue > 0)
                    _AlertChip(
                      label: '⚠️ Diet Overdue (7+ days)',
                      count: dietOverdue,
                      color: Colors.red,
                      onTap: () => showStaffMemberNamesSheet(context,
                          'alert_diet_overdue', 'Diet Overdue (7+ days)'),
                    ),
                  const SizedBox(height: 8),
                ],
              ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // MEMBERS TAB
  // ============================================================
  Widget _buildMembersTab() {
    if (isLoading || isLoadingPermissions) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.gold),
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
            children: [
              Expanded(
                child: Container(
                  height: 34,
                  decoration: BoxDecoration(
                    color: AppColors.cardDark,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: search.isNotEmpty
                          ? AppColors.gold.withOpacity(0.3)
                          : Colors.white.withOpacity(0.06),
                    ),
                  ),
                  child: TextField(
                    controller: searchController,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                    ),
                    decoration: InputDecoration(
                      hintText: 'Search...',
                      hintStyle: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: 11,
                      ),
                      prefixIcon: Icon(
                        Icons.search_rounded,
                        color: Colors.grey.shade600,
                        size: 16,
                      ),
                      suffixIcon: search.isNotEmpty
                          ? IconButton(
                              icon: Icon(
                                Icons.close_rounded,
                                color: Colors.grey.shade600,
                                size: 14,
                              ),
                              onPressed: () {
                                searchController.clear();
                                _searchDebounce?.cancel();
                                setState(() => search = '');
                                loadMembers(reset: true);
                              },
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(
                                minWidth: 24,
                                minHeight: 24,
                              ),
                            )
                          : null,
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 2,
                      ),
                      isDense: true,
                    ),
                    onChanged: onSearchChanged,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Container(
                height: 34,
                padding: const EdgeInsets.symmetric(horizontal: 6),
                decoration: BoxDecoration(
                  color: AppColors.cardDark,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: Colors.white.withOpacity(0.06),
                  ),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: filterType,
                    dropdownColor: AppColors.cardDark,
                    icon: Icon(
                      Icons.filter_list,
                      color: AppColors.gold,
                      size: 16,
                    ),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                    ),
                    onChanged: (value) {
                      if (value != null) onFilterChanged(value);
                    },
                    items: const [
                      DropdownMenuItem(value: 'all', child: Text('All')),
                      DropdownMenuItem(value: 'active', child: Text('Active')),
                      DropdownMenuItem(
                          value: 'inactive', child: Text('Inactive')),
                      DropdownMenuItem(value: 'new', child: Text('New')),
                      DropdownMenuItem(
                          value: 'no_diet', child: Text('No Diet')),
                      DropdownMenuItem(
                          value: 'no_workout', child: Text('No Workout')),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 2),
              IconButton(
                icon: Icon(
                  sortAscending
                      ? Icons.arrow_upward_rounded
                      : Icons.arrow_downward_rounded,
                  color: Colors.grey.shade500,
                  size: 16,
                ),
                onPressed: onSortToggled,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(
                  minWidth: 28,
                  minHeight: 28,
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 1),
          child: Row(
            children: [
              Text(
                'Showing ${filteredMembers.length} of $totalCount members',
                style: TextStyle(
                  color: Colors.grey.shade500,
                  fontSize: 10,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: filteredMembers.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.search_off_rounded,
                        color: Colors.grey.shade600,
                        size: 40,
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'No matches found',
                        style: TextStyle(
                          color: Colors.grey.shade500,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: () => loadMembers(reset: true, refreshStats: true),
                  color: AppColors.gold,
                  backgroundColor: AppColors.cardDark,
                  child: ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.fromLTRB(10, 4, 10, 10),
                    itemCount: filteredMembers.length + (hasMoreData ? 1 : 0),
                    itemBuilder: (context, index) {
                      // ✅ Load More button at the end
                      if (index == filteredMembers.length) {
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          child: Center(
                            child: isLoadingMore
                                ? const SizedBox(
                                    height: 24,
                                    width: 24,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: AppColors.gold,
                                    ),
                                  )
                                : TextButton(
                                    onPressed: () => loadMembers(reset: false),
                                    child: const Text(
                                      'Load More...',
                                      style: TextStyle(color: Colors.grey),
                                    ),
                                  ),
                          ),
                        );
                      }

                      return _MemberCard(
                        member: filteredMembers[index],
                        canEditDiet: canEditDiet,
                        canEditWorkout: canEditWorkout,
                        onTap: () async {
                          final memberId =
                              filteredMembers[index]['id'] as String?;
                          // ✅ Tiny server check BEFORE opening the profile:
                          // cache is cleared only if the member really changed
                          if (memberId != null) {
                            await _dataProvider.invalidateIfChanged(memberId);
                          }
                          _dataProvider.memberListDirty = false;
                          await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => MemberProfileCoachViewScreen(
                                member: filteredMembers[index],
                                canEditDiet: canEditDiet,
                                canEditWorkout: canEditWorkout,
                              ),
                            ),
                          );
                          // Diet saved inside the profile -> update ONLY this
                          // member's row locally (no Supabase call, no reload)
                          if (_dataProvider.memberListDirty) {
                            _dataProvider.memberListDirty = false;
                            final i = allMembers
                                .indexWhere((m) => m['id'] == memberId);
                            if (mounted && memberId != null && i != -1) {
                              setState(() {
                                allMembers[i] = {
                                  ...allMembers[i],
                                  'has_diet': true,
                                  'latest_diet':
                                      DateTime.now().toUtc().toIso8601String(),
                                };
                                filteredMembers = allMembers;
                              });
                            }
                          }
                        },
                        formatDate: formatDate,
                      );
                    },
                  ),
                ),
        ),
      ],
    );
  }
}

// ============================================================
// DASHBOARD STAT CARD
// ============================================================
class _DashboardStatCard extends StatelessWidget {
  final String label;
  final int count;
  final Color color;
  final IconData icon;
  final VoidCallback onTap;

  const _DashboardStatCard({
    required this.label,
    required this.count,
    required this.color,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isSmall = MediaQuery.of(context).size.width < 360;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.all(isSmall ? 8 : 12),
        decoration: BoxDecoration(
          color: AppColors.cardDark,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withOpacity(0.2)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: color, size: isSmall ? 12 : 14),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.grey.shade400,
                      fontSize: isSmall ? 9 : 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 1),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                '$count',
                style: TextStyle(
                  color: color,
                  fontSize: isSmall ? 16 : 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// ALERT CHIP
// ============================================================
class _AlertChip extends StatelessWidget {
  final String label;
  final int count;
  final Color color;
  final VoidCallback onTap;

  const _AlertChip({
    required this.label,
    required this.count,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isSmall = MediaQuery.of(context).size.width < 360;

    return GestureDetector(
      onTap: count > 0 ? onTap : null,
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 4),
        padding: EdgeInsets.symmetric(
          horizontal: isSmall ? 10 : 14,
          vertical: isSmall ? 6 : 8,
        ),
        decoration: BoxDecoration(
          color: AppColors.cardDark,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Flexible(
              child: Text(
                label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: isSmall ? 10 : 12,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
              decoration: BoxDecoration(
                color: color.withOpacity(0.2),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                count.toString(),
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.bold,
                  fontSize: isSmall ? 10 : 12,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// MEMBER CARD
// ============================================================
class _MemberCard extends StatefulWidget {
  final Map<String, dynamic> member;
  final bool canEditDiet;
  final bool canEditWorkout;
  final VoidCallback onTap;
  final String Function(String?) formatDate;

  const _MemberCard({
    required this.member,
    required this.canEditDiet,
    required this.canEditWorkout,
    required this.onTap,
    required this.formatDate,
  });

  @override
  State<_MemberCard> createState() => _MemberCardState();
}

class _MemberCardState extends State<_MemberCard> {
  MemberDashboardData? _masterData;

  String? get _memberId => widget.member['id'] as String?;

  @override
  void initState() {
    super.initState();
    _masterData = _memberId != null
        ? MasterDataProvider.instance.getData(_memberId!)
        : null;
    MasterDataProvider.instance.addListener(_onProviderChanged);
  }

  @override
  void didUpdateWidget(_MemberCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // List re-sorted/filtered and this slot now holds a different member —
    // re-sync so we're not comparing against the previous occupant's data.
    if (oldWidget.member['id'] != widget.member['id']) {
      _masterData = _memberId != null
          ? MasterDataProvider.instance.getData(_memberId!)
          : null;
    }
  }

  @override
  void dispose() {
    MasterDataProvider.instance.removeListener(_onProviderChanged);
    super.dispose();
  }

  // Provider notifies on ANY of the 500 members changing. Only rebuild THIS
  // card when THIS member's cached data object actually changed — patches
  // create a new object via copyWith(), so identical() stays true for every
  // other member and no other card rebuilds.
  void _onProviderChanged() {
    final id = _memberId;
    final latest = id != null ? MasterDataProvider.instance.getData(id) : null;
    if (identical(latest, _masterData)) return;
    _masterData = latest;
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final member = widget.member;
    final canEditDiet = widget.canEditDiet;
    final canEditWorkout = widget.canEditWorkout;
    final onTap = widget.onTap;
    final formatDate = widget.formatDate;
    final name = member['full_name'] ?? 'No name';
    final goal = member['goal'] ?? 'No goal';
    final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';
    final isActive = member['is_active'] ?? false;
    final hasWorkout = member['has_workout'] ?? false;
    final hasDiet = member['has_diet'] ?? false;
    final hasEditPermissions = canEditDiet || canEditWorkout;
    final isSmall = MediaQuery.of(context).size.width < 360;
    final masterData = _masterData;
    final currentStreak = (member['current_streak'] as num?)?.toInt() ??
        masterData?.currentStreak ??
        0;

    final daysLeft = member['days_left'] as int?;

    // ✅ Membership days left
    String membershipStatus = '';
    Color membershipColor = Colors.grey;
    if (daysLeft != null) {
      if (daysLeft >= 0) {
        membershipStatus = '$daysLeft d left';
        membershipColor = daysLeft <= 7 ? Colors.orange : Colors.green;
      } else {
        membershipStatus = 'Expired';
        membershipColor = Colors.red;
      }
    }

    // ✅ Diet status
    String dietStatus = '';
    Color dietColor = Colors.grey;
    if (member['latest_diet'] != null) {
      final dietDate = DateTime.parse(member['latest_diet']);
      final daysSince = DateTime.now().difference(dietDate).inDays;
      if (daysSince >= 7) {
        dietStatus = '⚠️ Diet Overdue';
        dietColor = Colors.red;
      } else if (daysSince >= 5) {
        dietStatus = '📋 Diet Due Soon';
        dietColor = Colors.orange;
      } else {
        dietStatus = '✅ Diet Updated';
        dietColor = Colors.green;
      }
    } else {
      dietStatus = '📋 No Diet';
      dietColor = Colors.grey;
    }

    final lastWorkoutText = formatDate(member['latest_workout']);

    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      decoration: BoxDecoration(
        color: AppColors.cardDark,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: hasEditPermissions
              ? AppColors.gold.withOpacity(0.15)
              : (isActive
                  ? Colors.white.withOpacity(0.04)
                  : Colors.red.withOpacity(0.15)),
        ),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: Row(
              children: [
                // Avatar
                Stack(
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: isActive
                              ? [
                                  AppColors.gold,
                                  AppColors.gold.withOpacity(0.6)
                                ]
                              : [Colors.grey, Colors.grey.withOpacity(0.6)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Text(
                          initial,
                          style: TextStyle(
                            color:
                                isActive ? Colors.black : Colors.grey.shade700,
                            fontSize: 12,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      bottom: 0,
                      right: 0,
                      child: Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: isActive ? Colors.green : Colors.red,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: AppColors.cardDark,
                            width: 1.5,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 8),

                // Name + Goal + Membership Status
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              name,
                              style: TextStyle(
                                color: isActive
                                    ? Colors.white
                                    : Colors.grey.shade400,
                                fontSize: isSmall ? 11 : 13,
                                fontWeight: FontWeight.w600,
                              ),
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                            ),
                          ),
                          if (isActive &&
                              daysLeft != null &&
                              daysLeft >= 0) ...[
                            const SizedBox(width: 4),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 4,
                                vertical: 1,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.gold.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(
                                  color: AppColors.gold.withOpacity(0.3),
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Text(
                                    '🔥',
                                    style: TextStyle(fontSize: 8),
                                  ),
                                  const SizedBox(width: 2),
                                  Text(
                                    '$currentStreak',
                                    style: TextStyle(
                                      color: AppColors.gold,
                                      fontSize: isSmall ? 7 : 9,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                          const SizedBox(width: 4),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 4, vertical: 1),
                            decoration: BoxDecoration(
                              color: membershipColor.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              membershipStatus,
                              maxLines: 1,
                              softWrap: false,
                              style: TextStyle(
                                color: membershipColor,
                                fontSize: isSmall ? 7 : 9,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                      Text(
                        goal,
                        style: TextStyle(
                          color: Colors.grey.shade500,
                          fontSize: isSmall ? 8 : 10,
                        ),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                      if (member['coach_name'] != null)
                        Text(
                          'Coach: ${member['coach_name']}',
                          style: TextStyle(
                            color: AppColors.gold.withOpacity(0.7),
                            fontSize: isSmall ? 7 : 9,
                          ),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                        ),
                      Text(
                        dietStatus,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: dietColor,
                          fontSize: isSmall ? 7 : 9,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),

                // Stats
                const SizedBox(width: 6),
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: isSmall ? 90 : 130,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: _buildStat(
                            'Workout', lastWorkoutText, isActive, isSmall),
                      ),
                      const SizedBox(width: 6),
                      _buildStat(
                          'Diet', hasDiet ? '✅' : '❌', isActive, isSmall),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStat(String label, String value, bool isActive, bool isSmall) {
    final isNotAssigned = value == '—';
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: TextStyle(
            color: isActive ? Colors.grey.shade600 : Colors.grey.shade700,
            fontSize: isSmall ? 6 : 8,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.3,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            color: isActive
                ? (isNotAssigned ? Colors.grey.shade600 : Colors.white70)
                : Colors.grey.shade600,
            fontSize: isSmall ? 7 : 9,
            fontWeight: isNotAssigned ? FontWeight.normal : FontWeight.w500,
          ),
          overflow: TextOverflow.ellipsis,
          maxLines: 1,
        ),
      ],
    );
  }
}
