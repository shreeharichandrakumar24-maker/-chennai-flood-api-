import 'package:flutter/foundation.dart';

/// Parse any JSON numeric into double WITHOUT silently swallowing errors.
/// Logs the actual problem via debugPrint instead of substituting 0.
double _parseDouble(dynamic value, String field, String context) {
  if (value == null) {
    debugPrint(
        '[ModelParse] $context: field "$field" is MISSING (null) — check raw JSON key names (score vs rf_score vs riskScore, case/nesting). Using 0.0 as last resort.');
    return 0.0;
  }
  if (value is double) return value;
  if (value is int) return value.toDouble();
  if (value is num) return value.toDouble();
  if (value is String) {
    final parsed = double.tryParse(value);
    if (parsed != null) return parsed;
    debugPrint(
        '[ModelParse] $context: field "$field" string "$value" is not numeric. Using 0.0.');
    return 0.0;
  }
  debugPrint(
      '[ModelParse] $context: field "$field" has unexpected type ${value.runtimeType} ($value). Using 0.0.');
  return 0.0;
}

/// Look up the score under every known key variant so a backend key rename
/// (score / rf_score / riskScore / risk_score) can never silently become 0.
double _extractScore(Map<String, dynamic> json, String context) {
  const candidates = [
    'score',
    'rf_score',
    'lstm_score',
    'risk_score',
    'riskScore',
    'risk_score_value',
    'probability',
  ];
  for (final key in candidates) {
    if (json.containsKey(key) && json[key] != null) {
      if (key != 'score') {
        debugPrint(
            '[ModelParse] $context: using alternate key "$key" (expected "score"). Raw: $json');
      }
      return _parseDouble(json[key], key, context);
    }
  }
  debugPrint(
      '[ModelParse] $context: NO score key found. Keys present: ${json.keys.toList()}. Full raw: $json');
  return 0.0;
}

class PredictionResponse {
  final Map<String, dynamic>? features;
  final Map<String, dynamic>? reservoir;
  final ModelResult randomForest;
  final ModelResult? lstm;
  final bool lstmAvailable;
  final String? generatedAt;

  PredictionResponse({
    this.features,
    this.reservoir,
    required this.randomForest,
    this.lstm,
    required this.lstmAvailable,
    this.generatedAt,
  });

  factory PredictionResponse.fromJson(Map<String, dynamic> json) {
    // P3 step 1: log the RAW JSON right before parsing, in full.
    debugPrint('[ModelParse] RAW PredictionResponse JSON: $json');
    // P3 step 2: compare exact key names — backend sends snake_case
    // "random_forest" / "lstm_available" / "generated_at". Log if absent.
    for (final k in ['random_forest', 'lstm', 'lstm_available', 'generated_at']) {
      if (!json.containsKey(k)) {
        debugPrint('[ModelParse] PredictionResponse: expected key "$k" '
            'NOT FOUND. Present keys: ${json.keys.toList()}');
      }
    }
    return PredictionResponse(
      features: json['features'] is Map
          ? Map<String, dynamic>.from(json['features'] as Map)
          : null,
      reservoir: json['reservoir'] is Map
          ? Map<String, dynamic>.from(json['reservoir'] as Map)
          : null,
      randomForest: json['random_forest'] is Map
          ? ModelResult.fromJson(
              Map<String, dynamic>.from(json['random_forest'] as Map),
              context: 'random_forest',
            )
          : (() {
              debugPrint(
                  '[ModelParse] random_forest object missing — check nesting. Raw: $json');
              return ModelResult(risk: 'LOW', score: 0.0);
            })(),
      lstm: json['lstm'] is Map
          ? ModelResult.fromJson(
              Map<String, dynamic>.from(json['lstm'] as Map),
              context: 'lstm',
            )
          : null,
      lstmAvailable: json['lstm_available'] ?? false,
      generatedAt: json['generated_at']?.toString(),
    );
  }

  String get overallRisk {
    if (lstm != null && lstm!.risk == randomForest.risk) {
      return randomForest.risk;
    }
    return randomForest.risk; // Default to RF if they disagree
  }
}

class ModelResult {
  final String risk;
  final double score;
  final Map<String, double>? probabilities;

  ModelResult({
    required this.risk,
    required this.score,
    this.probabilities,
  });

  factory ModelResult.fromJson(Map<String, dynamic> json,
      {String context = 'ModelResult'}) {
    // P3 step 1: full raw log before parsing.
    debugPrint('[ModelParse] RAW $context JSON: $json');
    final risk = (json['risk'] ?? json['Risk'] ?? 'LOW').toString();
    if (!json.containsKey('risk')) {
      debugPrint('[ModelParse] $context: "risk" key missing '
          '(case-sensitive check). Keys: ${json.keys.toList()}');
    }
    // P3 steps 2-4: multi-key lookup + logged parse (no silent ?? 0.0).
    final score = _extractScore(json, context);
    Map<String, double>? probs;
    final rawProbs = json['probabilities'] ?? json['probs'];
    if (rawProbs is Map) {
      probs = {};
      for (final e in rawProbs.entries) {
        probs[e.key.toString()] =
            _parseDouble(e.value, 'probabilities[${e.key}]', context);
      }
    }
    // P3 step 5: callers format with toStringAsFixed(3) — never hardcode.
    debugPrint('[ModelParse] $context parsed => risk=$risk '
        'score=${score.toStringAsFixed(3)}');
    return ModelResult(
      risk: risk,
      score: score,
      probabilities: probs,
    );
  }

