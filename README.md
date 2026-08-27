# 🌊 Chennai Disaster Management App

An AI-powered disaster management platform for Chennai, India — helping people prepare for, respond to, and recover from urban flooding. Combines LSTM deep learning and Random Forest models with real-time weather data to predict flood risk, provide early warnings, and connect citizens with emergency resources.

> **⚠️ Disclaimer:** This is an educational / college-submission project. Predictions are **not** a substitute for official IMD or Tamil Nadu state government flood warnings.

---

## What This App Does

Chennai is highly vulnerable to urban flooding during the northeast monsoon (October–December). This app helps people by:

- **Predicting flood risk** using AI models trained on 30 years of historical data
- **Forecasting the next 7 days** of flood risk using live weather data
- **Alerting citizens** when HIGH flood risk is detected
- **Mapping flood-prone zones** so people know where danger is highest
- **Showing nearby shelters** for emergency evacuation
- **Collecting complaints** about waterlogging, road closures, and damage — connecting citizens to authorities
- **Visualizing reservoir and groundwater levels** to track water saturation across the city

---

## Problem Statement

Urban flooding in Chennai causes massive displacement, property damage, and loss of life. Citizens need a single platform that:

1. Predicts flood risk before it happens (AI-based early warning)
2. Shows real-time and forecast weather conditions
3. Maps historical flood data and high-risk zones
4. Provides emergency shelter information
5. Allows citizens to report flood-related issues

This app addresses all five needs in one platform.

---

## Data Sources

| Dataset | Description | Period |
|---------|-------------|--------|
| **Rainfall** (`Rainfall_Dataset.csv`) | Station-level daily rainfall across Chennai | 1993–2023 |
| **Lake Levels** (`Lake level/`) | Monthly storage (mcft) for 5 reservoirs: Poondi, Chembarambakkam, Red Hills, Cholavaram, Thervoy Kandigai | Multi-year |
| **Inflow & Outflow** (`Lake inflow and outflow/`) | Daily inflow/outflow totals per reservoir | 2021–2024 |
| **Groundwater** (`Groundwater Levels/`) | Water table depth (m below ground) at monitoring wells | Snapshots |
| **KML Flood Layers** (`Chennai Flooding Data/`) | 2015 flood stagnation points, observed inundation depths, inundation risk zones, and storm return-period flood extents (5-year to 200-year) | 2015 study |
| **Open-Meteo Forecast API** | Live 7-day precipitation forecast for Chennai | Real-time |

### Open-Meteo API

- **Endpoint:** `https://api.open-meteo.com/v1/forecast`
- **No API key required** for the project's normal usage volume
- Used for both the Streamlit forecast tab and the FastAPI backend's auto-refresh
- Provides: daily precipitation sums, precipitation probability, temperature, and weather codes
- Coordinates: Chennai (13.0827°N, 80.2707°E)

---

## AI Architecture

```
Historical / Environmental Data
(rainfall, reservoir storage, groundwater)
        │
        ▼
Feature Engineering
(rainfall today + 2/3/5/7/14-day windows,
 reservoir avg/max % + total mcft,
 month, day-of-year)
        │
        ├──▶ Random Forest (300 trees, depth 12)
        │         │
        │         ▼
        │    Risk probabilities ──▶ LOW / MODERATE / HIGH
        │
        └──▶ LSTM (2 layers × 64 hidden, dropout 0.25)
                  │
                  ▼
             Continuous score (0–1) ──▶ LOW / MODERATE / HIGH
```

- **Random Forest** — trained on tabular engineered features; fast inference, ~93.7% test accuracy
- **LSTM** — reads a 14-day temporal sequence; captures sequential patterns; ~78.7% test accuracy
- **Labels** are derived from rainfall intensity + reservoir fullness thresholds (no official flood-event labels in the source data)

### Live Forecast Architecture

```
Open-Meteo API
        │
        ▼
7-Day Precipitation Forecast
        │
        ▼
Rainfall Feature Generation
(append forecast to 14-day historical tail)
        │
        ├──▶ Random Forest
        └──▶ LSTM
                │
                ▼
        7-Day Flood-Risk Timeline
        (per-day risk level + score from both models)
```

---

## Application Features

### 🎯 Flood Prediction & Early Warning
- Interactive predictor — enter rainfall + reservoir conditions, switch between RF and LSTM models
- **Flood alerts** with HIGH-risk formatting and optional email notifications
- Color-coded risk badges (GREEN = LOW, AMBER = MODERATE, RED = HIGH)

### 📈 7-Day Weather-Based Forecast
- Live Open-Meteo precipitation data drives a 7-day flood-risk timeline
- RF vs LSTM comparison with per-day risk scores
- Risk badges and detailed breakdown for each forecast day

### 🔬 Real Flood-Event Validation
- Run trained models against known historical events (2015 Chennai floods, Cyclone Michaung 2023)
- Compare model predictions to actual flood occurrences

