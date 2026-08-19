import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../theme/app_theme.dart';
import 'login_screen.dart';
import 'admin_settings_screen.dart';

class AdminHomeScreen extends StatefulWidget {
  const AdminHomeScreen({super.key});

  @override
  State<AdminHomeScreen> createState() => _AdminHomeScreenState();
}

class _AdminHomeScreenState extends State<AdminHomeScreen>
    with SingleTickerProviderStateMixin {
  late TabController tabController;

  final List<Widget> _tabs = const [
    AdminDashboardTab(),
    AdminMembersTab(),
    AdminCoachesTab(),
    AdminSettingsTab(),
  ];

  final List<String> _tabLabels = [
    'Dashboard',
    'Members',
    'Coaches',
    'Settings',
  ];

  @override
  void initState() {
    super.initState();
    tabController = TabController(length: 4, vsync: this, initialIndex: 0);
  }

  @override
  void dispose() {
    tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text(
          'Admin Dashboard',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        bottom: TabBar(
          controller: tabController,
          indicatorColor: AppColors.gold,
          labelColor: AppColors.gold,
          unselectedLabelColor: Colors.grey,
          tabs: _tabLabels.map((label) => Tab(text: label)).toList(),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              setState(() {});
            },
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              await Supabase.instance.client.auth.signOut();
              if (context.mounted) {
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(builder: (_) => const LoginScreen()),
                );
              }
            },
          ),
        ],
      ),
      body: TabBarView(
        controller: tabController,
        children: _tabs,
      ),
    );
  }
}

// ============================================================
// DASHBOARD TAB
// ============================================================
class AdminDashboardTab extends StatefulWidget {
  const AdminDashboardTab({super.key});

  @override
  State<AdminDashboardTab> createState() => _AdminDashboardTabState();
}

