import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/api_config.dart';
import '../models/prediction_model.dart';

class ApiService {
  /// Helper to get the current base URL (ensures it's loaded)
  static Future<String> _getUrl(String endpoint) async {
    final baseUrl = await ApiConfig.getBaseUrl();
    return '$baseUrl$endpoint';
  }

  /// Fetch current weather for Chennai
  static Future<WeatherResponse?> fetchWeather() async {
    try {
      final url = await _getUrl('/api/v1/weather');
      final response = await http
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        return WeatherResponse.fromJson(jsonDecode(response.body));
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  /// Fetch latest flood prediction
  static Future<PredictionResponse?> fetchPrediction() async {
    try {
      final url = await _getUrl('/api/v1/prediction');
      final response = await http
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        return PredictionResponse.fromJson(jsonDecode(response.body));
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  /// Force a prediction refresh
  static Future<PredictionResponse?> refreshPrediction() async {
    try {
      final url = await _getUrl('/api/v1/prediction/refresh');
      final response = await http
          .post(Uri.parse(url))
          .timeout(const Duration(seconds: 20));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return PredictionResponse.fromJson(data['prediction'] ?? {});
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  /// Check API health status
  static Future<Map<String, dynamic>?> fetchStatus() async {
    try {
      final url = await _getUrl('/api/v1/status');
      final response = await http
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  /// Submit a complaint
  static Future<Complaint?> submitComplaint(Complaint complaint) async {
    try {
      final url = await _getUrl('/api/v1/complaints');
      final response = await http
          .post(
            Uri.parse(url),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(complaint.toJson()),
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 201) {
        return Complaint.fromJson(jsonDecode(response.body));
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  /// Fetch all complaints
  static Future<List<Complaint>> fetchComplaints({String? status}) async {
    try {
      var url = await _getUrl('/api/v1/complaints');
      if (status != null) url += '?status=$status';

      final response = await http
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final items = data['items'] as List? ?? [];
        return items.map((c) => Complaint.fromJson(c)).toList();
      }
      return [];
    } catch (e) {
      return [];
    }
  }

  /// Fetch prediction history
  static Future<List<Map<String, dynamic>>> fetchPredictionHistory({int limit = 20}) async {
    try {
      final url = await _getUrl('/api/v1/prediction/history?limit=$limit');
      final response = await http
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return List<Map<String, dynamic>>.from(data);
      }
      return [];
    } catch (e) {
      return [];
    }
  }
}
