import 'package:flutter/material.dart';
import '../services/api_exception.dart';
import '../services/api_service.dart';
import '../models/prediction_model.dart';
import '../widgets/error_state.dart';

class PredictionScreen extends StatefulWidget {
  const PredictionScreen({super.key});

  @override
  State<PredictionScreen> createState() => _PredictionScreenState();
}

class _PredictionScreenState extends State<PredictionScreen> {
  double _rainfall = 50.0;
  double _reservoirPct = 70.0;
  PredictionResponse? _prediction;
  bool _loading = false;
  String? _fetchError;
  bool _isRetrying = false;
  int _retryAttempt = 0;

  Future<void> _getPrediction() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _isRetrying = true;
        _retryAttempt = 1;
        _fetchError = null;
      });
    }

    try {
      // Force refresh with current conditions (3 attempts, 2s/5s/10s)
      final result = await ApiService.withRetry(
        () => ApiService.refreshPrediction(),
        label: 'predict/refresh',
        onAttempt: (a) {
          if (mounted) setState(() => _retryAttempt = a);
        },
      );
      if (!mounted) return;
      setState(() {
        _prediction = result;
        _loading = false;
        _isRetrying = false;
        _fetchError = null;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _isRetrying = false;
        _fetchError = e.message;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _isRetrying = false;
        _fetchError = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('🎯 Flood Prediction'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Input Section
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Input Conditions',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 16),

                  // Rainfall Slider
                  Text('Rainfall Today: ${_rainfall.toStringAsFixed(0)} mm'),
                  Slider(
                    value: _rainfall,
                    min: 0,
                    max: 300,
                    divisions: 60,
                    label: '${_rainfall.toStringAsFixed(0)} mm',
                    onChanged: (value) => setState(() => _rainfall = value),
                  ),

                  const SizedBox(height: 16),

                  // Reservoir Slider
                  Text('Reservoir Fullness: ${_reservoirPct.toStringAsFixed(0)}%'),
                  Slider(
                    value: _reservoirPct,
                    min: 0,
                    max: 100,
                    divisions: 20,
                    label: '${_reservoirPct.toStringAsFixed(0)}%',
                    onChanged: (value) => setState(() => _reservoirPct = value),
                  ),

                  const SizedBox(height: 16),

                  // Predict Button
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _loading ? null : _getPrediction,
                      icon: _loading
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.psychology),
                      label: Text(_loading ? 'Analyzing...' : 'Get Prediction'),
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // P2: distinct error / retrying states (never blank)
          if (_isRetrying && _loading)
            ConnectionRetryingBanner(
              attempt: _retryAttempt,
              onRetryNow: _getPrediction,
            ),
          if (_fetchError != null && !_loading) ...[
            ConnectionFailedBanner(
              message: _fetchError!,
              onRetryNow: _getPrediction,
            ),
            const SizedBox(height: 12),
          ],

          // Results Section
          if (_prediction != null) ...[
            _buildResultCard(
              'Random Forest',
              _prediction!.randomForest.risk,
              _prediction!.randomForest.score,
              Colors.blue,
            ),
            const SizedBox(height: 12),
            if (_prediction!.lstm != null)
              _buildResultCard(
                'LSTM (Deep Learning)',
                _prediction!.lstm!.risk,
                _prediction!.lstm!.score,
                Colors.purple,
              ),
          ],
        ],
      ),
    );
  }

  Widget _buildResultCard(String model, String risk, double score, Color color) {
    final riskColor = _getRiskColor(risk);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.circle, color: color, size: 12),
                const SizedBox(width: 8),
                Text(model, style: Theme.of(context).textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Risk Level:'),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: riskColor.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: riskColor),
                  ),
                  child: Text(
                    risk,
                    style: TextStyle(
                      color: riskColor,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Risk Score:'),
                Text(
                  score.toStringAsFixed(3),
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 8),
            LinearProgressIndicator(
              value: score,
              backgroundColor: Colors.grey[200],
              color: riskColor,
              minHeight: 8,
            ),
          ],
        ),
      ),
    );
  }

  Color _getRiskColor(String risk) {
    switch (risk) {
      case 'HIGH':
        return Colors.red;
      case 'MODERATE':
        return Colors.orange;
      default:
        return Colors.green;
    }
  }
}
