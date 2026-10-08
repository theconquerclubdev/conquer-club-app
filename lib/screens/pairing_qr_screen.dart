import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../theme/app_theme.dart';
import '../utils/pairing_qr.dart';

class PairingQrScreen extends StatefulWidget {
  const PairingQrScreen({super.key});

  @override
  State<PairingQrScreen> createState() => _PairingQrScreenState();
}

class _PairingQrScreenState extends State<PairingQrScreen> {
  late final String _pairingCode;
  bool _copied = false;

  @override
  void initState() {
    super.initState();
    final userId = Supabase.instance.client.auth.currentUser?.id ?? 'guest';
    _pairingCode = buildPairingUri(
      memberId: userId,
      role: 'member',
      source: 'settings',
    ).toString();
  }

  Future<void> _copyCode() async {
    await Clipboard.setData(ClipboardData(text: _pairingCode));
    if (!mounted) return;
    setState(() => _copied = true);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Pairing code copied to clipboard.'),
        backgroundColor: AppColors.gold,
      ),
    );
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  Future<void> _shareCode() async {
    await Share.share(
      'My pairing code: $_pairingCode',
      subject: 'Conquer Club pairing QR code',
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        title: const Text('Pairing QR code',
            style: TextStyle(color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const Icon(Icons.qr_code_2, color: AppColors.gold, size: 52),
                  const SizedBox(height: 12),
                  const Text(
                    'Scan this code to pair your account',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 28,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Share this with your coach or trainer to quickly connect.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppColors.grey, fontSize: 16),
                  ),
                  const SizedBox(height: 24),
                  PairingQrCard(pairingCode: _pairingCode),
                  const SizedBox(height: 20),
                  SelectableText(
                    _pairingCode,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _copyCode,
                          icon: const Icon(Icons.copy_all_outlined),
                          label: Text(_copied ? 'Copied' : 'Copy code'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _shareCode,
                          icon: const Icon(Icons.share_outlined),
                          label: const Text('Share'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
