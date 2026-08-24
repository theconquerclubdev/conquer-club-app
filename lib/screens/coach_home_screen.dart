import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../theme/app_theme.dart';
import 'login_screen.dart';
import 'member_profile_coach_view_screen.dart';

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

  // ✅ Pagination variables — now backed by real server-side LIMIT/OFFSET
  bool isLoadingMore = false;
  final int pageSize = 20;
  bool hasMoreData = true;
  int totalCount = 0;
  final ScrollController _scrollController = ScrollController();
  Timer? _searchDebounce;

  // Role — fetched once, not on every page load
  bool isHeadCoach = false;

  // Dashboard Stats
  int activeCount = 0;
  int inactiveCount = 0;
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

  // Coach permissions
  bool canEditDiet = false;
  bool canEditWorkout = false;
  bool isLoadingPermissions = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _loadPermissionsAndMembers();
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    searchController.dispose();
    _searchDebounce?.cancel();
    super.dispose();
  }

  Future<void> _loadPermissionsAndMembers() async {
    await _loadPermissions();
    await loadMembers();
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
      print('Error loading permissions: $e');
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
  Future<void> loadMembers({bool reset = true}) async {
    if (!mounted) return;

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

      final results = List<Map<String, dynamic>>.from(data);
      final total = results.isNotEmpty
          ? (results.first['total_count'] as num).toInt()
          : (reset ? 0 : totalCount);

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
      }

      // Dashboard stat tiles are computed server-side too, so they stay
      // correct across the whole member set instead of only the loaded page.
      if (reset) {
        unawaited(_loadStats());
      }
    } catch (e) {
      print('Error loading members: $e');
      if (mounted) {
        setState(() {
          isLoading = false;
          isLoadingMore = false;
        });
      }
    }
  }

  Future<void> _loadStats() async {
    try {
      final currentUser = Supabase.instance.client.auth.currentUser!;
      final data = await Supabase.instance.client.rpc(
        'get_member_stats',
        params: {
          'p_coach_id': isHeadCoach ? null : currentUser.id,
          'p_is_head_coach': isHeadCoach,
        },
      );
      final stats = (data as List).isNotEmpty
          ? Map<String, dynamic>.from(data.first)
          : <String, dynamic>{};

      if (!mounted) return;
      setState(() {
        activeCount = (stats['active_count'] as num?)?.toInt() ?? 0;
        inactiveCount = (stats['inactive_count'] as num?)?.toInt() ?? 0;
        newMembersCount = (stats['new_members_count'] as num?)?.toInt() ?? 0;
        noDietCount = (stats['no_diet_count'] as num?)?.toInt() ?? 0;
        noWorkoutCount = (stats['no_workout_count'] as num?)?.toInt() ?? 0;
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
      print('Error loading stats: $e');
    }
  }

  // Debounced search — waits for the user to pause typing before hitting
  // the server, instead of filtering an incomplete in-memory list.
  void onSearchChanged(String value) {
    setState(() => search = value.trim());
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 350), () {
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
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
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
                      Text(
                        'Athletes',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
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
                    colors: [AppColors.gold, AppColors.gold.withOpacity(0.75)],
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
                  Tab(
                    height: 40,
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
    );
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
      onRefresh: () => loadMembers(reset: true),
      color: AppColors.gold,
      backgroundColor: AppColors.cardDark,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(12),
        physics: const AlwaysScrollableScrollPhysics(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _DashboardStatCard(
                  label: 'Active',
                  count: activeCount,
                  color: Colors.green,
                  icon: Icons.check_circle,
                  onTap: () => _navigateToMembersWithFilter('active'),
                ),
                const SizedBox(width: 8),
                _DashboardStatCard(
                  label: 'Inactive',
                  count: inactiveCount,
                  color: Colors.red,
                  icon: Icons.cancel,
                  onTap: () => _navigateToMembersWithFilter('inactive'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                _DashboardStatCard(
                  label: 'New Members',
                  count: newMembersCount,
                  color: AppColors.gold,
                  icon: Icons.person_add,
                  onTap: () => _navigateToMembersWithFilter('new'),
                ),
                const SizedBox(width: 8),
                _DashboardStatCard(
                  label: 'No Diet',
                  count: noDietCount,
                  color: Colors.orange,
                  icon: Icons.restaurant,
                  onTap: () => _navigateToMembersWithFilter('no_diet'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                _DashboardStatCard(
                  label: 'No Workout',
                  count: noWorkoutCount,
                  color: Colors.blue,
                  icon: Icons.fitness_center,
                  onTap: () => _navigateToMembersWithFilter('no_workout'),
                ),
                const SizedBox(width: 8),
                _DashboardStatCard(
                  label: 'Total',
                  count: totalCount,
                  color: Colors.grey,
                  icon: Icons.people,
                  onTap: () => _navigateToMembersWithFilter('all'),
                ),
              ],
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
                      onTap: () => _navigateToMembersWithFilter('inactive'),
                    ),
                  if (expiredYesterday > 0)
                    _AlertChip(
                      label: '⚠️ Expired Yesterday',
                      count: expiredYesterday,
                      color: Colors.deepOrange,
                      onTap: () => _navigateToMembersWithFilter('inactive'),
                    ),
                  if (expiredToday > 0)
                    _AlertChip(
                      label: '🔥 Expires Today',
                      count: expiredToday,
                      color: Colors.orange,
                      onTap: () => _navigateToMembersWithFilter('active'),
                    ),
                  if (expiringTomorrow > 0)
                    _AlertChip(
                      label: '📋 Expires Tomorrow',
                      count: expiringTomorrow,
                      color: Colors.blue,
                      onTap: () => _navigateToMembersWithFilter('active'),
                    ),
                  if (expiringIn7Days > 0)
                    _AlertChip(
                      label: '📅 Expires in 7 days',
                      count: expiringIn7Days,
                      color: Colors.green,
                      onTap: () => _navigateToMembersWithFilter('active'),
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
                      onTap: () => _navigateToMembersWithFilter('active'),
                    ),
                  if (dietDueTomorrow > 0)
                    _AlertChip(
                      label: '📋 Diet Due Tomorrow',
                      count: dietDueTomorrow,
                      color: Colors.blue,
                      onTap: () => _navigateToMembersWithFilter('active'),
                    ),
                  if (dietOverdue > 0)
                    _AlertChip(
                      label: '⚠️ Diet Overdue (7+ days)',
                      count: dietOverdue,
                      color: Colors.red,
                      onTap: () => _navigateToMembersWithFilter('active'),
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
                  onRefresh: () => loadMembers(reset: true),
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
                          loadMembers(reset: true);
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
                Text(
                  label,
                  style: TextStyle(
                    color: Colors.grey.shade400,
                    fontSize: isSmall ? 8 : 9,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 1),
            Text(
              '$count',
              style: TextStyle(
                color: color,
                fontSize: isSmall ? 16 : 18,
                fontWeight: FontWeight.bold,
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
            Text(
              label,
              style: TextStyle(
                color: Colors.white,
                fontSize: isSmall ? 10 : 12,
              ),
            ),
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
class _MemberCard extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final name = member['full_name'] ?? 'No name';
    final goal = member['goal'] ?? 'No goal';
    final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';
    final isActive = member['is_active'] ?? false;
    final hasWorkout = member['has_workout'] ?? false;
    final hasDiet = member['has_diet'] ?? false;
    final hasEditPermissions = canEditDiet || canEditWorkout;
    final isSmall = MediaQuery.of(context).size.width < 360;

    // ✅ Membership days left
    String membershipStatus = '';
    Color membershipColor = Colors.grey;
    final daysLeft = member['days_left'] as int?;
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
                          Text(
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
                Row(
                  children: [
                    _buildStat('Workout', lastWorkoutText, isActive, isSmall),
                    const SizedBox(width: 4),
                    _buildStat('Diet', hasDiet ? '✅' : '❌', isActive, isSmall),
                  ],
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
