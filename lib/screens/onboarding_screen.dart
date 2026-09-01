import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../theme/app_theme.dart';
import 'measurements_screen.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _fullNameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _heightController = TextEditingController();
  final _weightController = TextEditingController();
  final _goalController = TextEditingController();

  String _email = '';
  DateTime? _dob;
  String? _gender;
  bool _isLoading = false;
  bool _isLoadingProfile = true;
  String? _errorMessage;

  final List<String> _genderOptions = ['Male', 'Female', 'Other'];

  @override
  void initState() {
    super.initState();
    _loadUserEmail();
  }

  @override
  void dispose() {
    _fullNameController.dispose();
    _phoneController.dispose();
    _heightController.dispose();
    _weightController.dispose();
    _goalController.dispose();
    super.dispose();
  }

  Future<void> _loadUserEmail() async {
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user != null) {
        setState(() {
          _email = user.email ?? '';
          _isLoadingProfile = false;
        });
      }
    } catch (e) {
      setState(() {
        _isLoadingProfile = false;
      });
    }
  }

  int? get _age {
    if (_dob == null) return null;
    final now = DateTime.now();
    int age = now.year - _dob!.year;
    if (now.month < _dob!.month ||
        (now.month == _dob!.month && now.day < _dob!.day)) {
      age--;
    }
    return age;
  }

  Future<void> _saveProfile() async {
    final fullName = _fullNameController.text.trim();
    final phone = _phoneController.text.trim();
    final height = _heightController.text.trim();
    final weight = _weightController.text.trim();
    final goal = _goalController.text.trim();

    if (fullName.isEmpty) {
      setState(() => _errorMessage = 'Please enter your full name');
      return;
    }

    if (phone.isEmpty) {
      setState(() => _errorMessage = 'Please enter your phone number');
      return;
    }

    if (height.isEmpty) {
      setState(() => _errorMessage = 'Please enter your height');
      return;
    }

    if (weight.isEmpty) {
      setState(() => _errorMessage = 'Please enter your weight');
      return;
    }

    if (goal.isEmpty) {
      setState(() => _errorMessage = 'Please enter your goal');
      return;
    }

    if (_dob == null) {
      setState(() => _errorMessage = 'Please select your date of birth');
      return;
    }

    if (_gender == null) {
      setState(() => _errorMessage = 'Please select your gender');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final userId = Supabase.instance.client.auth.currentUser!.id;

      await Supabase.instance.client.from('profiles').update({
        'full_name': fullName,
        'phone': phone,
        'height_cm': double.tryParse(height),
        'weight_kg': double.tryParse(weight),
        'goal': goal,
        'date_of_birth':
            '${_dob!.year.toString().padLeft(4, '0')}-${_dob!.month.toString().padLeft(2, '0')}-${_dob!.day.toString().padLeft(2, '0')}',
        'gender': _gender,
      }).eq('id', userId);

      if (!mounted) return;

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => const MeasurementsScreen(isOnboarding: true),
        ),
      );
    } catch (e) {
      setState(() {
        _errorMessage = 'Could not save. Please try again.';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: _isLoadingProfile
            ? const Center(
                child: CircularProgressIndicator(color: AppColors.gold),
              )
            : SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight: MediaQuery.of(context).size.height -
                        MediaQuery.of(context).padding.top -
                        MediaQuery.of(context).padding.bottom -
                        32,
                  ),
                  child: Column(
                    mainAxisAlignment:
                        MainAxisAlignment.center, // ✅ Center vertically
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SizedBox(height: 20),
                      RichText(
                        textAlign: TextAlign.center,
                        text: TextSpan(
                          children: [
                            TextSpan(
                              text: 'THE ',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 28,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            TextSpan(
                              text: 'CONQUER',
                              style: TextStyle(
                                color: AppColors.gold,
                                fontSize: 28,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            TextSpan(
                              text: ' CLUB',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 28,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'COMPLETE YOUR PROFILE',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: AppColors.gold,
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 2,
                        ),
                      ),
                      const SizedBox(height: 32),

                      // Full Name
                      TextField(
                        controller: _fullNameController,
                        style: const TextStyle(color: Colors.white),
                        decoration: const InputDecoration(
                          labelText: 'Full Name *',
                          labelStyle: TextStyle(color: Colors.grey),
                          prefixIcon:
                              Icon(Icons.person_outline, color: Colors.grey),
                          filled: true,
                          fillColor: Color(0xFF1A1A1A),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.all(Radius.circular(12)),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Phone Number
                      TextField(
                        controller: _phoneController,
                        keyboardType: TextInputType.phone,
                        style: const TextStyle(color: Colors.white),
                        decoration: const InputDecoration(
                          labelText: 'Phone Number *',
                          labelStyle: TextStyle(color: Colors.grey),
                          prefixIcon:
                              Icon(Icons.phone_outlined, color: Colors.grey),
                          filled: true,
                          fillColor: Color(0xFF1A1A1A),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.all(Radius.circular(12)),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Email (Uneditable)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 16),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1A1A1A),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: Colors.grey.withOpacity(0.2),
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.email_outlined, color: Colors.grey),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                _email.isEmpty ? 'No email found' : _email,
                                style: TextStyle(
                                  color: _email.isEmpty
                                      ? Colors.grey
                                      : Colors.white70,
                                  fontSize: 16,
                                ),
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.grey.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Text(
                                'UNEDITABLE',
                                style: TextStyle(
                                  color: Colors.grey,
                                  fontSize: 9,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Date of Birth + Age
                      Row(
                        children: [
                          Expanded(
                            flex: 3,
                            child: InkWell(
                              onTap: () async {
                                final picked = await showDatePicker(
                                  context: context,
                                  initialDate: _dob ??
                                      DateTime.now().subtract(
                                        const Duration(days: 365 * 20),
                                      ),
                                  firstDate: DateTime(1940),
                                  lastDate: DateTime.now(),
                                );
                                if (picked != null)
                                  setState(() => _dob = picked);
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 16,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF1A1A1A),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: Colors.grey.withOpacity(0.2),
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Icon(Icons.cake_outlined,
                                        color: Colors.grey),
                                    const SizedBox(width: 12),
                                    Text(
                                      _dob == null
                                          ? 'Date of Birth *'
                                          : '${_dob!.day.toString().padLeft(2, '0')}-${_dob!.month.toString().padLeft(2, '0')}-${_dob!.year}',
                                      style: TextStyle(
                                        color: _dob == null
                                            ? Colors.grey
                                            : Colors.white,
                                      ),
                                    ),
                                    const Spacer(),
                                    Icon(Icons.calendar_today,
                                        color: Colors.grey, size: 18),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            flex: 1,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 16,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFF1A1A1A),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: Colors.grey.withOpacity(0.2),
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Age',
                                    style: TextStyle(
                                      color: Colors.grey,
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    _age != null ? '$_age yrs' : '-',
                                    style: TextStyle(
                                      color: _age != null
                                          ? AppColors.gold
                                          : Colors.grey,
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // Height & Weight Row
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _heightController,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                decimal: true,
                              ),
                              style: const TextStyle(color: Colors.white),
                              decoration: const InputDecoration(
                                labelText: 'Height (cm) *',
                                labelStyle: TextStyle(color: Colors.grey),
                                prefixIcon:
                                    Icon(Icons.height, color: Colors.grey),
                                filled: true,
                                fillColor: Color(0xFF1A1A1A),
                                border: OutlineInputBorder(
                                  borderRadius:
                                      BorderRadius.all(Radius.circular(12)),
                                  borderSide: BorderSide.none,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextField(
                              controller: _weightController,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                decimal: true,
                              ),
                              style: const TextStyle(color: Colors.white),
                              decoration: const InputDecoration(
                                labelText: 'Weight (kg) *',
                                labelStyle: TextStyle(color: Colors.grey),
                                prefixIcon: Icon(Icons.monitor_weight_outlined,
                                    color: Colors.grey),
                                filled: true,
                                fillColor: Color(0xFF1A1A1A),
                                border: OutlineInputBorder(
                                  borderRadius:
                                      BorderRadius.all(Radius.circular(12)),
                                  borderSide: BorderSide.none,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // Gender Dropdown
                      DropdownButtonFormField<String>(
                        value: _gender,
                        dropdownColor: AppColors.cardDark,
                        style: const TextStyle(color: Colors.white),
                        decoration: const InputDecoration(
                          labelText: 'Gender *',
                          labelStyle: TextStyle(color: Colors.grey),
                          prefixIcon:
                              Icon(Icons.wc_outlined, color: Colors.grey),
                          filled: true,
                          fillColor: Color(0xFF1A1A1A),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.all(Radius.circular(12)),
                            borderSide: BorderSide.none,
                          ),
                        ),
                        items: _genderOptions
                            .map((g) =>
                                DropdownMenuItem(value: g, child: Text(g)))
                            .toList(),
                        onChanged: (v) => setState(() => _gender = v),
                      ),
                      const SizedBox(height: 16),

                      // Goal
                      TextField(
                        controller: _goalController,
                        style: const TextStyle(color: Colors.white),
                        maxLines: 2,
                        decoration: const InputDecoration(
                          labelText: 'Your Goal (e.g. Fat Loss, Muscle Gain) *',
                          labelStyle: TextStyle(color: Colors.grey),
                          prefixIcon:
                              Icon(Icons.flag_outlined, color: Colors.grey),
                          filled: true,
                          fillColor: Color(0xFF1A1A1A),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.all(Radius.circular(12)),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),

                      if (_errorMessage != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Text(
                            _errorMessage!,
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.redAccent),
                          ),
                        ),

                      _isLoading
                          ? const Center(
                              child: CircularProgressIndicator(
                                  color: AppColors.gold),
                            )
                          : ElevatedButton(
                              onPressed: _saveProfile,
                              style: ElevatedButton.styleFrom(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 16),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              child: const Text('CONTINUE TO MEASUREMENTS'),
                            ),
                      const SizedBox(height: 32),
                    ],
                  ),
                ),
              ),
      ),
    );
  }
}
