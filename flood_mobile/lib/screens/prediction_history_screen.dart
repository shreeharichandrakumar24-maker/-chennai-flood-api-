import 'package:flutter/material.dart';
import '../services/api_service.dart';

class PredictionHistoryScreen extends StatefulWidget {
  const PredictionHistoryScreen({super.key});

  @override
  State<PredictionHistoryScreen> createState() => _PredictionHistoryScreenState();
}

class _PredictionHistoryScreenState extends State<PredictionHistoryScreen> {
  List<Map<String, dynamic>> _history = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    setState(() => _loading = true);
    final history = await ApiService.fetchPredictionHistory();
    setState(() {
      _history = history;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('📊 Prediction History'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadHistory,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _history.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.history, size: 64, color: Colors.grey[400]),
                      const SizedBox(height: 16),
                      Text(
                        'No predictions yet',
                        style: TextStyle(color: Colors.grey[600], fontSize: 16),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Predictions will appear here after the first refresh.',
                        style: TextStyle(color: Colors.grey[500], fontSize: 13),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadHistory,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _history.length,
                    itemBuilder: (context, index) {
                      final pred = _history[index];
                      return _buildHistoryCard(pred);
                    },
                  ),
                ),
    );
  }

  Widget _buildHistoryCard(Map<String, dynamic> pred) {
    final rfRisk = pred['rf_risk'] ?? 'LOW';
    final rfScore = (pred['rf_score'] ?? 0).toDouble();
    final lstmRisk = pred['lstm_risk'];
    final lstmScore = pred['lstm_score'] != null
        ? (pred['lstm_score']).toDouble()
        : null;
    final generatedAt = pred['generated_at'] ?? '';

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Timestamp
            Row(
              children: [
                Icon(Icons.access_time, size: 16, color: Colors.grey[500]),
                const SizedBox(width: 6),
                Text(
                  _formatDate(generatedAt),
                  style: TextStyle(color: Colors.grey[600], fontSize: 12),
                ),
              ],
            ),
            const Divider(height: 16),

            // RF Result
            Row(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: Colors.blue,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                const Text(
                  'Random Forest',
                  style: TextStyle(fontWeight: FontWeight.w500),
                ),
                const Spacer(),
                _riskChip(rfRisk),
                const SizedBox(width: 8),
                Text(
                  rfScore.toStringAsFixed(3),
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
            ),

            if (lstmRisk != null) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: const BoxDecoration(
                      color: Colors.purple,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'LSTM',
                    style: TextStyle(fontWeight: FontWeight.w500),
                  ),
                  const Spacer(),
                  _riskChip(lstmRisk),
                  const SizedBox(width: 8),
                  Text(
                    lstmScore!.toStringAsFixed(3),
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _riskChip(String risk) {
    final color = _getRiskColor(risk);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Text(
        risk,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.bold,
          fontSize: 12,
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

  String _formatDate(String iso) {
    try {
      final dt = DateTime.parse(iso);
      final months = [
        'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
      ];
      return '${months[dt.month - 1]} ${dt.day}, ${dt.year} at '
          '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return iso;
    }
  }
}
