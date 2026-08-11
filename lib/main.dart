import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'screens/login_screen.dart';
import 'screens/get_started_screen.dart';
import 'screens/coach_home_screen.dart';
import 'screens/member_home_screen.dart';
import 'screens/admin_home_screen.dart';
import 'screens/onboarding_screen.dart'; // ✅ ADD THIS
import 'theme/app_theme.dart';

/// Responsive breakpoints used by the app.
///
/// This does not change any existing screen logic. Screens can use these
/// helpers later when a specific layout genuinely needs to adapt.
class AppResponsive {
  static double width(BuildContext context) =>
      MediaQuery.sizeOf(context).width;

  static bool isCompact(BuildContext context) =>
      width(context) < 600;

  static bool isMedium(BuildContext context) =>
      width(context) >= 600 && width(context) < 1200;

  static bool isExpanded(BuildContext context) =>
      width(context) >= 1200;
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

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await SharedPreferences.getInstance();

  await Supabase.initialize(
    url: 'https://dafbinwvwxuekdomdmro.supabase.co',
    anonKey:
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImRhZmJpbnd2d3h1ZWtkb21kbXJvIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODMyNjQ2MjcsImV4cCI6MjA5ODg0MDYyN30.OpEAFP__r_lkBeih255iqHmFHW602BUHDfP_qe1iy6I',
  );

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Conquer Club',
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

  @override
  void initState() {
    super.initState();
    _checkAuth();
  }

  Future<void> _checkAuth() async {
    try {
      final session = Supabase.instance.client.auth.currentSession;

      if (session != null) {
        // ✅ Always try to refresh token if needed
        try {
          await Supabase.instance.client.auth.refreshSession();
        } catch (_) {
          // If refresh fails, still try to use existing session
        }

        // ✅ Get user role
        try {
          final profile =
              await Supabase.instance.client
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

          // ✅ Check if profile is complete
          final isProfileComplete =
              profile['weight_kg'] != null &&
              profile['height_cm'] != null &&
              profile['goal'] != null &&
              profile['date_of_birth'] != null &&
              profile['gender'] != null &&
              (profile['goal'] as String?)?.isNotEmpty == true;

          // ✅ For members only - check onboarding
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
          print('❌ Error checking profile: $e');
          setState(() {
            _initialScreen = const LoginScreen();
            _isLoading = false;
          });
        }
      } else {
        // ✅ NO SESSION - Show GetStartedScreen first, then Login
        setState(() {
          _initialScreen = const GetStartedScreen();
          _isLoading = false;
        });
      }
    } catch (e) {
      print('❌ Auth check error: $e');
      setState(() {
        _initialScreen = const GetStartedScreen();
        _isLoading = false;
      });
    }
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
