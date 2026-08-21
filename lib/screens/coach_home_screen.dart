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

  // ✅ Pagination variables
  bool isLoadingMore = false;
  int currentPage = 0;
  final int pageSize = 10;
  bool hasMoreData = true;
  final ScrollController _scrollController = ScrollController();

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
      final data = await Supabase.instance.client
          .from('coach_permissions')
          .select()
          .eq('coach_id', coachId)
          .maybeSingle();

      if (mounted) {
        setState(() {
          canEditDiet = data?['can_edit_diet'] ?? false;
          canEditWorkout = data?['can_edit_workout'] ?? false;
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
  // ✅ OPTIMIZED: loadMembers with parallel queries for speed
  // ============================================================
  Future<void> loadMembers({bool reset = true}) async {
    if (!mounted) return;

    if (reset) {
      setState(() {
        isLoading = true;
        allMembers = [];
        filteredMembers = [];
        currentPage = 0;
        hasMoreData = true;
      });
    } else {
      if (isLoadingMore || !hasMoreData) return;
      setState(() => isLoadingMore = true);
    }

    try {
      final currentUser = Supabase.instance.client.auth.currentUser!;

      // Check if user is head_coach
      final profile = await Supabase.instance.client
          .from('profiles')
          .select('role')
          .eq('id', currentUser.id)
          .maybeSingle();

      final isHeadCoach = profile?['role'] == 'head_coach';

      // ✅ SINGLE RPC CALL with pagination
      final offset = reset ? 0 : currentPage * pageSize;

      // ✅ First get members with coach info (we need coach name for search)
      final data = await Supabase.instance.client.rpc(
        'get_members_with_latest_data',
        params: {
          'coach_id': isHeadCoach ? null : currentUser.id,
          'is_head_coach': isHeadCoach,
        },
      );

      // ✅ Apply pagination in Dart (temporary until we update RPC)
      final allResults = List<Map<String, dynamic>>.from(data);

      // ✅ Get coach names for all coaches in one query (not per member!)
      final allCoachIds = allResults
          .map((m) => m['assigned_coach_id'] as String?)
          .where((id) => id != null)
          .toSet()
          .toList();

      Map<String, String> coachNames = {};
      if (allCoachIds.isNotEmpty) {
        final coachData = await Supabase.instance.client
            .from('profiles')
            .select('id, full_name')
            .inFilter('id', allCoachIds);

        for (final coach in coachData) {
          coachNames[coach['id']] = coach['full_name'] ?? 'Unknown Coach';
        }
      }

      // ✅ Add coach_name to each member
      for (final member in allResults) {
        final coachId = member['assigned_coach_id'] as String?;
        member['coach_name'] = coachId != null ? coachNames[coachId] : null;
      }

      final paginatedResults = allResults.skip(offset).take(pageSize).toList();
      final hasMore = (offset + pageSize) < allResults.length;

      final membersWithInfo = <Map<String, dynamic>>[];
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);

      int active = 0, inactive = 0, newMembers = 0, noDiet = 0, noWorkout = 0;
      int dueToday = 0, dueTomorrow = 0, overdue = 0;
      int expToday = 0,
          expYesterday = 0,
          expLastWeek = 0,
          expTomorrow = 0,
          expIn7Days = 0;

      // ✅ Only process paginated results for display
      // But count stats from ALL results for dashboard
      for (final member in allResults) {
        final hasWorkout = member['latest_workout'] != null;
        final hasDiet = member['latest_diet'] != null;
        final endDateStr = member['membership_end_date'] as String?;
        int daysLeft = -999;
        bool membershipActive = false;

        if (endDateStr != null) {
          try {
            final endDate = DateTime.parse(endDateStr);
            daysLeft = endDate.difference(today).inDays;
            membershipActive = daysLeft >= 0;
          } catch (_) {
            membershipActive = false;
          }
        }

        if (membershipActive) {
          active++;
          if (!hasWorkout) noWorkout++;
          if (!hasDiet) noDiet++;

          if (hasDiet) {
            final dietDate = DateTime.parse(member['latest_diet']);
            final daysSince = today.difference(dietDate).inDays;
            if (daysSince >= 7)
              overdue++;
            else if (daysSince == 6)
              dueTomorrow++;
            else if (daysSince == 5) dueToday++;
          }

          if (daysLeft == 0)
            expToday++;
          else if (daysLeft == 1)
            expTomorrow++;
          else if (daysLeft == 7) expIn7Days++;
        } else {
          inactive++;
          if (daysLeft == -1)
            expYesterday++;
          else if (daysLeft <= -7) expLastWeek++;
        }

        if (membershipActive && !hasDiet && !hasWorkout) newMembers++;
      }

      // ✅ Process only paginated results for display
      for (final member in paginatedResults) {
        final hasWorkout = member['latest_workout'] != null;
        final hasDiet = member['latest_diet'] != null;
        final endDateStr = member['membership_end_date'] as String?;
        int daysLeft = -999;
        bool membershipActive = false;

        if (endDateStr != null) {
          try {
            final endDate = DateTime.parse(endDateStr);
            daysLeft = endDate.difference(today).inDays;
            membershipActive = daysLeft >= 0;
          } catch (_) {
            membershipActive = false;
          }
        }

        membersWithInfo.add({
          ...member,
          'has_workout': hasWorkout,
          'has_diet': hasDiet,
          'is_active': membershipActive,
          'days_left': daysLeft,
          'membership_end_date': endDateStr,
        });
      }

      if (mounted) {
        setState(() {
          if (reset) {
            allMembers = membersWithInfo;
          } else {
            allMembers.addAll(membersWithInfo);
          }
          filteredMembers = allMembers;
          isLoading = false;
          isLoadingMore = false;
          hasMoreData = hasMore;
          if (hasMore) currentPage++;

          activeCount = active;
          inactiveCount = inactive;
          newMembersCount = newMembers;
          noDietCount = noDiet;
          noWorkoutCount = noWorkout;
          dietDueToday = dueToday;
          dietDueTomorrow = dueTomorrow;
          dietOverdue = overdue;
          expiredToday = expToday;
          expiredYesterday = expYesterday;
          expiredLastWeek = expLastWeek;
          expiringTomorrow = expTomorrow;
          expiringIn7Days = expIn7Days;

          applyFiltersAndSort();
        });
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

  void applyFiltersAndSort() {
    if (!mounted) return;
    var list = List<Map<String, dynamic>>.from(allMembers);

    // ✅ Search: member name, email, OR coach name
    if (search.isNotEmpty) {
      final q = search.toLowerCase();
      list = list.where((m) {
        final name = (m['full_name'] ?? '').toString().toLowerCase();
        final email = (m['email'] ?? '').toString().toLowerCase();
        final coachName = (m['coach_name'] ?? '').toString().toLowerCase();
        return name.contains(q) || email.contains(q) || coachName.contains(q);
      }).toList();
    }

    switch (filterType) {
      case 'active':
        list = list.where((m) => m['is_active'] == true).toList();
        break;
      case 'inactive':
        list = list.where((m) => m['is_active'] == false).toList();
        break;
      case 'new':
        list = list
            .where((m) =>
                m['is_active'] == true &&
                m['has_diet'] == false &&
                m['has_workout'] == false)
            .toList();
        break;
      case 'no_diet':
        list = list
            .where((m) =>
                m['is_active'] == true &&
                m['has_diet'] == false &&
                m['has_workout'] == true)
            .toList();
        break;
      case 'no_workout':
        list = list
            .where((m) =>
                m['is_active'] == true &&
                m['has_diet'] == true &&
                m['has_workout'] == false)
            .toList();
        break;
      default:
        break;
    }

    list.sort((a, b) {
      int comparison = 0;
      switch (sortType) {
        case 'name':
          comparison = (a['full_name'] ?? '').compareTo(b['full_name'] ?? '');
          break;
        case 'last_workout':
          final aDate = a['latest_workout'] ?? '';
          final bDate = b['latest_workout'] ?? '';
          comparison = aDate.compareTo(bDate);
          break;
        case 'last_diet':
          final aDate = a['latest_diet'] ?? '';
          final bDate = b['latest_diet'] ?? '';
          comparison = aDate.compareTo(bDate);
          break;
        case 'signup_date':
          final aDate = a['created_at'] ?? '';
          final bDate = b['created_at'] ?? '';
          comparison = aDate.compareTo(bDate);
          break;
        default:
          comparison = 0;
      }
      return sortAscending ? comparison : -comparison;
    });

    setState(() {
      filteredMembers = list;
    });
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
    setState(() {
      filterType = filter;
      applyFiltersAndSort();
    });
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
                              '${allMembers.length}',
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
      onRefresh: loadMembers,
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
                  count: allMembers.length,
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
                                setState(() {
                                  search = '';
                                  applyFiltersAndSort();
                                });
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
                    onChanged: (v) {
                      setState(() {
                        search = v.trim();
                        applyFiltersAndSort();
                      });
                    },
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
                      if (value != null) {
                        setState(() {
                          filterType = value;
                          applyFiltersAndSort();
                        });
                      }
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
                onPressed: () {
                  setState(() {
                    sortAscending = !sortAscending;
                    applyFiltersAndSort();
                  });
                },
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
                'Showing ${filteredMembers.length} members',
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
