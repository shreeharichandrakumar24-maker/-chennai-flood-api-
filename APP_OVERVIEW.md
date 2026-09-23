# Chennai Flood Prediction & Disaster Management App — Overall Working (Till Now)

> AI-powered flood-risk platform for Chennai (NE monsoon Oct–Dec).
> Educational project — predictions are NOT official IMD / Tamil Nadu warnings.

## 1. What the App Does

- Predicts flood risk (LOW / MODERATE / HIGH + numeric score) from rainfall + reservoir state.
- Shows live Chennai weather + 7-day forecast (Open-Meteo, no API key).
- Maps flood-prone zones, shelters, and citizen reports.
- Lets citizens submit flood reports (photo + GPS + category) and tracks them.
- Caches last-known data so the app degrades gracefully when the backend is down.

## 2. System Architecture

```
Rainfall CSV (1993–2023) ─┐
Lake levels (5 reservoirs) ├─> load_data.build_model_dataset() ─> Random Forest (300 trees)
Groundwater snapshots ─────┘                                      LSTM (2x64, 14-day window)
                                                                        │
Open-Meteo API (live) ──> flood_api (FastAPI) ──> flood_mobile (Flutter)
                           /weather /prediction   Dashboard / Predict /
                           /status /complaints    Forecast / Map / Report
                           SQLite flood.db
```

Three parts:

| Part | Folder | Role |
|------|--------|------|
| Dashboard + training | `flood_app/` | Streamlit 8-tab UI, `train_model.py`, `train_lstm.py`, `load_data.py`, `weather_api.py`, `alerts.py`, artifacts `flood_model.joblib` / `flood_lstm.pt` |
| REST backend | `flood_api/` | `main.py`, `predictor.py`, `weather.py`, `store.py`, `flood.db`. Deployed via `render.yaml` (`uvicorn main:app`) |
| Mobile app | `flood_mobile/` | Flutter: `lib/main.dart`, `config/`, `services/`, `models/`, `screens/` (8), `widgets/` |

## 3. Data & AI

- **Rainfall:** `Rainfall_Dataset.csv`, station daily, grouped to city daily.
- **Lakes:** `Lake level/` monthly mcft for Poondi, Chembarambakkam, Red Hills, Cholavaram, Thervoy Kandigai → `% capacity`, total mcft.
- **Inflow/outflow:** `Lake inflow and outflow/` daily (monitoring tab only).
- **Groundwater:** `Groundwater Levels/` well depth (monitoring tab only).
- **KML:** `Chennai Flooding Data/` — 2015 stagnation points, inundation depth, 7453 zone centroids, 5–200yr extents (Streamlit map; mobile uses demo zone pins).
- **Live:** Open-Meteo `https://api.open-meteo.com/v1/forecast` (Chennai 13.0827, 80.2707).

**Features (11):** `rainfall_mm, rain_2d/3d/5d/7d/14d, reservoir_avg/max_pct, reservoir_total_mcft, month, dayofyear`.

**Labels (synthetic):** `score = min(rain/120)*0.65 + min(rain3d/250)*0.20 + min(max_pct/100)*0.15`; `<0.35 LOW, <0.60 MODERATE, else HIGH`.

**Models:** RF ~93.7% test acc; LSTM regression score 0–1 → same thresholds, ~78.7% acc.

**Backend inference (`predictor.py`):** reservoir baseline = latest offline lake month (no free live telemetry API); 18-day Open-Meteo history → rolling windows → RF `score = P(HIGH)+0.5*P(MOD)` + LSTM score. Response keys: `random_forest.{risk,score,probabilities}`, `lstm.{risk,score}`, `lstm_available`, `generated_at`, `features`, `reservoir`, `weather`. History rows are flat: `rf_risk/rf_score/lstm_risk/lstm_score/generated_at`.

## 4. Backend Endpoints (`flood_api/main.py`)

