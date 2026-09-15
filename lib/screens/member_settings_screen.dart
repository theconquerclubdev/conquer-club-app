import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../theme/app_theme.dart';
import 'member_profile_edit_screen.dart';
import 'signup_screen.dart'
    show kTermsAndConditionsUrl, kPrivacyPolicyUrl;

class MemberSettingsScreen extends StatefulWidget {
  const MemberSettingsScreen({super.key});

  @override
  State<MemberSettingsScreen> createState() => _MemberSettingsScreenState();
}

class _MemberSettingsScreenState extends State<MemberSettingsScreen> {
  bool _checkingRequest = true;
  bool _hasPendingRequest = false;

  @override
  void initState() {
    super.initState();
    _checkExistingRequest();
  }

  Future<void> _checkExistingRequest() async {
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
          _hasPendingRequest = existing != null;
          _checkingRequest = false;
        });
      }
    } catch (e) {
      debugPrint('Error checking deletion request: $e');
      if (mounted) setState(() => _checkingRequest = false);
    }
  }

  Future<void> _openTerms() async {
    final uri = Uri.tryParse(kTermsAndConditionsUrl);
    if (uri != null) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _openPrivacyPolicy() async {
    final uri = Uri.tryParse(kPrivacyPolicyUrl);
    if (uri != null) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _confirmAndRequestDeletion() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.cardDark,
        title: const Text('Delete your account?',
            style: TextStyle(color: Colors.white)),
        content: const Text(
          'This will permanently delete your account and all your data — '
          'workout plans, diet plans, progress photos, measurements, and '
          'payment history. This cannot be undone.\n\n'
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
        setState(() => _hasPendingRequest = true);
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        title: const Text('Settings', style: TextStyle(color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: ListView(
        children: [
          const SizedBox(height: 8),
          _tile(
            icon: Icons.person_outline,
            color: AppColors.gold,
            title: 'Edit Profile',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const MemberProfileEditScreen()),
            ),
          ),
          _tile(
            icon: Icons.description_outlined,
            color: const Color(0xFF4FC3F7),
            title: 'Terms & Conditions',
            onTap: _openTerms,
          ),
          _tile(
            icon: Icons.privacy_tip_outlined,
            color: const Color(0xFF4FC3F7),
            title: 'Privacy Policy',
            onTap: _openPrivacyPolicy,
          ),
          const Divider(color: Colors.white12, height: 32),
          _tile(
            icon: Icons.delete_outline,
            color: Colors.red,
            title: _hasPendingRequest
                ? 'Deletion request pending'
                : 'Delete Account',
            titleColor: Colors.red,
            subtitle: _hasPendingRequest
                ? 'Your account will be deleted within 48 hours'
                : null,
            enabled: !_checkingRequest && !_hasPendingRequest,
            onTap: _confirmAndRequestDeletion,
          ),
        ],
      ),
    );
  }

  Widget _tile({
    required IconData icon,
    required Color color,
    required String title,
    String? subtitle,
    Color? titleColor,
    bool enabled = true,
    required VoidCallback onTap,
  }) {
    return ListTile(
      enabled: enabled,
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: color.withOpacity(0.12),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: color, size: 20),
      ),
      title: Text(
        title,
        style: TextStyle(
          color: enabled ? (titleColor ?? Colors.white) : Colors.grey,
          fontWeight: FontWeight.w600,
        ),
      ),
      subtitle: subtitle != null
          ? Text(subtitle, style: const TextStyle(color: Colors.grey))
          : null,
      trailing: enabled
          ? const Icon(Icons.chevron_right, color: Colors.grey)
          : null,
      onTap: enabled ? onTap : null,
    );
  }
}
