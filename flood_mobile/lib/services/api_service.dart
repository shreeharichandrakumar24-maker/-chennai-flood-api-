import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../config/api_config.dart';
import '../models/prediction_model.dart';
import 'api_exception.dart';
import 'cache_service.dart';

/// Central API layer — single source for the backend base URL (via
/// [ApiConfig]), with retry + caching + real error states.
///
/// Retry policy: 3 attempts, exponential backoff 2s, 5s, 10s.
class ApiService {
  static const List<Duration> _backoff = [
    Duration(seconds: 2),
    Duration(seconds: 5),
    Duration(seconds: 10),
  ];

  /// Generic retry wrapper. [onAttempt] fires before each attempt (1-based)
  /// so the UI can show a distinct "Connection failed — retrying..."
  /// banner instead of a fake-empty state.
  static Future<T> withRetry<T>(
    Future<T> Function() fn, {
    void Function(int attempt)? onAttempt,
    String label = 'request',
  }) async {
    Object? lastError;
    for (var attempt = 1; attempt <= 3; attempt++) {
      try {
        onAttempt?.call(attempt);
        return await fn();
      } catch (e) {
        lastError = e;
        debugPrint('[ApiService] $label attempt $attempt/3 failed: $e');
        if (attempt < 3) {
          await Future.delayed(_backoff[attempt - 1]);
        }
      }
    }
    if (lastError is ApiException) throw lastError;
    throw ApiException('Failed after 3 attempts: $lastError',
        isConnectionError: true);
  }

  /// Helper to get the current base URL (ensures it's loaded).
  /// Single source: [ApiConfig.getBaseUrl] — never hardcoded elsewhere.
  static Future<String> _getUrl(String endpoint) async {
    final baseUrl = await ApiConfig.getBaseUrl();
    return '$baseUrl$endpoint';
  }

  /// Build an error that INCLUDES the server's response body (FastAPI puts
  /// the real cause in {"detail": "..."}), so a 503 shows e.g.
  /// "Prediction unavailable: 429 ..." instead of a bare "HTTP 503".
  static ApiException _serverError(
      String label, http.Response response) {
    String detail = '';
    try {
      final body = jsonDecode(response.body);
      if (body is Map && body['detail'] != null) {
        detail = ' — ${body['detail']}';
      } else if (response.body.length < 300) {
        detail = ' — ${response.body}';
      }
    } catch (_) {
      if (response.body.isNotEmpty && response.body.length < 300) {
        detail = ' — ${response.body}';
      }
    }
    debugPrint('[ApiService] $label failed HTTP ${response.statusCode}$detail');
    return ApiException('$label failed: HTTP ${response.statusCode}$detail',
        statusCode: response.statusCode);
  }

  static ApiException _toApiException(Object e, {int? statusCode}) {
    if (e is ApiException) return e;
    if (e is TimeoutException) {
      return const ApiException('Connection timed out',
          isConnectionError: true);
    }
    final msg = e.toString();
    final isConn = msg.contains('SocketException') ||
        msg.contains('Connection refused') ||
        msg.contains('Failed host lookup') ||
        msg.contains('Network is unreachable') ||
        msg.contains('Connection reset') ||
        msg.contains('timed out');
    return ApiException(msg,
        statusCode: statusCode, isConnectionError: isConn);
  }

  /// Render free tier cold-starts in 30-60s; local LAN answers in ms.
  /// Public hosts get long timeouts so a waking Render service succeeds
  /// on the first attempt instead of timing out.
  static Future<Duration> _timeoutFor(String url,
      {required int localSeconds, required int publicSeconds}) async {
    final base = await ApiConfig.getBaseUrl();
    final public = base.contains('onrender') ||
        base.contains('ngrok') ||
        base.contains('railway') ||
        base.contains('duckdns.org') ||
        base.contains('trycloudflare.com');
    return Duration(seconds: public ? publicSeconds : localSeconds);
  }