| Method | Endpoint | Notes |
|--------|----------|-------|
| GET | `/api/v1/status` | health + `last_refresh`, `lstm_available` |
| GET | `/api/v1/weather` | current + `history{date:precip}` + 3-day `forecast` |
| GET | `/api/v1/prediction` | latest auto prediction (cached in `STATE`) |
| POST | `/api/v1/prediction/refresh` | force refresh; returns `{refreshed_at, prediction}` |
| GET | `/api/v1/prediction/history?limit=` | flat rows for history screen |
| GET/POST | `/api/v1/complaints` | citizen reports list / submit |
| GET/PATCH/DELETE | `/api/v1/complaints/{id}[/status]` | detail / status update / delete |

Auto-refresh every 30 min (APScheduler). `store.py` = SQLite (`complaints`, `predictions`) + `seed_sample_complaints()` (3 Chennai samples inserted only when empty — no endpoint changes). Run flags: `--tunnel` (Cloudflare), `--duckdns`.

## 5. Mobile App (`flood_mobile/`)

Entry `main.dart` loads saved backend URL then `SplashScreen → HomeScreen` (bottom nav: Dashboard, Predict, Forecast, Map, Report).

| Screen | File | Working |
|--------|------|---------|
| Dashboard | `dashboard_screen.dart` | risk badge, weather card, RF/LSTM stat cards, Model Details (LSTM, Generated, Last Refresh, Next Auto-Refresh, Connected via URL), 5-min auto-refresh countdown, pull-to-refresh |
| Predict | `prediction_screen.dart` | sliders (display only) + `POST prediction/refresh` → RF/LSTM result cards with `score.toStringAsFixed(3)` + progress bar |
| Forecast | `forecast_screen.dart` | current weather + coming-days list from `/weather` |
| Map | `map_screen.dart` | `flutter_map` + OSM tiles, risk-zone/shelter layers, GPS (`geolocator`), zoom controls, legend, Reports-pin toggle |
| Report | `report_screen.dart` + `report_detail_screen.dart` | submit form + reports list + detail (see §8) |
| Settings | `settings_screen.dart` | Backend URL field, Test & Save, auto-detect LAN scan, server status, about |
| History | `prediction_history_screen.dart` | flat history cards with RF/LSTM risk + score |
| Splash/Home | `splash_screen.dart`, `home_screen.dart` | animated splash, NavigationBar |

Shared: `widgets/risk_badge.dart`, `weather_card.dart`, `stat_card.dart`, `alert_banner.dart`, `error_state.dart`. Deps: `http, flutter_map, latlong2, fl_chart, geolocator, shared_preferences, image_picker, google_fonts, shimmer, lottie`.

## 6. P1 — Single Backend-URL Config

- `config/api_config.dart` is the single source: `defaultUrl`, `_storageKey='api_base_url'`, `getBaseUrl()/setBaseUrl()/baseUrl/currentUrl/connectionLabel/isPublicUrl`, `autoDetectServer()`. `ApiService._getUrl()` is the only URL builder — no hardcoded URLs elsewhere (map tiles excluded).
- Settings screen has a visible **Backend URL** field (persisted via SharedPreferences, survives restart) + Test & Save + auto-detect.
- Dashboard **Connected via** shows the real URL (`🌐 Public (url)` / `📶 Local (url)`) and **Model Details** reload on every fetch; returning from Settings re-calls `_loadData()` — no reinstall needed.

## 7. P2 — Connection-Failure Handling (No More Fake-Empty State)

- `services/api_exception.dart`: typed errors (`isConnectionError`, `statusCode`).
- `services/api_service.dart`: every call logs URL + RAW JSON, throws instead of returning null; `withRetry(fn, onAttempt)` = 3 attempts, backoff 2s/5s/10s.
- `services/cache_service.dart`: persists last successful prediction/weather/status JSON + timestamp; `staleLabel()` → "Last known data — X minutes ago, not live".
- `widgets/error_state.dart`: `ConnectionRetryingBanner` (attempt X/3 + Retry now), `ConnectionFailedBanner` (message + Retry now), `StaleDataBanner`, plus legacy `ConnectionStatusBanner`/`ErrorState`.
- Dashboard distinguishes **loading-first-time** (spinner) vs **retrying** vs **failed-with-cache** (banners + cached real values) vs **failed-no-cache** (dedicated failure page — never `Unknown`/`Never`/zeros). Forecast/Predict/History/Report/Map(Settings status) all use the same pattern.

