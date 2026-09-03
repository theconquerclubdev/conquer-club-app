// lib/screens/member/payments_screen.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../theme/app_theme.dart';
import '../../providers/master_data_provider.dart';

class PaymentsScreen extends StatefulWidget {
  const PaymentsScreen({super.key});

  @override
  State<PaymentsScreen> createState() => _PaymentsScreenState();
}

class _PaymentsScreenState extends State<PaymentsScreen> {
  bool isLoading = true;
  bool isProcessing = false;
  List<Map<String, dynamic>> payments = [];
  Map<String, dynamic>? standardPricing;
  Map<String, dynamic>? offerPricing;
  String? offerName;
  bool hasOffer = false;
  String? selectedPlan;
  String? selectedPricingType; // 'standard' or 'offer'
  String? memberName;
  String? membershipEndDate;
  int daysLeft = -1;
  final TextEditingController _notesController = TextEditingController();
  bool _isLoadingPayments = false;

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
    if (_isLoadingPayments) return;
    _isLoadingPayments = true;

    setState(() => isLoading = true);
    try {
      final userId = Supabase.instance.client.auth.currentUser!.id;

      // Get member profile
      final profile = await Supabase.instance.client
          .from('profiles')
          .select('full_name, membership_end_date')
          .eq('id', userId)
          .single();

      memberName = profile['full_name'] ?? 'Member';
      membershipEndDate = profile['membership_end_date'];
      daysLeft = _getDaysLeft(membershipEndDate);

      // Get payment history (explicit columns + limit 20)
      final paymentData = await Supabase.instance.client
          .from('payments')
          .select(
              'id, amount, plan_key, months, status, payment_date, notes, is_cash, offer_used, pricing_type')
          .eq('member_id', userId)
          .order('payment_date', ascending: false)
          .limit(20);

      payments = List<Map<String, dynamic>>.from(paymentData);

      // Get standard pricing
      final standardData = await Supabase.instance.client
          .from('pricing')
          .select('1_month, 3_month, 6_month, 1_year')
          .limit(1)
          .maybeSingle();

      if (standardData != null) {
        standardPricing = standardData;
      } else {
        standardPricing = {
          '1_month': 1500,
          '3_month': 4000,
          '6_month': 7000,
          '1_year': 12000,
        };
      }

      // Check if member has an offer
      final offerData = await Supabase.instance.client
          .from('offer_members')
          .select('offer_id, offers(1_month, 3_month, 6_month, 1_year, name)')
          .eq('member_id', userId)
          .maybeSingle();

      if (offerData != null && offerData['offers'] != null) {
        final offer = offerData['offers'] as Map<String, dynamic>;
        offerPricing = offer;
        hasOffer = true;
        offerName = offer['name'] as String?;
        selectedPricingType = 'offer';
      } else {
        hasOffer = false;
        selectedPricingType = 'standard';
      }

      if (mounted) {
        setState(() => isLoading = false);
      }
    } catch (e) {
      print('Error loading payment data: $e');
      if (mounted) {
        setState(() => isLoading = false);
      }
    } finally {
      _isLoadingPayments = false;
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

  double getPlanPrice(String planKey) {
    if (selectedPricingType == 'offer' && offerPricing != null) {
      final value = offerPricing![planKey];
      if (value != null) return (value as num).toDouble();
    }
    // Fallback to standard pricing
    if (standardPricing != null) {
      final value = standardPricing![planKey];
      if (value != null) return (value as num).toDouble();
    }
    return 0;
  }

  double getStandardPrice(String planKey) {
    if (standardPricing != null) {
      final value = standardPricing![planKey];
      if (value != null) return (value as num).toDouble();
    }
    return 0;
  }

  double getOfferPrice(String planKey) {
    if (offerPricing != null) {
      final value = offerPricing![planKey];
      if (value != null) return (value as num).toDouble();
    }
    return 0;
  }

  String _formatDate(String? dateTime) {
    if (dateTime == null) return 'N/A';
    try {
      final date = DateTime.parse(dateTime);
      return DateFormat('MMM d, yyyy').format(date);
    } catch (e) {
      return 'N/A';
    }
  }

  String _formatDateTime(String? dateTime) {
    if (dateTime == null) return 'N/A';
    try {
      final date = DateTime.parse(dateTime);
      return DateFormat('MMM d, yyyy · h:mm a').format(date);
    } catch (e) {
      return 'N/A';
    }
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
      final userId = Supabase.instance.client.auth.currentUser!.id;
      final plan = _plans.firstWhere((p) => p['key'] == selectedPlan);
      final amount = getPlanPrice(selectedPlan!);
      final months = plan['months'] as int;
      final planLabel = (plan['label'] ?? selectedPlan) as String;

      if (amount <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Invalid price. Please contact admin.')),
        );
        setState(() => isProcessing = false);
        return;
      }

      // Open UPI app
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
                  'No UPI app found. Please install Google Pay or PhonePe.'),
            ),
          );
        }
        setState(() => isProcessing = false);
        return;
      }

      // Record payment as PENDING
      await Supabase.instance.client.from('payments').insert({
        'member_id': userId,
        'amount': amount,
        'plan_key': selectedPlan,
        'months': months,
        'status': 'pending',
        'payment_date': DateTime.now().toUtc().toIso8601String(),
        'notes': _notesController.text.trim(),
        'is_cash': false,
        'offer_used':
            hasOffer && selectedPricingType == 'offer' ? offerName : null,
        'pricing_type': selectedPricingType,
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Payment initiated! Your membership will be renewed once admin confirms.',
            ),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 4),
          ),
        );
        // Invalidate cache for the user and force refresh
        final userId = Supabase.instance.client.auth.currentUser?.id;
        if (userId != null) {
          MasterDataProvider.instance.invalidateCache(userId);
          // Force refresh immediately to update membership status
          try {
            await MasterDataProvider.instance
                .fetchMemberData(userId, force: true);
            debugPrint('✅ Payment complete - refreshed member data');
          } catch (e) {
            debugPrint('❌ Failed to refresh after payment: $e');
          }
        }
        _loadData();
        setState(() {
          selectedPlan = null;
          _notesController.clear();
        });
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
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        title: const Text(
          'Payments',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadData,
          ),
        ],
      ),
      body: isLoading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.gold),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              physics: const BouncingScrollPhysics(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Membership Status Card
                  _buildMembershipStatusCard(),
                  const SizedBox(height: 20),
                  // Pay Now Section
                  _buildPayNowSection(),
                  const SizedBox(height: 24),
                  // Payment History
                  _buildPaymentHistory(),
                ],
              ),
            ),
    );
  }

  Widget _buildMembershipStatusCard() {
    final isActive = daysLeft >= 0;
    final isExpiringSoon = daysLeft >= 0 && daysLeft <= 30;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            isActive
                ? (isExpiringSoon
                    ? Colors.orange.withOpacity(0.15)
                    : Colors.green.withOpacity(0.15))
                : Colors.red.withOpacity(0.15),
            AppColors.cardDark,
          ],
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isActive
              ? (isExpiringSoon
                  ? Colors.orange.withOpacity(0.3)
                  : Colors.green.withOpacity(0.3))
              : Colors.red.withOpacity(0.3),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isActive
                  ? (isExpiringSoon
                      ? Colors.orange.withOpacity(0.2)
                      : Colors.green.withOpacity(0.2))
                  : Colors.red.withOpacity(0.2),
            ),
            child: Icon(
              isActive ? Icons.check_circle : Icons.cancel,
              color: isActive
                  ? (isExpiringSoon ? Colors.orange : Colors.green)
                  : Colors.red,
              size: 28,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isActive ? 'Membership Active' : 'Membership Expired',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  isActive
                      ? '$daysLeft days remaining'
                      : 'Please renew your membership',
                  style: TextStyle(
                    color: isActive
                        ? (isExpiringSoon ? Colors.orange : Colors.green)
                        : Colors.red,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (membershipEndDate != null)
                  Text(
                    'Expires: ${_formatDate(membershipEndDate)}',
                    style: const TextStyle(
                      color: Colors.grey,
                      fontSize: 12,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPayNowSection() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.cardDark,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.payment, color: AppColors.gold),
              const SizedBox(width: 10),
              const Text(
                'Pay Now',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (hasOffer) ...[
                const SizedBox(width: 10),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.gold.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'Offer Available!',
                    style: TextStyle(
                      color: AppColors.gold,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
          Text(
            hasOffer
                ? 'You have a special offer! Choose between Standard or Offer pricing.'
                : 'Select a plan to renew your membership.',
            style: const TextStyle(color: Colors.grey, fontSize: 13),
          ),

          // Pricing Type Selection (if offer exists)
          if (hasOffer) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                _buildPricingTypeChip('Standard', 'standard'),
                const SizedBox(width: 8),
                _buildPricingTypeChip('🎯 Offer: $offerName', 'offer'),
              ],
            ),
          ],

          const SizedBox(height: 16),

          // Plan Selection
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: _plans.map((plan) {
              final key = plan['key'] as String;
              final isSelected = selectedPlan == key;
              final price = getPlanPrice(key);
              final standardPrice = getStandardPrice(key);
              final offerPrice = getOfferPrice(key);
              final hasDiscount =
                  hasOffer && offerPrice > 0 && offerPrice < standardPrice;

              return GestureDetector(
                onTap: () {
                  setState(() {
                    selectedPlan = key;
                  });
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  constraints: const BoxConstraints(minWidth: 80),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? AppColors.gold.withOpacity(0.15)
                        : Colors.white.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: isSelected
                          ? AppColors.gold
                          : Colors.white.withOpacity(0.1),
                      width: isSelected ? 2 : 1,
                    ),
                    boxShadow: isSelected
                        ? [
                            BoxShadow(
                              color: AppColors.gold.withOpacity(0.2),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ]
                        : [],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
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
                      if (hasDiscount && selectedPricingType == 'offer')
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '₹${standardPrice.toStringAsFixed(0)}',
                              style: const TextStyle(
                                color: Colors.grey,
                                fontSize: 10,
                                decoration: TextDecoration.lineThrough,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '₹${price.toStringAsFixed(0)}',
                              style: TextStyle(
                                color:
                                    isSelected ? AppColors.gold : Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        )
                      else
                        Text(
                          price > 0 ? '₹${price.toStringAsFixed(0)}' : 'N/A',
                          style: TextStyle(
                            color: isSelected ? AppColors.gold : Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      if (hasDiscount && selectedPricingType == 'offer')
                        Container(
                          margin: const EdgeInsets.only(top: 2),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 1),
                          decoration: BoxDecoration(
                            color: Colors.green.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            'Save ${((1 - price / standardPrice) * 100).toStringAsFixed(0)}%',
                            style: const TextStyle(
                              color: Colors.green,
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),

          const SizedBox(height: 12),

          // Notes
          TextField(
            controller: _notesController,
            style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(
              labelText: 'Notes (optional)',
              labelStyle: TextStyle(color: Colors.grey),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.all(Radius.circular(8)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.all(Radius.circular(8)),
                borderSide: BorderSide(color: AppColors.gold),
              ),
            ),
            maxLines: 2,
          ),

          const SizedBox(height: 16),

          // Pay Button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: isProcessing ? null : _processPayment,
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                backgroundColor: AppColors.gold,
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: isProcessing
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.black,
                      ),
                    )
                  : const Text(
                      'PAY VIA UPI',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPricingTypeChip(String label, String value) {
    final isSelected = selectedPricingType == value;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          setState(() {
            selectedPricingType = value;
            selectedPlan = null; // Reset plan selection
          });
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: isSelected
                ? AppColors.gold.withOpacity(0.15)
                : Colors.white.withOpacity(0.05),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color:
                  isSelected ? AppColors.gold : Colors.white.withOpacity(0.1),
              width: isSelected ? 1.5 : 1,
            ),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: isSelected ? AppColors.gold : Colors.grey,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              fontSize: 12,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPaymentHistory() {
    if (payments.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppColors.cardDark,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withOpacity(0.06)),
        ),
        child: const Center(
          child: Column(
            children: [
              Icon(Icons.history, color: Colors.grey, size: 40),
              SizedBox(height: 8),
              Text(
                'No payment history',
                style: TextStyle(color: Colors.grey, fontSize: 16),
              ),
              SizedBox(height: 4),
              Text(
                'Your payments will appear here',
                style: TextStyle(color: Colors.grey, fontSize: 12),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Payment History',
          style: TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
        ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: payments.length > 10 ? 10 : payments.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (context, index) =>
              _PaymentCard(payment: payments[index]),
        ),
        if (payments.length > 10)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Center(
              child: Text(
                'Showing last 10 of ${payments.length} payments',
                style: TextStyle(
                  color: Colors.grey.shade600,
                  fontSize: 12,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _PaymentCard extends StatelessWidget {
  final Map<String, dynamic> payment;

  const _PaymentCard({required this.payment});

  @override
  Widget build(BuildContext context) {
    final amount = (payment['amount'] as num?)?.toDouble() ?? 0;
    final status = payment['status'] ?? 'pending';
    final isCompleted = status == 'completed';
    final isPending = status == 'pending';
    final isCash = payment['is_cash'] == true;
    final planKey = payment['plan_key'] ?? 'N/A';
    final months = payment['months'] ?? 0;
    final date = payment['payment_date'] != null
        ? DateTime.parse(payment['payment_date'])
        : DateTime.now();
    final notes = payment['notes'] ?? '';
    final offerUsed = payment['offer_used'];
    final pricingType = payment['pricing_type'];

    String statusLabel = status.toUpperCase();
    Color statusColor;
    IconData statusIcon;

    if (isCompleted) {
      statusColor = Colors.green;
      statusIcon = Icons.check_circle;
    } else if (isPending) {
      statusColor = Colors.orange;
      statusIcon = Icons.pending;
    } else {
      statusColor = Colors.red;
      statusIcon = Icons.cancel;
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.cardDark,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isCompleted
              ? Colors.green.withOpacity(0.2)
              : isPending
                  ? Colors.orange.withOpacity(0.2)
                  : Colors.red.withOpacity(0.2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isCompleted
                      ? Colors.green.withOpacity(0.15)
                      : isPending
                          ? Colors.orange.withOpacity(0.15)
                          : Colors.red.withOpacity(0.15),
                ),
                child: Icon(
                  isCash ? Icons.money : statusIcon,
                  color: statusColor,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          '₹${amount.toStringAsFixed(0)}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: statusColor.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            statusLabel,
                            style: TextStyle(
                              color: statusColor,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        if (isCash)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.blue.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Text(
                              'CASH',
                              style: TextStyle(
                                color: Colors.blue,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        if (pricingType == 'offer')
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.gold.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              'OFFER',
                              style: TextStyle(
                                color: AppColors.gold,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                      ],
                    ),
                    Text(
                      '$planKey · ${months} months',
                      style: const TextStyle(
                        color: Colors.grey,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Icon(Icons.calendar_today, color: Colors.grey.shade600, size: 12),
              const SizedBox(width: 4),
              Text(
                DateFormat('MMM d, yyyy · h:mm a').format(date),
                style: TextStyle(
                  color: Colors.grey.shade500,
                  fontSize: 11,
                ),
              ),
            ],
          ),
          if (offerUsed != null) ...[
            const SizedBox(height: 2),
            Row(
              children: [
                Icon(Icons.local_offer, color: AppColors.gold, size: 12),
                const SizedBox(width: 4),
                Text(
                  'Offer: $offerUsed',
                  style: TextStyle(
                    color: AppColors.gold,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ],
          if (notes.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              'Note: $notes',
              style: TextStyle(
                color: Colors.grey.shade500,
                fontSize: 11,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