### 🗺️ Chennai Flood-Risk Map
- **2015 flood stagnation points** — 753 water-stagnation locations from the 2015 disaster
- **Observed inundation depth** — measured flood depths in inches across the city
- **Inundation risk zones** — 7,453 zone centroids rated Very Low to Very High
- **Return-period flood extents** — 5-year to 200-year storm flood maps
- **Nearby Shelters** — demo/prototype relief shelter locations for evacuation

### 📊 Monitoring Dashboard
- Monthly rainfall trends across all Chennai stations
- Reservoir storage over time (% capacity) with danger thresholds
- Groundwater table depth across monitoring wells
- Top-10 wettest days and station-level rainfall analysis

### 📱 Disaster Management Backend (API)
- REST API for mobile app integration
- **Complaint system** — citizens report waterlogging, road closures, property damage
- Status tracking (submitted → in_progress → resolved)
- Auto-refreshing weather + prediction every 30 minutes

---

## Installation

```bash
# Clone the repository
git clone <repo-url>
cd <repo-directory>

# Create a virtual environment (recommended)
python -m venv .venv
source .venv/bin/activate   # Linux / macOS
# .venv\Scripts\activate    # Windows

# Install dependencies
pip install -r flood_app/requirements.txt
```

For the FastAPI backend:

```bash
pip install -r flood_api/requirements.txt
```

---

## Running the Application

### Streamlit Dashboard

```bash
cd flood_app
streamlit run app.py
```

Opens at `http://localhost:8501` with 8 tabs.

### FastAPI Backend (optional)

```bash
cd flood_api
python main.py
```

Runs at `http://localhost:8000`. Auto-refreshes weather + prediction every 30 minutes.

---

## Retraining the Models

```bash
cd flood_app

# Retrain Random Forest
python train_model.py

# Retrain LSTM
python train_lstm.py
```

Both scripts save model artifacts (`flood_model.joblib`, `flood_lstm.pt`) in the `flood_app/` directory.

---

## Known Limitations

- **Synthetic risk labels** — flood-risk labels are derived from rainfall/reservoir thresholds, not official flood event records
- **Small MODERATE class** — the MODERATE risk category has fewer training examples, leading to lower recall for that class
- **Weather forecast uncertainty** — Open-Meteo forecasts become less accurate beyond 3–5 days; the 7-day outlook is indicative only
- **Limited flood-event validation** — only a handful of historical events are used for validation; this is not a comprehensive backtest
- **Prototype shelter data** — shelter locations are demo placeholders, not verified government-designated relief centers
- **Reservoir baseline** — real-time reservoir telemetry is not available via a free public API; the latest offline dataset month is used as a baseline
- **Model predictions are not official warnings** — always follow IMD and state government emergency guidance

---

## Project Structure

```
.
├── flood_app/                  # Streamlit frontend + ML training
│   ├── app.py                  # Main Streamlit application (8 tabs)
│   ├── load_data.py            # Data loading & feature engineering
│   ├── weather_api.py          # Open-Meteo forecast integration
│   ├── train_model.py          # Random Forest training script
│   ├── train_lstm.py           # LSTM training script (PyTorch)
│   ├── alerts.py               # Flood alert formatting + email
│   ├── flood_model.joblib      # Trained Random Forest model
│   ├── flood_lstm.pt           # Trained LSTM model
│   ├── lstm_metrics.json       # LSTM evaluation metrics
│   └── requirements.txt        # Python dependencies for dashboard
│
├── flood_api/                  # FastAPI REST backend
│   ├── main.py                 # API endpoints (weather, prediction, complaints)
│   ├── predictor.py            # Model loading & inference
│   ├── store.py                # SQLite persistence
│   ├── weather.py              # Open-Meteo realtime weather
│   ├── flood.db                # SQLite database (auto-created)
│   └── requirements.txt        # Python dependencies for API
│
├── Rainfall_Dataset.csv        # Chennai station-level daily rainfall
├── Lake level/                 # Monthly reservoir storage CSVs
├── Lake inflow and outflow/    # Daily inflow/outflow CSVs
├── Groundwater Levels/         # Water table depth CSVs
├── Chennai Flooding Data/      # KML flood-zone layers
├── README.md
└── .gitignore
```

---

## API Endpoints (FastAPI Backend)

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/api/v1/status` | Health check + last refresh info |
| GET | `/api/v1/weather` | Live Chennai weather from Open-Meteo |
| GET | `/api/v1/prediction` | Latest automatic flood prediction |
| POST | `/api/v1/prediction/refresh` | Force a weather + prediction refresh |
| GET | `/api/v1/prediction/history` | Recent prediction history |
| GET | `/api/v1/complaints` | List complaints (`?status=` filter) |
| POST | `/api/v1/complaints` | Submit a flood-related complaint |
| GET | `/api/v1/complaints/{id}` | Get a single complaint |
| PATCH | `/api/v1/complaints/{id}/status` | Update complaint status |
| DELETE | `/api/v1/complaints/{id}` | Delete a complaint |

---

## License

Educational project for college submission. Not licensed for production use.
