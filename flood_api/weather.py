"""Realtime weather for Chennai via Open-Meteo (no API key required).

Open-Meteo endpoints used:
  - /v1/forecast    current weather + past/forecast daily precipitation
"""
from datetime import date, datetime, timezone

import requests

CHENNAI = {"latitude": 13.0827, "longitude": 80.2707}
FORECAST_URL = "https://api.open-meteo.com/v1/forecast"
PAST_DAYS = 18      # enough to build the 14-day rolling windows used by the models
FORECAST_DAYS = 3

WMO_CODES = {
    0: ("Clear sky", "clear"), 1: ("Mainly clear", "clear"),
    2: ("Partly cloudy", "partly_cloudy"), 3: ("Overcast", "cloudy"),
    45: ("Fog", "fog"), 48: ("Depositing rime fog", "fog"),
    51: ("Light drizzle", "drizzle"), 53: ("Drizzle", "drizzle"),
    55: ("Dense drizzle", "drizzle"), 56: ("Freezing drizzle light", "drizzle"),
    57: ("Freezing drizzle dense", "drizzle"),
    61: ("Light rain", "rain"), 63: ("Rain", "rain"),
    65: ("Heavy rain", "heavy_rain"),
    66: ("Freezing rain light", "rain"), 67: ("Freezing rain heavy", "heavy_rain"),
    71: ("Slight snow", "snow"), 73: ("Snow", "snow"), 75: ("Heavy snow", "snow"),
    77: ("Snow grains", "snow"), 80: ("Light rain showers", "rain"),
    81: ("Rain showers", "rain"), 82: ("Violent rain showers", "heavy_rain"),
    85: ("Snow showers slight", "snow"), 86: ("Snow showers heavy", "snow"),
    95: ("Thunderstorm", "storm"), 96: ("Thunderstorm with slight hail", "storm"),
    99: ("Thunderstorm with heavy hail", "storm"),
}


def _describe(code):
    return WMO_CODES.get(int(code), ("Unknown", "unknown"))


def fetch_weather() -> dict:
    """Fetch current conditions and a daily precipitation timeline."""
    params = {
        "latitude": CHENNAI["latitude"],
        "longitude": CHENNAI["longitude"],
        "current": ("temperature_2m,apparent_temperature,relative_humidity_2m,"
                    "precipitation,weather_code,wind_speed_10m,cloud_cover"),
        "daily": "precipitation_sum,temperature_2m_max,temperature_2m_min",
        "past_days": PAST_DAYS,
        "forecast_days": FORECAST_DAYS,
        "timezone": "Asia/Kolkata",
    }
    resp = requests.get(FORECAST_URL, params=params, timeout=25)
    resp.raise_for_status()
    data = resp.json()

    cur = data["current"]
    weather_code = cur["weather_code"]
    label, icon = _describe(weather_code)

    daily = data["daily"]
    daily_rows = [
        {
            "date": day,
            "precip_mm": precip,
            "t_max": tmax,
            "t_min": tmin,
        }
        for day, precip, tmax, tmin in zip(
            daily["time"], daily["precipitation_sum"],
            daily["temperature_2m_max"], daily["temperature_2m_min"],
        )
    ]

    # history: the past days that are already available from Open-Meteo
    today_iso = date.today().isoformat()
    history = {}
    forecast = []
    for row in daily_rows:
        if row["date"] <= today_iso:
            history[row["date"]] = float(row["precip_mm"] or 0.0)
        else:
            forecast.append(row)

    return {
        "source": "open-meteo",
        "fetched_at": datetime.now(timezone.utc).isoformat(),
        "today_iso": today_iso,
        "current": {
            "temp_c": cur["temperature_2m"],
            "feels_like_c": cur["apparent_temperature"],
            "humidity_pct": cur["relative_humidity_2m"],
            "precip_mm": cur["precipitation"],
            "wind_kmh": cur["wind_speed_10m"],
            "cloud_pct": cur["cloud_cover"],
            "weather_code": weather_code,
            "description": label,
            "icon": icon,
        },
        "history": history,
        "forecast": forecast,
    }
