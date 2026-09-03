import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../theme/app_theme.dart';

class AdminSettingsScreen extends StatefulWidget {
  const AdminSettingsScreen({super.key});

  @override
  State<AdminSettingsScreen> createState() => _AdminSettingsScreenState();
}

class _AdminSettingsScreenState extends State<AdminSettingsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        bottom: TabBar(
          controller: _tabController,
          isScrollable: MediaQuery.sizeOf(context).width < 600,
          indicatorColor: AppColors.gold,
          labelColor: AppColors.gold,
          unselectedLabelColor: Colors.grey,
          tabs: const [
            Tab(text: 'Standard Pricing'),
            Tab(text: 'Offers'),
            Tab(text: 'Exercises'),
            Tab(text: 'Food'),
            Tab(text: 'Categories'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: const [
          _StandardPricingTab(),
          _OffersTab(),
          _ExercisesTab(),
          _FoodTab(),
          _CategoriesTab(),
        ],
      ),
    );
  }
}

// ============================================================
// STANDARD PRICING TAB
// ============================================================
class _StandardPricingTab extends StatefulWidget {
  const _StandardPricingTab();

  @override
  State<_StandardPricingTab> createState() => _StandardPricingTabState();
}

class _StandardPricingTabState extends State<_StandardPricingTab> {
  bool isLoading = true;
  bool isSaving = false;
  final Map<String, TextEditingController> _controllers = {};
  String? pricingId;

  final List<Map<String, dynamic>> _plans = [
    {'key': '1_month', 'label': '1 Month'},
    {'key': '3_month', 'label': '3 Months'},
    {'key': '6_month', 'label': '6 Months'},
    {'key': '1_year', 'label': '12 Months'},
  ];

