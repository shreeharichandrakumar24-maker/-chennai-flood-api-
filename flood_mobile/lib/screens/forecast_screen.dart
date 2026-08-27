import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../models/prediction_model.dart';

class ForecastScreen extends StatefulWidget {
  const ForecastScreen({super.key});

  @override
  State<ForecastScreen> createState() => _ForecastScreenState();
}

class _ForecastScreenState extends State<ForecastScreen> {
  WeatherResponse? _weather;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadWeather();
  }

  Future<void> _loadWeather() async {
    setState(() => _loading = true);
    final weather = await ApiService.fetchWeather();
    setState(() {
      _weather = weather;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('📈 7-Day Forecast'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadWeather,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _weather == null
              ? const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.cloud_off, size: 64, color: Colors.grey),
                      SizedBox(height: 16),
                      Text('Weather data unavailable'),
                      Text('Check your internet connection'),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadWeather,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      // Source Info
                      Card(
                        color: Colors.blue[50],
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Row(
                            children: [
                              const Icon(Icons.info_outline, color: Colors.blue),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Data from Open-Meteo API (free, no key required)',
                                  style: TextStyle(color: Colors.blue[700]),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                      const SizedBox(height: 16),

                      // Current Weather
                      if (_weather!.current != null)
                        _buildCurrentWeather(_weather!.current!),

                      const SizedBox(height: 16),

                      // Forecast Days
                      if (_weather!.forecast != null &&
                          _weather!.forecast!.isNotEmpty) ...[
                        Text(
                          'Coming Days',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        ...(_weather!.forecast!.map((day) =>
                            _buildForecastDay(day))),
                      ],
                    ],
                  ),
                ),
    );
  }

  Widget _buildCurrentWeather(CurrentWeather weather) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Current Weather — Chennai',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const Divider(),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _weatherStat(
                  Icons.thermostat,
                  '${weather.tempC?.toStringAsFixed(1)}°C',
                  'Temperature',
                ),
                _weatherStat(
                  Icons.water_drop,
                  '${weather.humidityPct}%',
                  'Humidity',
                ),
                _weatherStat(
                  Icons.air,
                  '${weather.windKmh?.toStringAsFixed(1)} km/h',
                  'Wind',
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  weather.precipMm != null && weather.precipMm! > 0
                      ? Icons.umbrella
                      : Icons.wb_sunny,
                  color: weather.precipMm != null && weather.precipMm! > 0
                      ? Colors.blue
                      : Colors.orange,
                ),
                const SizedBox(width: 8),
                Text(
                  weather.description ?? 'Unknown',
                  style: const TextStyle(fontSize: 16),
                ),
                if (weather.precipMm != null && weather.precipMm! > 0) ...[
                  const SizedBox(width: 12),
                  Text(
                    '${weather.precipMm?.toStringAsFixed(1)} mm',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.blue,
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _weatherStat(IconData icon, String value, String label) {
    return Column(
      children: [
        Icon(icon, size: 28, color: Colors.blue),
        const SizedBox(height: 4),
        Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
        Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
      ],
    );
  }

  Widget _buildForecastDay(Map<String, dynamic> day) {
    final date = day['date'] ?? '';
    final precip = (day['precip_mm'] ?? 0).toDouble();
    final tMax = (day['t_max'] ?? 0).toDouble();
    final tMin = (day['t_min'] ?? 0).toDouble();

    return Card(
      child: ListTile(
        leading: Icon(
          precip > 10 ? Icons.thunderstorm : (precip > 0 ? Icons.grain : Icons.wb_sunny),
          color: precip > 10 ? Colors.red : (precip > 0 ? Colors.blue : Colors.orange),
          size: 32,
        ),
        title: Text(date),
        subtitle: Text('${tMin.toStringAsFixed(0)}–${tMax.toStringAsFixed(0)}°C'),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.water_drop, size: 16, color: Colors.blue),
            Text(
              '${precip.toStringAsFixed(1)} mm',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: precip > 10 ? Colors.red : Colors.blue,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