class _AdminDashboardTabState extends State<AdminDashboardTab> {
  bool isLoading = true;
  int activeMembers = 0;
  int activeCoaches = 0;
  double totalRevenue = 0.0;
  Map<String, double> categoryRevenue = {};
  int membersEnded = 0;
  int membersEndingIn2Days = 0;
  int membersEndingThisMonth = 0;
  int membersEndingNextMonth = 0;
  int dietChangesToday = 0;
  int dietChangesTomorrow = 0;
  int dietChangesOverdue = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _loadStats();
      }
    });
  }

  Future<void> _loadStats() async {
    if (!mounted) return;
    setState(() => isLoading = true);
    try {
      final members = await Supabase.instance.client
          .from('profiles')
          .select('id, membership_end_date, category_id')
          .eq('role', 'member');

      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);

      int active = 0;
      int ended = 0;
      int ending2Days = 0;
      int endingThisMonth = 0;
      int endingNextMonth = 0;

      for (final m in members) {
        final endDateStr = m['membership_end_date'] as String?;
        if (endDateStr == null) {
          active++;
          continue;
        }
        final endDate = DateTime.parse(endDateStr);
        final diff = endDate.difference(today).inDays;

        if (endDate.isAfter(today)) {
          active++;
          if (diff <= 2) ending2Days++;
          if (endDate.month == now.month && endDate.year == now.year) {
            endingThisMonth++;
          }
          if (endDate.month == now.month + 1 ||
              (endDate.month == 1 && now.month == 12)) {
            endingNextMonth++;
          }
        } else {
          ended++;
        }
      }

      final coaches = await Supabase.instance.client
          .from('profiles')
          .select('id')
          .eq('role', 'coach')
          .eq('is_active', true);

      final payments = await Supabase.instance.client
          .from('payments')
          .select('amount, member_id, profiles(category_id, categories(name))')
          .eq('status', 'completed');

      double total = 0;
      final Map<String, double> catRev = {};
      for (final p in payments) {
        final amount = (p['amount'] as num?)?.toDouble() ?? 0;
        total += amount;
        final catName =
            p['profiles']?['categories']?['name'] as String? ?? 'Uncategorized';
        catRev[catName] = (catRev[catName] ?? 0) + amount;
      }

      final diets = await Supabase.instance.client
          .from('diets')
          .select('updated_at, member_id')
          .order('updated_at', ascending: false);

      final lastDietPerMember = <String, DateTime>{};
      for (final d in diets) {
        final memberId = d['member_id'] as String;
        if (!lastDietPerMember.containsKey(memberId)) {
          final date = DateTime.tryParse(d['updated_at'] as String);
          if (date != null) {
            lastDietPerMember[memberId] = date;
          }
        }
      }

      int todayChanges = 0;
      int tomorrowChanges = 0;
      int overdueChanges = 0;

      for (final entry in lastDietPerMember.entries) {
        final lastDate = entry.value;
        final daysSince = today.difference(lastDate).inDays;
        if (daysSince >= 7) {
          overdueChanges++;
        } else if (daysSince == 6) {
          tomorrowChanges++;
        } else if (daysSince == 5) {
          todayChanges++;
        }
      }

      if (mounted) {
        setState(() {
          activeMembers = active;
          activeCoaches = coaches.length;
          totalRevenue = total;
          categoryRevenue = catRev;
          membersEnded = ended;
          membersEndingIn2Days = ending2Days;
          membersEndingThisMonth = endingThisMonth;
          membersEndingNextMonth = endingNextMonth;
          dietChangesToday = todayChanges;
          dietChangesTomorrow = tomorrowChanges;
          dietChangesOverdue = overdueChanges;
          isLoading = false;
        });
      }
    } catch (e) {
      print('Error loading stats: $e');
      if (mounted) {
        setState(() => isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.gold),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadStats,
      color: AppColors.gold,
      backgroundColor: AppColors.cardDark,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        physics: const AlwaysScrollableScrollPhysics(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _StatCard(
                  label: 'Active Members',
                  value: activeMembers.toString(),
                  icon: Icons.people,
                  color: Colors.blue,
                ),
                const SizedBox(width: 12),
                _StatCard(
                  label: 'Active Coaches',
                  value: activeCoaches.toString(),
                  icon: Icons.person,
                  color: Colors.green,
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                _StatCard(
                  label: 'Total Revenue',
                  value: '₹${totalRevenue.toStringAsFixed(0)}',
                  icon: Icons.currency_rupee,
                  color: AppColors.gold,
                ),
                const SizedBox(width: 12),
                _StatCard(
                  label: 'Members Ended',
                  value: membersEnded.toString(),
                  icon: Icons.person_off,
                  color: Colors.red,
                ),
              ],
            ),
            const SizedBox(height: 20),
            const Text(
              'REVENUE BY CATEGORY',
              style: TextStyle(
                color: AppColors.gold,
                fontSize: 13,
                fontWeight: FontWeight.bold,
                letterSpacing: 1,
              ),
            ),
            const SizedBox(height: 8),
            if (categoryRevenue.isEmpty)
              const Text(
                'No revenue data yet',
                style: TextStyle(color: Colors.grey),
              )
            else
              ...categoryRevenue.entries.map((entry) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 120,
                          child: Text(
                            entry.key,
                            style: const TextStyle(color: Colors.white),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                              value:
                                  (entry.value / totalRevenue).clamp(0.0, 1.0),
                              backgroundColor: Colors.grey.shade800,
                              color: AppColors.gold,
                              minHeight: 12,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '₹${entry.value.toStringAsFixed(0)}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  )),
            const SizedBox(height: 20),
            const Text(
              'MEMBERSHIP ALERTS',
              style: TextStyle(
                color: AppColors.gold,
                fontSize: 13,
                fontWeight: FontWeight.bold,
                letterSpacing: 1,
              ),
            ),
            const SizedBox(height: 8),
            _AlertChip(
              label: 'Ending in 2 days',
              count: membersEndingIn2Days,
              color: Colors.orange,
              onTap: () => _showMemberList(context, 'Ending in 2 days'),
            ),
            _AlertChip(
              label: 'Ending this month',
              count: membersEndingThisMonth,
              color: Colors.blue,
              onTap: () => _showMemberList(context, 'Ending this month'),
            ),
            _AlertChip(
              label: 'Ending next month',
              count: membersEndingNextMonth,
              color: Colors.green,
              onTap: () => _showMemberList(context, 'Ending next month'),
            ),
            _AlertChip(
              label: 'Membership Ended',
              count: membersEnded,
              color: Colors.red,
              onTap: () => _showMemberList(context, 'Membership Ended'),
            ),
            const SizedBox(height: 20),
            const Text(
              'DIET UPDATES',
              style: TextStyle(
                color: AppColors.gold,
                fontSize: 13,
                fontWeight: FontWeight.bold,
                letterSpacing: 1,
              ),
            ),
            const SizedBox(height: 8),
            _AlertChip(
              label: 'Due Today',
              count: dietChangesToday,
              color: Colors.orange,
              onTap: () => _showDietList(context, 'Due Today'),
            ),
            _AlertChip(
              label: 'Due Tomorrow',
              count: dietChangesTomorrow,
              color: Colors.blue,
              onTap: () => _showDietList(context, 'Due Tomorrow'),
            ),
            _AlertChip(
              label: 'Overdue (7+ days)',
              count: dietChangesOverdue,
              color: Colors.red,
              onTap: () => _showDietList(context, 'Overdue'),
            ),
          ],
        ),
      ),
    );
  }

  void _showMemberList(BuildContext context, String title) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.cardDark,
      isScrollControlled: true,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        maxChildSize: 0.9,
        expand: false,
        builder: (context, scrollController) {
          return Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: FutureBuilder(
                    future: _getMembersForStatus(title),
                    builder: (context, snapshot) {
                      if (!snapshot.hasData) {
                        return const Center(
                          child: CircularProgressIndicator(
                            color: AppColors.gold,
                          ),
                        );
                      }
                      final members = snapshot.data as List;
                      if (members.isEmpty) {
                        return const Center(
                          child: Text(
                            'No members found',
                            style: TextStyle(color: Colors.grey),
                          ),
                        );
                      }
                      return ListView.builder(
                        controller: scrollController,
                        itemCount: members.length,
                        itemBuilder: (context, index) {
                          final m = members[index];
                          return ListTile(
                            title: Text(
                              m['full_name'] ?? 'Unknown',
                              style: const TextStyle(color: Colors.white),
                            ),
                            subtitle: Text(
                              m['email'] ?? '',
                              style: const TextStyle(color: Colors.grey),
                            ),
                            trailing: Text(
                              m['membership_end_date'] != null
                                  ? m['membership_end_date'].substring(0, 10)
                                  : 'N/A',
                              style: const TextStyle(
                                color: Colors.grey,
                                fontSize: 12,
                              ),
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<List> _getMembersForStatus(String status) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    var query = Supabase.instance.client
        .from('profiles')
        .select('id, full_name, email, membership_end_date')
        .eq('role', 'member');

    if (status == 'Ending in 2 days') {
      final twoDays = today.add(const Duration(days: 2));
      final threeDays = today.add(const Duration(days: 3));
      query = query
          .gte('membership_end_date', twoDays.toIso8601String())
          .lt('membership_end_date', threeDays.toIso8601String());
    } else if (status == 'Ending this month') {
      final start = DateTime(now.year, now.month, 1);
      final end = DateTime(now.year, now.month + 1, 1);
      query = query
          .gte('membership_end_date', start.toIso8601String())
          .lt('membership_end_date', end.toIso8601String());
    } else if (status == 'Ending next month') {
      final start = DateTime(now.year, now.month + 1, 1);
      final end = DateTime(now.year, now.month + 2, 1);
      query = query
          .gte('membership_end_date', start.toIso8601String())
          .lt('membership_end_date', end.toIso8601String());
    } else if (status == 'Membership Ended') {
      query = query.lt('membership_end_date', today.toIso8601String());
    }

    return await query;
  }

  void _showDietList(BuildContext context, String status) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.cardDark,
      isScrollControlled: true,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        maxChildSize: 0.9,
        expand: false,
        builder: (context, scrollController) {
          return Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Diet - $status',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: FutureBuilder(
                    future: _getDietMembers(status),
                    builder: (context, snapshot) {
                      if (!snapshot.hasData) {
                        return const Center(
                          child: CircularProgressIndicator(
                            color: AppColors.gold,
                          ),
                        );
                      }
                      final members = snapshot.data as List;
                      if (members.isEmpty) {
                        return const Center(
                          child: Text(
                            'No members found',
                            style: TextStyle(color: Colors.grey),
                          ),
                        );
                      }
                      return ListView.builder(
                        controller: scrollController,
                        itemCount: members.length,
                        itemBuilder: (context, index) {
                          final m = members[index];
                          return ListTile(
                            title: Text(
                              m['full_name'] ?? 'Unknown',
                              style: const TextStyle(color: Colors.white),
                            ),
                            subtitle: Text(
                              'Last updated: ${m['last_diet_date'] ?? 'Never'}',
                              style: const TextStyle(color: Colors.grey),
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<List> _getDietMembers(String status) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    final diets = await Supabase.instance.client
        .from('diets')
        .select('member_id, updated_at, profiles(full_name, email)')
        .order('updated_at', ascending: false);

    final Map<String, dynamic> latest = {};
    for (final d in diets) {
      final memberId = d['member_id'] as String;
      if (!latest.containsKey(memberId)) {
        latest[memberId] = d;
      }
    }

    final result = <Map<String, dynamic>>[];
    for (final entry in latest.entries) {
      final data = entry.value;
      final lastDate = DateTime.tryParse(data['updated_at'] as String);
      if (lastDate == null) continue;
      final daysSince = today.difference(lastDate).inDays;

      bool include = false;
      if (status == 'Due Today' && daysSince >= 5 && daysSince < 6)
        include = true;
      if (status == 'Due Tomorrow' && daysSince >= 6 && daysSince < 7)
        include = true;
      if (status == 'Overdue' && daysSince >= 7) include = true;

      if (include) {
        final profile = data['profiles'] as Map<String, dynamic>?;
        result.add({
          'full_name': profile?['full_name'] ?? 'Unknown',
          'email': profile?['email'] ?? '',
          'last_diet_date': lastDate.toIso8601String().substring(0, 10),
        });
      }
    }

    return result;
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.cardDark,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.2)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: color, size: 18),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(
                    color: Colors.grey.shade400,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: TextStyle(
                color: color,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

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
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: GestureDetector(
        onTap: count > 0 ? onTap : null,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: AppColors.cardDark,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: color.withOpacity(0.3)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                label,
                style: const TextStyle(color: Colors.white),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  count.toString(),
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================
// MEMBERS TAB
// ============================================================
class AdminMembersTab extends StatefulWidget {
  const AdminMembersTab({super.key});

  @override
  State<AdminMembersTab> createState() => _AdminMembersTabState();
}

class _AdminMembersTabState extends State<AdminMembersTab> {
  List<Map<String, dynamic>> members = [];
  List<Map<String, dynamic>> categories = [];
  List<Map<String, dynamic>> coaches = [];
  bool isLoading = true;
  String searchQuery = '';
  String selectedCategory = 'All';

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => isLoading = true);
    try {
      final membersData = await Supabase.instance.client
          .from('profiles')
          .select(
              'id, full_name, email, membership_end_date, category_id, is_active, assigned_coach_id')
          .eq('role', 'member')
          .order('full_name');

      final categoriesData = await Supabase.instance.client
          .from('categories')
          .select('id, name')
          .order('name');

      final coachesData = await Supabase.instance.client
          .from('profiles')
          .select('id, full_name, email')
          .eq('role', 'coach')
          .eq('is_active', true)
          .order('full_name');

      setState(() {
        members = List<Map<String, dynamic>>.from(membersData);
        categories = List<Map<String, dynamic>>.from(categoriesData);
        coaches = List<Map<String, dynamic>>.from(coachesData);
        isLoading = false;
      });
    } catch (e) {
      print('Error loading data: $e');
      setState(() => isLoading = false);
    }
  }

  Future<void> _assignCategory(String memberId, String? categoryId) async {
    await Supabase.instance.client
        .from('profiles')
        .update({'category_id': categoryId}).eq('id', memberId);
    _loadData();
  }

  Future<void> _assignCoach(String memberId, String? coachId) async {
    await Supabase.instance.client
        .from('profiles')
        .update({'assigned_coach_id': coachId}).eq('id', memberId);
    _loadData();
  }

  List<Map<String, dynamic>> get _filteredMembers {
    var list = members;
    if (searchQuery.isNotEmpty) {
      list = list.where((m) {
        final name = (m['full_name'] ?? '').toString().toLowerCase();
        final email = (m['email'] ?? '').toString().toLowerCase();
        return name.contains(searchQuery.toLowerCase()) ||
            email.contains(searchQuery.toLowerCase());
      }).toList();
    }
    if (selectedCategory != 'All') {
      list = list.where((m) => m['category_id'] == selectedCategory).toList();
    }
    return list;
  }

  void _showPaymentSheet(Map<String, dynamic> member) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.cardDark,
      isScrollControlled: true,
      builder: (_) => MemberPaymentSheet(
        member: member,
        onPaymentComplete: _loadData,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    hintText: 'Search members...',
                    prefixIcon: Icon(Icons.search, color: Colors.grey),
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(vertical: 8),
                  ),
                  onChanged: (v) => setState(() => searchQuery = v),
                ),
              ),
              const SizedBox(width: 8),
              DropdownButton<String>(
                value: selectedCategory,
                dropdownColor: AppColors.cardDark,
                style: const TextStyle(color: Colors.white),
                items: [
                  const DropdownMenuItem(value: 'All', child: Text('All')),
                  ...categories.map((c) => DropdownMenuItem(
                        value: c['id'],
                        child: Text(c['name']),
                      )),
                ],
                onChanged: (v) => setState(() => selectedCategory = v!),
              ),
            ],
          ),
        ),
        Expanded(
          child: isLoading
              ? const Center(
                  child: CircularProgressIndicator(color: AppColors.gold),
                )
              : _filteredMembers.isEmpty
                  ? const Center(
                      child: Text(
                        'No members found',
                        style: TextStyle(color: Colors.grey),
                      ),
                    )
                  : ListView.builder(
                      itemCount: _filteredMembers.length,
                      itemBuilder: (context, index) {
                        final m = _filteredMembers[index];
                        final isActive = m['is_active'] ?? true;
                        final daysLeft = _getDaysLeft(m['membership_end_date']);
                        return Container(
                          margin: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 4,
                          ),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: AppColors.cardDark,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: SizedBox(
                              width: 700,
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          m['full_name'] ?? 'Unknown',
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        Text(
                                          m['email'] ?? '',
                                          style: const TextStyle(
                                            color: Colors.grey,
                                            fontSize: 12,
                                          ),
                                        ),
                                        Row(
                                          children: [
                                            if (m['membership_end_date'] !=
                                                null)
                                              Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                  horizontal: 8,
                                                  vertical: 2,
                                                ),
                                                decoration: BoxDecoration(
                                                  color: daysLeft >= 0
                                                      ? Colors.green
                                                          .withOpacity(0.2)
                                                      : Colors.red
                                                          .withOpacity(0.2),
                                                  borderRadius:
                                                      BorderRadius.circular(8),
                                                ),
                                                child: Text(
                                                  daysLeft >= 0
                                                      ? '$daysLeft days left'
                                                      : 'Expired',
                                                  style: TextStyle(
                                                    color: daysLeft >= 0
                                                        ? Colors.green
                                                        : Colors.red,
                                                    fontSize: 10,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                              ),
                                            const SizedBox(width: 8),
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                horizontal: 8,
                                                vertical: 2,
                                              ),
                                              decoration: BoxDecoration(
                                                color: isActive
                                                    ? Colors.blue
                                                        .withOpacity(0.2)
                                                    : Colors.grey
                                                        .withOpacity(0.2),
                                                borderRadius:
                                                    BorderRadius.circular(8),
                                              ),
                                              child: Text(
                                                isActive
                                                    ? 'Active'
                                                    : 'Inactive',
                                                style: TextStyle(
                                                  color: isActive
                                                      ? Colors.blue
                                                      : Colors.grey,
                                                  fontSize: 10,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                  IconButton(
                                    icon: const Icon(
                                      Icons.payment,
                                      color: AppColors.gold,
                                    ),
                                    onPressed: () => _showPaymentSheet(m),
                                    tooltip: 'Payment',
                                  ),
                                  DropdownButton<String>(
                                    value: m['assigned_coach_id'] as String?,
                                    dropdownColor: AppColors.cardDark,
                                    hint: const Text(
                                      'Coach',
                                      style: TextStyle(color: Colors.grey),
                                    ),
                                    style: const TextStyle(color: Colors.white),
                                    items: [
                                      const DropdownMenuItem(
                                        value: null,
                                        child: Text('None'),
                                      ),
                                      ...coaches.map((c) => DropdownMenuItem(
                                            value: c['id'],
                                            child: Text(
                                                c['full_name'] ?? c['email']),
                                          )),
                                    ],
                                    onChanged: (val) =>
                                        _assignCoach(m['id'], val),
                                  ),
                                  DropdownButton<String>(
                                    value: m['category_id'] as String?,
                                    dropdownColor: AppColors.cardDark,
                                    hint: const Text(
                                      'Category',
                                      style: TextStyle(color: Colors.grey),
                                    ),
                                    style: const TextStyle(color: Colors.white),
                                    items: [
                                      const DropdownMenuItem(
                                        value: null,
                                        child: Text('None'),
                                      ),
                                      ...categories.map((c) => DropdownMenuItem(
                                            value: c['id'],
                                            child: Text(c['name']),
                                          )),
                                    ],
                                    onChanged: (val) =>
                                        _assignCategory(m['id'], val),
                                  ),
                                  Switch(
                                    value: isActive,
                                    activeColor: AppColors.gold,
                                    onChanged: (_) async {
                                      await Supabase.instance.client
                                          .from('profiles')
                                          .update({'is_active': !isActive}).eq(
                                              'id', m['id']);
                                      _loadData();
                                    },
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
        ),
      ],
    );
  }

  int _getDaysLeft(String? endDateStr) {
    if (endDateStr == null) return -1;
    try {
      final endDate = DateTime.parse(endDateStr);
      final now = DateTime.now();
      return endDate.difference(now).inDays;
    } catch (e) {
      return -1;
    }
  }
}

// ============================================================
// COACHES TAB
// ============================================================
class AdminCoachesTab extends StatefulWidget {
  const AdminCoachesTab({super.key});

  @override
  State<AdminCoachesTab> createState() => _AdminCoachesTabState();
}

class _AdminCoachesTabState extends State<AdminCoachesTab> {
  List<Map<String, dynamic>> coaches = [];
  bool isLoading = true;
  String searchQuery = '';
  String filterStatus = 'all';
  String sortBy = 'name';

  @override
  void initState() {
    super.initState();
    _loadCoaches();
  }

  Future<void> _loadCoaches() async {
    setState(() => isLoading = true);
    try {
      final data = await Supabase.instance.client
          .from('profiles')
          .select(
              'id, full_name, email, is_active, assigned_members:profiles!assigned_coach_id(count)')
          .eq('role', 'coach')
          .order('full_name');

      setState(() {
        coaches = List<Map<String, dynamic>>.from(data);
        isLoading = false;
      });
    } catch (e) {
      print('Error loading coaches: $e');
      setState(() => isLoading = false);
    }
  }

  List<Map<String, dynamic>> get _filteredCoaches {
    var list = coaches;
    if (searchQuery.isNotEmpty) {
      list = list.where((c) {
        final name = (c['full_name'] ?? '').toString().toLowerCase();
        final email = (c['email'] ?? '').toString().toLowerCase();
        return name.contains(searchQuery.toLowerCase()) ||
            email.contains(searchQuery.toLowerCase());
      }).toList();
    }
    if (filterStatus == 'active') {
      list = list.where((c) => c['is_active'] == true).toList();
    } else if (filterStatus == 'inactive') {
      list = list.where((c) => c['is_active'] == false).toList();
    }
    if (sortBy == 'members') {
      list.sort((a, b) {
        final aCount = (a['assigned_members'] as List?)?.length ?? 0;
        final bCount = (b['assigned_members'] as List?)?.length ?? 0;
        return bCount.compareTo(aCount);
      });
    }
    return list;
  }

  Future<void> _showAddCoachDialog() async {
    final emailController = TextEditingController();
    final passwordController = TextEditingController();
    final nameController = TextEditingController();

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.cardDark,
        title: const Text(
          'Add New Coach',
          style: TextStyle(color: Colors.white),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: 'Full Name *',
                labelStyle: TextStyle(color: Colors.grey),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: emailController,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: 'Email *',
                labelStyle: TextStyle(color: Colors.grey),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: passwordController,
              style: const TextStyle(color: Colors.white),
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Password * (min 6 chars)',
                labelStyle: TextStyle(color: Colors.grey),
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () {
              if (nameController.text.trim().isNotEmpty &&
                  emailController.text.trim().isNotEmpty &&
                  passwordController.text.trim().length >= 6) {
                Navigator.pop(context, true);
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                        'Please fill all fields and password must be at least 6 characters'),
                  ),
                );
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.gold,
              foregroundColor: Colors.black,
            ),
            child: const Text('Create Coach'),
          ),
        ],
      ),
    );

    if (result == true) {
      try {
        await Supabase.instance.client.functions.invoke(
          'create-coach',
          body: {
            'email': emailController.text.trim(),
            'password': passwordController.text.trim(),
            'fullName': nameController.text.trim(),
          },
        );

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Coach created successfully!'),
              backgroundColor: Colors.green,
            ),
          );
          _loadCoaches();
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to create coach: $e')),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton(
        backgroundColor: AppColors.gold,
        onPressed: _showAddCoachDialog,
        tooltip: 'Add Coach',
        child: const Icon(Icons.person_add, color: Colors.black),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                      hintText: 'Search coaches...',
                      prefixIcon: Icon(Icons.search, color: Colors.grey),
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(vertical: 8),
                    ),
                    onChanged: (v) => setState(() => searchQuery = v),
                  ),
                ),
                const SizedBox(width: 8),
                DropdownButton<String>(
                  value: filterStatus,
                  dropdownColor: AppColors.cardDark,
                  style: const TextStyle(color: Colors.white),
                  items: const [
                    DropdownMenuItem(value: 'all', child: Text('All')),
                    DropdownMenuItem(value: 'active', child: Text('Active')),
                    DropdownMenuItem(
                        value: 'inactive', child: Text('Inactive')),
                  ],
                  onChanged: (v) => setState(() => filterStatus = v!),
                ),
                const SizedBox(width: 8),
                DropdownButton<String>(
                  value: sortBy,
                  dropdownColor: AppColors.cardDark,
                  style: const TextStyle(color: Colors.white),
                  items: const [
                    DropdownMenuItem(value: 'name', child: Text('Name')),
                    DropdownMenuItem(value: 'members', child: Text('Members')),
                  ],
                  onChanged: (v) => setState(() => sortBy = v!),
                ),
              ],
            ),
          ),
          Expanded(
            child: isLoading
                ? const Center(
                    child: CircularProgressIndicator(color: AppColors.gold),
                  )
                : _filteredCoaches.isEmpty
                    ? const Center(
                        child: Text(
                          'No coaches found',
                          style: TextStyle(color: Colors.grey),
                        ),
                      )
                    : ListView.builder(
                        itemCount: _filteredCoaches.length,
                        itemBuilder: (context, index) {
                          final c = _filteredCoaches[index];
                          final isActive = c['is_active'] ?? true;
                          final memberCount =
                              (c['assigned_members'] as List?)?.length ?? 0;

                          return Container(
                            margin: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 4,
                            ),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: AppColors.cardDark,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        c['full_name'] ?? 'Unknown',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      Text(
                                        c['email'] ?? '',
                                        style: const TextStyle(
                                          color: Colors.grey,
                                          fontSize: 12,
                                        ),
                                      ),
                                      Text(
                                        '$memberCount members',
                                        style: const TextStyle(
                                          color: Colors.grey,
                                          fontSize: 11,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                IconButton(
                                  icon: Icon(
                                    Icons.edit,
                                    color: isActive ? Colors.blue : Colors.grey,
                                  ),
                                  onPressed: () =>
                                      _showCoachSettings(context, c),
                                ),
                                Switch(
                                  value: isActive,
                                  activeColor: AppColors.gold,
                                  onChanged: (_) async {
                                    await Supabase.instance.client
                                        .from('profiles')
                                        .update({'is_active': !isActive}).eq(
                                            'id', c['id']);
                                    _loadCoaches();
                                  },
                                ),
                              ],
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }

  void _showCoachSettings(BuildContext context, Map<String, dynamic> coach) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.cardDark,
      isScrollControlled: true,
      builder: (_) => CoachSettingsSheet(coach: coach),
    );
  }
}

class CoachSettingsSheet extends StatefulWidget {
  final Map<String, dynamic> coach;
  const CoachSettingsSheet({super.key, required this.coach});

  @override
  State<CoachSettingsSheet> createState() => _CoachSettingsSheetState();
}

class _CoachSettingsSheetState extends State<CoachSettingsSheet> {
  bool canEditDiet = false;
  bool canEditWorkout = false;
  bool isLoading = true;
  bool isSaving = false;

  @override
  void initState() {
    super.initState();
    _loadPermissions();
  }

  Future<void> _loadPermissions() async {
    setState(() => isLoading = true);
    try {
      final data = await Supabase.instance.client
          .from('coach_permissions')
          .select()
          .eq('coach_id', widget.coach['id'])
          .maybeSingle();

      setState(() {
        canEditDiet = data?['can_edit_diet'] ?? false;
        canEditWorkout = data?['can_edit_workout'] ?? false;
        isLoading = false;
      });
    } catch (e) {
      print('Error loading permissions: $e');
      setState(() => isLoading = false);
    }
  }

  Future<void> _savePermissions() async {
    setState(() => isSaving = true);
    try {
      await Supabase.instance.client.from('coach_permissions').upsert({
        'coach_id': widget.coach['id'],
        'can_edit_diet': canEditDiet,
        'can_edit_workout': canEditWorkout,
      }, onConflict: 'coach_id');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Permissions saved successfully!'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save permissions: $e')),
        );
      }
    } finally {
      setState(() => isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Permissions for ${widget.coach['full_name'] ?? 'Coach'}',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Enable or disable what this coach can do',
              style: TextStyle(
                color: Colors.grey.shade400,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 20),
            if (isLoading)
              const Center(
                child: CircularProgressIndicator(color: AppColors.gold),
              )
            else ...[
              SwitchListTile(
                title: const Text(
                  'Can Edit Diet',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                subtitle: Text(
                  canEditDiet
                      ? 'Coach can create and modify member diets'
                      : 'Coach can only view diets',
                  style: TextStyle(
                    color: canEditDiet ? Colors.green : Colors.grey,
                    fontSize: 12,
                  ),
                ),
                value: canEditDiet,
                activeColor: AppColors.gold,
                activeTrackColor: AppColors.gold.withOpacity(0.3),
                inactiveTrackColor: Colors.grey.shade700,
                onChanged: (v) => setState(() => canEditDiet = v),
              ),
              const Divider(color: Colors.white12, height: 1),
              SwitchListTile(
                title: const Text(
                  'Can Edit Workout',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                subtitle: Text(
                  canEditWorkout
                      ? 'Coach can create and modify member workouts'
                      : 'Coach can only view workouts',
                  style: TextStyle(
                    color: canEditWorkout ? Colors.green : Colors.grey,
                    fontSize: 12,
                  ),
                ),
                value: canEditWorkout,
                activeColor: AppColors.gold,
                activeTrackColor: AppColors.gold.withOpacity(0.3),
                inactiveTrackColor: Colors.grey.shade700,
                onChanged: (v) => setState(() => canEditWorkout = v),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: isSaving ? null : _savePermissions,
                  child: isSaving
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.black,
                          ),
                        )
                      : const Text('SAVE PERMISSIONS'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ============================================================
// SETTINGS TAB
// ============================================================
class AdminSettingsTab extends StatelessWidget {
  const AdminSettingsTab({super.key});

  @override
  Widget build(BuildContext context) {
    return const AdminSettingsScreen();
  }
}

// ============================================================
// MEMBER PAYMENT SHEET
// ============================================================
class MemberPaymentSheet extends StatefulWidget {
  final Map<String, dynamic> member;
  final VoidCallback onPaymentComplete;

  const MemberPaymentSheet({
    super.key,
    required this.member,
    required this.onPaymentComplete,
  });

  @override
  State<MemberPaymentSheet> createState() => _MemberPaymentSheetState();
}

class _MemberPaymentSheetState extends State<MemberPaymentSheet> {
  bool isLoading = true;
  bool isProcessing = false;
  Map<String, dynamic>? pricing;
  Map<String, dynamic>? memberPricing;
  List<Map<String, dynamic>> payments = [];
  String? selectedPlan;
  bool useCustomAmount = false;
  final TextEditingController _customAmountController = TextEditingController();
  final TextEditingController _notesController = TextEditingController();
  bool isCashPayment = false;

  final List<Map<String, dynamic>> _plans = [
    {'key': '1_month', 'label': '1 Month', 'months': 1},
    {'key': '3_month', 'label': '3 Months', 'months': 3},
    {'key': '6_month', 'label': '6 Months', 'months': 6},
    {'key': '1_year', 'label': '1 Year', 'months': 12},
  ];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _customAmountController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => isLoading = true);
    try {
      pricing =
          await Supabase.instance.client.from('pricing').select().maybeSingle();

      memberPricing = await Supabase.instance.client
          .from('member_pricing')
          .select()
          .eq('member_id', widget.member['id'])
          .maybeSingle();

      final paymentData = await Supabase.instance.client
          .from('payments')
          .select()
          .eq('member_id', widget.member['id'])
          .order('payment_date', ascending: false);

      payments = List<Map<String, dynamic>>.from(paymentData);

      setState(() => isLoading = false);
    } catch (e) {
      print('Error loading data: $e');
      setState(() => isLoading = false);
    }
  }

  double getPlanPrice(String planKey) {
    if (memberPricing != null && memberPricing![planKey] != null) {
      return (memberPricing![planKey] as num).toDouble();
    }
    return (pricing?[planKey] as num?)?.toDouble() ?? 0;
  }

  Future<void> _processPayment() async {
    if (selectedPlan == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a plan')),
      );
      return;
    }

    setState(() => isProcessing = true);

    try {
      final plan = _plans.firstWhere((p) => p['key'] == selectedPlan);
      final amount = useCustomAmount
          ? double.tryParse(_customAmountController.text) ?? 0
          : getPlanPrice(selectedPlan!);
      final months = plan['months'] as int;

      final currentEndDate = widget.member['membership_end_date'] != null
          ? DateTime.parse(widget.member['membership_end_date'])
          : DateTime.now();

      final now = DateTime.now();

      DateTime newEndDate;
      if (currentEndDate.isAfter(now)) {
        newEndDate = DateTime(
          currentEndDate.year,
          currentEndDate.month + months,
          currentEndDate.day,
        );
      } else {
        newEndDate = DateTime(
          now.year,
          now.month + months,
          now.day,
        );
      }

      await Supabase.instance.client.from('payments').insert({
        'member_id': widget.member['id'],
        'amount': amount,
        'plan_key': selectedPlan,
        'months': months,
        'status': 'completed',
        'payment_date': DateTime.now().toIso8601String(),
        'notes': _notesController.text.trim(),
        'is_cash': isCashPayment,
      });

      await Supabase.instance.client.from('profiles').update({
        'membership_end_date': newEndDate.toIso8601String().substring(0, 10),
      }).eq('id', widget.member['id']);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Payment recorded successfully!'),
            backgroundColor: Colors.green,
          ),
        );
        widget.onPaymentComplete();
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Payment failed: $e')),
        );
      }
    } finally {
      setState(() => isProcessing = false);
    }
  }

  Future<void> _setCustomPrice() async {
    final controller = TextEditingController();
    final result = await showDialog<double>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.cardDark,
        title: const Text(
          'Set Custom Price',
          style: TextStyle(color: Colors.white),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Override standard price for this member',
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                prefixText: '₹ ',
                hintText: 'Enter custom amount',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              final val = double.tryParse(controller.text);
              if (val != null && val > 0) {
                Navigator.pop(context, val);
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (result != null) {
      setState(() {
        useCustomAmount = true;
        _customAmountController.text = result.toString();
      });
    }
  }

  int _getDaysLeft(String? endDateStr) {
    if (endDateStr == null) return -1;
    try {
      final endDate = DateTime.parse(endDateStr);
      final now = DateTime.now();
      return endDate.difference(now).inDays;
    } catch (e) {
      return -1;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.gold),
      );
    }

    final daysLeft = _getDaysLeft(widget.member['membership_end_date']);

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        padding: const EdgeInsets.all(20),
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.9,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Payment for ${widget.member['full_name'] ?? 'Member'}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: daysLeft > 0
                        ? Colors.green.withOpacity(0.2)
                        : Colors.red.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: daysLeft > 0 ? Colors.green : Colors.red,
                    ),
                  ),
                  child: Text(
                    daysLeft > 0 ? '$daysLeft days left' : 'Expired',
                    style: TextStyle(
                      color: daysLeft > 0 ? Colors.green : Colors.red,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Text(
              'SELECT PLAN',
              style: TextStyle(
                color: AppColors.gold,
                fontSize: 12,
                fontWeight: FontWeight.bold,
                letterSpacing: 1,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _plans.map((plan) {
                final key = plan['key'] as String;
                final isSelected = selectedPlan == key;
                final price = getPlanPrice(key);
                return GestureDetector(
                  onTap: () {
                    setState(() {
                      selectedPlan = key;
                      useCustomAmount = false;
                    });
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? AppColors.gold.withOpacity(0.2)
                          : AppColors.cardDark,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: isSelected
                            ? AppColors.gold
                            : Colors.white.withOpacity(0.1),
                        width: isSelected ? 2 : 1,
                      ),
                    ),
                    child: Column(
                      children: [
                        Text(
                          plan['label'] as String,
                          style: TextStyle(
                            color: isSelected ? AppColors.gold : Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          '₹${price.toStringAsFixed(0)}',
                          style: TextStyle(
                            color: isSelected ? AppColors.gold : Colors.grey,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                if (memberPricing != null)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.orange.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Text(
                      'Custom Pricing Active',
                      style: TextStyle(
                        color: Colors.orange,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                const Spacer(),
                TextButton.icon(
                  icon: const Icon(Icons.edit, size: 16),
                  label: const Text('Set Custom Price'),
                  onPressed: _setCustomPrice,
                ),
              ],
            ),
            if (useCustomAmount) ...[
              const SizedBox(height: 8),
              TextField(
                controller: _customAmountController,
                keyboardType: TextInputType.number,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  prefixText: '₹ ',
                  labelText: 'Custom amount',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.all(Radius.circular(8)),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 12),
            TextField(
              controller: _notesController,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: 'Notes (optional)',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.all(Radius.circular(8)),
                ),
              ),
              maxLines: 2,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Checkbox(
                  value: isCashPayment,
                  onChanged: (v) => setState(() => isCashPayment = v ?? false),
                  activeColor: AppColors.gold,
                ),
                const Text(
                  'Cash payment (record manually)',
                  style: TextStyle(color: Colors.white),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: isProcessing ? null : _processPayment,
                child: isProcessing
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.black,
                        ),
                      )
                    : const Text('RECORD PAYMENT'),
              ),
            ),
            if (payments.isNotEmpty) ...[
              const Divider(color: Colors.white12),
              const SizedBox(height: 8),
              const Text(
                'PAYMENT HISTORY',
                style: TextStyle(
                  color: AppColors.gold,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1,
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: payments.length > 5 ? 5 : payments.length,
                  itemBuilder: (context, index) {
                    final p = payments[index];
                    final date = DateTime.parse(p['payment_date']);
                    return ListTile(
                      dense: true,
                      title: Text(
                        '₹${(p['amount'] as num).toStringAsFixed(0)}',
                        style: const TextStyle(color: Colors.white),
                      ),
                      subtitle: Text(
                        '${p['plan_key']} · ${date.day}/${date.month}/${date.year}',
                        style:
                            const TextStyle(color: Colors.grey, fontSize: 12),
                      ),
                      trailing: Text(
                        p['status'] ?? 'completed',
                        style: TextStyle(
                          color: p['status'] == 'completed'
                              ? Colors.green
                              : Colors.orange,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    );
                  },
                ),
              ),
              if (payments.length > 5)
                TextButton(
                  onPressed: () => _showFullPaymentHistory(),
                  child: const Text('View all payments'),
                ),
            ],
          ],
        ),
      ),
    );
  }

  void _showFullPaymentHistory() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.cardDark,
      isScrollControlled: true,
      builder: (_) => Container(
        padding: const EdgeInsets.all(20),
        height: MediaQuery.of(context).size.height * 0.7,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'All Payments',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: ListView.builder(
                itemCount: payments.length,
                itemBuilder: (context, index) {
                  final p = payments[index];
                  final date = DateTime.parse(p['payment_date']);
                  return ListTile(
                    title: Text(
                      '₹${(p['amount'] as num).toStringAsFixed(0)}',
                      style: const TextStyle(color: Colors.white),
                    ),
                    subtitle: Text(
                      '${p['plan_key']} · ${date.day}/${date.month}/${date.year}',
                      style: const TextStyle(color: Colors.grey),
                    ),
                    trailing: Text(
                      p['notes'] ?? '',
                      style: const TextStyle(color: Colors.grey, fontSize: 12),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
