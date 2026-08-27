import 'package:flutter/material.dart';
import '../config/api_config.dart';
import '../services/api_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _urlController = TextEditingController();
  bool _testing = false;
  bool? _connectionOk;
  Map<String, dynamic>? _status;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _initUrl();
  }

  Future<void> _initUrl() async {
    final baseUrl = await ApiConfig.getBaseUrl();
    if (mounted) {
      setState(() {
        _urlController.text = baseUrl;
        _loading = false;
      });
      _loadStatus();
    }
  }

  Future<void> _loadStatus() async {
    final status = await ApiService.fetchStatus();
    if (mounted) {
      setState(() => _status = status);
    }
  }

  Future<void> _testConnection() async {
    setState(() {
      _testing = true;
      _connectionOk = null;
    });

    await ApiConfig.setBaseUrl(_urlController.text.trim());
    final status = await ApiService.fetchStatus();

    setState(() {
      _testing = false;
      _connectionOk = status != null;
      _status = status;
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _connectionOk == true
                ? '✅ Connected successfully!'
                : '❌ Could not connect to server',
          ),
          backgroundColor: _connectionOk == true ? Colors.green : Colors.red,
        ),
      );
    }
  }

  Future<void> _autoDetect() async {
    setState(() {
      _testing = true;
      _connectionOk = null;
    });

    final detectedUrl = await ApiConfig.autoDetectServer();

    setState(() {
      _testing = false;
    });

    if (detectedUrl != null) {
      setState(() {
        _urlController.text = detectedUrl;
        _connectionOk = true;
      });
      await ApiConfig.setBaseUrl(detectedUrl);
      _loadStatus();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ Server found: $detectedUrl'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('❌ Not found. Try entering URL manually or check server is running.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('⚙️ Settings')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // ── Connection Status Banner ──
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: _connectionOk == true
                        ? Colors.green.shade50
                        : Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: _connectionOk == true
                          ? Colors.green.shade200
                          : Colors.orange.shade200,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        _connectionOk == true
                            ? Icons.check_circle
                            : Icons.info_outline,
                        color: _connectionOk == true
                            ? Colors.green
                            : Colors.orange,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _connectionOk == true
                              ? 'Connected to: ${ApiConfig.baseUrl}'
                              : 'Not connected. Set up below.',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: _connectionOk == true
                                ? Colors.green.shade800
                                : Colors.orange.shade800,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                // ── Method 1: Same WiFi (Auto-detect) ──
                Card(
                  color: Colors.blue.shade50,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.wifi, color: Colors.blue.shade700),
                            const SizedBox(width: 8),
                            Text(
                              'Method 1: Same WiFi',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.blue.shade800,
                                fontSize: 16,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Phone & PC on same WiFi network. Tap to scan.',
                          style: TextStyle(fontSize: 13),
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            onPressed: _testing ? null : _autoDetect,
                            icon: _testing
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  )
                                : const Icon(Icons.wifi_find),
                            label: Text(_testing ? 'Scanning WiFi...' : 'Auto-Detect Server'),
                            style: FilledButton.styleFrom(
                              backgroundColor: Colors.blue,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 12),

                // ── Method 2: Public URL (ngrok / cloud) ──
                Card(
                  color: Colors.purple.shade50,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.public, color: Colors.purple.shade700),
                            const SizedBox(width: 8),
                            Text(
                              'Method 2: Any Network (Public)',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.purple.shade800,
                                fontSize: 16,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Fixed URL via DuckDNS. Works from mobile data,\n'
                          'different WiFi, or anywhere in the world.',
                          style: TextStyle(fontSize: 13),
                        ),
                        const SizedBox(height: 8),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.purple.shade200),
                          ),
                          child: const Text(
                            'On PC run:  python main.py --duckdns\n'
                            'Fixed URL: http://chennai-flood.duckdns.org:8000\n'
                            'Requires port forwarding on your router.',
                            style: TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                // ── Manual URL Entry ──
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Server URL',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _urlController,
                          decoration: const InputDecoration(
                            labelText: 'Backend URL',
                            hintText: 'http://192.168.1.x:8000  or  https://xxx.ngrok-free.app',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.link),
                          ),
                          keyboardType: TextInputType.url,
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            FilledButton.icon(
                              onPressed: _testing ? null : _testConnection,
                              icon: _testing
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(strokeWidth: 2),
                                    )
                                  : const Icon(Icons.check),
                              label: Text(_testing ? 'Testing...' : 'Test & Save'),
                            ),
                            if (_connectionOk != null) ...[
                              const SizedBox(width: 12),
                              Icon(
                                _connectionOk! ? Icons.check_circle : Icons.error,
                                color: _connectionOk! ? Colors.green : Colors.red,
                                size: 28,
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                // ── Server Status ──
                if (_status != null)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Server Status', style: Theme.of(context).textTheme.titleMedium),
                          const Divider(),
                          _statusRow('Service', _status!['service'] ?? 'Unknown'),
                          _statusRow('Status', _status!['status'] ?? 'Unknown'),
                          _statusRow('Last Refresh', _status!['last_refresh'] ?? 'Never'),
                          _statusRow('LSTM Available', _status!['lstm_available'] == true ? '✅ Yes' : '❌ No'),
                          if (_status!['error'] != null)
                            _statusRow('Error', _status!['error']),
                        ],
                      ),
                    ),
                  ),

                const SizedBox(height: 16),

                // ── About ──
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('About', style: Theme.of(context).textTheme.titleMedium),
                        const Divider(),
                        _statusRow('App', 'Chennai Flood Alert v1.0.0'),
                        _statusRow('AI Models', 'Random Forest + LSTM'),
                        _statusRow('Weather Data', 'Open-Meteo API'),
                        const SizedBox(height: 12),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.orange.shade50,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.orange.shade200),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(Icons.warning_amber, color: Colors.orange.shade700, size: 20),
                                  const SizedBox(width: 6),
                                  Text(
                                    'Disclaimer',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Colors.orange.shade800,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'This is an educational project. Predictions are NOT official flood warnings.',
                                style: TextStyle(fontSize: 12, color: Colors.orange.shade900),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _statusRow(String label, dynamic value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.grey)),
          Flexible(
            child: Text(
              value.toString(),
              style: const TextStyle(fontWeight: FontWeight.bold),
              textAlign: TextAlign.end,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }
}
