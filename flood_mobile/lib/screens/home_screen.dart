import 'package:flutter/material.dart';
import 'dashboard_screen.dart';
import 'prediction_screen.dart';
import 'forecast_screen.dart';
import 'map_screen.dart';
import 'report_screen.dart';
import 'settings_screen.dart';
import 'prediction_history_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;

  final List<Widget> _screens = [
    const DashboardScreen(),
    const PredictionScreen(),
    const ForecastScreen(),
    const FloodMapScreen(),
    const ReportScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _screens[_currentIndex],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (index) {
          if (index == _screens.length) {
            // Settings overflow — show as a full-screen route
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            );
            return;
          }
          setState(() => _currentIndex = index);
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard),
            label: 'Dashboard',
          ),
          NavigationDestination(
            icon: Icon(Icons.warning_amber_outlined),
            selectedIcon: Icon(Icons.warning),
            label: 'Predict',
          ),
          NavigationDestination(
            icon: Icon(Icons.calendar_today_outlined),
            selectedIcon: Icon(Icons.calendar_today),
            label: 'Forecast',
          ),
          NavigationDestination(
            icon: Icon(Icons.map_outlined),
            selectedIcon: Icon(Icons.map),
            label: 'Map',
          ),
          NavigationDestination(
            icon: Icon(Icons.report_outlined),
            selectedIcon: Icon(Icons.report),
            label: 'Report',
          ),
        ],
      ),
      floatingActionButton: _currentIndex == 0
          ? FloatingActionButton.extended(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const PredictionHistoryScreen(),
                  ),
                );
              },
              icon: const Icon(Icons.history),
              label: const Text('History'),
            )
          : null,
    );
  }
}
