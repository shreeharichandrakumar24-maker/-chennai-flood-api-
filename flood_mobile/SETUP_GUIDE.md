# 📱 Chennai Flood Alert — Mobile App Setup Guide

## Prerequisites — What You Need to Install

### Already Installed ✅
- Java (OpenJDK 21)
- Node.js 24.14.0
- npm 11.10.1

### You Need to Install ❌

#### 1. Android Studio (Required)
- **Download:** https://developer.android.com/studio
- **What it provides:** Android SDK, emulator, build tools
- **During setup:** Install these components:
  - Android SDK (API 34 or higher)
  - Android SDK Build-Tools
  - Android SDK Platform-Tools
  - Android Emulator

#### 2. Flutter SDK (Required)
- **Download:** https://docs.flutter.dev/get-started/install/windows/mobile
- **Extract to:** `C:\flutter`
- **Add to PATH:** `C:\flutter\bin`

#### 3. Run Flutter Doctor
After installing both, open a terminal and run:
```bash
flutter doctor
```
This will tell you exactly what's still missing.

---

## Project Structure

```
flood_mobile/
├── lib/
│   ├── main.dart                    # App entry point
│   ├── config/
│   │   └── api_config.dart          # API base URL configuration
│   ├── models/
│   │   └── prediction_model.dart    # Data models
│   ├── services/
│   │   └── api_service.dart         # API calls
│   ├── screens/
│   │   ├── home_screen.dart         # Bottom navigation
│   │   ├── dashboard_screen.dart    # Current risk + weather
│   │   ├── prediction_screen.dart   # Manual prediction input
│   │   ├── forecast_screen.dart     # 7-day forecast
│   │   ├── map_screen.dart          # Flood risk map
│   │   └── report_screen.dart       # Submit complaints
│   └── widgets/
│       ├── risk_badge.dart          # Risk level display
│       ├── weather_card.dart        # Weather info card
│       └── stat_card.dart           # Metric card
├── assets/
│   └── images/                      # App icons, images
├── pubspec.yaml                     # Dependencies
└── SETUP_GUIDE.md                   # This file
```

---

## How to Run

### Step 1: Start Your Backend
```bash
cd flood_api
python main.py
```
This starts the API at http://localhost:8000

### Step 2: Update API URL
Edit `lib/config/api_config.dart`:
- For Android emulator: use `http://10.0.2.2:8000`
- For physical device: use your电脑's IP address + port
- For production: use your deployed backend URL

### Step 3: Run the App
```bash
cd flood_mobile
flutter pub get
flutter run
```

### Step 4: Build APK
```bash
flutter build apk --release
```
The APK will be at: `build/app/outputs/flutter-apk/app-release.apk`

---

## App Screens

| Screen | Description |
|--------|-------------|
| Dashboard | Current flood risk, weather, model status |
| Predict | Get AI prediction for current conditions |
| Forecast | 7-day weather forecast from Open-Meteo |
| Map | Interactive flood risk map with zones & shelters |
| Report | Submit flood-related complaints |

---

## API Endpoints Used

| Screen | Endpoint | Method |
|--------|----------|--------|
| Dashboard | `/api/v1/status` | GET |
| Dashboard | `/api/v1/weather` | GET |
| Dashboard | `/api/v1/prediction` | GET |
| Predict | `/api/v1/prediction/refresh` | POST |
| Forecast | `/api/v1/weather` | GET |
| Report | `/api/v1/complaints` | GET/POST |

---

## Next Steps

1. Install Android Studio + Flutter SDK
2. Run `flutter doctor` to verify setup
3. Start your FastAPI backend
4. Run `flutter pub get` in flood_mobile/
5. Run `flutter run` to test on emulator/device
6. Build APK with `flutter build apk --release`

---

## Troubleshooting

### "flutter: command not found"
- Add Flutter to PATH: `C:\flutter\bin`

### "No connected devices"
- Start Android Studio → Tools → Device Manager → Create/Start emulator

### "Connection refused" errors
- Make sure FastAPI is running on port 8000
- Check API URL in `lib/config/api_config.dart`

### Build fails
- Run `flutter clean` then `flutter pub get` again
