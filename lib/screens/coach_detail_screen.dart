import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../theme/app_theme.dart';

class CoachDetailScreen extends StatefulWidget {
  final Map coach;
  const CoachDetailScreen({super.key, required this.coach});

  @override
  State<CoachDetailScreen> createState() => _CoachDetailScreenState();
}

class _CoachDetailScreenState extends State<CoachDetailScreen> {
  List<Map<String, dynamic>> _assignedMembers = [];
  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _hasMoreData = false;
  int _totalCount = 0;
  int _currentOffset = 0;
  final int _pageSize = 20;

  // Threshold: if total assigned members <= 200, use instant client-side mode
  static const int _kPaginationThreshold = 200;
  bool get _isClientSideMode => _totalCount <= _kPaginationThreshold;

  String _searchQuery = '';
  Timer? _searchDebounce;
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadAssignedMembers();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  // 1. Get total count first, then fetch first batch
  Future<void> _loadAssignedMembers() async {
    setState(() => _isLoading = true);
    try {
      final countData = await Supabase.instance.client
          .from('profiles')
          .select('id')
          .eq('assigned_coach_id', widget.coach['id']);
      _totalCount = (countData as List).length;

      await _fetchAssignedMembers(reset: true);
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // 2. Auto-switches between single-query (<=200) and paginated (>200) fetch
  Future<void> _fetchAssignedMembers({bool reset = false}) async {
    if (reset) {
      setState(() {
        _currentOffset = 0;
        _isLoading = true;
        if (_isClientSideMode) _assignedMembers.clear();
      });
    } else {
      if (_isLoadingMore || !_hasMoreData || _isClientSideMode) return;
      setState(() => _isLoadingMore = true);
    }

    try {
      var query = Supabase.instance.client
          .from('profiles')
          .select('id, full_name, email')
          .eq('assigned_coach_id', widget.coach['id']);

      if (_isClientSideMode) {
        final data = await query.order('full_name');
        final items = List<Map<String, dynamic>>.from(data);

        if (mounted) {
          setState(() {
            _assignedMembers = items;
            _hasMoreData = false;
            _isLoading = false;
          });
        }
      } else {
        if (_searchQuery.isNotEmpty) {
          query = query.or(
            'full_name.ilike.%$_searchQuery%,email.ilike.%$_searchQuery%',
          );
        }

        final data = await query
            .order('full_name')
            .range(_currentOffset, _currentOffset + _pageSize - 1);

        final items = List<Map<String, dynamic>>.from(data);

        if (mounted) {
          setState(() {
            if (reset) {
              _assignedMembers = items;
            } else {
              _assignedMembers.addAll(items);
            }
            _currentOffset += items.length;
            _hasMoreData = items.length == _pageSize;
            _isLoading = false;
            _isLoadingMore = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isLoadingMore = false;
        });
      }
    }
  }

  // Instant filter for <=200 members, already-filtered-by-server for >200
  List<Map<String, dynamic>> get _displayedMembers {
    if (!_isClientSideMode) return _assignedMembers;

    var list = _assignedMembers;
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      list = list.where((m) {
        final name = (m['full_name'] ?? '').toString().toLowerCase();
        final email = (m['email'] ?? '').toString().toLowerCase();
        return name.contains(q) || email.contains(q);
      }).toList();
    }
    return list;
  }

  void _onSearchChanged(String v) {
    setState(() => _searchQuery = v.trim());

    if (_isClientSideMode) {
      setState(() {});
    } else {
      _searchDebounce?.cancel();
      _searchDebounce = Timer(const Duration(milliseconds: 350), () {
        _fetchAssignedMembers(reset: true);
      });
    }
  }

  Future<void> resetPassword() async {
    final controller = TextEditingController();
    final newPassword = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.cardDark,
        title: const Text(
          'Set New Password',
          style: TextStyle(color: Colors.white),
        ),
        content: TextField(
          controller: controller,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            labelText: 'New password (min 6 chars)',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Set'),
          ),
        ],
      ),
    );

    if (newPassword == null || newPassword.length < 6) return;

    try {
      await Supabase.instance.client.functions.invoke(
        'reset-password',
        body: {'targetUserId': widget.coach['id'], 'newPassword': newPassword},
      );
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Password updated!')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final coachId = widget.coach['id'];

    return Scaffold(
      appBar: AppBar(title: Text(widget.coach['full_name'] ?? 'Coach')),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (widget.coach['role'] == 'head_coach')
                  Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.gold.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: AppColors.gold.withOpacity(0.4),
                      ),
                    ),
                    child: Text(
                      'HEAD COACH',
                      style: TextStyle(
                        color: AppColors.gold,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1,
                      ),
                    ),
                  ),
                Text(
                  'Email: ${widget.coach['email']}',
                  style: const TextStyle(color: Colors.white),
                ),
                const SizedBox(height: 4),
                Text(
                  'ID: $coachId',
                  style: const TextStyle(color: Colors.grey, fontSize: 12),
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: resetPassword,
                  child: const Text('RESET PASSWORD'),
                ),
                const SizedBox(height: 24),
                const Text(
                  'ASSIGNED MEMBERS',
                  style: TextStyle(
                    color: AppColors.gold,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _searchController,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    hintText: 'Search members...',
                    prefixIcon: Icon(Icons.search, color: Colors.grey),
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(vertical: 8),
                  ),
                  onChanged: _onSearchChanged,
                ),
              ],
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(color: AppColors.gold),
                  )
                : _displayedMembers.isEmpty
                    ? const Center(
                        child: Text(
                          'No members assigned yet',
                          style: TextStyle(color: Colors.grey),
                        ),
                      )
                    : ListView.builder(
                        itemCount:
                            _displayedMembers.length + (_hasMoreData ? 1 : 0),
                        itemBuilder: (context, index) {
                          if (index == _displayedMembers.length) {
                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              child: Center(
                                child: _isLoadingMore
                                    ? const SizedBox(
                                        height: 24,
                                        width: 24,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: AppColors.gold,
                                        ),
                                      )
                                    : TextButton(
                                        onPressed: () =>
                                            _fetchAssignedMembers(reset: false),
                                        child: const Text(
                                          'Load More...',
                                          style: TextStyle(color: Colors.grey),
                                        ),
                                      ),
                              ),
                            );
                          }

                          final m = _displayedMembers[index];
                          return ListTile(
                            title: Text(
                              m['full_name'] ?? '',
                              style: const TextStyle(color: Colors.white),
                            ),
                            subtitle: Text(
                              m['email'] ?? '',
                              style: const TextStyle(color: Colors.grey),
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
