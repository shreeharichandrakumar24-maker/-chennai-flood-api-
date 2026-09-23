import 'dart:async';
import 'package:flutter/material.dart';
import '../config/api_config.dart';
import '../services/api_exception.dart';
import '../services/api_service.dart';
import '../services/cache_service.dart';
import '../models/prediction_model.dart';
import '../widgets/risk_badge.dart';
import '../widgets/weather_card.dart';
import '../widgets/stat_card.dart';
import '../widgets/alert_banner.dart';
import '../widgets/error_state.dart';
import 'settings_screen.dart';
import 'prediction_history_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  WeatherResponse? _weather;
  PredictionResponse? _prediction;
  Map<String, dynamic>? _status;
  bool _loading = true;
  bool _isConnected = true;
  String _baseUrlForDisplay = '';
  // P2: distinct connection-failure state (never conflated with "no data yet")
  bool _isRetrying = false;
  int _retryAttempt = 0;
  String? _fetchError;
  bool _hasEverLoaded = false;
  bool _isStale = false;
  String _staleLabel = '';
  Timer? _autoRefreshTimer;
  int _countdown = 300; // 5 minutes

  @override
  void initState() {
    super.initState();
    _loadData();
    _startAutoRefresh();
  }

  @override
  void dispose() {
    _autoRefreshTimer?.cancel();
    super.dispose();
  }

  void _startAutoRefresh() {
    _autoRefreshTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() {
          _countdown--;
          if (_countdown <= 0) {
            _countdown = 300;
            _loadData();
          }
        });
      }
    });
  }

  String get _countdownText {
    final min = _countdown ~/ 60;
    final sec = _countdown % 60;
    return '$min:${sec.toString().padLeft(2, '0')}';
  }

  Future<void> _loadData() async {
    final bool firstLoad = !_hasEverLoaded && _prediction == null;
    if (mounted) {
      setState(() {
        if (firstLoad) {
          _loading = true;
        } else {
          _isRetrying = true;
          _retryAttempt = 1;
        }
        _fetchError = null;
      });
    }
    try {
      final results = await ApiService.withRetry(
        () => Future.wait([
          ApiService.fetchWeather(),
          ApiService.fetchPrediction(),
          ApiService.fetchStatus(),
          ApiConfig.getBaseUrl(),
        ]),
        label: 'dashboard',
        onAttempt: (attempt) {
          if (mounted && !firstLoad) {
            setState(() {
              _isRetrying = true;
              _retryAttempt = attempt;
            });
          }
        },
      );
      if (mounted) {
        setState(() {
          _weather = results[0] as WeatherResponse;
          _prediction = results[1] as PredictionResponse;
          _status = results[2] as Map<String, dynamic>;
          _baseUrlForDisplay = results[3] as String;
          _isConnected = true;
          _loading = false;
          _isRetrying = false;
          _retryAttempt = 0;
          _fetchError = null;
          _hasEverLoaded = true;
          _isStale = false;
          _staleLabel = '';
        });
      }
    } on ApiException catch (e) {
      // Fetch failed — try cached last-known data, never fake-empty zeros.
      final cachedPred = await CacheService.loadPrediction();
      final cachedWeather = await CacheService.loadWeather();
      final cachedStatus = await CacheService.loadStatus();
      final baseUrl = await ApiConfig.getBaseUrl();
      if (!mounted) return;
      if (cachedPred != null) {
        setState(() {
          try {
            _prediction = PredictionResponse.fromJson(cachedPred.json);
          } catch (_) {
            // Keep existing prediction if cache corrupt; do not zero it.
          }
          if (cachedWeather != null) {
            try {
              _weather = WeatherResponse.fromJson(cachedWeather.json);
            } catch (_) {}
          }
          if (cachedStatus != null) {
            _status = cachedStatus.json;
          }
          _baseUrlForDisplay = baseUrl;
          _isConnected = false;
          _loading = false;
          _isRetrying = false;
          _hasEverLoaded = true;
          _isStale = true;
          _staleLabel = CacheService.staleLabel(cachedPred.at);
          _fetchError = e.message;
        });
      } else {
        setState(() {
          _baseUrlForDisplay = baseUrl;
          _isConnected = false;
          _loading = false;
          _isRetrying = false;
          _fetchError = e.message;
          _isStale = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      final baseUrl = await ApiConfig.getBaseUrl();
      setState(() {
        _baseUrlForDisplay = baseUrl;
        _isConnected = false;
        _loading = false;
        _isRetrying = false;
        _fetchError = e.toString();
      });
    }
  }

  void _openSettings() {
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const SettingsScreen()))
        .then((_) => _loadData());
  }

  void _openHistory() {
    Navigator.of(context)
        .push(
            MaterialPageRoute(builder: (_) => const PredictionHistoryScreen()))
        .then((_) => _loadData());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('🌊 Chennai Flood Alert'),
        actions: [
          // Auto-refresh countdown
          if (!_loading)
            Center(
              child: Padding(
                padding: const EdgeInsets.only(right: 4),
                child: Text(
                  '🔄 $_countdownText',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[500],
                  ),
                ),
              ),
            ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadData,
          ),
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'settings') {
                _openSettings();
              } else if (value == 'history') {
                _openHistory();
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'history',
                child: Row(
                  children: [
                    Icon(Icons.history, size: 20),
                    SizedBox(width: 8),
                    Text('Prediction History'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'settings',
                child: Row(
                  children: [
                    Icon(Icons.settings, size: 20),
                    SizedBox(width: 8),
                    Text('Settings'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: _loading && _prediction == null && _fetchError == null
          ? const Center(child: CircularProgressIndicator())
          : (_fetchError != null && _prediction == null)
              // DISTINCT failure state: never show fake-empty zeros here.
              ? ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    ConnectionFailedBanner(
                      message: _fetchError ?? 'Unknown error',
                      onRetryNow: _loadData,
                    ),
                    const SizedBox(height: 16),
                    ErrorState(
                      title: 'Could not reach the backend',
                      message:
                          'No cached data available yet.\n${_fetchError ?? ''}\n\nBackend: ${_baseUrlForDisplay.isEmpty ? ApiConfig.currentUrl : _baseUrlForDisplay}',
                      icon: Icons.cloud_off,
                      onRetry: _loadData,
                    ),
                  ],
                )
              : RefreshIndicator(
              onRefresh: _loadData,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // P2: distinct retrying banner (not the same as "no data yet")
                  if (_isRetrying)
                    ConnectionRetryingBanner(
                      attempt: _retryAttempt == 0 ? 1 : _retryAttempt,
                      onRetryNow: _loadData,
                    ),
                  if (_isRetrying) const SizedBox(height: 12),
                  // P2: hard failure banner with manual "Retry now"
                  if (_fetchError != null && !_isRetrying)
                    ConnectionFailedBanner(
                      message: _fetchError ?? 'Unknown error',
                      onRetryNow: _loadData,
                    ),
                  if (_fetchError != null && !_isRetrying)
                    const SizedBox(height: 12),
                  // P2: cached fallback label, never blank/zero fields
                  if (_isStale)
                    StaleDataBanner(label: _staleLabel),
                  if (_isStale) const SizedBox(height: 12),
                  // Legacy online/offline pill (kept, but no longer the
                  // only signal — retrying/failed/stale banners sit above)
                  ConnectionStatusBanner(
                    isConnected: _isConnected,
                    onRetry: _loadData,
                  ),

                  // High Risk Alert Banner
                  if (_prediction != null)
                    AlertBanner(
                      risk: _prediction!.overallRisk,
                    ),

                  if (_prediction != null && _prediction!.overallRisk == 'HIGH')
                    const SizedBox(height: 12),

                  // Current Risk
                  if (_prediction != null)
                    RiskBadge(
                      risk: _prediction!.overallRisk,
                      score: _prediction!.randomForest.score,
                    ),

                  const SizedBox(height: 16),

                  // Weather Card
                  if (_weather?.current != null)
                    WeatherCard(weather: _weather!.current!),

                  const SizedBox(height: 16),

                  // Stats Row
                  if (_prediction?.randomForest.probabilities != null)
                    Row(
                      children: [
                        Expanded(
                          child: StatCard(
                            title: 'RF Risk',
                            value: _prediction!.randomForest.risk,
                            color: _getRiskColor(_prediction!.randomForest.risk),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: StatCard(
                            title: 'RF Score',
                            value: _prediction!.randomForest.score.toStringAsFixed(3),
                            color: Colors.blue,
                          ),
                        ),
                      ],
                    ),

                  const SizedBox(height: 8),

                  if (_prediction?.lstm != null)
                    Row(
                      children: [
                        Expanded(
                          child: StatCard(
                            title: 'LSTM Risk',
                            value: _prediction!.lstm!.risk,
                            color: _getRiskColor(_prediction!.lstm!.risk),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: StatCard(
                            title: 'LSTM Score',
                            value: _prediction!.lstm!.score.toStringAsFixed(3),
                            color: Colors.purple,
                          ),
                        ),
                      ],
                    ),

                  const SizedBox(height: 16),

                  // Model Details
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  'Model Details',
                                  style: Theme.of(context).textTheme.titleMedium,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: _isConnected
                                      ? Colors.green.shade50
                                      : Colors.red.shade50,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: _isConnected
                                        ? Colors.green.shade200
                                        : Colors.red.shade200,
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      _isConnected
                                          ? Icons.check_circle
                                          : Icons.error,
                                      size: 14,
                                      color: _isConnected
                                          ? Colors.green
                                          : Colors.red,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      _isConnected ? 'Online' : 'Offline',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                        color: _isConnected
                                            ? Colors.green.shade700
                                            : Colors.red.shade700,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const Divider(),
                          _detailRow('LSTM Available',
                              _prediction?.lstmAvailable == true ? '✅ Yes' : '❌ No'),
                          _detailRow('Generated',
                              _prediction?.generatedAt ?? 'Unknown'),
                          _detailRow('Last Refresh',
                              _status?['last_refresh'] ?? 'Never'),
                          _detailRow('Next Auto-Refresh', _countdownText),
                          _detailRow('Connected via',
                              _baseUrlForDisplay.isEmpty ? ApiConfig.connectionLabel : '${ApiConfig.isPublicUrl ? '🌐 Public' : '📶 Local'} ($_baseUrlForDisplay)'),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Quick Actions
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Quick Actions',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: _actionChip(
                                  Icons.history,
                                  'History',
                                  _openHistory,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: _actionChip(
                                  Icons.settings,
                                  'Settings',
                                  _openSettings,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 24),
                ],
              ),
            ),
    );
  }

  Widget _actionChip(IconData icon, String label, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.2),
          ),
        ),
        child: Column(
          children: [
            Icon(icon, size: 28, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 8),
            Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.w500,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Text(label, style: const TextStyle(color: Colors.grey)),
          const Spacer(),
          Flexible(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.bold),
              textAlign: TextAlign.end,
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
          ),
        ],
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
