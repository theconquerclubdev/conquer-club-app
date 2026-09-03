import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'screens/login_screen.dart';
import 'screens/get_started_screen.dart';
import 'screens/coach_home_screen.dart';
import 'screens/member_home_screen.dart';
import 'screens/admin_home_screen.dart';
import 'screens/onboarding_screen.dart';
import 'theme/app_theme.dart';
import 'providers/master_data_provider.dart';

// ✅ Define your current app build version
const String kCurrentAppVersion = '2.0.1';

/// Responsive breakpoints used by the app.
///
/// This does not change any existing screen logic. Screens can use these
/// helpers later when a specific layout genuinely needs to adapt.
class AppResponsive {
  static double width(BuildContext context) => MediaQuery.sizeOf(context).width;

  static bool isCompact(BuildContext context) => width(context) < 600;

  static bool isMedium(BuildContext context) =>
      width(context) >= 600 && width(context) < 1200;

  static bool isExpanded(BuildContext context) => width(context) >= 1200;
}

/// Common maximum content width for large windows.
///
/// Mobile/tablet layouts keep their available width. Very wide windows are
/// prevented from stretching content unnecessarily.
class ResponsiveContent extends StatelessWidget {
  final Widget child;

  const ResponsiveContent({
    super.key,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: 1400,
        ),
        child: child,
      ),
    );
  }
}

// Global navigator key for deep link handling
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

// ============================================================
// 🔄 APP LIFECYCLE OBSERVER
// ============================================================
class AppLifecycleObserver extends WidgetsBindingObserver {
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // App opened from background - refresh cached data
      _refreshAllCachedData();
    }
  }

  void _refreshAllCachedData() async {
    try {
      // Import master_data_provider here
      final provider = MasterDataProvider.instance;
      final memberIds = provider.cachedMemberIds;

      for (final memberId in memberIds) {
        try {
          // ✅ Force refresh with skipCache to get latest membership status
          await provider.fetchMemberData(memberId,
              force: true, skipCache: true);
          debugPrint('✅ Refreshed $memberId on app open');
        } catch (e) {
          debugPrint('❌ Failed to refresh $memberId: $e');
        }
      }
    } catch (e) {
      debugPrint('❌ Error refreshing cache on app open: $e');
    }
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Use path URL strategy on Web so /reset-password routes cleanly
  if (kIsWeb) {
    usePathUrlStrategy();
  }

  await SharedPreferences.getInstance();

  await Supabase.initialize(
    url: 'https://dafbinwvwxuekdomdmro.supabase.co',
    anonKey:
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImRhZmJpbnd2d3h1ZWtkb21kbXJvIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODMyNjQ2MjcsImV4cCI6MjA5ODg0MDYyN30.OpEAFP__r_lkBeih255iqHmFHW602BUHDfP_qe1iy6I',
  );

  // Add lifecycle observer
  WidgetsBinding.instance.addObserver(AppLifecycleObserver());

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Conquer Club',
      navigatorKey: navigatorKey,
      theme: ThemeData(
        brightness: Brightness.dark,
        primaryColor: Colors.orange,
        scaffoldBackgroundColor: Colors.black,
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
          elevation: 0,
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.orange,
            foregroundColor: Colors.black,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            padding: const EdgeInsets.symmetric(vertical: 16),
          ),
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(foregroundColor: Colors.orange),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.grey[900],
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          hintStyle: const TextStyle(color: Colors.grey),
        ),
        textTheme: const TextTheme(
          headlineLarge: TextStyle(
            color: Colors.white,
            fontSize: 32,
            fontWeight: FontWeight.bold,
          ),
          headlineMedium: TextStyle(color: Colors.white, fontSize: 24),
          bodyLarge: TextStyle(color: Colors.white),
          bodyMedium: TextStyle(color: Colors.white),
        ),
      ),
      home: const AuthWrapper(),
      debugShowCheckedModeBanner: false,

      // Responsive foundation: allows the app to receive its actual
      // available window size and supports mouse/trackpad scrolling on
      // desktop/tablet web without changing existing screen logic.
      scrollBehavior: const MaterialScrollBehavior().copyWith(
        scrollbars: true,
        dragDevices: {
          PointerDeviceKind.touch,
          PointerDeviceKind.mouse,
          PointerDeviceKind.trackpad,
        },
      ),
    );
  }
}

class AuthWrapper extends StatefulWidget {
  const AuthWrapper({super.key});

