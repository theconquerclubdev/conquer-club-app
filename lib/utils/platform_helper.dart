import 'package:flutter/foundation.dart'
    show kIsWeb, TargetPlatform, defaultTargetPlatform;

/// Safe cross-platform platform detection that works on Web, iOS, Android
class PlatformHelper {
  /// Returns true if running on iOS (native or simulator) - Web-safe
  static bool get isIOS {
    if (kIsWeb) return false;
    return defaultTargetPlatform == TargetPlatform.iOS;
  }

  /// Returns true if running on Android - Web-safe
  static bool get isAndroid {
    if (kIsWeb) return false;
    return defaultTargetPlatform == TargetPlatform.android;
  }

  /// Returns true if running on macOS - Web-safe
  static bool get isMacOS {
    if (kIsWeb) return false;
    return defaultTargetPlatform == TargetPlatform.macOS;
  }
}
