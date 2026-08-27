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
  static const String _defaultUrl = 'https://chennai-flood-api.onrender.com';
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

  /// Save a new base URL to persistent storage
  static Future<void> setBaseUrl(String url) async {
    _baseUrl = url.replaceAll(RegExp(r'/+$'), '');
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_storageKey, _baseUrl!);
  }

  /// Returns true if the saved URL looks like a public URL
  static bool get isPublicUrl =>
      _baseUrl?.contains('ngrok') == true ||
      _baseUrl?.contains('onrender') == true ||
      _baseUrl?.contains('railway') == true ||
      _baseUrl?.contains('duckdns.org') == true ||
      _baseUrl?.contains('trycloudflare.com') == true ||
      _baseUrl?.contains('cfargotunnel.com') == true;

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

  static String get status => '$baseUrl/api/v1/status';
  static String get weather => '$baseUrl/api/v1/weather';
  static String get prediction => '$baseUrl/api/v1/prediction';
  static String get predictionRefresh => '$baseUrl/api/v1/prediction/refresh';
  static String get predictionHistory => '$baseUrl/api/v1/prediction/history';
  static String get complaints => '$baseUrl/api/v1/complaints';
}
