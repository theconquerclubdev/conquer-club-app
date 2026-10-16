import 'package:flutter/material.dart';
import '../providers/staff_dashboard_provider.dart';
import '../theme/app_theme.dart';

/// Bottom sheet with member names for a dashboard tile.
/// kinds: total, in_membership, ended, new, no_diet, no_workout
void showStaffMemberNamesSheet(
    BuildContext context, String kind, String title) {
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
                child: _StaffNamesList(
                  kind: kind,
                  scrollController: scrollController,
                ),
              ),
            ],
          ),
        );
      },
    ),
  );
}

class _StaffNamesList extends StatefulWidget {
  final String kind;
  final ScrollController scrollController;

  const _StaffNamesList({
    required this.kind,
    required this.scrollController,
  });

  @override
  State<_StaffNamesList> createState() => _StaffNamesListState();
}

class _StaffNamesListState extends State<_StaffNamesList> {
  StaffNameList? _list;
  bool _loading = true;
  bool _loadingMore = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool more = false}) async {
    if (more) {
      if (_loadingMore) return;
      setState(() => _loadingMore = true);
    }
    try {
      final list = await StaffDashboardProvider.instance
          .loadNames(widget.kind, more: more);
      if (!mounted) return;
      setState(() {
        _list = list;
        _loading = false;
        _loadingMore = false;
        _failed = false;
      });
    } catch (e) {
      debugPrint('Error loading staff member names: $e');
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadingMore = false;
        _failed = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.gold),
      );
    }
    final list = _list;
    if (list == null || list.items.isEmpty) {
      return Center(
        child: Text(
          _failed ? 'Unable to load. Please try again.' : 'No members found',
          style: const TextStyle(color: Colors.grey),
        ),
      );
    }
    return ListView.builder(
      controller: widget.scrollController,
      itemCount: list.items.length + (list.hasMore ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == list.items.length) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Center(
              child: _loadingMore
                  ? const SizedBox(
                      height: 24,
                      width: 24,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.gold,
                      ),
                    )
                  : TextButton(
                      onPressed: () => _load(more: true),
                      child: const Text(
                        'Load More...',
                        style: TextStyle(color: Colors.grey),
                      ),
                    ),
            ),
          );
        }
        final m = list.items[index];
        final end = m['membership_end_date'];
        return ListTile(
          title: Text(
            m['full_name'] ?? 'Unknown',
            style: const TextStyle(color: Colors.white),
          ),
          subtitle: Text(
            end != null
                ? 'Ends: ${end.toString().substring(0, 10)}'
                : 'No end date',
            style: const TextStyle(color: Colors.grey),
          ),
        );
      },
    );
  }
}