## 8. P3 — Score 0.000 Fix

- Backend confirmed live: `random_forest.score` (e.g. 0.0115), `lstm.score` (e.g. 0.2256). History uses `rf_score`/`lstm_score`. Old `?? 0.0` + `Map<String,double>.from` silently produced 0/crashes.
- `models/prediction_model.dart`: RAW-JSON `debugPrint` before parse; `_extractScore` tries `score/rf_score/lstm_score/risk_score/riskScore/...` with key-mismatch warnings; `_parseDouble` handles int/double/String with logged errors; `ModelResult.fromHistory` for history rows; `CurrentWeather` hardened. All scores display with `toStringAsFixed(3)` of the real value.

## 9. P4 — Citizen Reporting (Full Flow)

- **Submit tab:** name*, phone, location* (GPS autofill `lat,lon`), mini-map pin adjust (tap), category UI dropdown [`Waterlogging`, `Blocked road`, `Damaged infrastructure`, `Other`] mapped to backend [`Waterlogging`, `Road closure`, `House/Property damage`, `Other`], description* max 200 (`maxLength`), optional Camera/Gallery photo (`image_picker`, on-device preview; backend row has no photo column so photo is session-local), Submit disabled + spinner, success → snackbar + jump to Reports tab + reload, failure → error banner + Retry-now with all inputs preserved.
- **Reports tab:** most-recent-first list (backend `ORDER BY created_at DESC`), category icon, description, `distance` (geolocator vs report lat/lon), `time-ago`, location, status chip; tap → detail (photo or placeholder, category/status chips, coordinates, distance, timestamps, reporter, 220px exact-location map). Pull-to-refresh; failure shows banner + cached list, not blank.
- **Map tab:** `Reports` switch → fetches `/complaints`, pins reports with lat/lon (deep-purple), tap → bottom sheet; legend shows count/loading; load errors show banner + retry.
- **Seed:** 3 samples (T. Nagar waterlogging, Velachery road closure, Adyar blocked drain) with real coordinates.

## 10. How to Run

```bash
# Dashboard
pip install -r flood_app/requirements.txt
cd flood_app
streamlit run app.py            # :8501

# Backend
pip install -r flood_api/requirements.txt
cd flood_api
python main.py                  # :8000 (add --duckdns / --tunnel for public)
python -c "import store; store.init_db()"   # ensure seed rows

# Mobile
cd flood_mobile
flutter pub get
flutter analyze --no-pub
flutter run                     # set Backend URL in Settings:
                                # emulator → http://10.0.2.2:8000
                                # device    → http://<PC-LAN-IP>:8000
                                # cloud     → https://chennai-flood-api.onrender.com
flutter build apk --release
```

## 11. Verification Done

- `flutter analyze --no-pub`: 0 errors (5 pre-existing `prefer_const` infos).
- Backend direct: `predictor.run_prediction` → RF `0.0115`, LSTM `0.2256` with correct keys; `store.init_db` → 3 seeded complaints.
- P1: URL change in Settings reflects in Dashboard Connected via on next refresh. P2: backend-off shows retrying → failed + stale-cache label. P3: app scores match backend values. P4: submit (with/without photo) appears in list; airplane mode preserves data + retry; map toggle shows pins.

## 12. Known Limitations

- Synthetic risk labels; small MODERATE class; forecast skill drops after 3–5 days.
- Reservoir uses latest offline month (no free live telemetry).
- Shelters + some map zones are demo data, not verified GCC/SDMA sites.
- Report photos are device-local (no backend photo column by design — endpoints left untouched).
- Render free-tier cold start ~30s on first request.
