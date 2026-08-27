"""Open-Meteo Forecast API integration for Chennai flood prediction.

Fetches 7-day precipitation forecast from the free Open-Meteo API (no key needed).
Returns a pandas DataFrame with columns: date, rainfall_mm_forecast,
plus optional precipitation_probability_max when available.
"""

import requests
import pandas as pd

CHENNAI_LAT = 13.0827
CHENNAI_LON = 80.2707
FORECAST_URL = "https://api.open-meteo.com/v1/forecast"
REQUEST_TIMEOUT = 20  # seconds


def fetch_forecast(forecast_days: int = 7) -> pd.DataFrame:
    """Fetch precipitation forecast from Open-Meteo for Chennai.

    Returns
    -------
    pd.DataFrame
        Columns: date (pd.Timestamp), rainfall_mm_forecast (float),
        and optionally precipitation_probability_max (float, 0-100).
        On any failure, returns an empty DataFrame.
    """
    params = {
        "latitude": CHENNAI_LAT,
        "longitude": CHENNAI_LON,
        "daily": "precipitation_sum,precipitation_probability_max,"
                 "temperature_2m_max,temperature_2m_min,"
                 "weathercode",
        "forecast_days": forecast_days,
        "timezone": "Asia/Kolkata",
    }

    try:
        resp = requests.get(FORECAST_URL, params=params, timeout=REQUEST_TIMEOUT)
        resp.raise_for_status()
    except requests.exceptions.Timeout:
        return pd.DataFrame()
    except requests.exceptions.ConnectionError:
        return pd.DataFrame()
    except requests.exceptions.HTTPError:
        return pd.DataFrame()
    except requests.exceptions.RequestException:
        return pd.DataFrame()

    try:
        data = resp.json()
    except (ValueError, KeyError):
        return pd.DataFrame()

    daily = data.get("daily")
    if daily is None:
        return pd.DataFrame()

    dates_raw = daily.get("time")
    precip_raw = daily.get("precipitation_sum")
    if dates_raw is None or precip_raw is None:
        return pd.DataFrame()

    df = pd.DataFrame({
        "date": pd.to_datetime(pd.Series(dates_raw)),
        "rainfall_mm_forecast": pd.to_numeric(
            pd.Series(precip_raw), errors="coerce"
        ).fillna(0.0),
    })

    prob_raw = daily.get("precipitation_probability_max")
    if prob_raw is not None:
        df["precipitation_probability_max"] = pd.to_numeric(
            pd.Series(prob_raw), errors="coerce"
        ).fillna(0.0)

    tmax_raw = daily.get("temperature_2m_max")
    tmin_raw = daily.get("temperature_2m_min")
    if tmax_raw is not None:
        df["temp_max_c"] = pd.to_numeric(pd.Series(tmax_raw), errors="coerce")
    if tmin_raw is not None:
        df["temp_min_c"] = pd.to_numeric(pd.Series(tmin_raw), errors="coerce")

    wc_raw = daily.get("weathercode")
    if wc_raw is not None:
        df["weather_code"] = pd.Series(wc_raw)

    return df


def get_source_info() -> str:
    """Return a human-readable string about the data source."""
    return (
        "Open-Meteo Forecast API — free, no API key required.\n"
        "Coordinates: Chennai (13.0827°N, 80.2707°E)\n"
        "Source: https://api.open-meteo.com/v1/forecast"
    )
