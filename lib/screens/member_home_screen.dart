import 'dart:convert';
import '../utils/platform_helper.dart';
import '../utils/app_version.dart';
import 'package:intl/intl.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:pedometer/pedometer.dart';
import 'package:health/health.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../theme/app_theme.dart';
import 'login_screen.dart';
import 'measurements_screen.dart';
import 'step_counter_screen.dart';
import 'workout_day_session_screen.dart';
import 'member_diet_preview_loader.dart';
import 'member_profile_edit_screen.dart';
import 'member_progress_screen.dart';
import 'workout_progress_screen.dart';
import 'member_payment_sheet.dart';
import 'streaks_tab.dart';
import 'payments_screen.dart';
import '../providers/master_data_provider.dart';
import '../widgets/plan_update_popup.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_file/open_file.dart';

class MemberHomeScreen extends StatefulWidget {
  const MemberHomeScreen({super.key});

  @override
  State<MemberHomeScreen> createState() => _MemberHomeScreenState();
}

class _MemberHomeScreenState extends State<MemberHomeScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late TabController tabController;
  final days = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];
  String todayName = '';
  String fullName = '';
  Map<String, dynamic>? coach;
  bool isLoadingProfile = true;
  bool profileComplete = true;

  // Membership related
  int daysLeft = -1;
  bool isMembershipActive = false;
  bool isMembershipExpiringSoon = false;
  String membershipEndDate = '';
  bool isNewMember = true;

  // Streak related
  int currentStreak = 0;
  bool isLoadingStreak = true;

  // Step tracker
  int todaySteps = 0;
  int stepGoal = 10000;
  DateTime signupDate = DateTime.now();
  bool stepPermissionDenied = false;
  StreamSubscription<StepCount>? _stepSub;
  int? _stepsAtMidnight;
  String? _baselineDate;
  Timer? _stepSaveTimer;
  Timer? _healthPollTimer;
  bool _usingHealthSource = false;

  // Concrete reason step tracking isn't live right now (null = working fine)
  String? stepIssueMessage;
  bool stepIssueCanOpenSettings = false;

  // Today's Tasks Data
  bool _workoutCompletedToday = false;
  bool _measurementsUpdatedToday = false;
  Map<String, bool> _photoStatus = {'front': false, 'back': false};

  int _lastSavedSteps = -1;
  DateTime? _lastStepSaveTime;
  static const Duration _stepSaveThrottle = Duration(hours: 4);
  // Update checker - auto-generated from build time
  bool _isCheckingUpdate = false;
  String get _currentVersion => kCurrentAppVersion;

  String get firstName {
    final trimmed = fullName.trim();
    if (trimmed.isEmpty) return 'Champion';
    return trimmed.split(RegExp(r'\s+')).first;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    tabController = TabController(length: 2, vsync: this, initialIndex: 0);
    todayName = days[(DateTime.now().toUtc().add(
              const Duration(hours: 5, minutes: 30),
            )).weekday -
        1];
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        loadProfile();
        // ✅ _loadTodayTaskStatus data is now loaded from MasterDataProvider inside loadProfile
      }
    });
    _initStepTracker();
    MasterDataProvider.instance.addListener(_onMasterDataChanged);
  }

  void _onMasterDataChanged() {
    if (!mounted) return;
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;
    final latest = MasterDataProvider.instance.getData(userId);
    if (latest == null || identical(latest, _lastAppliedData)) return;
    loadProfile();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    MasterDataProvider.instance.removeListener(_onMasterDataChanged);
    tabController.dispose();
    _stepSub?.cancel();
    _stepSaveTimer?.cancel();
    _healthPollTimer?.cancel();
    super.dispose();
  }

  DateTime? _lastResumeTime;
  MemberDashboardData? _lastAppliedData;
  String? _dietStatusText;
  String? _workoutStatusText;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      // ✅ App going to background - save current steps
      _flushPendingStepSave();
      // ❌ Don't cancel timer! Let it continue in background
      // _healthPollTimer?.cancel();  // ← Remove this
      // _stepSub?.cancel();  // ← Remove this
    } else if (state == AppLifecycleState.resumed) {
      // ✅ App resumed - fetch latest steps from Health API
      final now = DateTime.now();
      if (_lastResumeTime == null ||
          now.difference(_lastResumeTime!) >= const Duration(seconds: 30)) {
        _lastResumeTime = now;
        // ✅ Re-initialize to fetch latest data
        _initStepTracker();
        // ✅ Force fresh data on resume — realtime websocket gets
        // suspended in background (esp. iOS), so a diet/workout change
        // made while app was closed/backgrounded can hide behind the
        // 3-min cache window. Invalidate so the mandatory popup always
        // fires the moment member reopens app.
        final resumedUserId = Supabase.instance.client.auth.currentUser?.id;
        if (resumedUserId != null) {
          MasterDataProvider.instance.invalidateCache(resumedUserId);
        }
        // ✅ Task status is loaded via MasterDataProvider in loadProfile()
        loadProfile();
      }
    }
  }

  bool stepPermanentlyDenied = false;
  bool _stepTrackerStarting = false;

  Future<void> _initStepTracker() async {
    if (kIsWeb) {
      // ⚠️ Web browsers don't support step tracking — show a clear message
      // instead of a blank/frozen step bar.
      if (mounted) {
        setState(() {
          stepPermissionDenied = true;
          stepPermanentlyDenied = false;
          stepIssueCanOpenSettings = false;
          stepIssueMessage =
              "Step counting isn't available on web. Use the Android or iPhone app to track steps.";
        });
      }
      return;
    }
    if (_stepTrackerStarting) return;
    _stepTrackerStarting = true;
    _flushPendingStepSave();
    final gotHealth = await _tryInitHealthSource();
    if (!gotHealth) await _initRawSensorTracker();
    _stepTrackerStarting = false;
  }

  Future<bool> _tryInitHealthSource() async {
    try {
      final health = Health();
      await health.configure();
      const types = [HealthDataType.STEPS];
      const permissions = [HealthDataAccess.READ];
      final hasPermission =
          await health.hasPermissions(types, permissions: permissions) ?? false;
      final granted = hasPermission ||
          await health.requestAuthorization(types, permissions: permissions);
      if (!granted) {
        print('⚠️ Health permission denied');
        return false;
      }

      final ok = await _fetchHealthSteps();
      if (!ok) return false;

      _usingHealthSource = true;
      if (mounted) {
        setState(() {
          stepPermissionDenied = false;
          stepPermanentlyDenied = false;
          stepIssueMessage = null;
          stepIssueCanOpenSettings = false;
        });
      }
      _healthPollTimer?.cancel();
      // ✅ Poll every 60 seconds for updated steps from Health API
      // This works even when app is in background
      _healthPollTimer = Timer.periodic(
        const Duration(seconds: 60),
        (_) => _fetchHealthSteps(),
      );
      return true;
    } catch (_) {
      print('❌ Health API failed: $_');
      return false;
    }
  }

  Future<bool> _fetchHealthSteps() async {
    try {
      final nowUtc = DateTime.now().toUtc();
      final now = nowUtc.add(const Duration(hours: 5, minutes: 30));
      final istMidnightUtc = DateTime.utc(
        now.year,
        now.month,
        now.day,
      ).subtract(const Duration(hours: 5, minutes: 30));
      final steps =
          await Health().getTotalStepsInInterval(istMidnightUtc, nowUtc) ?? 0;
      if (mounted) {
        setState(() => todaySteps = steps);
        _stepSaveTimer?.cancel();
        _stepSaveTimer = Timer(const Duration(seconds: 60), _saveTodaySteps);
      }
      return true;
    } catch (_) {
      if (_usingHealthSource) {
        _usingHealthSource = false;
        _healthPollTimer?.cancel();
        await _initRawSensorTracker();
      }
      return false;
    }
  }

  Future<void> _initRawSensorTracker() async {
    final status = PlatformHelper.isIOS
        ? await Permission.sensors.request()
        : await Permission.activityRecognition.request();
    if (!status.isGranted) {
      if (mounted) {
        setState(() {
          stepPermissionDenied = true;
          stepPermanentlyDenied = status.isPermanentlyDenied;
          stepIssueCanOpenSettings = true;
          stepIssueMessage = status.isPermanentlyDenied
              ? (PlatformHelper.isIOS
                  ? 'Motion & Fitness access is off. Turn it on in Settings > Privacy > Motion & Fitness to see your steps.'
                  : 'Physical activity permission is off. Turn it on in Settings > Apps > Conquer Club > Permissions to see your steps.')
              : 'Step tracking needs motion/activity permission. Tap below to allow it.';
        });
      }
      return;
    }
    if (mounted) {
      setState(() {
        stepPermissionDenied = false;
        stepPermanentlyDenied = false;
        stepIssueMessage = null;
        stepIssueCanOpenSettings = false;
      });
    }
    _stepSub?.cancel();
    _stepSub = Pedometer.stepCountStream.listen(
      (event) async {
        await _resolveBaseline(event.steps);
        final delta = event.steps - (_stepsAtMidnight ?? event.steps);
        if (mounted) {
          setState(() {
            todaySteps = delta < 0 ? 0 : delta.clamp(0, 1000000);
          });
          _stepSaveTimer?.cancel();
          _stepSaveTimer = Timer(const Duration(seconds: 20), _saveTodaySteps);
        }
      },
      onError: (_) async {
        final status = PlatformHelper.isIOS
            ? await Permission.sensors.status
            : await Permission.activityRecognition.status;
        if (!status.isGranted) {
          if (mounted) {
            setState(() {
              stepPermissionDenied = true;
              stepPermanentlyDenied = status.isPermanentlyDenied;
              stepIssueCanOpenSettings = true;
              stepIssueMessage = status.isPermanentlyDenied
                  ? (PlatformHelper.isIOS
                      ? 'Motion & Fitness access is off. Turn it on in Settings > Privacy > Motion & Fitness to see your steps.'
                      : 'Physical activity permission is off. Turn it on in Settings > Apps > Conquer Club > Permissions to see your steps.')
                  : 'Step tracking needs motion/activity permission. Tap below to allow it.';
            });
          }
          return;
        }
        if (mounted) {
          setState(() {
            stepIssueCanOpenSettings = false;
            stepIssueMessage =
                'Step sensor is not responding right now. Retrying...';
          });
        }
        await Future.delayed(const Duration(seconds: 5));
        if (mounted) _initRawSensorTracker();
      },
    );
  }

  String _todayKey() {
    final now = DateTime.now().toUtc().add(
          const Duration(hours: 5, minutes: 30),
        );
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }

  String _fmtDateKey(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  // ✅ Runs once per app-open. Catches any day(s) whose final step count
  // never got saved (net was off at 11PM cutoff, app killed, etc).
  // Works identically on Android (Health Connect) and iOS (HealthKit) —
  // both support historical range queries via the same Health() API.
  // Egress: 1 select total (covers all missing days) + upsert only for
  // days whose value actually changed. Zero extra calls on a normal day.
  Future<void> _backfillMissingStepDays(String userId) async {
    if (!isMembershipActive) return;

    // ✅ Don't backfill if Health permission isn't currently granted — avoids
    // writing a false "0 steps" day when we simply can't read real data.
    // Silent check only (no prompt) — the existing step card already handles
    // asking the member to grant/open settings.
    final hasStepPermission = await Health().hasPermissions(
          const [HealthDataType.STEPS],
          permissions: const [HealthDataAccess.READ],
        ) ??
        false;
    if (!hasStepPermission) return; // retries automatically next app open

    final prefs = await SharedPreferences.getInstance();
    final lastSynced = prefs.getString('last_step_sync_date');
    final nowIst = DateTime.now().toUtc().add(
          const Duration(hours: 5, minutes: 30),
        );
    final todayIst = DateTime.utc(nowIst.year, nowIst.month, nowIst.day);

    if (lastSynced == null) {
      await prefs.setString('last_step_sync_date', _fmtDateKey(todayIst));
      return;
    }

    final parts = lastSynced.split('-');
    final lastDate = DateTime.utc(
      int.parse(parts[0]),
      int.parse(parts[1]),
      int.parse(parts[2]),
    );
    var cursor = lastDate.add(const Duration(days: 1));
    final earliestAllowed = todayIst.subtract(const Duration(days: 30));
    if (cursor.isBefore(earliestAllowed)) cursor = earliestAllowed;
    if (!cursor.isBefore(todayIst)) return;

    final missingDates = <DateTime>[];
    for (var d = cursor;
        d.isBefore(todayIst);
        d = d.add(const Duration(days: 1))) {
      missingDates.add(d);
    }

    try {
      final existingRows = await Supabase.instance.client
          .from('step_logs')
          .select('log_date, steps')
          .eq('member_id', userId)
          .gte('log_date', _fmtDateKey(missingDates.first))
          .lt('log_date', _fmtDateKey(todayIst));
      final existingMap = <String, int>{
        for (final r in List<Map<String, dynamic>>.from(existingRows))
          r['log_date'].toString().substring(0, 10):
              (r['steps'] as num?)?.toInt() ?? 0,
      };

      for (final d in missingDates) {
        final dateKey = _fmtDateKey(d);
        final dayStartUtc = d.subtract(const Duration(hours: 5, minutes: 30));
        final dayEndUtc = dayStartUtc.add(const Duration(days: 1));
        int steps;
        try {
          steps =
              await Health().getTotalStepsInInterval(dayStartUtc, dayEndUtc) ??
                  0;
        } catch (_) {
          return; // Health/network failure — retry remaining dates next open.
        }
        if (existingMap[dateKey] != steps) {
          await _upsertStepLog(userId, dateKey, steps);
        }
      }
      await prefs.setString('last_step_sync_date', _fmtDateKey(todayIst));
    } catch (_) {
      // Network failure — last_step_sync_date left untouched, retries next open.
    }
  }

  Future<void> _resolveBaseline(int cumulativeSteps) async {
    if (_stepsAtMidnight != null && _baselineDate == _todayKey()) return;
    final prefs = await SharedPreferences.getInstance();
    final storedDate = prefs.getString('step_baseline_date');
    final storedBaseline = prefs.getInt('step_baseline_value');
    final todayKey = _todayKey();
    if (storedDate == todayKey && storedBaseline != null) {
      if (cumulativeSteps < storedBaseline) {
        _stepsAtMidnight = cumulativeSteps;
      } else {
        _stepsAtMidnight = storedBaseline;
      }
    } else {
      _stepsAtMidnight = cumulativeSteps;
    }
    _baselineDate = todayKey;
    await prefs.setString('step_baseline_date', todayKey);
    await prefs.setInt('step_baseline_value', _stepsAtMidnight!);
  }

  Future<bool> _doSaveStep(String userId, String logDate) async {
    final ok = await _upsertStepLog(userId, logDate, todaySteps);
    final prefs = await SharedPreferences.getInstance();
    if (!ok) {
      // ✅ Store pending save locally (works even if app is killed)
      await prefs.setString('pending_step_log_date', logDate);
      await prefs.setInt('pending_step_log_value', todaySteps);
      return false;
    } else {
      if (prefs.getString('pending_step_log_date') == logDate) {
        await prefs.remove('pending_step_log_date');
        await prefs.remove('pending_step_log_value');
      }
      return true;
    }
  }

  Future<void> _saveTodaySteps() async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;
    if (!isMembershipActive) return; // expired days: don't collect/write steps

    final prefs = await SharedPreferences.getInstance();
    final pendingDate = prefs.getString('pending_step_log_date');
    final pendingSteps = prefs.getInt('pending_step_log_value');
    final todayKey = _todayKey();

    // ✅ Read the shared throttle clock so a widget rebuild (or a different
    // screen like StepCounterScreen also writing steps) can't reset/bypass
    // the 4-hour write limit — one clock, shared via SharedPreferences.
    if (_lastStepSaveTime == null) {
      final storedTime = prefs.getString('last_step_save_time');
      if (storedTime != null) {
        _lastStepSaveTime = DateTime.tryParse(storedTime);
      }
    }

    // ✅ Try to flush pending first if it exists
    if (pendingDate != null && pendingSteps != null) {
      final ok = await _upsertStepLog(userId, pendingDate, pendingSteps);
      if (ok) {
        // Pending flushed successfully - remove it
        await prefs.remove('pending_step_log_date');
        await prefs.remove('pending_step_log_value');
        // ✅ ONLY update throttle state if pending is from TODAY
        if (pendingDate == todayKey) {
          // Today's pending was flushed - use its value as baseline
          _lastSavedSteps = pendingSteps;
          _lastStepSaveTime = DateTime.now();
        }
        // If pending is from yesterday or older, DON'T update _lastSavedSteps
        // because mixing dates would corrupt the throttle calculation
      } else {
        // Pending still failing - don't proceed with today's save
        // to avoid creating another pending record for the same day
        return;
      }
    }

    final now = DateTime.now();
    final logDate = _todayKey();

    // ✅ First save of the day - always save
    if (_lastSavedSteps == -1) {
      final success = await _doSaveStep(userId, logDate);
      if (success) {
        _lastSavedSteps = todaySteps;
        _lastStepSaveTime = now;
        await prefs.setString('last_step_save_time', now.toIso8601String());
      }
      return;
    }

    // ✅ Save to Supabase only once every 6 hours. UI stays live regardless —
    // this only gates how often we write to the database.
    final timeSinceLastSave = _lastStepSaveTime == null
        ? Duration.zero
        : now.difference(_lastStepSaveTime!);
    if (timeSinceLastSave < _stepSaveThrottle) {
      return; // Skip write - 6 hours haven't passed yet
    }

    final success = await _doSaveStep(userId, logDate);
    if (success) {
      _lastSavedSteps = todaySteps;
      _lastStepSaveTime = now;
    }
  }

  Future<bool> _upsertStepLog(String userId, String date, int steps) async {
    try {
      await Supabase.instance.client.from('step_logs').upsert({
        'member_id': userId,
        'log_date': date,
        'steps': steps,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }, onConflict: 'member_id,log_date');
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _flushPendingStepSave() async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;
    final prefs = await SharedPreferences.getInstance();
    final date = prefs.getString('pending_step_log_date');
    final steps = prefs.getInt('pending_step_log_value');
    if (date == null || steps == null) return;
    final ok = await _upsertStepLog(userId, date, steps);
    if (ok) {
      await prefs.remove('pending_step_log_date');
      await prefs.remove('pending_step_log_value');
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

  // _loadStreak() removed - streak data is loaded via loadProfile()
  // ============================================================
  // TODAY'S TASK STATUS - Data is loaded via MasterDataProvider in loadProfile()
  // ============================================================
  // Method removed - task status is loaded from MasterDataProvider
  Future<void> loadProfile() async {
    if (!mounted) return;
    final userId = Supabase.instance.client.auth.currentUser!.id;

    try {
      // Respect the in-memory cache — every write path already calls
      // MasterDataProvider.instance.invalidateCache(userId) right before
      // this runs, so this still gets fresh data whenever it truly changed.
      final data = await MasterDataProvider.instance.fetchMemberData(userId);
      _lastAppliedData = data;
      final profile = data.profile;
      fullName = profile?['full_name'] ?? '';

      // ✅ If fullName is still "Unknown", try direct Supabase query
      if (fullName == 'Unknown' || fullName.isEmpty) {
        try {
          final directProfile = await Supabase.instance.client
              .from('profiles')
              .select('full_name')
              .eq('id', userId)
              .maybeSingle();
          if (directProfile != null && directProfile['full_name'] != null) {
            fullName = directProfile['full_name'] as String;
          }
        } catch (_) {
          // Silently fall back to existing name
        }
      }

      membershipEndDate = profile?['membership_end_date'] ?? '';
      daysLeft = data.daysLeft;
      stepGoal = data.stepGoal;
      signupDate =
          DateTime.tryParse(profile?['created_at'] ?? '') ?? signupDate;

      isMembershipActive = data.isMembershipActive;
      // ✅ Backfill any missed step-log days (net-off protection) —
      // fire-and-forget, active members only, only writes days that changed.
      _backfillMissingStepDays(userId);
      isMembershipExpiringSoon = daysLeft > 0 && daysLeft <= 30;
      isNewMember = membershipEndDate.isEmpty || daysLeft <= 0;

      // ✅ Update state from provider data
      setState(() {
        currentStreak = data.currentStreak;
        todaySteps = data.todaySteps;
        isLoadingStreak = false;

        // ✅ Tasks
        _workoutCompletedToday = data.workoutCompletedToday;
        _measurementsUpdatedToday = data.measurementUpdatedToday;
        _photoStatus['front'] = data.photoFrontUpdated;
        _photoStatus['back'] = data.photoBackUpdated;
      });

      // ✅ Coach info
      final coachId = profile?['assigned_coach_id'];
      if (coachId != null) {
        final coachData = await Supabase.instance.client
            .from('profiles')
            .select('full_name, email')
            .eq('id', coachId)
            .maybeSingle();
        if (mounted) {
          setState(() {
            coach = coachData;
          });
        }
      }

      // ✅ Profile completion check
      profileComplete =
          (profile?['full_name'] as String?)?.isNotEmpty == true &&
              profile?['weight_kg'] != null &&
              profile?['height_cm'] != null &&
              (profile?['goal'] as String?)?.isNotEmpty == true &&
              profile?['date_of_birth'] != null &&
              (profile?['gender'] as String?)?.isNotEmpty == true;

      if (mounted) {
        setState(() {
          isLoadingProfile = false;
        });
      }

      if (!profileComplete && mounted) {
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => _showCompleteProfilePrompt(),
        );
      }

      // 🔔 Real-time + on-open popup: coach assigned/updated diet or workout.
      // Only for active-membership members, and only when the value truly
      // changed since we last showed it (so it never repeats itself).
      if (isMembershipActive && mounted) {
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => _checkPlanUpdatePopups(data, userId),
        );
      }
    } on AuthException catch (e) {
      print('Error loading profile: $e');
      if (mounted) {
        setState(() => isLoadingProfile = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Session expired. Please login again.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } on PostgrestException catch (e) {
      print('Error loading profile: $e');
      if (mounted) {
        setState(() => isLoadingProfile = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Unable to load profile. Please check your connection.',
            ),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } catch (e) {
      print('Error loading profile: $e');
      if (mounted) {
        setState(() => isLoadingProfile = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Network error. Please check your internet connection.',
            ),
            backgroundColor: Colors.orange,
          ),
        );
      }
    }
  }

  /// Compares the member's latest diet/workout `updated_at` against what we
  /// last showed them (stored locally), and pops up an attractive 3D
  /// notification if it's new — "assigned" the very first time, "updated"
  /// every time after that. Also keeps `_dietStatusText` / `_workoutStatusText`
  /// in sync so the coach banner always shows the current "Assigned on /
  /// Updated on" date, not just at the moment it changes. Runs after
  /// realtime pushes AND on app open.
  Future<void> _checkPlanUpdatePopups(
    MemberDashboardData data,
    String userId,
  ) async {
    if (!mounted) return;
    final prefs = await SharedPreferences.getInstance();

    final dietUpdatedAt = data.latestDiet?['updated_at'] as String?;
    final workoutUpdatedAt = data.latestWorkout?['updated_at'] as String?;

    // First time this device has EVER tracked this member: silently
    // remember whatever diet/workout state already exists right now
    // (no popup) instead of treating both as "brand new" and firing two
    // notifications at once. From this point on, only a real future
    // change to either one will trigger its own popup.
    final initKey = 'plan_tracking_initialized_$userId';
    if ((prefs.getBool(initKey) ?? false) == false) {
      if (dietUpdatedAt != null) {
        await prefs.setString('diet_last_seen_$userId', dietUpdatedAt);
      }
      if (workoutUpdatedAt != null) {
        await prefs.setString('workout_last_seen_$userId', workoutUpdatedAt);
      }
      await prefs.setBool(initKey, true);
    }

    if (dietUpdatedAt != null) {
      final dietKey = 'diet_last_seen_$userId';
      final dietKindKey = 'diet_last_kind_$userId';
      final lastSeenDiet = prefs.getString(dietKey);
      if (lastSeenDiet != dietUpdatedAt) {
        final isFirstTime = lastSeenDiet == null;
        await prefs.setString(dietKey, dietUpdatedAt);
        await prefs.setString(
          dietKindKey,
          isFirstTime ? 'assigned' : 'updated',
        );
        if (mounted) {
          await showPlanUpdatePopup(
            context,
            isDiet: true,
            isFirstTime: isFirstTime,
          );
        }
      }
      final dietDate = DateTime.tryParse(dietUpdatedAt);
      if (mounted && dietDate != null) {
        final dietDateIst = dietDate.toUtc().add(
              const Duration(hours: 5, minutes: 30),
            );
        setState(() {
          _dietStatusText = DateFormat('dd/MM/yy h:mm a').format(dietDateIst);
        });
      }
    }

    if (!mounted) return;
    if (workoutUpdatedAt != null) {
      final workoutKey = 'workout_last_seen_$userId';
      final workoutKindKey = 'workout_last_kind_$userId';
      final lastSeenWorkout = prefs.getString(workoutKey);
      if (lastSeenWorkout != workoutUpdatedAt) {
        final isFirstTime = lastSeenWorkout == null;
        await prefs.setString(workoutKey, workoutUpdatedAt);
        await prefs.setString(
          workoutKindKey,
          isFirstTime ? 'assigned' : 'updated',
        );
        if (mounted) {
          await showPlanUpdatePopup(
            context,
            isDiet: false,
            isFirstTime: isFirstTime,
          );
        }
      }
      final workoutDate = DateTime.tryParse(workoutUpdatedAt);
      if (mounted && workoutDate != null) {
        final workoutDateIst = workoutDate.toUtc().add(
              const Duration(hours: 5, minutes: 30),
            );
        setState(() {
          _workoutStatusText = DateFormat(
            'dd/MM/yy h:mm a',
          ).format(workoutDateIst);
        });
      }
    }
  }

  void _showCompleteProfilePrompt() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.cardDark,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
        title: const Row(
          children: [
            Icon(Icons.rocket_launch, color: AppColors.gold),
            SizedBox(width: 10),
            Flexible(
              child: Text(
                'Complete Your Profile',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: Colors.white, fontSize: 17),
              ),
            ),
          ],
        ),
        content: const Text(
          'Add your weight, height, date of birth, gender and goal so your coach can build the right plan for you.',
          style: TextStyle(color: Colors.grey),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(
              'Later',
              style: TextStyle(color: Colors.grey),
            ),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const MemberProfileEditScreen(),
                ),
              );
              loadProfile();
            },
            child: const Text('Complete Now'),
          ),
        ],
      ),
    );
  }

  void _showContactAdminDialog() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.cardDark,
        title: const Text(
          'Contact Admin',
          style: TextStyle(color: Colors.white),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Please contact your admin to renew your membership:',
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.background,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Row(
                children: [
                  Icon(Icons.email, color: AppColors.gold),
                  SizedBox(width: 12),
                  Text(
                    'admin@conquerclub.com',
                    style: TextStyle(color: Colors.white),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.background,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Row(
                children: [
                  Icon(Icons.phone, color: AppColors.gold),
                  SizedBox(width: 12),
                  Text(
                    '+91 98765 43210',
                    style: TextStyle(color: Colors.white),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  void _openPaymentsScreen() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const PaymentsScreen()),
    ).then((_) {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId != null) {
        MasterDataProvider.instance.invalidateCache(userId);
        loadProfile();
      }
    });
  }

  void _openStreaksPage() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const StreaksTab()),
    ).then((_) {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId != null) {
        MasterDataProvider.instance.invalidateCache(userId);
        loadProfile();
      }
    });
  }

  // ============================================================
  // NAVIGATION HELPERS FOR TASKS
  // ============================================================
  void _openWorkoutTab() {
    tabController.animateTo(0);
  }

  void _openStepCounter() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => StepCounterScreen(
          liveTodaySteps: todaySteps,
          initialGoal: stepGoal,
          signupDate: signupDate,
        ),
      ),
    ).then((_) {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId != null) {
        MasterDataProvider.instance.invalidateCache(userId);
        loadProfile();
      }
    });
  }

  void _openMeasurements() {
    print('📏 Opening Measurements from Sunday task');
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const MeasurementsScreen()),
    ).then((_) {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId != null) {
        MasterDataProvider.instance.invalidateCache(userId);
        loadProfile();
      }
    });
  }

  void _openProgressPhotos() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const MemberProgressScreen()),
    ).then((_) {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId != null) {
        MasterDataProvider.instance.invalidateCache(userId);
        loadProfile();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final userId = Supabase.instance.client.auth.currentUser!.id;

    return Scaffold(
      backgroundColor: AppColors.background,
      bottomNavigationBar:
          !isLoadingProfile ? _buildQuickActions(context) : null,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(context),
            _buildStepTrackerCard(),
            // Today's Tasks Card
            _buildTodayTasksCard(),
            _buildCoachBanner(),
            _buildTabBar(),
            Expanded(
              child: TabBarView(
                controller: tabController,
                children: [
                  _WeekWorkoutList(
                    memberId: userId,
                    todayName: todayName,
                    days: days,
                    isMembershipActive: isMembershipActive,
                  ),
                  _MyDietsList(
                    memberId: userId,
                    isMembershipActive: isMembershipActive,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // COMPACT STEP TRACKER CARD
  // ============================================================
  Widget _buildStepTrackerCard() {
    final progress = (todaySteps / stepGoal).clamp(0.0, 1.0);
    final screenWidth = MediaQuery.of(context).size.width;
    final isCompact = screenWidth < 360;
    final hasIssue = stepIssueMessage != null;

    return GestureDetector(
      onTap: hasIssue
          ? (stepIssueCanOpenSettings ? _retryStepPermission : null)
          : () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => StepCounterScreen(
                    liveTodaySteps: todaySteps,
                    initialGoal: stepGoal,
                    signupDate: signupDate,
                  ),
                ),
              );
              loadProfile();
            },
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.fromLTRB(16, 4, 16, 6),
        padding: EdgeInsets.symmetric(
          horizontal: isCompact ? 10 : 12,
          vertical: isCompact ? 6 : 8,
        ),
        decoration: BoxDecoration(
          color: AppColors.cardDark,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.gold.withOpacity(0.12)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.15),
              blurRadius: 6,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: hasIssue
            ? _buildStepIssueCard() // Exact reason instead of a fake/manual step bar
            : Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                '$todaySteps / $stepGoal steps',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w500,
                                  fontSize: isCompact ? 11 : 12,
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              '${(progress * 100).round()}%',
                              style: TextStyle(
                                color: AppColors.gold,
                                fontWeight: FontWeight.bold,
                                fontSize: isCompact ? 10 : 11,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 3),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(3),
                          child: LinearProgressIndicator(
                            value: progress,
                            minHeight: 4,
                            backgroundColor: Colors.white.withOpacity(0.08),
                            valueColor: const AlwaysStoppedAnimation<Color>(
                              AppColors.gold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildStepIssueCard() {
    final isCompact = MediaQuery.of(context).size.width < 360;

    return Row(
      children: [
        // Warning icon
        Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: Colors.orange.withOpacity(0.15),
            borderRadius: BorderRadius.circular(6),
          ),
          child: const Icon(
            Icons.warning_amber_rounded,
            color: Colors.orange,
            size: 16,
          ),
        ),
        const SizedBox(width: 8),

        // Concrete reason + one-tap fix — no manual number entry
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                stepIssueMessage ?? '',
                style: TextStyle(
                  color: Colors.orange,
                  fontSize: isCompact ? 10 : 11,
                  fontWeight: FontWeight.w500,
                ),
              ),
              if (stepIssueCanOpenSettings) ...[
                const SizedBox(height: 6),
                GestureDetector(
                  onTap: _retryStepPermission,
                  child: Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: isCompact ? 8 : 10,
                      vertical: isCompact ? 4 : 6,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.gold,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      stepPermanentlyDenied
                          ? 'Open Settings'
                          : 'Allow Permission',
                      style: TextStyle(
                        color: Colors.black,
                        fontWeight: FontWeight.bold,
                        fontSize: isCompact ? 9 : 10,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  // ============================================================
  // TODAY'S TASKS CARD - Updated to remove steps from streak
  // ============================================================
  Widget _buildTodayTasksCard() {
    final now = DateTime.now().toUtc().add(
          const Duration(hours: 5, minutes: 30),
        );
    final isSunday = now.weekday == DateTime.sunday;
    final isAfterCutoff = isSunday && now.hour >= 21;

    // Skip if membership not active
    if (!isMembershipActive) return const SizedBox.shrink();

    // Build task items based on day
    List<Map<String, dynamic>> tasks = [];

    if (isSunday) {
      // SUNDAY TASKS - Only Photos + Measurements
      final photosDone =
          _photoStatus['front'] == true && _photoStatus['back'] == true;
      final photoCount = (_photoStatus['front'] == true ? 1 : 0) +
          (_photoStatus['back'] == true ? 1 : 0);

      tasks = [
        {
          'icon': '📸',
          'label': 'Photos',
          'completed': photosDone,
          'detail': '${photoCount}/2',
          'progress': photoCount / 2,
          'actionable': !isAfterCutoff && !photosDone,
          'onTap': _openProgressPhotos,
        },
        {
          'icon': '📏',
          'label': 'Measurements',
          'completed': _measurementsUpdatedToday,
          'detail': _measurementsUpdatedToday ? '✅' : 'Tap',
          'progress': _measurementsUpdatedToday ? 1.0 : 0.0,
          'actionable': !isAfterCutoff && !_measurementsUpdatedToday,
          'onTap': _openMeasurements,
        },
      ];
    } else {
      // WEEKDAY TASKS (Mon-Sat) - Only Workout
      final day = DateFormat('EEE').format(now);

      tasks = [
        {
          'icon': '🏋️',
          'label': 'Workout ($day)',
          'completed': _workoutCompletedToday,
          'detail': _workoutCompletedToday ? '✅' : 'Start',
          'progress': _workoutCompletedToday ? 1.0 : 0.0,
          'actionable': !_workoutCompletedToday,
          'onTap': _openWorkoutTab,
        },
      ];
    }

    final completedCount = tasks.where((t) => t['completed'] == true).length;
    final totalCount = tasks.length;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: isSunday ? AppColors.gold.withOpacity(0.08) : AppColors.cardDark,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isSunday
              ? AppColors.gold.withOpacity(0.25)
              : Colors.white.withOpacity(0.06),
          width: isSunday ? 1.2 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Row
          Row(
            children: [
              Icon(
                isSunday ? Icons.event_note : Icons.checklist,
                color: isSunday ? AppColors.gold : Colors.grey.shade400,
                size: 14,
              ),
              const SizedBox(width: 6),
              Text(
                isSunday
                    ? (isAfterCutoff ? '⏰ Sunday Closed' : '📋 Sunday Check-in')
                    : '📋 Today\'s Tasks',
                style: TextStyle(
                  color: isSunday ? AppColors.gold : Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: isSunday
                      ? AppColors.gold.withOpacity(0.15)
                      : Colors.white.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '$completedCount/$totalCount',
                  style: TextStyle(
                    color: isSunday ? AppColors.gold : Colors.grey.shade400,
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              if (isSunday && !isAfterCutoff && completedCount < totalCount)
                const Icon(Icons.timer, color: Colors.orange, size: 12),
            ],
          ),
          const SizedBox(height: 4),
          // Task Rows - Compact
          Row(
            children: tasks.asMap().entries.map((entry) {
              final index = entry.key;
              final task = entry.value;
              final isLast = index == tasks.length - 1;
              final completed = task['completed'] as bool;
              final actionable = task['actionable'] as bool;
              final progress = (task['progress'] as double).clamp(0.0, 1.0);

              return Expanded(
                child: GestureDetector(
                  onTap: actionable ? task['onTap'] as VoidCallback : null,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 3,
                    ),
                    margin: EdgeInsets.only(right: isLast ? 0 : 4),
                    decoration: BoxDecoration(
                      color: completed
                          ? Colors.green.withOpacity(0.08)
                          : (actionable
                              ? AppColors.gold.withOpacity(0.05)
                              : Colors.transparent),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: completed
                            ? Colors.green.withOpacity(0.2)
                            : (actionable
                                ? AppColors.gold.withOpacity(0.15)
                                : Colors.transparent),
                        width: 0.5,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              task['icon'],
                              style: const TextStyle(fontSize: 12),
                            ),
                            const SizedBox(width: 2),
                            Text(
                              task['label'],
                              style: TextStyle(
                                color: completed
                                    ? Colors.grey.shade500
                                    : (actionable
                                        ? Colors.white
                                        : Colors.grey.shade500),
                                fontSize: 9,
                                fontWeight: completed
                                    ? FontWeight.normal
                                    : FontWeight.w500,
                                decoration: completed
                                    ? TextDecoration.lineThrough
                                    : null,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                        const SizedBox(height: 1),
                        // Progress bar or detail
                        if (completed)
                          Text('✅', style: TextStyle(fontSize: 8))
                        else if (progress > 0 && progress < 1)
                          SizedBox(
                            width: 30,
                            height: 3,
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(2),
                              child: LinearProgressIndicator(
                                value: progress,
                                backgroundColor: Colors.grey.shade700,
                                valueColor: const AlwaysStoppedAnimation<Color>(
                                  AppColors.gold,
                                ),
                                minHeight: 3,
                              ),
                            ),
                          )
                        else
                          Text(
                            task['detail'] ?? '',
                            style: TextStyle(
                              color: actionable
                                  ? AppColors.gold
                                  : Colors.grey.shade600,
                              fontSize: 7,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                      ],
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          // Sunday warning
          if (isSunday && !isAfterCutoff && completedCount < totalCount)
            Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Text(
                '⏰ Complete before 9PM to keep streak!',
                style: TextStyle(
                  color: Colors.orange,
                  fontSize: 8,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          if (isSunday && isAfterCutoff && completedCount < totalCount)
            Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Text(
                '⚠️ Deadline passed - streak may break!',
                style: TextStyle(
                  color: Colors.red,
                  fontSize: 8,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    String membershipText;
    Color membershipColor;
    IconData membershipIcon;

    if (isLoadingProfile) {
      membershipText = 'Loading...';
      membershipColor = Colors.grey;
      membershipIcon = Icons.hourglass_empty;
    } else if (isMembershipActive) {
      membershipText = '$daysLeft d left';
      membershipColor = isMembershipExpiringSoon ? Colors.orange : Colors.green;
      membershipIcon = isMembershipExpiringSoon
          ? Icons.warning_amber_rounded
          : Icons.check_circle;
    } else {
      membershipText = 'Expired';
      membershipColor = Colors.red;
      membershipIcon = Icons.cancel;
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 14, 12, 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.cardDark, AppColors.background],
        ),
        border: Border(
          bottom: BorderSide(color: AppColors.gold.withOpacity(0.18)),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.35),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              GestureDetector(
                onTap: _openStreaksPage,
                child: Container(
                  width: 50,
                  height: 50,
                  padding: const EdgeInsets.all(2.5),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: [
                        AppColors.gold,
                        AppColors.gold.withOpacity(0.25),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.gold.withOpacity(0.45),
                        blurRadius: 14,
                        spreadRadius: -2,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Container(
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.background,
                    ),
                    child: Center(
                      child: ShaderMask(
                        shaderCallback: (bounds) => LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            AppColors.gold,
                            AppColors.gold.withOpacity(0.6),
                          ],
                        ).createShader(bounds),
                        child: Text(
                          firstName.isNotEmpty
                              ? firstName[0].toUpperCase()
                              : '?',
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: RichText(
                            text: TextSpan(
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w900,
                              ),
                              children: [
                                const TextSpan(
                                  text: 'Welcome, ',
                                  style: TextStyle(color: Colors.white),
                                ),
                                TextSpan(
                                  text:
                                      isLoadingProfile ? '...' : '$firstName!',
                                  style: const TextStyle(color: AppColors.gold),
                                ),
                              ],
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 1),
                    const Text(
                      'To The Conquer Club 🔥',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    const Text(
                      'Discipline today. Results tomorrow.',
                      style: TextStyle(
                        color: Colors.grey,
                        fontSize: 10,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.logout, color: Colors.grey, size: 20),
                tooltip: 'Logout',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                onPressed: () async {
                  await Supabase.instance.client.auth.signOut();
                  if (context.mounted) {
                    Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(builder: (_) => const LoginScreen()),
                    );
                  }
                },
              ),
            ],
          ),
          const SizedBox(height: 4),
          // Tiny version - tap to check update
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              GestureDetector(
                onTap: _isCheckingUpdate ? null : _checkForUpdate,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  child: Text(
                    _isCheckingUpdate ? '...' : 'v$_currentVersion',
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 8),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              GestureDetector(
                onTap: _openStreaksPage,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        AppColors.gold.withOpacity(0.2),
                        AppColors.gold.withOpacity(0.05),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: currentStreak > 0
                          ? AppColors.gold.withOpacity(0.4)
                          : Colors.grey.withOpacity(0.2),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        currentStreak > 0 ? '🔥' : '⏳',
                        style: const TextStyle(fontSize: 12),
                      ),
                      const SizedBox(width: 3),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Streak',
                            style: TextStyle(
                              color: Colors.grey.shade500,
                              fontSize: 6,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          Text(
                            isLoadingStreak ? '--' : '$currentStreak d',
                            style: TextStyle(
                              color: currentStreak > 0
                                  ? AppColors.gold
                                  : Colors.grey,
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(width: 2),
                      const Icon(
                        Icons.chevron_right,
                        color: Colors.grey,
                        size: 14,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        isMembershipActive
                            ? (isMembershipExpiringSoon
                                ? Colors.orange.withOpacity(0.2)
                                : Colors.green.withOpacity(0.1))
                            : Colors.red.withOpacity(0.2),
                        Colors.transparent,
                      ],
                    ),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: isMembershipActive
                          ? (isMembershipExpiringSoon
                              ? Colors.orange.withOpacity(0.3)
                              : Colors.green.withOpacity(0.2))
                          : Colors.red.withOpacity(0.3),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              membershipIcon,
                              color: membershipColor,
                              size: 12,
                            ),
                            const SizedBox(width: 3),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    isMembershipActive
                                        ? 'Membership'
                                        : 'Access',
                                    style: TextStyle(
                                      color: Colors.grey.shade500,
                                      fontSize: 6,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  Text(
                                    membershipText,
                                    style: TextStyle(
                                      color: membershipColor,
                                      fontSize: 9,
                                      fontWeight: FontWeight.bold,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      GestureDetector(
                        onTap: _openPaymentsScreen,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.gold,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            isMembershipActive ? 'Renew' : 'Pay Now',
                            style: const TextStyle(
                              color: Colors.black,
                              fontSize: 8,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildQuickActions(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.background,
          border: Border(
            top: BorderSide(color: AppColors.gold.withOpacity(0.12)),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _buildQuickActionIcon(
              Icons.person_outline,
              AppColors.gold,
              () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const MemberProfileEditScreen(),
                  ),
                );
                loadProfile();
              },
            ),
            _buildQuickActionIcon(
              Icons.straighten,
              const Color(0xFF4FC3F7),
              () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const MeasurementsScreen()),
              ).then((_) => loadProfile()),
            ),
            _buildQuickActionIcon(
              Icons.show_chart,
              const Color(0xFF81C784),
              () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const WorkoutProgressScreen(),
                ),
              ),
            ),
            _buildQuickActionIcon(
              Icons.camera_alt_outlined,
              const Color(0xFFBA68C8),
              () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const MemberProgressScreen()),
              ).then((_) => loadProfile()),
            ),
            _buildQuickActionIcon(
              Icons.payment,
              const Color(0xFF4CAF50),
              () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const PaymentsScreen()),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickActionIcon(IconData icon, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(right: 12),
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [color.withOpacity(0.15), color.withOpacity(0.05)],
          ),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withOpacity(0.3), width: 1.5),
          boxShadow: [
            BoxShadow(
              color: color.withOpacity(0.1),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Icon(icon, color: color, size: 22),
      ),
    );
  }

  Future<void> _retryStepPermission() async {
    if (stepPermanentlyDenied) {
      await openAppSettings();
      return;
    }
    await _initStepTracker();
  }

  Widget _buildCoachBanner() {
    if (isLoadingProfile) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.cardDark,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.gold.withOpacity(0.15)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.sports, color: AppColors.gold, size: 14),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  coach == null
                      ? 'No coach assigned yet — contact admin.'
                      : 'Your Coach: ${coach!['full_name'] ?? coach!['email']}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          if (_dietStatusText != null)
            Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Row(
                children: [
                  Icon(
                    Icons.restaurant_menu,
                    color: AppColors.gold.withOpacity(0.85),
                    size: 13,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Diet Updated on $_dietStatusText',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.grey.shade400,
                        fontSize: 11,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          if (_workoutStatusText != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Row(
                children: [
                  Icon(
                    Icons.fitness_center,
                    color: AppColors.gold.withOpacity(0.85),
                    size: 13,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Workout Updated on $_workoutStatusText',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.grey.shade400,
                        fontSize: 11,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  // ============================================================
  // UPDATE CHECKER
  // ============================================================
  Future<void> _checkForUpdate() async {
    if (_isCheckingUpdate) return;
    setState(() => _isCheckingUpdate = true);

    try {
      final url = Uri.parse(
        'https://main.conquer-club-app.pages.dev/version.json',
      );
      final response = await http.get(url);
      if (!mounted) return;
      setState(() => _isCheckingUpdate = false);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final hasUpdate = data['version'] != _currentVersion;

        if (hasUpdate) {
          _showUpdateDialog(
            data['version'],
            data['apk_url'] ?? '',
            data['changelog'] ?? '',
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('✅ You have the latest version')),
          );
        }
      } else {
        // ✅ Silently fail — don't show error to user
        // Just do nothing
      }
    } catch (e) {
      // ✅ Silently fail — don't show error to user
      if (mounted) setState(() => _isCheckingUpdate = false);
    }
  }

  void _showUpdateDialog(String version, String apkUrl, String changelog) {
    final isWeb = kIsWeb;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: Row(
          children: [
            const Icon(Icons.system_update_alt, color: Colors.orange),
            const SizedBox(width: 10),
            const Text(
              'Update Available!',
              style: TextStyle(color: Colors.white),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Current: v$_currentVersion',
              style: TextStyle(color: Colors.grey.shade400, fontSize: 13),
            ),
            Text(
              'Latest: v$version',
              style: TextStyle(color: Colors.orange, fontSize: 13),
            ),
            if (changelog.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                changelog,
                style: TextStyle(color: Colors.grey, fontSize: 12),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(
              'Close',
              style: TextStyle(color: Colors.grey),
            ),
          ),
          if (isWeb)
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('🔄 Refresh browser to update!'),
                  ),
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
              ),
              child: const Text('Refresh Now'),
            ),
          if (!isWeb && apkUrl.isNotEmpty)
            ElevatedButton(
              onPressed: () async {
                Navigator.pop(context);
                final url = Uri.parse(apkUrl);
                if (await canLaunchUrl(url)) {
                  await launchUrl(url);
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
                foregroundColor: Colors.black,
              ),
              child: const Text('Download APK'),
            ),
        ],
      ),
    );
  }

  Widget _buildTabBar() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: AppColors.cardDark,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.25),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: TabBar(
        controller: tabController,
        indicator: BoxDecoration(
          gradient: LinearGradient(
            colors: [AppColors.gold, AppColors.gold.withOpacity(0.75)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: AppColors.gold.withOpacity(0.4),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        indicatorSize: TabBarIndicatorSize.tab,
        labelColor: Colors.black,
        unselectedLabelColor: Colors.grey,
        labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
        unselectedLabelStyle: const TextStyle(
          fontWeight: FontWeight.w500,
          fontSize: 11,
        ),
        tabs: const [
          Tab(
            height: 40,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.fitness_center, size: 14),
                SizedBox(width: 4),
                Text('WORKOUT'),
              ],
            ),
          ),
          Tab(
            height: 40,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.restaurant, size: 14),
                SizedBox(width: 4),
                Text('DIET'),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// WEEK WORKOUT LIST - FIXED
// ============================================================
class _WeekWorkoutList extends StatefulWidget {
  final String memberId;
  final String todayName;
  final List<String> days;
  final bool isMembershipActive;

  const _WeekWorkoutList({
    required this.memberId,
    required this.todayName,
    required this.days,
    required this.isMembershipActive,
  });

  @override
  State<_WeekWorkoutList> createState() => _WeekWorkoutListState();
}

class _WeekWorkoutListState extends State<_WeekWorkoutList>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  Map<String, Map<String, dynamic>> workouts = {};
  Map<String, String> todaySessionStatus = {};
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    setState(() => isLoading = true);
    final data = await Supabase.instance.client
        .from('workouts')
        .select()
        .eq('member_id', widget.memberId);

    final List<dynamic> workoutsList = data as List<dynamic>;
    final Map<String, Map<String, dynamic>> map = {};
    for (var w in workoutsList) {
      final workout = w as Map<String, dynamic>;
      map[workout['day_of_week'] as String] = workout;
    }

    final todayWorkout = map[widget.todayName];
    if (todayWorkout != null) {
      final istNow = DateTime.now().toUtc().add(
            const Duration(hours: 5, minutes: 30),
          );
      final startOfDay = DateTime.utc(
        istNow.year,
        istNow.month,
        istNow.day,
      ).subtract(const Duration(hours: 5, minutes: 30));
      final session = await Supabase.instance.client
          .from('workout_sessions')
          .select()
          .eq('workout_id', todayWorkout['id'])
          .eq('member_id', widget.memberId)
          .gte('started_at', startOfDay.toIso8601String())
          .order('started_at', ascending: false)
          .limit(1)
          .maybeSingle();

      if (session != null) {
        todaySessionStatus[todayWorkout['id']] = session['status'];
      }
    }

    setState(() {
      workouts = map;
      isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.gold),
      );
    }

    // Show locked message if membership is not active
    if (!widget.isMembershipActive) {
      return _buildLockedMessage(
        '💪 Workouts Locked',
        'Subscribe to unlock your workout plans',
      );
    }

    return RefreshIndicator(
      onRefresh: load,
      color: AppColors.gold,
      backgroundColor: AppColors.cardDark,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: widget.days.length,
        itemBuilder: (context, index) {
          final day = widget.days[index];
          final isToday = day == widget.todayName;
          final workout = workouts[day];
          final status =
              workout != null ? todaySessionStatus[workout['id']] : null;
          final isCompleted = status == 'completed';
          final isInProgress = status == 'in_progress';

          // Determine if workout can be started (only for today and not completed)
          final now = DateTime.now().toUtc().add(
                const Duration(hours: 5, minutes: 30),
              );
          final isSundayReset =
              now.weekday == DateTime.sunday && now.hour >= 21;
          // FIX: If there's an in-progress session, allow continuing (not view-only)
          // Also allow starting if not completed and membership is active
          final bool canStart = widget.isMembershipActive &&
              isToday &&
              workout != null &&
              !isCompleted &&
              !isSundayReset;

          // If in progress, we should allow continuing the workout (not view-only)
          final bool canContinue = isToday && isInProgress && workout != null;

          final accent = isCompleted
              ? Colors.green
              : isToday
                  ? AppColors.gold
                  : Colors.grey;

          String trailingText;
          Icon? trailingIcon;

          if (isCompleted) {
            trailingText = 'Completed';
            trailingIcon = null;
          } else if (isInProgress) {
            trailingText = 'Continue';
            trailingIcon = null;
          } else if (isToday && isSundayReset) {
            trailingText = 'Reset at 9pm';
            trailingIcon = null;
          } else if (isToday && workout != null && widget.isMembershipActive) {
            trailingText = '';
            trailingIcon = const Icon(
              Icons.chevron_right,
              color: AppColors.gold,
            );
          } else if (!isToday) {
            trailingText = 'Preview';
            trailingIcon = null;
          } else {
            trailingText = 'Locked';
            trailingIcon = null;
          }

          return Container(
            margin: const EdgeInsets.only(bottom: 9),
            decoration: BoxDecoration(
              color: AppColors.cardDark,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: isToday
                    ? AppColors.gold.withOpacity(0.6)
                    : Colors.white.withOpacity(0.04),
                width: isToday ? 1.4 : 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.22),
                  blurRadius: 8,
                  offset: const Offset(0, 4),
                ),
                if (isToday)
                  BoxShadow(
                    color: AppColors.gold.withOpacity(0.15),
                    blurRadius: 12,
                    offset: const Offset(0, 3),
                  ),
              ],
            ),
            clipBehavior: Clip.antiAlias,
            child: IntrinsicHeight(
              child: Row(
                children: [
                  Container(width: 4, color: accent.withOpacity(0.7)),
                  Expanded(
                    child: ListTile(
                      dense: true,
                      visualDensity: const VisualDensity(vertical: -3),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 0,
                      ),
                      leading: Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              accent.withOpacity(0.28),
                              accent.withOpacity(0.1),
                            ],
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: accent.withOpacity(0.3),
                              blurRadius: 6,
                              spreadRadius: -2,
                            ),
                          ],
                        ),
                        child: Icon(
                          isCompleted
                              ? Icons.check_circle
                              : isInProgress
                                  ? Icons.play_circle
                                  : isToday
                                      ? Icons.today
                                      : Icons.remove_red_eye,
                          color: isCompleted
                              ? Colors.green
                              : isInProgress
                                  ? AppColors.gold
                                  : (isToday ? AppColors.gold : Colors.grey),
                          size: 18,
                        ),
                      ),
                      title: Text(
                        day,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                      subtitle: Text(
                        workout == null
                            ? 'No workout assigned'
                            : workout['workout_name'],
                        style: const TextStyle(
                          color: Colors.grey,
                          fontSize: 12.5,
                        ),
                      ),
                      trailing: trailingIcon != null
                          ? trailingIcon
                          : Text(
                              trailingText,
                              style: TextStyle(
                                color: isCompleted
                                    ? Colors.green
                                    : isToday && isSundayReset
                                        ? Colors.orange
                                        : Colors.grey.shade600,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                      onTap: (workout != null)
                          ? () {
                              // FIX: If in progress, allow continuing with edit mode (not view-only)
                              // If not in progress, use canStart to determine view-only
                              final bool isViewOnly = !canStart && !canContinue;

                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => WorkoutDaySessionScreen(
                                    workout: workout,
                                    isViewOnly: isViewOnly,
                                  ),
                                ),
                              ).then((_) => load());
                            }
                          : null,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildLockedMessage(String title, String subtitle) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.lock_outline, color: Colors.grey.shade600, size: 64),
          const SizedBox(height: 16),
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            style: TextStyle(color: Colors.grey.shade500, fontSize: 14),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const PaymentsScreen()),
              );
            },
            icon: const Icon(Icons.lock_open, color: Colors.black),
            label: const Text('UNLOCK NOW'),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// MY DIETS LIST
// ============================================================
class _MyDietsList extends StatefulWidget {
  final String memberId;
  final bool isMembershipActive;

  const _MyDietsList({
    required this.memberId,
    required this.isMembershipActive,
  });

  @override
  State<_MyDietsList> createState() => _MyDietsListState();
}

class _MyDietsListState extends State<_MyDietsList>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  bool isLoading = true;
  List<Map<String, dynamic>> diets = [];

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    setState(() => isLoading = true);
    final data = await Supabase.instance.client
        .from('diets')
        .select()
        .eq('member_id', widget.memberId)
        .order('slot');
    setState(() {
      diets = List<Map<String, dynamic>>.from(data);
      isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.gold),
      );
    }

    // Show locked message if membership is not active
    if (!widget.isMembershipActive) {
      return _buildLockedMessage(
        '🍽️ Diet Plans Locked',
        'Subscribe to unlock your diet plans',
      );
    }

    if (diets.isEmpty) {
      return const Center(
        child: Text(
          'No diet plans assigned yet.',
          style: TextStyle(color: Colors.grey),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: load,
      color: AppColors.gold,
      backgroundColor: AppColors.cardDark,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: diets.length,
        itemBuilder: (context, index) {
          final diet = diets[index];
          final isVeg = diet['slot'] == 1;
          final chipColor = isVeg ? Colors.green : Colors.deepOrange;
          final chipLabel = isVeg ? 'VEG' : 'NON-VEG';

          return Container(
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: AppColors.cardDark,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white.withOpacity(0.04)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.22),
                  blurRadius: 8,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            clipBehavior: Clip.antiAlias,
            child: IntrinsicHeight(
              child: Row(
                children: [
                  Container(width: 4, color: chipColor.withOpacity(0.7)),
                  Expanded(
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 4,
                      ),
                      leading: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              AppColors.gold.withOpacity(0.28),
                              AppColors.gold.withOpacity(0.1),
                            ],
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.gold.withOpacity(0.3),
                              blurRadius: 6,
                              spreadRadius: -2,
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.restaurant,
                          color: AppColors.gold,
                          size: 20,
                        ),
                      ),
                      title: Text(
                        diet['name'] ?? 'Diet Plan',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                      subtitle: Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: chipColor.withOpacity(0.15),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                  color: chipColor.withOpacity(0.4),
                                ),
                              ),
                              child: Text(
                                chipLabel,
                                style: TextStyle(
                                  color: chipColor,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            const Text(
                              'Tap to view',
                              style: TextStyle(
                                color: Colors.grey,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      trailing: const Icon(
                        Icons.chevron_right,
                        color: AppColors.gold,
                      ),
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) =>
                                MemberDietPreviewLoader(dietId: diet['id']),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildLockedMessage(String title, String subtitle) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.lock_outline, color: Colors.grey.shade600, size: 64),
          const SizedBox(height: 16),
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            style: TextStyle(color: Colors.grey.shade500, fontSize: 14),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const PaymentsScreen()),
              );
            },
            icon: const Icon(Icons.lock_open, color: Colors.black),
            label: const Text('UNLOCK NOW'),
          ),
        ],
      ),
    );
  }
}
