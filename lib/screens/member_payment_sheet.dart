import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../theme/app_theme.dart';

class MemberPaymentSheet extends StatefulWidget {
  final String memberId;
  final VoidCallback onPaymentComplete;

  const MemberPaymentSheet({
    super.key,
    required this.memberId,
    required this.onPaymentComplete,
  });

  @override
  State<MemberPaymentSheet> createState() => _MemberPaymentSheetState();
}

class _MemberPaymentSheetState extends State<MemberPaymentSheet> {
  bool isLoading = true;
  bool isProcessing = false;
  Map<String, dynamic>? pricing;
  String? offerName;
  bool hasOffer = false;
  String? selectedPlan;
  String?
      selectedPricingType; // ✅ Added: tracks whether using standard or offer pricing
  final TextEditingController _notesController = TextEditingController();
  // _customAmountController removed — customize amount option no longer offered
  // useCustomAmount removed — plan price is now always fixed/admin-set

  final List<Map<String, dynamic>> _plans = [
    {'key': '1_month', 'label': '1 Month', 'months': 1},
    {'key': '3_month', 'label': '3 Months', 'months': 3},
    {'key': '6_month', 'label': '6 Months', 'months': 6},
    {'key': '1_year', 'label': '12 Months', 'months': 12},
  ];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => isLoading = true);
    try {
      print('🔄 Loading payment data for member: ${widget.memberId}');

      // 1. Check if member has an offer assigned
      final offerData = await Supabase.instance.client
          .from('offer_members')
          .select('offer_id, offers(*)')
          .eq('member_id', widget.memberId)
          .maybeSingle();

      if (offerData != null && offerData['offers'] != null) {
        final offer = offerData['offers'] as Map<String, dynamic>;
        pricing = offer;
        hasOffer = true;
        offerName = offer['name'] as String?;
        selectedPricingType = 'offer'; // ✅ Set pricing type
        print('✅ Using OFFER: $offerName');
        print(
            '   Prices: 1M=${offer['1_month']}, 3M=${offer['3_month']}, 6M=${offer['6_month']}, 12M=${offer['1_year']}');
      } else {
        // 2. Use standard pricing
        final standardPricing = await Supabase.instance.client
            .from('pricing')
            .select()
            .limit(1)
            .maybeSingle();

        if (standardPricing != null) {
          pricing = standardPricing;
          selectedPricingType = 'standard'; // ✅ Set pricing type
          print('✅ Using STANDARD pricing');
          print(
              '   Prices: 1M=${standardPricing['1_month']}, 3M=${standardPricing['3_month']}, 6M=${standardPricing['6_month']}, 12M=${standardPricing['1_year']}');
        } else {
          // 3. Fallback defaults
          pricing = {
            '1_month': 1500,
            '3_month': 4000,
            '6_month': 7000,
            '1_year': 12000,
          };
          selectedPricingType = 'standard'; // ✅ Set pricing type
          print('⚠️ Using FALLBACK default pricing');
        }
        hasOffer = false;
      }

      setState(() => isLoading = false);
    } catch (e) {
      print('❌ Error loading pricing: $e');
      setState(() => isLoading = false);
    }
  }

  double getPlanPrice(String planKey) {
    if (pricing == null) return 0;
    final value = pricing![planKey];
    if (value == null) return 0;
    return (value as num).toDouble();
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
      final amount = getPlanPrice(selectedPlan!);
      final months = plan['months'] as int;
      final planLabel =
          (plan['label'] ?? plan['name'] ?? selectedPlan) as String;

      if (amount <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Invalid price. Please contact admin.')),
        );
        setState(() => isProcessing = false);
        return;
      }

      // ---- Open UPI app (Google Pay / PhonePe / any UPI app) to pay ----
      // TEST UPI ID — swap for the real business UPI ID before going live.
      const upiId = 'abhimohite13@oksbi';
      final note = Uri.encodeComponent('Conquer Club - $planLabel');
      final upiUri = Uri.parse(
        'upi://pay?pa=$upiId&pn=Conquer%20Club&am=${amount.toStringAsFixed(2)}&cu=INR&tn=$note',
      );

      final launched =
          await launchUrl(upiUri, mode: LaunchMode.externalApplication);
      if (!launched) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text(
                    'No UPI app found. Please install Google Pay or PhonePe.')),
          );
        }
        setState(() => isProcessing = false);
        return;
      }

      // ✅ Auto-confirm payment - membership starts today
      final now = DateTime.now();
      final startDateStr = now.toIso8601String().substring(0, 10);
      final endDate = DateTime(now.year, now.month + months, now.day);
      final endDateStr = endDate.toIso8601String().substring(0, 10);

      await Supabase.instance.client.from('payments').insert({
        'member_id': widget.memberId,
        'amount': amount,
        'plan_key': selectedPlan,
        'months': months,
        'status': 'completed', // ✅ Auto-complete
        'payment_date': DateTime.now().toIso8601String(),
        'notes': _notesController.text.trim(),
        'is_cash': false,
        'offer_used': hasOffer ? offerName : null,
        'start_date': startDateStr,
        'end_date': endDateStr,
        'is_manual': false, // ✅ Auto-generated by member
        'pricing_type': selectedPricingType,
      });

      // ✅ Update membership immediately
      await Supabase.instance.client.from('profiles').update({
        'membership_start_date': startDateStr,
        'membership_end_date': endDateStr,
      }).eq('id', widget.memberId);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              '⏳ Payment submitted! Your membership will be activated once admin approves.',
            ),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 4),
          ),
        );
        widget.onPaymentComplete();
        // Close the sheet after payment
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

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.gold),
      );
    }

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        padding: const EdgeInsets.all(20),
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(Icons.payment, color: AppColors.gold),
                const SizedBox(width: 10),
                const Text(
                  'Renew Membership',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            if (hasOffer)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: AppColors.gold.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.local_offer, color: AppColors.gold, size: 14),
                    const SizedBox(width: 4),
                    Text(
                      'Special Offer: $offerName',
                      style: TextStyle(
                        color: AppColors.gold,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 8),
            Text(
              hasOffer
                  ? 'You have a special offer! Select a plan below.'
                  : 'Select a plan to renew your membership.',
              style: const TextStyle(color: Colors.grey, fontSize: 13),
            ),
            const SizedBox(height: 20),
            const Text(
              'SELECT PLAN',
              style: TextStyle(
                color: AppColors.gold,
                fontSize: 12,
                fontWeight: FontWeight.bold,
                letterSpacing: 1,
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: _plans.map((plan) {
                final key = plan['key'] as String;
                final isSelected = selectedPlan == key;
                final price = getPlanPrice(key);
                return GestureDetector(
                  onTap: () {
                    setState(() {
                      selectedPlan = key;
                    });
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? AppColors.gold.withOpacity(0.2)
                          : AppColors.cardDark,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isSelected
                            ? AppColors.gold
                            : Colors.white.withOpacity(0.1),
                        width: isSelected ? 2 : 1,
                      ),
                      boxShadow: isSelected
                          ? [
                              BoxShadow(
                                color: AppColors.gold.withOpacity(0.3),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ]
                          : [],
                    ),
                    child: Column(
                      children: [
                        Text(
                          plan['label'] as String,
                          style: TextStyle(
                            color: isSelected ? AppColors.gold : Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          price > 0 ? '₹${price.toStringAsFixed(0)}' : 'N/A',
                          style: TextStyle(
                            color: isSelected ? AppColors.gold : Colors.grey,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
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
            const SizedBox(height: 20),
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
                    : const Text('PAY VIA UPI'),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text(
                  'Need help? ',
                  style: TextStyle(color: Colors.grey),
                ),
                TextButton(
                  onPressed: () {
                    Navigator.pop(context);
                    showDialog(
                      context: context,
                      builder: (_) => AlertDialog(
                        backgroundColor: AppColors.cardDark,
                        title: const Text(
                          'Contact Admin',
                          style: TextStyle(color: Colors.white),
                        ),
                        content: const Text(
                          'Please contact your admin for assistance with payment.',
                          style: TextStyle(color: Colors.grey),
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text('Close'),
                          ),
                        ],
                      ),
                    );
                  },
                  child: const Text('Contact Admin'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
