import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../theme/app_theme.dart';

class MemberDetailScreen extends StatefulWidget {
  final Map member;
  const MemberDetailScreen({super.key, required this.member});

  @override
  State<MemberDetailScreen> createState() => _MemberDetailScreenState();
}

class _MemberDetailScreenState extends State<MemberDetailScreen> {
  String? selectedCoachId;
  late final Future<List<dynamic>> _coachesFuture;

  @override
  void initState() {
    super.initState();
    selectedCoachId = widget.member['assigned_coach_id'];
    // Fetched ONCE here instead of inline in build() — see coach_detail_screen.dart
    // for why that's a real perceived-speed bug (re-fetches on every rebuild).
    _coachesFuture =
        Supabase.instance.client.from('profiles').select().eq('role', 'coach');
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
        body: {'targetUserId': widget.member['id'], 'newPassword': newPassword},
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

  Future<void> assignCoach(String? coachId) async {
    await Supabase.instance.client
        .from('profiles')
        .update({'assigned_coach_id': coachId}).eq('id', widget.member['id']);
    setState(() => selectedCoachId = coachId);
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Coach updated!')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.member['full_name'] ?? 'Member')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Email: ${widget.member['email']}',
              style: const TextStyle(color: Colors.white),
            ),
            const SizedBox(height: 4),
            Text(
              'ID: ${widget.member['id']}',
              style: const TextStyle(color: Colors.grey, fontSize: 12),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: resetPassword,
              child: const Text('RESET PASSWORD'),
            ),
            const SizedBox(height: 24),
            const Text(
              'ASSIGN COACH',
              style: TextStyle(
                color: AppColors.gold,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            FutureBuilder(
              future: _coachesFuture,
              builder: (context, snapshot) {
                if (!snapshot.hasData)
                  return const CircularProgressIndicator(color: AppColors.gold);
                final coaches = snapshot.data as List;
                return DropdownButton<String>(
                  value: selectedCoachId,
                  dropdownColor: AppColors.cardDark,
                  hint: const Text(
                    'No coach assigned',
                    style: TextStyle(color: Colors.grey),
                  ),
                  isExpanded: true,
                  items: coaches.map<DropdownMenuItem<String>>((c) {
                    return DropdownMenuItem(
                      value: c['id'] as String,
                      child: Text(
                        c['full_name'] ?? c['email'],
                        style: const TextStyle(color: Colors.white),
                      ),
                    );
                  }).toList(),
                  onChanged: assignCoach,
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
