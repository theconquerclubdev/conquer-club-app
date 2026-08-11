import 'package:flutter/material.dart';

class Responsive {
  static double getFontSize(BuildContext context, double baseSize) {
    double screenWidth = MediaQuery.of(context).size.width;
    if (screenWidth < 400) {
      return baseSize * 0.75; // Small phones
    } else if (screenWidth < 600) {
      return baseSize * 0.9; // Medium phones
    } else {
      return baseSize; // Tablets/desktop
    }
  }

  static bool isMobile(BuildContext context) {
    return MediaQuery.of(context).size.width < 600;
  }

  static bool isTablet(BuildContext context) {
    return MediaQuery.of(context).size.width >= 600 &&
        MediaQuery.of(context).size.width < 1200;
  }

  static bool isDesktop(BuildContext context) {
    return MediaQuery.of(context).size.width >= 1200;
  }
}
