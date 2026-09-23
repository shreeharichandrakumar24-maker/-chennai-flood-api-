import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;

/// API Configuration
///
/// Supports two modes:
/// 1. Same WiFi   — server runs on local network (e.g. http://192.168.1.7:8000)
/// 2. Any Network — server exposes ngrok public URL (e.g. https://xxx.ngrok-free.app)
///
/// Both modes work through the Settings screen.
class ApiConfig {
  static const String _storageKey = 'api_base_url';

  /// SINGLE source of truth for the backend base URL default.
  /// All API calls, display strings, and Settings UI must reference this
  /// (or the persisted override) — never hardcode the URL elsewhere.
  static const String defaultUrl = 'https://chennai-flood-api.onrender.com';
  static const String _defaultUrl = defaultUrl;
  static String? _baseUrl;

  /// Get the current base URL (loads from storage on first access)
  static Future<String> getBaseUrl() async {
    if (_baseUrl != null) return _baseUrl!;
    final prefs = await SharedPreferences.getInstance();
    _baseUrl = prefs.getString(_storageKey) ?? _defaultUrl;
    return _baseUrl!;
  }

  /// Synchronous getter — use only after getBaseUrl() has been called once
  static String get baseUrl => _baseUrl ?? _defaultUrl;

  /// Save a new base URL to persistent storage.
  /// Strips ALL whitespace (pasted URLs often carry stray spaces/newlines
  /// that would otherwise break every request).
  static Future<void> setBaseUrl(String url) async {
    _baseUrl = url.replaceAll(RegExp(r'\s+'), '').replaceAll(RegExp(r'/+$'), '');
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_storageKey, _baseUrl!);
  }

  /// Returns true if the saved URL looks like a public URL
  static bool get isPublicUrl {
    final u = _baseUrl ?? _defaultUrl;
    return u.contains('ngrok') ||
        u.contains('onrender') ||
        u.contains('railway') ||
        u.contains('duckdns.org') ||
        u.contains('trycloudflare.com') ||
        u.contains('cfargotunnel.com');
  }

  /// Human-readable source label for the current URL.
  /// Used by Dashboard "Connected via" + "Model Details" so a URL change
  /// in Settings is immediately reflected on next refresh.
  static String get connectionLabel {
    final u = _baseUrl ?? _defaultUrl;
    return isPublicUrl ? '🌐 Public ($u)' : '📶 Local ($u)';
  }

  /// Current URL for display (sync, safe to call after getBaseUrl() in main).
  static String get currentUrl => _baseUrl ?? _defaultUrl;

  /// Try to auto-detect the server.
  /// Checks saved URL first, then scans common local IPs on port 8000.
  static Future<String?> autoDetectServer() async {
    // Try the current saved URL first
    final currentUrl = await getBaseUrl();
    if (await _testUrl(currentUrl)) return currentUrl;

    // Scan common local subnets on port 8000
    final prefixes = [
      '192.168.1',
      '192.168.0',
      '192.168.43',
      '10.0.2',
      '172.20.10',
    ];

    final hosts = [1, 2, 3, 5, 7, 8, 10, 100, 200, 254];

    for (final prefix in prefixes) {
      for (final host in hosts) {
        final url = 'http://$prefix.$host:8000';
        if (await _testUrl(url)) return url;
      }
    }

    // Try localhost
    if (await _testUrl('http://localhost:8000')) {
      return 'http://localhost:8000';
    }

    return null;
  }

  static Future<bool> _testUrl(String baseUrl) async {
    // Fast probe for LAN scan; use testCandidate() for public/Render URLs.
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/api/v1/status'))
          .timeout(const Duration(seconds: 2));
      return response.statusCode == 200 &&
          response.body.contains('chennai-flood-api');
    } catch (_) {
      return false;
    }
  }

  static bool _isPublic(String url) =>
      url.contains('ngrok') ||
      url.contains('onrender') ||
      url.contains('railway') ||
      url.contains('duckdns.org') ||
      url.contains('trycloudflare.com') ||
      url.contains('cfargotunnel.com');

  /// Test a candidate URL WITHOUT saving it (so a failed Render wake-up
  /// never clobbers the last working URL). Public hosts get a long timeout
  /// because Render free tier cold-starts in 30-60s.
  ///
  /// Returns 'ok' (serves predictions), 'degraded' (reachable but NOT
  /// serving predictions yet — starting up / rate-limited), or 'fail'.
  /// Callers must NOT report success on 'degraded': that is exactly the
  /// "connected successfully but nothing works" trap.
  static Future<String> testCandidate(String rawUrl) async {
    final url =
        rawUrl.replaceAll(RegExp(r'\s+'), '').replaceAll(RegExp(r'/+$'), '');
    if (url.isEmpty) return 'fail';
    final public = _isPublic(url);
    try {
      final response = await http
          .get(Uri.parse('$url/api/v1/status'))
          .timeout(Duration(seconds: public ? 60 : 8));
      if (response.statusCode != 200 ||
          !response.body.contains('chennai-flood-api')) {
        return 'fail';
      }
      try {
        final Map<String, dynamic> body =
            Map<String, dynamic>.from(jsonDecode(response.body) as Map);
        // 'ok' means predictions are actually servable. Anything else
        // (e.g. 'degraded' with last_refresh=null) means the server is up
        // but /prediction will 503 — report it honestly.
        return body['status'] == 'ok' ? 'ok' : 'degraded';
      } catch (_) {
        return 'degraded';
      }
    } catch (_) {
      return 'fail';
    }
  }

  static String get status => '$baseUrl/api/v1/status';
  static String get weather => '$baseUrl/api/v1/weather';
  static String get prediction => '$baseUrl/api/v1/prediction';
  static String get predictionRefresh => '$baseUrl/api/v1/prediction/refresh';
  static String get predictionHistory => '$baseUrl/api/v1/prediction/history';
  static String get complaints => '$baseUrl/api/v1/complaints';
}
