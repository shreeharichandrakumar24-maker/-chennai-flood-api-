import 'package:flutter/material.dart';

class AlertBanner extends StatelessWidget {
  final String risk;
  final String message;
  final VoidCallback? onTap;

  const AlertBanner({
    super.key,
    required this.risk,
    this.message = '',
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    if (risk != 'HIGH') return const SizedBox.shrink();

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [Colors.red.shade600, Colors.red.shade800],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.red.withValues(alpha: 0.3),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.warning_amber_rounded,
                color: Colors.white,
                size: 28,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '⚠️ HIGH FLOOD RISK',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    message.isNotEmpty
                        ? message
                        : 'Immediate precautions recommended. Stay alert.',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.85),
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right,
              color: Colors.white.withValues(alpha: 0.7),
            ),
          ],
        ),
      ),
    );
  }
}
