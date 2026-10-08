import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

/// The pairing scheme used when generating QR codes for member/coach links.
const String kPairingScheme = 'conquerclub';

/// Build a canonical pairing payload for a member or coach.
///
/// The generated value is intentionally a URL-like payload so it can be used as
/// a deep-link target and can be scanned by another device to open the app.
Uri buildPairingUri({
  required String memberId,
  String? coachId,
  String role = 'member',
  String? source,
}) {
  final params = <String, String>{
    'memberId': memberId,
    'role': role,
    if (coachId != null && coachId.trim().isNotEmpty) 'coachId': coachId,
    if (source != null && source.trim().isNotEmpty) 'source': source,
  };

  return Uri(
    scheme: kPairingScheme,
    host: 'pair',
    queryParameters: params,
  );
}

Map<String, String> parsePairingUri(Uri uri) {
  if (uri.scheme != kPairingScheme || uri.host != 'pair') {
    return const {};
  }

  final params = <String, String>{};
  for (final entry in uri.queryParameters.entries) {
    params[entry.key] = entry.value;
  }
  return params;
}

class PairingQrCard extends StatelessWidget {
  final String pairingCode;
  final double size;

  const PairingQrCard({
    super.key,
    required this.pairingCode,
    this.size = 220,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: QrImageView(
        data: pairingCode,
        version: QrVersions.auto,
        backgroundColor: Colors.white,
        eyeStyle: const QrEyeStyle(
          eyeShape: QrEyeShape.square,
          color: Colors.black,
        ),
        dataModuleStyle: const QrDataModuleStyle(
          dataModuleShape: QrDataModuleShape.square,
          color: Colors.black,
        ),
      ),
    );
  }
}
