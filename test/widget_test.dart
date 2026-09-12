// Real regression tests for two production bugs found during the bug-fix
// pass — kept deliberately backend-free so they run fast and reliably in
// CI without needing a live Supabase instance.

import 'package:flutter_test/flutter_test.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

import 'package:conquer_club/main.dart';
import 'package:conquer_club/providers/master_data_provider.dart';

/// A fake url_launcher backend that just records what it was asked to open,
/// instead of actually opening anything. This is the standard pattern for
/// testing url_launcher without touching a device/browser.
class _RecordingUrlLauncher extends UrlLauncherPlatform {
  String? lastLaunchedUrl;

  @override
  get linkDelegate => null;

  @override
  Future<bool> canLaunch(String url) async => true;

  @override
  Future<bool> launchUrl(String url, LaunchOptions options) async {
    lastLaunchedUrl = url;
    return true;
  }
}

void main() {
  group('Force update "UPDATE NOW" button', () {
    late _RecordingUrlLauncher fakeLauncher;

    setUp(() {
      fakeLauncher = _RecordingUrlLauncher();
      UrlLauncherPlatform.instance = fakeLauncher;
    });

    test('actually attempts to open the download link', () async {
      // Regression test for the exact bug found in production: the button
      // existed and looked correct, but its onPressed body was empty, so
      // tapping it silently did nothing while blocking the whole app.
      await openUpdateUrl(
          'https://play.google.com/store/apps/details?id=com.conquerclub');

      expect(
        fakeLauncher.lastLaunchedUrl,
        'https://play.google.com/store/apps/details?id=com.conquerclub',
      );
    });

    test('does nothing (and does not crash) for an empty URL', () async {
      await openUpdateUrl('');
      expect(fakeLauncher.lastLaunchedUrl, isNull);
    });
  });

  group('MasterDataProvider cache pruning', () {
    test('removes the oldest entries down to maxEntries', () {
      final keys = List.generate(60, (i) => 'member_$i');
      final toRemove = MasterDataProvider.keysToPrune(keys, keys.length, 50);
      expect(toRemove.length, 10);
      expect(toRemove, keys.sublist(0, 10));
    });

    test('never throws even if entryCount is larger than the key list', () {
      // Regression test for the exact bug found in production: pruning
      // used to compute the removal count from a different number
      // (_cache.length) than the list it was slicing (_cacheTimestamps
      // keys). If those two ever drifted apart, sublist() would be asked
      // for more items than existed and crash. This proves it can't.
      final keys = List.generate(5, (i) => 'member_$i');
      expect(
        () => MasterDataProvider.keysToPrune(keys, 999, 50),
        returnsNormally,
      );
      final toRemove = MasterDataProvider.keysToPrune(keys, 999, 50);
      expect(toRemove.length, lessThanOrEqualTo(keys.length));
    });

    test('removes nothing when already under the limit', () {
      final keys = List.generate(10, (i) => 'member_$i');
      final toRemove = MasterDataProvider.keysToPrune(keys, keys.length, 50);
      expect(toRemove, isEmpty);
    });
  });
}
