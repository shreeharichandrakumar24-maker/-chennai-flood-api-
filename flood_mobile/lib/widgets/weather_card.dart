import 'package:flutter/material.dart';
import '../models/prediction_model.dart';

class WeatherCard extends StatelessWidget {
  final CurrentWeather weather;

  const WeatherCard({super.key, required this.weather});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  _getWeatherIcon(),
                  size: 32,
                  color: _getWeatherColor(),
                ),
                const SizedBox(width: 8),
                Text(
                  'Current Weather',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ),
            const Divider(),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _stat(Icons.thermostat, '${weather.tempC?.toStringAsFixed(1)}°C', 'Temp'),
                _stat(Icons.water_drop, '${weather.humidityPct}%', 'Humidity'),
                _stat(Icons.air, '${weather.windKmh?.toStringAsFixed(1)} km/h', 'Wind'),
              ],
            ),
            const SizedBox(height: 12),
            Center(
              child: Text(
                weather.description ?? 'Unknown',
                style: TextStyle(
                  fontSize: 16,
                  color: _getWeatherColor(),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _stat(IconData icon, String value, String label) {
    return Column(
      children: [
        Icon(icon, size: 24, color: Colors.blue),
        const SizedBox(height: 4),
        Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
        Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
      ],
    );
  }

  IconData _getWeatherIcon() {
    final desc = weather.description?.toLowerCase() ?? '';
    if (desc.contains('rain') || desc.contains('drizzle')) return Icons.umbrella;
    if (desc.contains('storm')) return Icons.thunderstorm;
    if (desc.contains('cloud')) return Icons.cloud;
    if (desc.contains('fog')) return Icons.foggy;
    return Icons.wb_sunny;
  }

  Color _getWeatherColor() {
    final desc = weather.description?.toLowerCase() ?? '';
    if (desc.contains('rain') || desc.contains('heavy')) return Colors.blue;
    if (desc.contains('storm')) return Colors.red;
    if (desc.contains('cloud')) return Colors.grey;
    return Colors.orange;
  }
}
