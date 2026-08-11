import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../theme/app_theme.dart';
import '../utils/text_normalize.dart';

/// Lets a member update their own basic profile info — name, weight,
/// height, and goal. Email/role/coach assignment are intentionally left
/// out here: the DB blocks members from changing those fields anyway
/// (see the `prevent_member_privilege_escalation` trigger), so this
/// screen only exposes what a member is actually allowed to edit.
class MemberProfileEditScreen extends StatefulWidget {
  const MemberProfileEditScreen({super.key});

  @override
  State<MemberProfileEditScreen> createState() =>
      _MemberProfileEditScreenState();
}

class _MemberProfileEditScreenState extends State<MemberProfileEditScreen> {
  final _nameController = TextEditingController();
  final _weightController = TextEditingController();
  final _heightController = TextEditingController();
  final _goalController = TextEditingController();

  bool isLoading = true;
  bool isSaving = false;
  String email = '';
  DateTime? dob;
  String? gender;

  static const _genderOptions = ['Male', 'Female', 'Other'];

  // Age is always derived from date_of_birth, never stored or typed in
  // directly — that way it can never go stale.
  int? get age {
    if (dob == null) return null;
    final now = DateTime.now();
    int a = now.year - dob!.year;
    if (now.month < dob!.month ||
        (now.month == dob!.month && now.day < dob!.day)) {
      a--;
    }
    return a;
  }

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _weightController.dispose();
    _heightController.dispose();
    _goalController.dispose();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    final userId = Supabase.instance.client.auth.currentUser!.id;
    final profile = await Supabase.instance.client
        .from('profiles')
        .select(
            'full_name, email, weight_kg, height_cm, goal, date_of_birth, gender')
        .eq('id', userId)
        .single();

    _nameController.text = profile['full_name'] ?? '';
    _weightController.text = profile['weight_kg']?.toString() ?? '';
    _heightController.text = profile['height_cm']?.toString() ?? '';
    _goalController.text = profile['goal'] ?? '';
    email = profile['email'] ?? '';
    dob = profile['date_of_birth'] != null
        ? DateTime.tryParse(profile['date_of_birth'])
        : null;
    gender = profile['gender'];

    if (mounted) setState(() => isLoading = false);
  }

  Future<void> _save() async {
    if (_nameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Name cannot be empty')),
      );
      return;
    }

    setState(() => isSaving = true);
    try {
      final userId = Supabase.instance.client.auth.currentUser!.id;
      await Supabase.instance.client.from('profiles').update({
        'full_name': toTitleCase(_nameController.text),
        'weight_kg': double.tryParse(_weightController.text.trim()),
        'height_cm': double.tryParse(_heightController.text.trim()),
        'goal': _goalController.text.trim().isEmpty
            ? null
            : _goalController.text.trim(),
        'date_of_birth': dob != null
            ? '${dob!.year.toString().padLeft(4, '0')}-${dob!.month.toString().padLeft(2, '0')}-${dob!.day.toString().padLeft(2, '0')}'
            : null,
        'gender': gender,
      }).eq('id', userId);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Profile updated')),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Update failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => isSaving = false);
    }
  }

  InputDecoration _decoration(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon, color: AppColors.gold, size: 20),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Edit Profile')),
      body: isLoading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.gold),
            )
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Center(
                  child: Container(
                    width: 84,
                    height: 84,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        colors: [
                          AppColors.gold,
                          AppColors.gold.withOpacity(0.5),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                    ),
                    child: Center(
                      child: Text(
                        _nameController.text.isNotEmpty
                            ? _nameController.text[0].toUpperCase()
                            : '?',
                        style: const TextStyle(
                          fontSize: 34,
                          fontWeight: FontWeight.w900,
                          color: Colors.black,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Center(
                  child: Text(
                    email,
                    style: const TextStyle(color: Colors.grey, fontSize: 13),
                  ),
                ),
                const SizedBox(height: 28),
                TextField(
                  controller: _nameController,
                  style: const TextStyle(color: Colors.white),
                  decoration: _decoration('Full Name', Icons.person_outline),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _weightController,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        style: const TextStyle(color: Colors.white),
                        decoration: _decoration(
                            'Weight (kg)', Icons.monitor_weight_outlined),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: _heightController,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        style: const TextStyle(color: Colors.white),
                        decoration: _decoration('Height (cm)', Icons.height),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 3,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(8),
                        onTap: () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: dob ??
                                DateTime.now()
                                    .subtract(const Duration(days: 365 * 20)),
                            firstDate: DateTime(1940),
                            lastDate: DateTime.now(),
                          );
                          if (picked != null) setState(() => dob = picked);
                        },
                        child: InputDecorator(
                          decoration:
                              _decoration('Date of Birth', Icons.cake_outlined),
                          child: Text(
                            dob == null
                                ? 'Select date'
                                : '${dob!.day.toString().padLeft(2, '0')}-${dob!.month.toString().padLeft(2, '0')}-${dob!.year}',
                            style: TextStyle(
                              color: dob == null ? Colors.grey : Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: InputDecorator(
                        decoration: _decoration('Age', Icons.numbers),
                        child: Text(
                          age == null ? '-' : '$age yrs',
                          style: const TextStyle(color: Colors.white),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                DropdownButtonFormField<String>(
                  value: gender,
                  dropdownColor: AppColors.cardDark,
                  style: const TextStyle(color: Colors.white),
                  decoration: _decoration('Gender', Icons.wc_outlined),
                  items: _genderOptions
                      .map((g) => DropdownMenuItem(value: g, child: Text(g)))
                      .toList(),
                  onChanged: (v) => setState(() => gender = v),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _goalController,
                  style: const TextStyle(color: Colors.white),
                  maxLines: 2,
                  decoration: _decoration(
                      'Goal (e.g. Fat loss, Muscle gain)', Icons.flag_outlined),
                ),
                const SizedBox(height: 28),
                ElevatedButton(
                  onPressed: isSaving ? null : _save,
                  child: isSaving
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.black,
                          ),
                        )
                      : const Text('SAVE CHANGES'),
                ),
              ],
            ),
    );
  }
}