  @override
  State<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> {
  bool _isLoading = true;
  Widget? _initialScreen;

  static const String _currentVersion = '2.0.0';

  @override
  void initState() {
    super.initState();
    _checkAuth();
  }

  Future<void> _checkAuth() async {
    // Check Android version (skip on web)
    if (!kIsWeb) {
      if (!await _checkAppVersion()) {
        setState(() {
          _isLoading = false;
        });
        return;
      }
    }

    // Continue with normal auth flow
    try {
      final session = Supabase.instance.client.auth.currentSession;

      if (session != null) {
        try {
          await Supabase.instance.client.auth.refreshSession();
        } catch (_) {}

        try {
          final profile = await Supabase.instance.client
              .from('profiles')
              .select(
                'role, weight_kg, height_cm, goal, date_of_birth, gender',
              )
              .eq('id', session.user.id)
              .maybeSingle();

          if (profile == null) {
            setState(() {
              _initialScreen = const GetStartedScreen();
              _isLoading = false;
            });
            return;
          }

          final role = profile['role'] as String? ?? 'member';

          final isProfileComplete = profile['weight_kg'] != null &&
              profile['height_cm'] != null &&
              profile['goal'] != null &&
              profile['date_of_birth'] != null &&
              profile['gender'] != null &&
              (profile['goal'] as String?)?.isNotEmpty == true;

          if (role == 'member' && !isProfileComplete) {
            setState(() {
              _initialScreen = const OnboardingScreen();
              _isLoading = false;
            });
            return;
          }

          setState(() {
            _initialScreen = _getHomeScreen(role);
            _isLoading = false;
          });
        } catch (e) {
          debugPrint('❌ Error checking profile: $e');
          setState(() {
            _initialScreen = const LoginScreen();
            _isLoading = false;
          });
        }
      } else {
        setState(() {
          _initialScreen = const GetStartedScreen();
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('❌ Auth check error: $e');
      setState(() {
        _initialScreen = const GetStartedScreen();
        _isLoading = false;
      });
    }
  }

  Future<bool> _checkAppVersion() async {
    try {
      final res = await Supabase.instance.client
          .from('app_versions')
          .select('minimum_version, download_url')
          .eq('platform', 'android')
          .maybeSingle();

      if (res != null) {
        final minVersion = res['minimum_version'] as String;
        final downloadUrl = res['download_url'] as String? ?? '';

        if (_isVersionOutdated(_currentVersion, minVersion)) {
          if (mounted) {
            _showBlockingUpdateDialog(context, downloadUrl);
          }
          return false;
        }
      }
    } catch (e) {
      debugPrint('Version check failed: $e');
    }
    return true;
  }

  bool _isVersionOutdated(String current, String minimum) {
    List<int> currParts =
        current.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    List<int> minParts =
        minimum.split('.').map((e) => int.tryParse(e) ?? 0).toList();

    for (int i = 0; i < 3; i++) {
      int c = i < currParts.length ? currParts[i] : 0;
      int m = i < minParts.length ? minParts[i] : 0;
      if (c < m) return true;
      if (c > m) return false;
    }
    return false;
  }

  void _showBlockingUpdateDialog(BuildContext context, String downloadUrl) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.cardDark,
        title: const Text(
          'Update Required',
          style: TextStyle(color: Colors.white),
        ),
        content: const Text(
          'Your app version is outdated. Please update to continue.',
          style: TextStyle(color: Colors.grey),
        ),
        actions: [
          if (downloadUrl.isNotEmpty)
            ElevatedButton(
              onPressed: () {
                // Open download URL
                // Use url_launcher to open the link
              },
              child: const Text('UPDATE NOW'),
            ),
          TextButton(
            onPressed: () {
              // Close app or stay on this screen
            },
            child: const Text('Close', style: TextStyle(color: Colors.grey)),
          ),
        ],
      ),
    );
  }

  Widget _getHomeScreen(String role) {
    switch (role) {
      case 'admin':
        return const AdminHomeScreen();
      case 'coach':
        return const CoachHomeScreen();
      default:
        return const MemberHomeScreen();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: CircularProgressIndicator(color: Colors.orange)),
      );
    }
    return _initialScreen ?? const GetStartedScreen();
  }
}

// ============================================================
// 🔒 BLOCKING FORCE UPDATE SCREEN
// ============================================================
class ForceUpdateScreen extends StatelessWidget {
  final String currentVersion;
  final String minimumVersion;
  final String downloadUrl;

  const ForceUpdateScreen({
    super.key,
    required this.currentVersion,
    required this.minimumVersion,
    required this.downloadUrl,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 90,
                height: 90,
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.system_update,
                  color: Colors.orange,
                  size: 46,
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'Update Required',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'A new version ($minimumVersion) is available with critical performance and stability updates. Please update to continue using The Conquer Club.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.grey.shade400,
                  fontSize: 14,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.download, color: Colors.black),
                  label: const Text(
                    'DOWNLOAD UPDATE',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                  ),
                  onPressed: () async {
                    if (downloadUrl.isNotEmpty) {
                      final uri = Uri.parse(downloadUrl);
                      if (await canLaunchUrl(uri)) {
                        await launchUrl(uri,
                            mode: LaunchMode.externalApplication);
                      }
                    }
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
