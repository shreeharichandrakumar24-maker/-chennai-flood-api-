import 'package:flutter/material.dart';

class RiskBadge extends StatelessWidget {
  final String risk;
  final double score;

  const RiskBadge({
    super.key,
    required this.risk,
    required this.score,
  });

  @override
  Widget build(BuildContext context) {
    final color = _getRiskColor(risk);
    final icon = _getRiskIcon(risk);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [color.withValues(alpha: 0.8), color],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.3),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Icon(icon, size: 48, color: Colors.white),
          const SizedBox(height: 12),
          const Text(
            'Current Flood Risk',
            style: TextStyle(
              color: Colors.white70,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            risk,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 32,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              'Score: ${score.toStringAsFixed(3)}',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Color _getRiskColor(String risk) {
    switch (risk) {
      case 'HIGH':
        return const Color(0xFFe63946);
      case 'MODERATE':
        return const Color(0xFFf4a261);
      default:
        return const Color(0xFF2a9d8f);
    }
  }

  IconData _getRiskIcon(String risk) {
    switch (risk) {
      case 'HIGH':
        return Icons.warning_amber_rounded;
      case 'MODERATE':
        return Icons.info_outline;
      default:
        return Icons.check_circle_outline;
    }
  }
}
