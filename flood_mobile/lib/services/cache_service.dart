import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// Persists the last successful full backend response so a fetch failure
/// can show "Last known data — X minutes ago, not live" instead of
/// blank/zero fields.
class CacheService {
  static const _kPrediction = 'cached_prediction_json';
  static const _kPredictionAt = 'cached_prediction_time';
  static const _kWeather = 'cached_weather_json';
  static const _kWeatherAt = 'cached_weather_time';
  static const _kStatus = 'cached_status_json';
  static const _kStatusAt = 'cached_status_time';

  static Future<void> savePrediction(String rawJson) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kPrediction, rawJson);
    await p.setString(_kPredictionAt, DateTime.now().toIso8601String());
  }

  static Future<void> saveWeather(String rawJson) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kWeather, rawJson);
    await p.setString(_kWeatherAt, DateTime.now().toIso8601String());
  }

  static Future<void> saveStatus(String rawJson) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kStatus, rawJson);
    await p.setString(_kStatusAt, DateTime.now().toIso8601String());
  }

  static Future<({Map<String, dynamic> json, DateTime at})?>
      loadPrediction() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_kPrediction);
    final atRaw = p.getString(_kPredictionAt);
    if (raw == null) return null;
    try {
      final at =
          atRaw != null ? DateTime.parse(atRaw) : DateTime.now();
      return (
        json: Map<String, dynamic>.from(jsonDecode(raw)),
        at: at,
      );
    } catch (_) {
      return null;
    }
  }

  static Future<({Map<String, dynamic> json, DateTime at})?>
      loadWeather() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_kWeather);
    final atRaw = p.getString(_kWeatherAt);
    if (raw == null) return null;
    try {
      final at =
          atRaw != null ? DateTime.parse(atRaw) : DateTime.now();
      return (
        json: Map<String, dynamic>.from(jsonDecode(raw)),
        at: at,
      );
    } catch (_) {
      return null;
    }
  }

  static Future<({Map<String, dynamic> json, DateTime at})?>
      loadStatus() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_kStatus);
    final atRaw = p.getString(_kStatusAt);
    if (raw == null) return null;
    try {
      final at =
          atRaw != null ? DateTime.parse(atRaw) : DateTime.now();
      return (
        json: Map<String, dynamic>.from(jsonDecode(raw)),
        at: at,
      );
    } catch (_) {
      return null;
    }
  }

  /// Minutes since [at], for the "X minutes ago, not live" label.
  static int minutesAgo(DateTime at) {
    return DateTime.now().difference(at).inMinutes;
  }

  static String staleLabel(DateTime at) {
    final mins = minutesAgo(at);
    if (mins < 1) return 'Last known data — just now, not live';
    if (mins == 1) return 'Last known data — 1 minute ago, not live';
    if (mins < 60) return 'Last known data — $mins minutes ago, not live';
    final hrs = mins ~/ 60;
    if (hrs == 1) return 'Last known data — 1 hour ago, not live';
    return 'Last known data — $hrs hours ago, not live';
  }
}
