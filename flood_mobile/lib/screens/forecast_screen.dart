import 'package:flutter/material.dart';
import '../services/api_exception.dart';
import '../services/api_service.dart';
import '../models/prediction_model.dart';
import '../widgets/error_state.dart';

class ForecastScreen extends StatefulWidget {
  const ForecastScreen({super.key});

  @override
  State<ForecastScreen> createState() => _ForecastScreenState();
}

class _ForecastScreenState extends State<ForecastScreen> {
  WeatherResponse? _weather;
  bool _loading = true;
  String? _fetchError;
  bool _isRetrying = false;
  int _retryAttempt = 0;
  bool _isDirectFallback = false;

  @override
  void initState() {
    super.initState();
    _loadWeather();
  }

  Future<void> _loadWeather() async {
    if (mounted) {
      setState(() {
        _loading = _weather == null;
        _isRetrying = _weather != null;
        _retryAttempt = 1;
        _fetchError = null;
        _isDirectFallback = false;
      });
    }
    try {
      final weather = await ApiService.withRetry(
        () => ApiService.fetchWeather(),
        label: 'forecast/weather',
        onAttempt: (a) {
          if (mounted) setState(() => _retryAttempt = a);
        },
      );
      if (!mounted) return;
      setState(() {
        _weather = weather;
        _loading = false;
        _isRetrying = false;
        _fetchError = null;
        _isDirectFallback = false;
      });
    } catch (_) {
      // Backend unreachable (local down / Render asleep): fall back to
      // live Open-Meteo direct so weather still works.
      try {
        final direct = await ApiService.fetchDirectWeather();
        if (!mounted) return;
        setState(() {
          _weather = direct;
          _loading = false;
          _isRetrying = false;
          _fetchError = null;
          _isDirectFallback = true;
        });
      } on ApiException catch (e) {
        if (!mounted) return;
        setState(() {
          _loading = false;
          _isRetrying = false;
          _fetchError = e.message;
          _isDirectFallback = false;
        });
      } catch (e) {
        if (!mounted) return;
        setState(() {
          _loading = false;
          _isRetrying = false;
          _fetchError = e.toString();
          _isDirectFallback = false;
        });
      }
    }
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
              ? ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    if (_isRetrying)
                      ConnectionRetryingBanner(
                        attempt: _retryAttempt,
                        onRetryNow: _loadWeather,
                      )
                    else
                      ConnectionFailedBanner(
                        message: _fetchError ?? 'Weather data unavailable',
                        onRetryNow: _loadWeather,
                      ),
                    const SizedBox(height: 16),
                    ErrorState(
                      title: _fetchError != null
                          ? 'Connection failed'
                          : 'Weather data unavailable',
                      message:
                          '${_fetchError ?? 'Check your internet connection'}\n(No cached forecast — this is a fetch failure, not empty data.)',
                      icon: Icons.cloud_off,
                      onRetry: _loadWeather,
                    ),
                  ],
                )
              : RefreshIndicator(
                  onRefresh: _loadWeather,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      if (_fetchError != null) ...[
                        ConnectionFailedBanner(
                          message: _fetchError!,
                          onRetryNow: _loadWeather,
                        ),
                        const SizedBox(height: 12),
                      ],
                      // Source Info
                      Card(
                        color: _isDirectFallback
                            ? Colors.green[50]
                            : Colors.blue[50],
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Row(
                            children: [
                              Icon(
                                  _isDirectFallback
                                      ? Icons.bolt
                                      : Icons.info_outline,
                                  color: _isDirectFallback
                                      ? Colors.green
                                      : Colors.blue),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _isDirectFallback
                                      ? 'Live weather direct from Open-Meteo (backend unreachable — predictions need backend, weather does not). Pull to retry backend.'
                                      : 'Data from Open-Meteo API via backend (free, no key required)',
                                  style: TextStyle(
                                      color: _isDirectFallback
                                          ? Colors.green[800]
                                          : Colors.blue[700]),
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
