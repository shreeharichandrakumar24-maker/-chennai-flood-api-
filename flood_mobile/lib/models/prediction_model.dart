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
    return PredictionResponse(
      features: json['features'],
      reservoir: json['reservoir'],
      randomForest: ModelResult.fromJson(json['random_forest'] ?? {}),
      lstm: json['lstm'] != null ? ModelResult.fromJson(json['lstm']) : null,
      lstmAvailable: json['lstm_available'] ?? false,
      generatedAt: json['generated_at'],
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

  factory ModelResult.fromJson(Map<String, dynamic> json) {
    return ModelResult(
      risk: json['risk'] ?? 'LOW',
      score: (json['score'] ?? 0.0).toDouble(),
      probabilities: json['probabilities'] != null
          ? Map<String, double>.from(json['probabilities'])
          : null,
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
      tempC: (json['temp_c'] ?? 0).toDouble(),
      feelsLikeC: (json['feels_like_c'] ?? 0).toDouble(),
      humidityPct: json['humidity_pct'] ?? 0,
      precipMm: (json['precip_mm'] ?? 0).toDouble(),
      windKmh: (json['wind_kmh'] ?? 0).toDouble(),
      description: json['description'] ?? 'Unknown',
      icon: json['icon'] ?? 'unknown',
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
  });

  factory Complaint.fromJson(Map<String, dynamic> json) {
    return Complaint(
      id: json['id'],
      name: json['name'] ?? '',
      phone: json['phone'],
      location: json['location'] ?? '',
      lat: json['lat']?.toDouble(),
      lon: json['lon']?.toDouble(),
      category: json['category'] ?? 'Other',
      description: json['description'] ?? '',
      status: json['status'] ?? 'submitted',
      createdAt: json['created_at'],
      updatedAt: json['updated_at'],
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
      };
}