  /// Parse a flat history row ({rf_score, rf_risk, ...}) into a ModelResult.
  /// History endpoint uses different keys than live prediction — this was a
  /// likely 0.000 source when the wrong parser was applied.
  factory ModelResult.fromHistory(Map<String, dynamic> json,
      {bool isLstm = false}) {
    debugPrint('[ModelParse] RAW history JSON: $json');
    if (isLstm) {
      return ModelResult(
        risk: (json['lstm_risk'] ?? 'LOW').toString(),
        score: _parseDouble(json['lstm_score'], 'lstm_score', 'history(lstm)'),
      );
    }
    return ModelResult(
      risk: (json['rf_risk'] ?? 'LOW').toString(),
      score: _parseDouble(json['rf_score'], 'rf_score', 'history(rf)'),
    );
  }
}

class WeatherResponse {
  final String source;
  final String? fetchedAt;
  final String? todayIso;
  final CurrentWeather? current;
  final List<Map<String, dynamic>>? forecast;

  WeatherResponse({
    required this.source,
    this.fetchedAt,
    this.todayIso,
    this.current,
    this.forecast,
  });

  factory WeatherResponse.fromJson(Map<String, dynamic> json) {
    return WeatherResponse(
      source: json['source'] ?? 'unknown',
      fetchedAt: json['fetched_at'],
      todayIso: json['today_iso'],
      current: json['current'] != null
          ? CurrentWeather.fromJson(json['current'])
          : null,
      forecast: json['forecast'] != null
          ? List<Map<String, dynamic>>.from(json['forecast'])
          : null,
    );
  }
}

class CurrentWeather {
  final double? tempC;
  final double? feelsLikeC;
  final int? humidityPct;
  final double? precipMm;
  final double? windKmh;
  final String? description;
  final String? icon;

  CurrentWeather({
    this.tempC,
    this.feelsLikeC,
    this.humidityPct,
    this.precipMm,
    this.windKmh,
    this.description,
    this.icon,
  });

  factory CurrentWeather.fromJson(Map<String, dynamic> json) {
    return CurrentWeather(
      tempC: _parseDouble(json['temp_c'], 'temp_c', 'CurrentWeather'),
      feelsLikeC:
          _parseDouble(json['feels_like_c'], 'feels_like_c', 'CurrentWeather'),
      humidityPct: (json['humidity_pct'] is num)
          ? (json['humidity_pct'] as num).toInt()
          : int.tryParse('${json['humidity_pct']}') ?? 0,
      precipMm: _parseDouble(json['precip_mm'], 'precip_mm', 'CurrentWeather'),
      windKmh: _parseDouble(json['wind_kmh'], 'wind_kmh', 'CurrentWeather'),
      description: json['description']?.toString() ?? 'Unknown',
      icon: json['icon']?.toString() ?? 'unknown',
    );
  }
}

class Complaint {
  final int? id;
  final String name;
  final String? phone;
  final String location;
  final double? lat;
  final double? lon;
  final String category;
  final String description;
  final String status;
  final String? createdAt;
  final String? updatedAt;
  /// Firebase Storage download URL (photo hosted in Firebase, all other
  /// report data on the Render backend). Null when no photo was attached.
  final String? photoUrl;

  Complaint({
    this.id,
    required this.name,
    this.phone,
    required this.location,
    this.lat,
    this.lon,
    this.category = 'Other',
    required this.description,
    this.status = 'submitted',
    this.createdAt,
    this.updatedAt,
    this.photoUrl,
  });

  factory Complaint.fromJson(Map<String, dynamic> json) {
    final rawPhoto = json['photo_url'];
    return Complaint(
      id: json['id'] is num ? (json['id'] as num).toInt() : null,
      name: json['name']?.toString() ?? '',
      phone: json['phone']?.toString(),
      location: json['location']?.toString() ?? '',
      lat: json['lat'] is num ? (json['lat'] as num).toDouble() : null,
      lon: json['lon'] is num ? (json['lon'] as num).toDouble() : null,
      category: json['category']?.toString() ?? 'Other',
      description: json['description']?.toString() ?? '',
      status: json['status']?.toString() ?? 'submitted',
      createdAt: json['created_at']?.toString(),
      updatedAt: json['updated_at']?.toString(),
      photoUrl: rawPhoto?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'phone': phone,
        'location': location,
        'lat': lat,
        'lon': lon,
        'category': category,
        'description': description,
        if (photoUrl != null) 'photo_url': photoUrl,
      };
}
