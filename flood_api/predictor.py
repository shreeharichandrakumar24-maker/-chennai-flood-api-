"""Loads the trained models from flood_app and runs predictions from features.

The Random Forest model always runs. The LSTM is optional: if PyTorch is not
installed, predict_lstm() returns None and the API reports it as unavailable.
"""
import os
import sys
from datetime import timedelta

import joblib
import numpy as np
import pandas as pd

BASE = os.path.dirname(os.path.abspath(__file__))
FLOOD_APP = os.path.abspath(os.path.join(BASE, "..", "flood_app"))
sys.path.insert(0, FLOOD_APP)

import load_data as ld  # noqa: E402

MODEL_PATH = os.path.join(FLOOD_APP, "flood_model.joblib")
LSTM_PATH = os.path.join(FLOOD_APP, "flood_lstm.pt")

FEATURES = ld.FEATURES
CLASSES = ld.CLASSES

_art = joblib.load(MODEL_PATH)
_MODEL = _art["model"]
_LE = _art["label_encoder"]

_LSTM = None
_LSTM_DATA = None
_LSTM_ERROR = ""
try:
    import torch  # noqa: F401

    _LSTM_DATA = torch.load(LSTM_PATH, map_location="cpu", weights_only=False)
    from train_lstm import FloodLSTM  # noqa: E402

    _LSTM = FloodLSTM(n_features=_LSTM_DATA["n_features"],
                      hidden=_LSTM_DATA["hidden"],
                      layers=_LSTM_DATA["layers"],
                      dropout=_LSTM_DATA["dropout"])
    _LSTM.load_state_dict(_LSTM_DATA["state_dict"], strict=False)
    _LSTM.eval()
except Exception as exc:  # torch missing or model load failed
    _LSTM = None
    _LSTM_DATA = None
    _LSTM_ERROR = str(exc)


def lstm_available() -> bool:
    return _LSTM is not None


def lstm_error() -> str:
    return _LSTM_ERROR


def reservoir_baseline() -> dict:
    """Latest known reservoir storage from the local lake-level dataset.

    Real-time reservoir telemetry is not available via a free public API, so
    the most recent month of the offline dataset is used as a baseline.
    """
    lakes = ld.load_lake_levels()
    latest = lakes.sort_values("date").groupby("reservoir").tail(1)
    return {
        "reservoir_total_mcft": float(latest["mcft"].sum()),
        "reservoir_avg_pct": float(latest["storage_pct"].mean()),
        "reservoir_max_pct": float(latest["storage_pct"].max()),
    }


def build_daily_table(history_rain: dict, res: dict) -> pd.DataFrame:
    """Turn the daily precipitation timeline into a per-day feature table."""
    series = pd.Series(history_rain).astype(float)
    series.index = pd.to_datetime(series.index)
    series = series.sort_index()

    df = pd.DataFrame({"rainfall_mm": series})
    df = df.resample("D").sum().fillna(0.0)
    for w in (2, 3, 5, 7, 14):
        df[f"rain_{w}d"] = df["rainfall_mm"].rolling(w, min_periods=1).sum()
    for key in ("reservoir_avg_pct", "reservoir_max_pct", "reservoir_total_mcft"):
        df[key] = res[key]
    df["month"] = df.index.month
    df["dayofyear"] = df.index.dayofyear
    return df


def predict_rf(row: pd.Series) -> tuple:
    """Random Forest prediction. Returns (risk, probability dict)."""
    X = np.array([[float(row[f]) for f in FEATURES]]).astype(float)
    proba = _MODEL.predict_proba(X)[0]
    risk = _LE.inverse_transform([_MODEL.predict(X)[0]])[0]
    return risk, {c: float(p) for c, p in zip(_LE.classes_, proba)}


def predict_lstm(daily_table: pd.DataFrame):
    """LSTM score on the last 14-day window. Returns dict or None."""
    if _LSTM is None:
        return None
    df = daily_table.dropna(subset=FEATURES)
    if len(df) < _LSTM_DATA["window"]:
        return None
    seq = df.iloc[-_LSTM_DATA["window"]:][FEATURES].values.astype(float)
    scaler = _LSTM_DATA["scaler"]
    w, f = seq.shape
    seq = scaler.transform(seq.reshape(-1, f)).reshape(1, w, f)
    import torch

    with torch.no_grad():
        score = float(_LSTM(torch.tensor(seq, dtype=torch.float32)).item())
    if score >= 0.60:
        risk = "HIGH"
    elif score >= 0.35:
        risk = "MODERATE"
    else:
        risk = "LOW"
    return {"risk": risk, "score": round(score, 4)}


def run_prediction(history_rain: dict, today_iso: str) -> dict:
    """Full automatic prediction for the given daily rain timeline."""
    res = reservoir_baseline()
    daily_table = build_daily_table(history_rain, res)
    if daily_table.empty:
        raise ValueError("No weather history available to build features.")

    row = daily_table.iloc[-1]
    rf_risk, rf_proba = predict_rf(row)
    lstm = predict_lstm(daily_table)

    score = rf_proba.get("HIGH", 0.0) + 0.5 * rf_proba.get("MODERATE", 0.0)

    return {
        "features": {f: (None if pd.isna(row[f]) else float(row[f]))
                     for f in FEATURES},
        "reservoir": res,
        "random_forest": {
            "risk": rf_risk,
            "probabilities": rf_proba,
            "score": round(score, 4),
        },
        "lstm": lstm,
        "lstm_available": lstm_available(),
        "generated_at": pd.Timestamp(today_iso).isoformat(),
    }
