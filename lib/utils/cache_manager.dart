import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class CacheManager {
  static const String _membersCacheKey = 'cached_members';
  static const String _membersTimestampKey = 'cached_members_timestamp';
  static const Duration _cacheDuration = Duration(minutes: 5);

  /// Save members list to local SharedPreferences cache
  static Future<void> saveMembers(List<Map<String, dynamic>> members) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonString = jsonEncode(members);
      await prefs.setString(_membersCacheKey, jsonString);
      await prefs.setString(
        _membersTimestampKey,
        DateTime.now().toIso8601String(),
      );
    } catch (_) {
      // Fail silently if storage write fails
    }
  }

  /// Get members from cache if not expired (valid for 5 mins)
  static Future<List<Map<String, dynamic>>?> getMembers() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonString = prefs.getString(_membersCacheKey);
      final timestamp = prefs.getString(_membersTimestampKey);

      if (jsonString == null || timestamp == null) return null;

      final cachedTime = DateTime.parse(timestamp);
      if (DateTime.now().difference(cachedTime) > _cacheDuration) {
        return null; // Cache expired
      }

      final List<dynamic> decoded = jsonDecode(jsonString);
      return decoded.map((e) => Map<String, dynamic>.from(e)).toList();
    } catch (_) {
      // If corrupted, fallback to null (fetches fresh data)
      return null;
    }
  }

  /// Completely clear all cached data
  static Future<void> clearCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_membersCacheKey);
      await prefs.remove(_membersTimestampKey);
    } catch (_) {}
  }

  /// Invalidate cache timestamp to force next fetch to be fresh
  static Future<void> invalidateCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_membersTimestampKey);
    } catch (_) {}
  }
}
