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
  late final Future<List<dynamic>> _assignedMembersFuture;

  @override
  void initState() {
    super.initState();
    // Fetched ONCE here instead of inline in build() — a FutureBuilder with
    // its `future:` created fresh on every build() re-fires the network
    // call every single rebuild (e.g. every setState anywhere on screen),
    // causing repeated spinners/lag. Caching it here fixes that.
    _assignedMembersFuture = Supabase.instance.client
        .from('profiles')
        .select()
        .eq('assigned_coach_id', widget.coach['id']);
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
              ],
            ),
          ),
          Expanded(
            child: FutureBuilder(
              future: _assignedMembersFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(
                    child: CircularProgressIndicator(color: AppColors.gold),
                  );
                }
                final data = snapshot.data as List? ?? [];
                if (data.isEmpty) {
                  return const Center(
                    child: Text(
                      'No members assigned yet',
                      style: TextStyle(color: Colors.grey),
                    ),
                  );
                }
                return ListView.builder(
                  itemCount: data.length,
                  itemBuilder: (context, index) {
                    final m = data[index];
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
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
