import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Shows an attractive 3D sliding popup notifying the member that their
/// coach has assigned (first time) or updated (later) their diet or
/// workout plan. Returns a Future that completes once the member taps OK,
/// so callers can `await` it before showing a second popup back-to-back.
Future<void> showPlanUpdatePopup(
  BuildContext context, {
  required bool isDiet,
  required bool isFirstTime,
}) {
  final icon = isDiet ? Icons.restaurant_menu : Icons.fitness_center;
  final planWord = isDiet ? 'Diet Plan' : 'Workout Plan';
  final title = isFirstTime
      ? '🔔Your coach has assigned you a $planWord! 🔔'
      : '🔔Your coach has updated your $planWord! 🔔';

  return showGeneralDialog(
    context: context,
    barrierDismissible: false,
    barrierLabel: 'Plan update',
    barrierColor: Colors.black.withOpacity(0.6),
    transitionDuration: const Duration(milliseconds: 550),
    pageBuilder: (context, animation, secondaryAnimation) {
      return _PlanUpdatePopupCard(icon: icon, title: title);
    },
    transitionBuilder: (context, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutBack,
      );
      final value = curved.value.clamp(0.0, 1.2);
      return Opacity(
        opacity: animation.value.clamp(0.0, 1.0),
        child: Transform(
          alignment: Alignment.center,
          transform: Matrix4.identity()
            ..setEntry(3, 2, 0.0018) // perspective for a 3D feel
            ..rotateX((1 - value) * -1.1) // tilt in from the top
            ..translate(0.0, (1 - value) * 220, 0.0) // slide up into place
            ..scale(0.85 + (0.15 * value)),
          child: child,
        ),
      );
    },
  );
}

class _PlanUpdatePopupCard extends StatelessWidget {
  final IconData icon;
  final String title;

  const _PlanUpdatePopupCard({required this.icon, required this.title});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Material(
        color: Colors.transparent,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 32),
          padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
          decoration: BoxDecoration(
            color: AppColors.cardDark,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColors.gold.withOpacity(0.4)),
            boxShadow: [
              BoxShadow(
                color: AppColors.gold.withOpacity(0.35),
                blurRadius: 30,
                spreadRadius: 2,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      AppColors.gold.withOpacity(0.35),
                      AppColors.gold.withOpacity(0.05),
                    ],
                  ),
                ),
                child: Icon(icon, color: AppColors.gold, size: 36),
              ),
              const SizedBox(height: 18),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                  height: 1.3,
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.gold,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text(
                    'OK',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