  @override
  void initState() {
    super.initState();
    _loadPrices();
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _loadPrices() async {
    setState(() => isLoading = true);
    try {
      final data = await Supabase.instance.client
          .from('pricing')
          .select()
          .limit(1)
          .maybeSingle();

      if (data != null) {
        pricingId = data['id'];
        for (final plan in _plans) {
          final key = plan['key'] as String;
          final value = data[key] as num?;
          _controllers[key] = TextEditingController(
            text: value?.toStringAsFixed(0) ?? '0',
          );
        }
      } else {
        // No pricing exists - create default
        final defaults = {
          '1_month': 1500,
          '3_month': 4000,
          '6_month': 7000,
          '1_year': 12000,
        };
        final result = await Supabase.instance.client
            .from('pricing')
            .insert(defaults)
            .select()
            .single();
        pricingId = result['id'];
        for (final plan in _plans) {
          final key = plan['key'] as String;
          _controllers[key] = TextEditingController(
            text: defaults[key].toString(),
          );
        }
      }

      setState(() => isLoading = false);
    } catch (e) {
      print('Error loading prices: $e');
      setState(() => isLoading = false);
    }
  }

  Future<void> _savePrices() async {
    if (pricingId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Error: No pricing record found')),
      );
      return;
    }

    setState(() => isSaving = true);

    try {
      final data = {
        for (final plan in _plans)
          plan['key']: double.tryParse(_controllers[plan['key']]!.text) ?? 0,
      };

      await Supabase.instance.client
          .from('pricing')
          .update(data)
          .eq('id', pricingId!);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Standard prices updated!')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to update: $e')),
        );
      }
    } finally {
      setState(() => isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.gold),
      );
    }

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'STANDARD PRICING',
            style: TextStyle(
              color: AppColors.gold,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'These prices apply to ALL members by default.',
            style: TextStyle(color: Colors.grey, fontSize: 13),
          ),
          const SizedBox(height: 24),
          ..._plans.map((plan) => Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: Row(
                  children: [
                    SizedBox(
                      width: 120,
                      child: Text(
                        plan['label'] as String,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    Expanded(
                      child: TextField(
                        controller: _controllers[plan['key']],
                        keyboardType: TextInputType.number,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                        ),
                        decoration: const InputDecoration(
                          prefixText: '₹ ',
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.all(Radius.circular(8)),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              )),
          const Spacer(),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: isSaving ? null : _savePrices,
              child: isSaving
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.black,
                      ),
                    )
                  : const Text('SAVE STANDARD PRICES'),
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }
}

// ============================================================
// OFFERS TAB
// ============================================================
class _OffersTab extends StatefulWidget {
  const _OffersTab();

  @override
  State<_OffersTab> createState() => _OffersTabState();
}

class _OffersTabState extends State<_OffersTab> {
  List<Map<String, dynamic>> offers = [];
  List<Map<String, dynamic>> filteredOffers = [];
  List<Map<String, dynamic>> allMembers = [];
  List<Map<String, dynamic>> filteredMembers = [];
  bool isLoading = true;
  String searchQuery = '';
  String offerSearchQuery = '';
  bool isMultiSelectMode = false;
  final Set<String> _selectedMemberIds = {};

  final List<Map<String, dynamic>> _plans = [
    {'key': '1_month', 'label': '1 Month'},
    {'key': '3_month', 'label': '3 Months'},
    {'key': '6_month', 'label': '6 Months'},
    {'key': '1_year', 'label': '12 Months'},
  ];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => isLoading = true);
    try {
      // Load offers with member counts
      final offersData = await Supabase.instance.client
          .from('offers')
          .select('*, offer_members(count)')
          .order('created_at', ascending: false);

      final membersData = await Supabase.instance.client
          .from('profiles')
          .select('id, full_name, email')
          .eq('role', 'member')
          .order('full_name');

      setState(() {
        offers = List<Map<String, dynamic>>.from(offersData);
        filteredOffers = List<Map<String, dynamic>>.from(offersData);
        allMembers = List<Map<String, dynamic>>.from(membersData);
        filteredMembers = List<Map<String, dynamic>>.from(membersData);
        isLoading = false;
      });
    } catch (e) {
      print('Error loading data: $e');
      setState(() => isLoading = false);
    }
  }

  void _applySearch() {
    if (searchQuery.isEmpty) {
      setState(() {
        filteredMembers = List<Map<String, dynamic>>.from(allMembers);
      });
      return;
    }

    final q = searchQuery.toLowerCase();
    setState(() {
      filteredMembers = allMembers.where((m) {
        final name = (m['full_name'] ?? '').toString().toLowerCase();
        final email = (m['email'] ?? '').toString().toLowerCase();
        return name.contains(q) || email.contains(q);
      }).toList();
    });
  }

  void _applyOfferSearch() {
    if (offerSearchQuery.isEmpty) {
      setState(() {
        filteredOffers = List<Map<String, dynamic>>.from(offers);
      });
      return;
    }

    final q = offerSearchQuery.toLowerCase();
    setState(() {
      filteredOffers = offers.where((o) {
        final name = (o['name'] ?? '').toString().toLowerCase();
        return name.contains(q);
      }).toList();
    });
  }

  Future<void> _createOffer() async {
    final nameController = TextEditingController();
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.cardDark,
        title: const Text(
          'Create New Offer',
          style: TextStyle(color: Colors.white),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Enter a name for this offer (e.g. Summer Sale, New Year Offer)',
              style: TextStyle(color: Colors.grey, fontSize: 12),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: nameController,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                hintText: 'Enter offer name',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.all(Radius.circular(8)),
                ),
              ),
              autofocus: true,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              if (nameController.text.trim().isNotEmpty) {
                Navigator.pop(context, true);
              }
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );

    if (result == true && nameController.text.trim().isNotEmpty) {
      await Supabase.instance.client.from('offers').insert({
        'name': nameController.text.trim(),
        '1_month': 0,
        '3_month': 0,
        '6_month': 0,
        '1_year': 0,
      });
      _loadData();
    }
  }

  Future<void> _deleteOffer(String offerId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.cardDark,
        title: const Text(
          'Delete Offer?',
          style: TextStyle(color: Colors.white),
        ),
        content: const Text(
          'This will remove the offer and members will revert to standard pricing.',
          style: TextStyle(color: Colors.grey),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await Supabase.instance.client.from('offers').delete().eq('id', offerId);
      _loadData();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.gold),
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              const Expanded(
                child: Text(
                  'Create custom offers with discounted pricing for selected members.',
                  style: TextStyle(color: Colors.grey, fontSize: 13),
                ),
              ),
              ElevatedButton.icon(
                icon: const Icon(Icons.add, size: 18),
                label: const Text('New Offer'),
                onPressed: _createOffer,
              ),
            ],
          ),
        ),
        // Offer Search Bar
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: TextField(
            style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(
              hintText: 'Search offers...',
              prefixIcon: Icon(Icons.search, color: Colors.grey),
              isDense: true,
              contentPadding: EdgeInsets.symmetric(vertical: 8),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.all(Radius.circular(8)),
              ),
            ),
            onChanged: (v) {
              setState(() {
                offerSearchQuery = v.trim();
                _applyOfferSearch();
              });
            },
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: filteredOffers.isEmpty
              ? const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.local_offer_outlined,
                          color: Colors.grey, size: 48),
                      SizedBox(height: 12),
                      Text(
                        'No offers found',
                        style: TextStyle(color: Colors.grey, fontSize: 16),
                      ),
                      SizedBox(height: 8),
                      Text(
                        'Tap "New Offer" to create one',
                        style: TextStyle(color: Colors.grey, fontSize: 13),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  itemCount: filteredOffers.length,
                  itemBuilder: (context, index) {
                    final offer = filteredOffers[index];
                    final memberCount =
                        (offer['offer_members'] as List?)?.length ?? 0;
                    return _OfferCard(
                      offer: offer,
                      memberCount: memberCount,
                      allMembers: allMembers,
                      plans: _plans,
                      onRefresh: _loadData,
                      onDelete: () => _deleteOffer(offer['id']),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

// ============================================================
// OFFER CARD
// ============================================================
class _OfferCard extends StatefulWidget {
  final Map<String, dynamic> offer;
  final int memberCount;
  final List<Map<String, dynamic>> allMembers;
  final List<Map<String, dynamic>> plans;
  final VoidCallback onRefresh;
  final VoidCallback onDelete;

  const _OfferCard({
    required this.offer,
    required this.memberCount,
    required this.allMembers,
    required this.plans,
    required this.onRefresh,
    required this.onDelete,
  });

  @override
  State<_OfferCard> createState() => _OfferCardState();
}

class _OfferCardState extends State<_OfferCard> {
  bool isExpanded = false;
  bool isEditing = false;
  bool isMultiSelectMode = false;
  final Map<String, TextEditingController> _controllers = {};
  final List<String> _assignedMemberIds = [];
  final List<Map<String, dynamic>> _assignedMembers = [];
  final Set<String> _selectedMemberIds = {};

  @override
  void initState() {
    super.initState();
    _loadAssignedMembers();
    _initControllers();
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  void _initControllers() {
    for (final plan in widget.plans) {
      final key = plan['key'] as String;
      final value = widget.offer[key] as num? ?? 0;
      _controllers[key] = TextEditingController(
        text: value.toStringAsFixed(0),
      );
    }
  }

  Future<void> _loadAssignedMembers() async {
    try {
      final data = await Supabase.instance.client
          .from('offer_members')
          .select('member_id, profiles(id, full_name, email)')
          .eq('offer_id', widget.offer['id']);

      setState(() {
        _assignedMembers.clear();
        _assignedMemberIds.clear();
        for (final item in data) {
          final profile = item['profiles'] as Map<String, dynamic>?;
          if (profile != null) {
            _assignedMembers.add(profile);
            _assignedMemberIds.add(profile['id']);
          }
        }
      });
    } catch (e) {
      print('Error loading assigned members: $e');
    }
  }

  Future<void> _saveOfferPrices() async {
    final data = {
      for (final plan in widget.plans)
        plan['key']: double.tryParse(_controllers[plan['key']]!.text) ?? 0,
    };

    await Supabase.instance.client
        .from('offers')
        .update(data)
        .eq('id', widget.offer['id']);

    setState(() => isEditing = false);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Offer prices updated!')),
      );
    }
    widget.onRefresh();
  }

  Future<void> _editOfferName() async {
    final controller = TextEditingController(text: widget.offer['name']);
    final result = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.cardDark,
        title: const Text(
          'Edit Offer Name',
          style: TextStyle(color: Colors.white),
        ),
        content: TextField(
          controller: controller,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            hintText: 'Enter offer name',
            border: OutlineInputBorder(
              borderRadius: BorderRadius.all(Radius.circular(8)),
            ),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              if (controller.text.trim().isNotEmpty) {
                Navigator.pop(context, controller.text.trim());
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (result != null) {
      await Supabase.instance.client
          .from('offers')
          .update({'name': result}).eq('id', widget.offer['id']);
      widget.onRefresh();
    }
  }

  Future<void> _addMember() async {
    // Get members NOT already assigned to ANY offer
    final assignedMemberIds = await Supabase.instance.client
        .from('offer_members')
        .select('member_id');

    final assignedIds =
        assignedMemberIds.map((e) => e['member_id'] as String).toSet();

    final availableMembers =
        widget.allMembers.where((m) => !assignedIds.contains(m['id'])).toList();

    if (availableMembers.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('All members already have an offer assigned'),
        ),
      );
      return;
    }

    final Set<String> selectedMemberIds = {};
    bool isSelectAll = false;
    String memberSearchQuery = '';
    List<Map<String, dynamic>> filteredMembers = List.from(availableMembers);

    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.cardDark,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) {
          void applyMemberSearch(String query) {
            final q = query.toLowerCase().trim();
            setSheetState(() {
              if (q.isEmpty) {
                filteredMembers = List.from(availableMembers);
              } else {
                filteredMembers = availableMembers.where((m) {
                  final name = (m['full_name'] ?? '').toString().toLowerCase();
                  final email = (m['email'] ?? '').toString().toLowerCase();
                  return name.contains(q) || email.contains(q);
                }).toList();
              }
            });
          }

          void toggleMemberSelection(String memberId) {
            setSheetState(() {
              if (selectedMemberIds.contains(memberId)) {
                selectedMemberIds.remove(memberId);
              } else {
                selectedMemberIds.add(memberId);
              }
            });
          }

          void toggleSelectAll() {
            setSheetState(() {
              final currentFiltered = filteredMembers;
              if (selectedMemberIds.length == currentFiltered.length) {
                selectedMemberIds.clear();
                isSelectAll = false;
              } else {
                selectedMemberIds.clear();
                for (final m in currentFiltered) {
                  selectedMemberIds.add(m['id']);
                }
                isSelectAll = true;
              }
            });
          }

          return Container(
            height: MediaQuery.of(context).size.height * 0.75,
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Add Members',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Select members to assign to this offer',
                  style: TextStyle(color: Colors.grey),
                ),
                const SizedBox(height: 10),
                TextField(
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    hintText: 'Search members...',
                    prefixIcon: Icon(Icons.search, color: Colors.grey),
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(vertical: 8),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.all(Radius.circular(8)),
                    ),
                  ),
                  onChanged: (v) {
                    applyMemberSearch(v.trim());
                  },
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Text(
                      '${selectedMemberIds.length} selected',
                      style: TextStyle(
                        color: selectedMemberIds.isNotEmpty
                            ? AppColors.gold
                            : Colors.grey,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const Spacer(),
                    if (filteredMembers.isNotEmpty)
                      TextButton(
                        onPressed: toggleSelectAll,
                        child: Text(
                          selectedMemberIds.length == filteredMembers.length
                              ? 'Deselect All'
                              : 'Select All',
                          style: TextStyle(
                            color: AppColors.gold,
                            fontSize: 12,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Expanded(
                  child: filteredMembers.isEmpty
                      ? Center(
                          child: Text(
                            'No members found',
                            style: TextStyle(color: Colors.grey),
                          ),
                        )
                      : ListView.builder(
                          itemCount: filteredMembers.length,
                          itemBuilder: (context, index) {
                            final m = filteredMembers[index];
                            final isSelected =
                                selectedMemberIds.contains(m['id']);
                            return ListTile(
                              leading: Container(
                                width: 24,
                                height: 24,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: isSelected
                                      ? AppColors.gold
                                      : Colors.transparent,
                                  border: Border.all(
                                    color: isSelected
                                        ? AppColors.gold
                                        : Colors.grey,
                                    width: 1.5,
                                  ),
                                ),
                                child: isSelected
                                    ? const Icon(
                                        Icons.check,
                                        size: 16,
                                        color: Colors.black,
                                      )
                                    : null,
                              ),
                              title: Text(
                                m['full_name'] ?? 'Unknown',
                                style: TextStyle(
                                  color: isSelected
                                      ? AppColors.gold
                                      : Colors.white,
                                ),
                              ),
                              subtitle: Text(
                                m['email'] ?? '',
                                style: const TextStyle(color: Colors.grey),
                              ),
                              onTap: () => toggleMemberSelection(m['id']),
                            );
                          },
                        ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: selectedMemberIds.isEmpty
                        ? null
                        : () {
                            for (final memberId in selectedMemberIds) {
                              _assignMember(memberId);
                            }
                            Navigator.pop(context);
                          },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.gold,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: Text(
                      'Assign ${selectedMemberIds.length} Member${selectedMemberIds.length > 1 ? 's' : ''}',
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _assignMember(String memberId) async {
    await Supabase.instance.client.from('offer_members').insert({
      'offer_id': widget.offer['id'],
      'member_id': memberId,
    });
    widget.onRefresh();
    _loadAssignedMembers();
  }

  Future<void> _removeMember(String memberId) async {
    await Supabase.instance.client
        .from('offer_members')
        .delete()
        .eq('offer_id', widget.offer['id'])
        .eq('member_id', memberId);
    _loadAssignedMembers();
    widget.onRefresh();
  }

  Future<void> _removeSelectedMembers() async {
    if (_selectedMemberIds.isEmpty) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.cardDark,
        title: const Text(
          'Remove Members?',
          style: TextStyle(color: Colors.white),
        ),
        content: Text(
          'Remove ${_selectedMemberIds.length} selected member${_selectedMemberIds.length > 1 ? 's' : ''} from this offer?',
          style: const TextStyle(color: Colors.grey),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Remove'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      for (final memberId in _selectedMemberIds) {
        await Supabase.instance.client
            .from('offer_members')
            .delete()
            .eq('offer_id', widget.offer['id'])
            .eq('member_id', memberId);
      }
      setState(() {
        _selectedMemberIds.clear();
        isMultiSelectMode = false;
      });
      _loadAssignedMembers();
      widget.onRefresh();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${_selectedMemberIds.length} members removed'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to remove members: $e')),
        );
      }
    }
  }

  void _toggleMemberSelection(String memberId) {
    setState(() {
      if (_selectedMemberIds.contains(memberId)) {
        _selectedMemberIds.remove(memberId);
      } else {
        _selectedMemberIds.add(memberId);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.cardDark,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: Column(
        children: [
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16),
            leading: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: AppColors.gold.withOpacity(0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                Icons.local_offer,
                color: AppColors.gold,
                size: 20,
              ),
            ),
            title: Row(
              children: [
                Text(
                  widget.offer['name'] ?? 'Unnamed Offer',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.gold.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${widget.memberCount}',
                    style: TextStyle(
                      color: AppColors.gold,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.edit_outlined, size: 20),
                  color: Colors.grey,
                  onPressed: _editOfferName,
                ),
                IconButton(
                  icon: Icon(
                    isExpanded ? Icons.expand_less : Icons.expand_more,
                  ),
                  color: Colors.grey,
                  onPressed: () => setState(() => isExpanded = !isExpanded),
                ),
              ],
            ),
          ),
          if (isExpanded) ...[
            const Divider(color: Colors.white12, height: 1),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Expanded(
                        flex: 2,
                        child: Text(
                          'Plan',
                          style: TextStyle(
                            color: Colors.grey,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ),
                      Expanded(
                        flex: 2,
                        child: Text(
                          'Amount (₹)',
                          style: TextStyle(
                            color: Colors.grey,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ),
                      const SizedBox(width: 40),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ...widget.plans.map((plan) {
                    final key = plan['key'] as String;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        children: [
                          Expanded(
                            flex: 2,
                            child: Text(
                              plan['label'] as String,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                              ),
                            ),
                          ),
                          Expanded(
                            flex: 2,
                            child: TextField(
                              controller: _controllers[key],
                              keyboardType: TextInputType.number,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                              ),
                              decoration: const InputDecoration(
                                prefixText: '₹ ',
                                isDense: true,
                                contentPadding: EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 6,
                                ),
                                border: OutlineInputBorder(
                                  borderRadius:
                                      BorderRadius.all(Radius.circular(6)),
                                ),
                              ),
                              readOnly: !isEditing,
                            ),
                          ),
                          const SizedBox(width: 40),
                        ],
                      ),
                    );
                  }),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      if (!isEditing)
                        ElevatedButton.icon(
                          icon: const Icon(Icons.edit, size: 16),
                          label: const Text('Edit Prices'),
                          onPressed: () => setState(() => isEditing = true),
                        )
                      else ...[
                        ElevatedButton.icon(
                          icon: const Icon(Icons.save, size: 16),
                          label: const Text('Save'),
                          onPressed: _saveOfferPrices,
                        ),
                        const SizedBox(width: 8),
                        TextButton(
                          onPressed: () {
                            setState(() => isEditing = false);
                            _initControllers();
                          },
                          child: const Text('Cancel'),
                        ),
                      ],
                    ],
                  ),
                  const Divider(color: Colors.white12, height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          const Text(
                            'Assigned Members',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                          if (_selectedMemberIds.isNotEmpty)
                            Container(
                              margin: const EdgeInsets.only(left: 8),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.gold.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                '${_selectedMemberIds.length} selected',
                                style: TextStyle(
                                  color: AppColors.gold,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                        ],
                      ),
                      Row(
                        children: [
                          if (_selectedMemberIds.isNotEmpty)
                            TextButton.icon(
                              icon: const Icon(Icons.delete,
                                  size: 16, color: Colors.red),
                              label: const Text(
                                'Remove Selected',
                                style: TextStyle(color: Colors.red),
                              ),
                              onPressed: _removeSelectedMembers,
                            ),
                          TextButton.icon(
                            icon: Icon(
                              isMultiSelectMode ? Icons.close : Icons.check_box,
                              size: 16,
                              color: isMultiSelectMode
                                  ? AppColors.gold
                                  : Colors.grey,
                            ),
                            label: Text(
                              isMultiSelectMode ? 'Done' : 'Select',
                              style: TextStyle(
                                color: isMultiSelectMode
                                    ? AppColors.gold
                                    : Colors.grey,
                              ),
                            ),
                            onPressed: () {
                              setState(() {
                                isMultiSelectMode = !isMultiSelectMode;
                                if (!isMultiSelectMode) {
                                  _selectedMemberIds.clear();
                                }
                              });
                            },
                          ),
                          TextButton.icon(
                            icon: const Icon(Icons.add, size: 16),
                            label: const Text('Add Member'),
                            onPressed: _addMember,
                          ),
                        ],
                      ),
                    ],
                  ),
                  if (_assignedMembers.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: Text(
                        'No members assigned',
                        style: TextStyle(color: Colors.grey, fontSize: 13),
                      ),
                    )
                  else
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _assignedMembers.map((m) {
                        final memberId = m['id'] as String;
                        final isSelected =
                            _selectedMemberIds.contains(memberId);
                        return GestureDetector(
                          onTap: isMultiSelectMode
                              ? () => _toggleMemberSelection(memberId)
                              : null,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? AppColors.gold.withOpacity(0.2)
                                  : Colors.white.withOpacity(0.05),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: isSelected
                                    ? AppColors.gold
                                    : Colors.white.withOpacity(0.1),
                                width: isSelected ? 1.5 : 1,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (isMultiSelectMode)
                                  Container(
                                    width: 16,
                                    height: 16,
                                    margin: const EdgeInsets.only(right: 4),
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: isSelected
                                          ? AppColors.gold
                                          : Colors.transparent,
                                      border: Border.all(
                                        color: isSelected
                                            ? AppColors.gold
                                            : Colors.grey,
                                        width: 1.5,
                                      ),
                                    ),
                                    child: isSelected
                                        ? const Icon(
                                            Icons.check,
                                            size: 10,
                                            color: Colors.black,
                                          )
                                        : null,
                                  ),
                                Text(
                                  m['full_name'] ?? 'Unknown',
                                  style: TextStyle(
                                    color: isSelected
                                        ? AppColors.gold
                                        : Colors.white,
                                    fontSize: 12,
                                  ),
                                ),
                                if (!isMultiSelectMode) ...[
                                  const SizedBox(width: 4),
                                  GestureDetector(
                                    onTap: () => _removeMember(memberId),
                                    child: const Icon(
                                      Icons.close,
                                      size: 14,
                                      color: Colors.grey,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      icon: const Icon(Icons.delete_outline, size: 16),
                      label: const Text('Delete Offer'),
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.red,
                      ),
                      onPressed: widget.onDelete,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ============================================================
// EXERCISES TAB
// ============================================================
class _ExercisesTab extends StatefulWidget {
  const _ExercisesTab();

  @override
  State<_ExercisesTab> createState() => _ExercisesTabState();
}

class _ExercisesTabState extends State<_ExercisesTab> {
  bool isLoading = true;
  List<Map<String, dynamic>> exercises = [];
  String search = '';

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    setState(() => isLoading = true);
    try {
      final data = await Supabase.instance.client
          .from('exercises')
          .select()
          .order('body_part')
          .order('name');
      setState(() {
        exercises = List<Map<String, dynamic>>.from(data);
        isLoading = false;
      });
    } catch (e) {
      print('Error loading exercises: $e');
      setState(() => isLoading = false);
    }
  }

  static const Map<String, List<String>> _muscleGroupsByCategory = {
    'Lower': ['Quads', 'Hamstrings', 'Calves'],
    'Upper': [
      'Back',
      'Chest',
      'Shoulders',
      'Traps',
      'Biceps',
      'Triceps',
      'Overall',
      'Abs',
    ],
    'Upper/Lower': ['Cardio'],
  };

  static const List<String> _typeOptions = ['Free', 'Weighted'];

  static const List<String> _inputOptions = ['Reps', 'kg × reps', 'Min'];

  Future<void> addExercise() async {
    final nameController = TextEditingController();
    String selectedCategory = _muscleGroupsByCategory.keys.first;
    String selectedMuscleGroup = _muscleGroupsByCategory[selectedCategory]![0];
    String selectedType = _typeOptions[0];
    String selectedInput = _inputOptions[0];

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: AppColors.cardDark,
          title:
              const Text('Add Exercise', style: TextStyle(color: Colors.white)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  value: selectedCategory,
                  dropdownColor: AppColors.cardDark,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    labelText: 'Category',
                    labelStyle: TextStyle(color: Colors.grey),
                    border: OutlineInputBorder(),
                  ),
                  items: _muscleGroupsByCategory.keys
                      .map((category) => DropdownMenuItem<String>(
                            value: category,
                            child: Text(category),
                          ))
                      .toList(),
                  onChanged: (value) {
                    if (value == null) return;
                    setDialogState(() {
                      selectedCategory = value;
                      selectedMuscleGroup = _muscleGroupsByCategory[value]![0];
                    });
                  },
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: selectedMuscleGroup,
                  dropdownColor: AppColors.cardDark,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    labelText: 'Muscle Group',
                    labelStyle: TextStyle(color: Colors.grey),
                    border: OutlineInputBorder(),
                  ),
                  items: _muscleGroupsByCategory[selectedCategory]!
                      .map((muscleGroup) => DropdownMenuItem<String>(
                            value: muscleGroup,
                            child: Text(muscleGroup),
                          ))
                      .toList(),
                  onChanged: (value) {
                    if (value == null) return;
                    setDialogState(() => selectedMuscleGroup = value);
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: nameController,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    labelText: 'Exercise Name',
                    labelStyle: TextStyle(color: Colors.grey),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: selectedType,
                  dropdownColor: AppColors.cardDark,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    labelText: 'Type',
                    labelStyle: TextStyle(color: Colors.grey),
                    border: OutlineInputBorder(),
                  ),
                  items: _typeOptions
                      .map((type) => DropdownMenuItem<String>(
                            value: type,
                            child: Text(type),
                          ))
                      .toList(),
                  onChanged: (value) {
                    if (value == null) return;
                    setDialogState(() => selectedType = value);
                  },
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: selectedInput,
                  dropdownColor: AppColors.cardDark,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    labelText: 'Input',
                    labelStyle: TextStyle(color: Colors.grey),
                    border: OutlineInputBorder(),
                  ),
                  items: _inputOptions
                      .map((input) => DropdownMenuItem<String>(
                            value: input,
                            child: Text(input),
                          ))
                      .toList(),
                  onChanged: (value) {
                    if (value == null) return;
                    setDialogState(() => selectedInput = value);
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              onPressed: () {
                if (nameController.text.trim().isNotEmpty) {
                  Navigator.pop(context, true);
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.gold,
                foregroundColor: Colors.black,
              ),
              child: const Text('Add'),
            ),
          ],
        ),
      ),
    );

    if (confirmed != true) return;

    try {
      await Supabase.instance.client.from('exercises').insert({
        'body_part': selectedCategory,
        'category': selectedCategory,
        'muscle_group': selectedMuscleGroup,
        'name': nameController.text.trim(),
        'exercise_type': selectedType,
        'input_type': selectedInput,
      });
      await load();
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Exercise added')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Failed: $e')));
      }
    }
  }

  Future<void> deleteExercise(String id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.cardDark,
        title: const Text('Delete Exercise?',
            style: TextStyle(color: Colors.white)),
        content: const Text(
          'This removes it from the exercise library. Existing workouts that already use it are unaffected.',
          style: TextStyle(color: Colors.grey),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await Supabase.instance.client.from('exercises').delete().eq('id', id);
      await load();
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Exercise deleted')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Failed: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final filtered = search.isEmpty
        ? exercises
        : exercises
            .where((e) =>
                (e['name'] ?? '')
                    .toString()
                    .toLowerCase()
                    .contains(search.toLowerCase()) ||
                (e['body_part'] ?? '')
                    .toString()
                    .toLowerCase()
                    .contains(search.toLowerCase()))
            .toList();

    final Map<String, List<Map<String, dynamic>>> grouped = {};
    for (final e in filtered) {
      grouped.putIfAbsent(e['body_part'] ?? 'Other', () => []).add(e);
    }

    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton(
        backgroundColor: AppColors.gold,
        onPressed: addExercise,
        child: const Icon(Icons.add, color: Colors.black),
      ),
      body: isLoading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.gold))
          : RefreshIndicator(
              onRefresh: load,
              color: AppColors.gold,
              backgroundColor: AppColors.cardDark,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: TextField(
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                        labelText: 'Search exercises or body part',
                        labelStyle: TextStyle(color: Colors.grey),
                        prefixIcon: Icon(Icons.search, color: Colors.grey),
                        border: OutlineInputBorder(),
                        filled: true,
                        fillColor: AppColors.cardDark,
                      ),
                      onChanged: (v) => setState(() => search = v.trim()),
                    ),
                  ),
                  Expanded(
                    child: grouped.isEmpty
                        ? const Center(
                            child: Text('No exercises found',
                                style: TextStyle(color: Colors.grey)),
                          )
                        : ListView(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            children: grouped.entries
                                .map((entry) => Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Padding(
                                          padding: const EdgeInsets.symmetric(
                                              vertical: 8),
                                          child: Text(
                                            entry.key.toUpperCase(),
                                            style: const TextStyle(
                                                color: AppColors.gold,
                                                fontWeight: FontWeight.bold,
                                                fontSize: 12,
                                                letterSpacing: 1),
                                          ),
                                        ),
                                        ...entry.value.map((ex) => Card(
                                              color: AppColors.cardDark,
                                              margin: const EdgeInsets.only(
                                                  bottom: 8),
                                              child: ListTile(
                                                title: Text(ex['name'] ?? '',
                                                    style: const TextStyle(
                                                        color: Colors.white)),
                                                trailing: IconButton(
                                                  icon: const Icon(
                                                      Icons.delete_outline,
                                                      color: Colors.redAccent),
                                                  onPressed: () =>
                                                      deleteExercise(ex['id']),
                                                ),
                                              ),
                                            )),
                                      ],
                                    ))
                                .toList(),
                          ),
                  ),
                ],
              ),
            ),
    );
  }
}

