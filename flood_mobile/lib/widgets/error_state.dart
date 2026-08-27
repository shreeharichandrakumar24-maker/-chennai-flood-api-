import 'package:flutter/material.dart';

class ErrorState extends StatelessWidget {
  final String title;
  final String message;
  final IconData icon;
  final VoidCallback? onRetry;

  const ErrorState({
    super.key,
    this.title = 'Something went wrong',
    this.message = 'Please check your connection and try again.',
    this.icon = Icons.error_outline,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              title,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: Colors.grey[600],
                  ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              message,
              style: TextStyle(color: Colors.grey[500], fontSize: 14),
              textAlign: TextAlign.center,
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('Try Again'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class ConnectionStatusBanner extends StatelessWidget {
  final bool isConnected;
  final VoidCallback? onRetry;

  const ConnectionStatusBanner({
    super.key,
    required this.isConnected,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    if (isConnected) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: Colors.orange.shade100,
      child: Row(
        children: [
          Icon(Icons.wifi_off, size: 18, color: Colors.orange.shade800),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'No connection to server',
              style: TextStyle(
                color: Colors.orange.shade900,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          if (onRetry != null)
            TextButton(
              onPressed: onRetry,
              child: Text(
                'Retry',
                style: TextStyle(color: Colors.orange.shade800),
              ),
            ),
        ],
      ),
    );
  }
}
