import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'config/api_config.dart';
import 'screens/splash_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Load the saved API URL before the app starts
  await ApiConfig.getBaseUrl();
  // Firebase — photo storage only. A missing/invalid google-services.json
  // must never stop the app: reports still submit as text-only.
  try {
    await Firebase.initializeApp();
    debugPrint('[Firebase] ready, bucket: '
        '${FirebaseStorage.instance.bucket}');
  } catch (e) {
    debugPrint('[Firebase] initializeApp failed (photo upload disabled): $e');
  }
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
