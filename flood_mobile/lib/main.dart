import 'package:flutter/material.dart';
import 'config/api_config.dart';
import 'screens/splash_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Load the saved API URL before the app starts
  await ApiConfig.getBaseUrl();
  runApp(const ChennaiFloodApp());
}

class ChennaiFloodApp extends StatelessWidget {
  const ChennaiFloodApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Chennai Flood Alert',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1d3557),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
        fontFamily: 'Roboto',
      ),
      home: const SplashScreen(),
    );
  }
}