  /// Fetch current weather for Chennai. Throws [ApiException] on failure.
  static Future<WeatherResponse> fetchWeather() async {
    try {
      final url = await _getUrl('/api/v1/weather');
      debugPrint('[ApiService] GET $url');
      final timeout =
          await _timeoutFor(url, localSeconds: 15, publicSeconds: 50);
      final response =
          await http.get(Uri.parse(url)).timeout(timeout);

      debugPrint(
          '[ApiService] RAW /weather (${response.statusCode}): ${response.body.length > 2000 ? '${response.body.substring(0, 2000)}...[truncated]' : response.body}');
      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        await CacheService.saveWeather(response.body);
        return WeatherResponse.fromJson(json);
      }
      throw _serverError('Weather request', response);
    } catch (e) {
      throw _toApiException(e);
    }
  }

  /// Fetch latest flood prediction. Throws [ApiException] on failure.
  /// Logs the RAW JSON right before parsing (P3 diagnosis step).
  static Future<PredictionResponse> fetchPrediction() async {
    try {
      final url = await _getUrl('/api/v1/prediction');
      debugPrint('[ApiService] GET $url');
      final timeout =
          await _timeoutFor(url, localSeconds: 15, publicSeconds: 50);
      final response =
          await http.get(Uri.parse(url)).timeout(timeout);

      debugPrint(
          '[ApiService] RAW /prediction (${response.statusCode}): ${response.body.length > 3000 ? '${response.body.substring(0, 3000)}...[truncated]' : response.body}');
      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        await CacheService.savePrediction(response.body);
        return PredictionResponse.fromJson(json);
      }
      throw _serverError('Prediction request', response);
    } catch (e) {
      throw _toApiException(e);
    }
  }

  /// Force a prediction refresh. Throws [ApiException] on failure.
  static Future<PredictionResponse> refreshPrediction() async {
    try {
      final url = await _getUrl('/api/v1/prediction/refresh');
      debugPrint('[ApiService] POST $url');
      final timeout =
          await _timeoutFor(url, localSeconds: 20, publicSeconds: 60);
      final response =
          await http.post(Uri.parse(url)).timeout(timeout);

      debugPrint(
          '[ApiService] RAW /prediction/refresh (${response.statusCode}): ${response.body.length > 3000 ? '${response.body.substring(0, 3000)}...[truncated]' : response.body}');
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final pred = data['prediction'];
        if (pred is Map<String, dynamic>) {
          await CacheService.savePrediction(jsonEncode(pred));
          return PredictionResponse.fromJson(pred);
        }
        throw const ApiException('Malformed refresh response: '
            'missing "prediction" object');
      }
      throw _serverError('Prediction refresh', response);
    } catch (e) {
      throw _toApiException(e);
    }
  }

  /// Check API health status. Throws [ApiException] on failure.
  static Future<Map<String, dynamic>> fetchStatus() async {
    try {
      final url = await _getUrl('/api/v1/status');
      debugPrint('[ApiService] GET $url');
      final timeout =
          await _timeoutFor(url, localSeconds: 10, publicSeconds: 60);
      final response =
          await http.get(Uri.parse(url)).timeout(timeout);

      if (response.statusCode == 200) {
        final json =
            jsonDecode(response.body) as Map<String, dynamic>;
        await CacheService.saveStatus(response.body);
        return json;
      }
      throw _serverError('Status request', response);
    } catch (e) {
      throw _toApiException(e);
    }
  }

  /// Submit a complaint. Throws [ApiException] on failure so the form
  /// can keep user data and show a retry option.
  static Future<Complaint> submitComplaint(Complaint complaint) async {
    try {
      final url = await _getUrl('/api/v1/complaints');
      final timeout =
          await _timeoutFor(url, localSeconds: 15, publicSeconds: 45);
      final response = await http
          .post(
            Uri.parse(url),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(complaint.toJson()),
          )
          .timeout(timeout);

      if (response.statusCode == 201) {
        return Complaint.fromJson(
            jsonDecode(response.body) as Map<String, dynamic>);
      }
      throw _serverError('Report submit', response);
    } catch (e) {
      throw _toApiException(e);
    }
  }

  /// Fetch all complaints. Throws [ApiException] on failure.
  static Future<List<Complaint>> fetchComplaints({String? status}) async {
    try {
      var url = await _getUrl('/api/v1/complaints');
      if (status != null) url += '?status=$status';
      final timeout =
          await _timeoutFor(url, localSeconds: 10, publicSeconds: 45);

      final response =
          await http.get(Uri.parse(url)).timeout(timeout);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final items = data['items'] as List? ?? [];
        return items
            .map((c) => Complaint.fromJson(
                Map<String, dynamic>.from(c as Map)))
            .toList();
      }
      throw _serverError('Reports list request', response);
    } catch (e) {
      throw _toApiException(e);
    }
  }

  /// Fetch prediction history. Throws [ApiException] on failure.
  static Future<List<Map<String, dynamic>>> fetchPredictionHistory(
      {int limit = 20}) async {
    try {
      final url = await _getUrl('/api/v1/prediction/history?limit=$limit');
      final timeout =
          await _timeoutFor(url, localSeconds: 10, publicSeconds: 45);
      final response =
          await http.get(Uri.parse(url)).timeout(timeout);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as List;
        return List<Map<String, dynamic>>.from(
            data.map((e) => Map<String, dynamic>.from(e as Map)));
      }
      throw _serverError('History request', response);
    } catch (e) {
      throw _toApiException(e);
    }
  }

  /// Direct live-weather fallback straight from Open-Meteo (no backend).
  /// Used by the Forecast screen when the backend (local or Render) is
  /// unreachable, so live weather still works. Shape matches the backend
  /// /weather response subset the app renders.
  static Future<WeatherResponse> fetchDirectWeather() async {
    const url =
        'https://api.open-meteo.com/v1/forecast?latitude=13.0827&longitude=80.2707'
        '&current=temperature_2m,apparent_temperature,relative_humidity_2m,precipitation,weather_code,wind_speed_10m,cloud_cover'
        '&daily=precipitation_sum,temperature_2m_max,temperature_2m_min'
        '&past_days=3&forecast_days=7&timezone=Asia%2FKolkata';
    try {
      debugPrint('[ApiService] GET (direct) $url');
      final response = await http
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 25));
      if (response.statusCode != 200) {
        throw ApiException(
            'Open-Meteo error: HTTP ${response.statusCode}',
            statusCode: response.statusCode);
      }
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final cur = Map<String, dynamic>.from(data['current'] as Map);
      final daily = Map<String, dynamic>.from(data['daily'] as Map);
      const wmo = {
        0: 'Clear sky', 1: 'Mainly clear', 2: 'Partly cloudy', 3: 'Overcast',
        51: 'Light drizzle', 53: 'Drizzle', 55: 'Dense drizzle',
        61: 'Light rain', 63: 'Rain', 65: 'Heavy rain',
        80: 'Light rain showers', 81: 'Rain showers', 82: 'Violent rain showers',
        95: 'Thunderstorm', 96: 'Thunderstorm with hail', 99: 'Thunderstorm with hail',
      };
      final code = (cur['weather_code'] as num?)?.toInt() ?? 0;
      final times = List<String>.from(daily['time'] as List);
      final precips = List<dynamic>.from(daily['precipitation_sum'] as List);
      final tmax = List<dynamic>.from(daily['temperature_2m_max'] as List);
      final tmin = List<dynamic>.from(daily['temperature_2m_min'] as List);
      final forecast = <Map<String, dynamic>>[];
      for (var i = 1; i < times.length; i++) {
        forecast.add({
          'date': times[i],
          'precip_mm': (precips[i] as num?)?.toDouble() ?? 0.0,
          't_max': (tmax[i] as num?)?.toDouble() ?? 0.0,
          't_min': (tmin[i] as num?)?.toDouble() ?? 0.0,
        });
      }
      return WeatherResponse.fromJson({
        'source': 'open-meteo-direct',
        'fetched_at': DateTime.now().toUtc().toIso8601String(),
        'today_iso': times.isNotEmpty ? times[0] : null,
        'current': {
          'temp_c': (cur['temperature_2m'] as num?)?.toDouble() ?? 0.0,
          'feels_like_c':
              (cur['apparent_temperature'] as num?)?.toDouble() ?? 0.0,
          'humidity_pct':
              (cur['relative_humidity_2m'] as num?)?.toInt() ?? 0,
          'precip_mm': (cur['precipitation'] as num?)?.toDouble() ?? 0.0,
          'wind_kmh': (cur['wind_speed_10m'] as num?)?.toDouble() ?? 0.0,
          'cloud_pct': (cur['cloud_cover'] as num?)?.toInt() ?? 0,
          'weather_code': code,
          'description': wmo[code] ?? 'Unknown',
          'icon': 'unknown',
        },
        'forecast': forecast,
      });
    } catch (e) {
      throw _toApiException(e);
    }
  }
}
