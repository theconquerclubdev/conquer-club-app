import 'dart:async';
import 'dart:convert';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:pedometer/pedometer.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Runs only on Android, only when Health Connect isn't available/granted.
/// Keeps counting steps from the raw hardware sensor all day long, even
/// with the app fully closed — no Health Connect dependency at all.
class StepTaskHandler extends TaskHandler {
  StreamSubscription<StepCount>? _sub;
  int? _baseline;
  String? _baselineDate;

  String _todayKeyIst() {
    final now = DateTime.now().toUtc().add(const Duration(hours: 5, minutes: 30));
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    _sub = Pedometer.stepCountStream.listen((event) async {
      final todayKey = _todayKeyIst();
      final prefs = await SharedPreferences.getInstance();
      if (_baselineDate != todayKey) {
        final storedDate = prefs.getString('pedo_baseline_date');
        final storedBase = prefs.getInt('pedo_baseline_value');
        _baseline = (storedDate == todayKey && storedBase != null && event.steps >= storedBase)
            ? storedBase
            : event.steps;
        _baselineDate = todayKey;
        await prefs.setString('pedo_baseline_date', todayKey);
        await prefs.setInt('pedo_baseline_value', _baseline!);
      }
      final delta = (event.steps - (_baseline ?? event.steps)).clamp(0, 1000000);

      // Same local-storage format MasterDataProvider already reads —
      // written here so it's picked up and synced next time app opens.
      final raw = prefs.getString('pending_step_days_v1');
      final map = raw != null
          ? Map<String, dynamic>.from(jsonDecode(raw))
          : <String, dynamic>{};
      final existing = (map[todayKey] as num?)?.toInt() ?? 0;
      if (delta > existing) {
        map[todayKey] = delta;
        await prefs.setString('pending_step_days_v1', jsonEncode(map));
      }
      FlutterForegroundTask.updateService(
        notificationTitle: 'Conquer Club',
        notificationText: '$delta steps today',
      );
    }, onError: (_) {});
  }

  @override
  void onRepeatEvent(DateTime timestamp) {}

  @override
  Future<void> onDestroy(DateTime timestamp) async {
    await _sub?.cancel();
  }
}