// ============================================================
// FOOD TAB
// ============================================================
class _FoodTab extends StatefulWidget {
  const _FoodTab();

  @override
  State<_FoodTab> createState() => _FoodTabState();
}

class _FoodTabState extends State<_FoodTab> {
  bool isLoading = true;
  List<Map<String, dynamic>> foods = [];
  String search = '';

  final List<String> _unitOptions = ['gm', 'ml', 'scoop'];
  String _selectedUnit = 'gm';

  final List<String> _categoryOptions = ['Veg', 'Non-Veg'];
  String _selectedCategory = 'Veg';

  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _qtyController = TextEditingController(text: '0');
  final TextEditingController _calController = TextEditingController(text: '0');
  final TextEditingController _proteinController =
      TextEditingController(text: '0');
  final TextEditingController _carbsController =
      TextEditingController(text: '0');
  final TextEditingController _fatsController =
      TextEditingController(text: '0');

  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _qtyController.dispose();
    _calController.dispose();
    _proteinController.dispose();
    _carbsController.dispose();
    _fatsController.dispose();
    super.dispose();
  }

  Future<void> load() async {
    setState(() => isLoading = true);
    try {
      final data =
          await Supabase.instance.client.from('foods').select().order('name');

      setState(() {
        foods = List<Map<String, dynamic>>.from(data);
        isLoading = false;
      });
    } catch (e) {
      print('Error loading foods: $e');
      setState(() => isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading foods: $e')),
        );
      }
    }
  }

  void _resetForm() {
    _nameController.clear();
    _qtyController.text = '0';
    _calController.text = '0';
    _proteinController.text = '0';
    _carbsController.text = '0';
    _fatsController.text = '0';
    _selectedUnit = 'gm';
    _selectedCategory = 'Veg';
  }

  Future<void> addFood() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: AppColors.cardDark,
          title: const Text('Add Food', style: TextStyle(color: Colors.white)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: _nameController,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    labelText: 'Food Name *',
                    labelStyle: TextStyle(color: Colors.grey),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _qtyController,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    labelText: 'Base Quantity',
                    labelStyle: TextStyle(color: Colors.grey),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  value: _selectedUnit,
                  dropdownColor: AppColors.cardDark,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    labelText: 'Unit',
                    labelStyle: TextStyle(color: Colors.grey),
                    border: OutlineInputBorder(),
                  ),
                  items: _unitOptions.map((unit) {
                    return DropdownMenuItem<String>(
                      value: unit,
                      child: Text(unit,
                          style: const TextStyle(color: Colors.white)),
                    );
                  }).toList(),
                  onChanged: (value) {
                    if (value != null) {
                      setDialogState(() => _selectedUnit = value);
                    }
                  },
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  value: _selectedCategory,
                  dropdownColor: AppColors.cardDark,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    labelText: 'Category',
                    labelStyle: TextStyle(color: Colors.grey),
                    border: OutlineInputBorder(),
                  ),
                  items: _categoryOptions.map((category) {
                    return DropdownMenuItem<String>(
                      value: category,
                      child: Text(category,
                          style: const TextStyle(color: Colors.white)),
                    );
                  }).toList(),
                  onChanged: (value) {
                    if (value != null) {
                      setDialogState(() => _selectedCategory = value);
                    }
                  },
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _calController,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        style: const TextStyle(color: Colors.white),
                        decoration: const InputDecoration(
                          labelText: 'Calories',
                          labelStyle: TextStyle(color: Colors.grey),
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _proteinController,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        style: const TextStyle(color: Colors.white),
                        decoration: const InputDecoration(
                          labelText: 'Protein (g)',
                          labelStyle: TextStyle(color: Colors.grey),
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _carbsController,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        style: const TextStyle(color: Colors.white),
                        decoration: const InputDecoration(
                          labelText: 'Carbs (g)',
                          labelStyle: TextStyle(color: Colors.grey),
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _fatsController,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        style: const TextStyle(color: Colors.white),
                        decoration: const InputDecoration(
                          labelText: 'Fats (g)',
                          labelStyle: TextStyle(color: Colors.grey),
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                _resetForm();
                Navigator.pop(context, false);
              },
              child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              onPressed: () {
                if (_nameController.text.trim().isNotEmpty) {
                  Navigator.pop(context, true);
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Please enter a food name')),
                  );
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.gold,
                foregroundColor: Colors.black,
              ),
              child: const Text('Add'),
            ),
          ],
        ),
      ),
    );

    if (confirmed != true) return;

    try {
      final newFood = {
        'name': _nameController.text.trim(),
        'base_quantity': double.tryParse(_qtyController.text.trim()) ?? 0,
        'base_unit': _selectedUnit,
        'calories': double.tryParse(_calController.text.trim()) ?? 0,
        'protein': double.tryParse(_proteinController.text.trim()) ?? 0,
        'carbs': double.tryParse(_carbsController.text.trim()) ?? 0,
        'fats': double.tryParse(_fatsController.text.trim()) ?? 0,
        'category': _selectedCategory,
      };

      await Supabase.instance.client.from('foods').insert(newFood);
      _resetForm();
      await load();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Food added successfully!')),
        );
      }
    } catch (e) {
      print('Error adding food: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to add food: $e')),
        );
      }
    }
  }

  Future<void> deleteFood(String id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.cardDark,
        title:
            const Text('Delete Food?', style: TextStyle(color: Colors.white)),
        content: const Text(
          'This removes it from the food library. Diets that already use it keep their saved values.',
          style: TextStyle(color: Colors.grey),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await Supabase.instance.client.from('foods').delete().eq('id', id);
      await load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Food deleted successfully')),
        );
      }
    } catch (e) {
      print('Error deleting food: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to delete: $e')),
        );
      }
    }
  }

  Future<void> changeCategory(Map<String, dynamic> food) async {
    final newCategory = food['category'] == 'Veg' ? 'Non-Veg' : 'Veg';
    try {
      await Supabase.instance.client
          .from('foods')
          .update({'category': newCategory}).eq('id', food['id']);

      await load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Category changed to $newCategory')),
        );
      }
    } catch (e) {
      print('Error changing category: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to update category: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final filtered = search.isEmpty
        ? foods
        : foods
            .where((f) => (f['name'] ?? '')
                .toString()
                .toLowerCase()
                .contains(search.toLowerCase()))
            .toList();

    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton(
        backgroundColor: AppColors.gold,
        onPressed: addFood,
        child: const Icon(Icons.add, color: Colors.black),
      ),
      body: isLoading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.gold))
          : RefreshIndicator(
              onRefresh: load,
              color: AppColors.gold,
              backgroundColor: AppColors.cardDark,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: TextField(
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                        labelText: 'Search food',
                        labelStyle: TextStyle(color: Colors.grey),
                        prefixIcon: Icon(Icons.search, color: Colors.grey),
                        border: OutlineInputBorder(),
                        filled: true,
                        fillColor: AppColors.cardDark,
                      ),
                      onChanged: (v) => setState(() => search = v.trim()),
                    ),
                  ),
                  Expanded(
                    child: filtered.isEmpty
                        ? const Center(
                            child: Text('No food items found',
                                style: TextStyle(color: Colors.grey)),
                          )
                        : ListView(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            children: filtered
                                .map((f) => Card(
                                      color: AppColors.cardDark,
                                      margin: const EdgeInsets.only(bottom: 8),
                                      child: ListTile(
                                        title: Text(f['name'] ?? '',
                                            style: const TextStyle(
                                                color: Colors.white)),
                                        subtitle: Text(
                                          '${f['base_quantity']}${f['base_unit']} · ${f['calories']} kcal · P${f['protein']}g C${f['carbs']}g F${f['fats']}g',
                                          style: const TextStyle(
                                              color: Colors.grey, fontSize: 11),
                                        ),
                                        trailing: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            GestureDetector(
                                              onTap: () => changeCategory(f),
                                              child: Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                        horizontal: 8,
                                                        vertical: 4),
                                                decoration: BoxDecoration(
                                                  color: f['category'] == 'Veg'
                                                      ? Colors.green
                                                          .withOpacity(0.15)
                                                      : Colors.redAccent
                                                          .withOpacity(0.15),
                                                  borderRadius:
                                                      BorderRadius.circular(6),
                                                ),
                                                child: Text(
                                                  f['category'] ?? 'Veg',
                                                  style: TextStyle(
                                                    color:
                                                        f['category'] == 'Veg'
                                                            ? Colors.green
                                                            : Colors.redAccent,
                                                    fontSize: 11,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                              ),
                                            ),
                                            IconButton(
                                              icon: const Icon(
                                                  Icons.delete_outline,
                                                  color: Colors.redAccent),
                                              onPressed: () =>
                                                  deleteFood(f['id']),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ))
                                .toList(),
                          ),
                  ),
                ],
              ),
            ),
    );
  }
}

// ============================================================
// CATEGORIES TAB
// ============================================================
class _CategoriesTab extends StatefulWidget {
  const _CategoriesTab();

  @override
  State<_CategoriesTab> createState() => _CategoriesTabState();
}

class _CategoriesTabState extends State<_CategoriesTab> {
  List<Map<String, dynamic>> categories = [];
  bool isLoading = true;
  final TextEditingController _nameController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadCategories();
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _loadCategories() async {
    setState(() => isLoading = true);
    try {
      final data = await Supabase.instance.client
          .from('categories')
          .select()
          .order('name');
      setState(() {
        categories = List<Map<String, dynamic>>.from(data);
        isLoading = false;
      });
    } catch (e) {
      print('Error loading categories: $e');
      setState(() => isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading categories: $e')),
        );
      }
    }
  }

  Future<void> _addCategory() async {
    if (_nameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a category name')),
      );
      return;
    }

    try {
      await Supabase.instance.client.from('categories').insert({
        'name': _nameController.text.trim(),
      });
      _nameController.clear();
      await _loadCategories();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Category added successfully!')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to add category: $e')),
        );
      }
    }
  }

  Future<void> _deleteCategory(String id) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.cardDark,
        title: const Text(
          'Delete Category?',
          style: TextStyle(color: Colors.white),
        ),
        content: const Text(
          'This will remove the category. Members assigned to this category will be unassigned.',
          style: TextStyle(color: Colors.grey),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await Supabase.instance.client.from('categories').delete().eq('id', id);
        await _loadCategories();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Category deleted successfully!')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to delete category: $e')),
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
        onPressed: _addCategory,
        child: const Icon(Icons.add, color: Colors.black),
      ),
      body: isLoading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.gold),
            )
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _nameController,
                          style: const TextStyle(color: Colors.white),
                          decoration: const InputDecoration(
                            hintText: 'Enter category name (e.g. Silver, Gold)',
                            hintStyle: TextStyle(color: Colors.grey),
                            prefixIcon:
                                Icon(Icons.category, color: Colors.grey),
                            border: OutlineInputBorder(),
                            filled: true,
                            fillColor: AppColors.cardDark,
                          ),
                          onSubmitted: (_) => _addCategory(),
                        ),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: _addCategory,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.gold,
                          foregroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 14,
                          ),
                        ),
                        child: const Text('ADD'),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: categories.isEmpty
                      ? const Center(
                          child: Text(
                            'No categories added yet',
                            style: TextStyle(color: Colors.grey),
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          itemCount: categories.length,
                          itemBuilder: (context, index) {
                            final c = categories[index];
                            return Card(
                              color: AppColors.cardDark,
                              margin: const EdgeInsets.only(bottom: 8),
                              child: ListTile(
                                leading: Container(
                                  width: 40,
                                  height: 40,
                                  decoration: BoxDecoration(
                                    color: AppColors.gold.withOpacity(0.15),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Icon(
                                    Icons.category,
                                    color: AppColors.gold,
                                    size: 20,
                                  ),
                                ),
                                title: Text(
                                  c['name'] ?? 'Unnamed',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                subtitle: Text(
                                  'ID: ${c['id'].toString().substring(0, 8)}...',
                                  style: const TextStyle(
                                    color: Colors.grey,
                                    fontSize: 11,
                                  ),
                                ),
                                trailing: IconButton(
                                  icon: const Icon(
                                    Icons.delete_outline,
                                    color: Colors.redAccent,
                                  ),
                                  onPressed: () => _deleteCategory(c['id']),
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }
}
