import joblib
import numpy as np
import pandas as pd
import streamlit as st
import matplotlib.pyplot as plt
import matplotlib.dates as mdates
import matplotlib.font_manager as fm
import pydeck as pdk
import torch

import load_data as ld
import weather_api
import alerts

st.set_page_config(page_title="Chennai Flood Prediction", layout="wide",
                   page_icon="🌊")

RED, AMBER, GREEN = "#e63946", "#f4a261", "#2a9d8f"


@st.cache_data
def get_datasets():
    daily, raw_rain = ld.load_rainfall()
    lakes = ld.load_lake_levels()
    inflow = ld.load_inflow_outflow()
    gw = ld.load_groundwater()
    model_df = ld.build_model_dataset()
    score, labels = ld.make_labels(model_df)
    model_df = model_df.assign(score=score, risk=labels)
    return daily, raw_rain, lakes, inflow, gw, model_df


@st.cache_data
def get_kml_data():
    p15 = ld.load_2015_flood_points()
    ip = ld.load_inundation_points()
    iz = ld.load_inundation_zones()
    rp = ld.load_return_periods()
    return p15, ip, iz, rp


@st.cache_data
def get_shelters():
    return ld.get_shelters()


@st.cache_resource
def get_model():
    art = joblib.load("flood_model.joblib")
    return art


@st.cache_resource
def get_lstm():
    torch.manual_seed(42)
    data = torch.load("flood_lstm.pt", map_location="cpu", weights_only=False)
    from train_lstm import FloodLSTM
    model = FloodLSTM(n_features=data["n_features"], hidden=data["hidden"],
                      layers=data["layers"], dropout=data["dropout"])
    model.load_state_dict(data["state_dict"], strict=False)
    model.eval()
    return model, data


def risk_colors(risk):
    return {"LOW": GREEN, "MODERATE": AMBER, "HIGH": RED}[risk]


def style_ax(ax):
    for s in ("top", "right"):
        ax.spines[s].set_visible(False)
    ax.grid(axis="y", alpha=0.25)


def header():
    st.markdown(
        "<h1 style='text-align:center;color:#1d3557'>🌊 Chennai Flood Risk "
        "Prediction System</h1>",
        unsafe_allow_html=True,
    )
    st.markdown(
        "<p style='text-align:center;color:#457b9d'>Rainfall · Reservoir · "
        "Groundwater monitoring & ML-based flood risk forecasting</p>",
        unsafe_allow_html=True,
    )
    st.divider()


daily, raw_rain, lakes, inflow, gw, model_df = get_datasets()
art = get_model()
model, le, features = art["model"], art["label_encoder"], art["features"]


def predict_row(row_dict, model_name="Random Forest", prediction_date=None):
    """Run model inference on a single feature row.

    For LSTM, builds a real 14-day temporal sequence:
      - 13 historical days preceding ``prediction_date`` from model_df
      - the supplied ``row_dict`` features as the 14th (current) timestep
    Falls back gracefully if fewer than 13 historical days are available.
    """
    if model_name == "LSTM":
        lstm_model, data = get_lstm()
        scaler = data["scaler"]
        window = data["window"]  # 14
        f = data["n_features"]   # number of features

        # --- Build a real 14-day temporal sequence ---
        current_row = np.array(
            [row_dict.get(fe, 0) for fe in ld.FEATURES], dtype=float
        )

        if prediction_date is not None:
            pred_date = pd.Timestamp(prediction_date)
            hist = model_df[model_df["date"] < pred_date].tail(window - 1)
            if len(hist) >= window - 1:
                hist_seq = hist[ld.FEATURES].values.astype(float)
            else:
                # Fewer than 13 historical days: pad with the earliest
                # available row repeated to fill the window
                if len(hist) > 0:
                    pad_count = (window - 1) - len(hist)
                    pad = np.tile(hist[ld.FEATURES].values[0:1], (pad_count, 1))
                    hist_seq = np.vstack([pad, hist[ld.FEATURES].values])
                else:
                    hist_seq = np.tile(current_row, (window - 1, 1))
        else:
            # No date supplied — repeat the current row (legacy fallback)
            hist_seq = np.tile(current_row, (window - 1, 1))

        full_seq = np.vstack([hist_seq, current_row.reshape(1, -1)])
        assert full_seq.shape == (window, f), (
            f"Sequence shape {full_seq.shape} != expected ({window}, {f})"
        )

        # Apply the scaler exactly as during training:
        # scaler was fit on (n_samples * window, n_features) then reshaped
        scaled = scaler.transform(full_seq.reshape(-1, f)).reshape(1, window, f)

        with torch.no_grad():
            score = float(
                lstm_model(torch.tensor(scaled, dtype=torch.float32)).item()
            )
        pred_idx = 0 if score < 0.35 else (1 if score < 0.60 else 2)
        pred = ld.CLASSES[pred_idx]
        proba = {c: 0.0 for c in ld.CLASSES}
        proba[pred] = 1.0
        proba["score"] = score
        return pred, proba

    # --- Random Forest path (unchanged) ---
    X = np.array([[row_dict.get(f, 0) for f in features]]).astype(float)
    proba = model.predict_proba(X)[0]
    pred = le.inverse_transform([model.predict(X)[0]])[0]
    return pred, {c: float(p) for c, p in zip(le.classes_, proba)}


def show_prediction_ui():
    st.subheader("🎯 Flood Risk Predictor")
    st.caption("Enter rainfall and reservoir conditions to get a flood-risk "
               "forecast. Switch between the Random Forest and LSTM models.")

    model_name = st.radio("Model", ["Random Forest", "LSTM"], horizontal=True)

    c1, c2, c3 = st.columns(3)
    with c1:
        rain = st.number_input("Rainfall today (mm)", 0.0, 600.0, 50.0, 5.0)
        rain3 = st.number_input("Rainfall last 3 days (mm)", 0.0, 1000.0, 80.0, 10.0)
    with c2:
        rain5 = st.number_input("Rainfall last 5 days (mm)", 0.0, 1500.0, 100.0, 10.0)
        rain7 = st.number_input("Rainfall last 7 days (mm)", 0.0, 2000.0, 120.0, 10.0)
    with c3:
        pct = st.slider("Reservoir storage (max %)", 0, 100, 70)
        date_pick = st.date_input("Seasonal context (month)", value=pd.Timestamp("2023-11-01"))

    rain14 = float(rain7)
    doy = pd.Timestamp(date_pick).dayofyear
    month = pd.Timestamp(date_pick).month
    total_mcft = pct / 100 * sum(ld.RESERVOIR_CAPACITY.values())

    row = {
        "rainfall_mm": rain, "rain_2d": (rain3 + rain) / 2, "rain_3d": rain3,
        "rain_5d": rain5, "rain_7d": rain7, "rain_14d": rain14,
        "reservoir_avg_pct": pct, "reservoir_max_pct": pct,
        "reservoir_total_mcft": total_mcft, "month": month, "dayofyear": doy,
    }
    pred, proba = predict_row(row, model_name, prediction_date=pd.Timestamp(date_pick))

    g1, g2 = st.columns([1, 1.4])
    with g1:
        color = risk_colors(pred)
        score_line = ""
        if "score" in proba:
            score_line = (f"<p style='margin:0'>risk score: "
                          f"{proba['score']:.2f} / 1.00</p>")
        st.markdown(
            f"<div style='background:{color};color:white;padding:24px;"
            f"border-radius:12px;text-align:center'>"
            f"<h2 style='margin:0;color:white'>Predicted Risk: {pred}</h2>"
            f"<p style='margin:0'>with rainfall {rain} mm / reservoir {pct}% full</p>"
            f"{score_line}</div>",
            unsafe_allow_html=True,
        )
    with g2:
        st.markdown("**Probability of each risk level**")
        p_df = pd.DataFrame({"Risk": list(proba.keys()), "Probability": list(proba.values())})
        fig, ax = plt.subplots(figsize=(5, 3))
        order = ["LOW", "MODERATE", "HIGH"]
        p_df = p_df.set_index("Risk").reindex(order).fillna(0)
        colors = [risk_colors(r) for r in order]
        ax.bar(p_df.index, p_df["Probability"], color=colors)
        ax.set_ylim(0, 1)
        ax.set_ylabel("Probability")
        style_ax(ax)
        st.pyplot(fig)
    # --- HIGH risk alert ---
    alert_msg = alerts.check_and_format_alert(pred, proba.get("score"))
    if alert_msg:
        st.error(alert_msg)
        # Email alerting is OFF by default — no credentials needed to start.
        # See alerts.py for instructions on enabling Gmail SMTP.
        alerts.send_email_alert(
            subject=f"[Chennai Flood Alert] HIGH risk predicted — {pred}",
            body=alert_msg,
        )

    st.caption("⚠️ Disclaimer: Educational ML project for a college submission. "
               "Not a substitute for official IMD / state government flood warnings.")


def tab_dashboard():
    st.subheader("📊 Chennai Flood Dashboard")

    latest = model_df.iloc[-1]
    risk_now = "LOW"
    if latest["rainfall_mm"] > 0:
        _, _, risk_now = latest["score"], None, None

    c1, c2, c3, c4 = st.columns(4)
    peak = model_df["rainfall_mm"].max()
    c1.metric("Max daily rainfall", f"{peak:.0f} mm")
    c2.metric("Rainy days recorded", f"{int((model_df['rainfall_mm']>0).sum()):,}")
    c3.metric("Reservoirs monitored", f"{len(ld.RESERVOIR_CAPACITY)}")
    c4.metric("Data span", f"{model_df['date'].min().year}–{model_df['date'].max().year}")

    st.markdown("---")
    st.markdown("**Monthly rainfall trend (all Chennai stations)**")
    month_trend = model_df.groupby(["year", "month"])["rainfall_mm"].sum().reset_index()
    month_trend["ym"] = pd.to_datetime(
        month_trend["year"].astype(str) + "-" + month_trend["month"].astype(str) + "-01")
    m1, m2 = st.columns([2, 1])
    with m1:
        fig, ax = plt.subplots(figsize=(10, 3.4))
        ax.bar(month_trend["ym"], month_trend["rainfall_mm"], width=20, color="#457b9d")
        ax.set_ylabel("Monthly rainfall (mm)")
        style_ax(ax)
        ax.xaxis.set_major_locator(mdates.YearLocator(3))
        st.pyplot(fig)
    with m2:
        month_avg = month_trend.groupby("month")["rainfall_mm"].mean()
        fig, ax = plt.subplots(figsize=(5, 3.4))
        ax.plot(month_avg.index, month_avg.values, marker="o", color=RED)
        ax.set_ylabel("Avg monthly rainfall (mm)")
        ax.set_xlabel("Month")
        style_ax(ax)
        st.pyplot(fig)

    st.markdown("---")
    st.markdown("**Reservoir storage over time (% of capacity)**")
    c_l, c_r = st.columns([2, 1])
    with c_l:
        fig, ax = plt.subplots(figsize=(10, 3.4))
        for res, grp in lakes.groupby("reservoir"):
            ax.plot(grp["date"], grp["storage_pct"], label=res, lw=1.2)
        ax.axhline(90, color=RED, ls="--", lw=1, alpha=0.7)
        ax.axhline(100, color="#333", ls=":", lw=1)
        ax.legend(loc="upper left", fontsize=7)
        ax.set_ylabel("Storage (% capacity)")
        style_ax(ax)
        ax.xaxis.set_major_locator(mdates.YearLocator(4))
        st.pyplot(fig)
    with c_r:
        latest_lake = lakes.sort_values("date").groupby("reservoir").last()
        latest_lake = latest_lake.reset_index()
        st.markdown("**Latest storage levels**")
        for _, r in latest_lake.iterrows():
            color = RED if r["storage_pct"] >= 90 else (AMBER if r["storage_pct"] >= 70 else GREEN)
            st.markdown(
                f"- **{r['reservoir']}**: <span style='color:{color}'>"
                f"{r['storage_pct']:.0f}%</span> "
                f"({r['mcft']:.0f} / {r['capacity_mcft']:.0f} mcft)",
                unsafe_allow_html=True,
            )


def tab_rainfall():
    st.subheader("🌧️ Rainfall Analysis")
    st.markdown("Station-level daily rainfall across Chennai (1993–2023).")

    stations = sorted(raw_rain["Station"].unique())
    sel = st.multiselect("Stations", stations, default=stations[:4])
    if not sel:
        st.info("Select at least one station.")
        return

    sub = raw_rain[raw_rain["Station"].isin(sel)]
    daily_st = sub.groupby("Date")["Rainfall"].sum().reset_index()

    rng = st.slider("Year range", int(daily_st["Date"].dt.year.min()),
                    int(daily_st["Date"].dt.year.max()),
                    (2015, 2023))
    filt = daily_st[(daily_st["Date"].dt.year >= rng[0]) &
                    (daily_st["Date"].dt.year <= rng[1])]

    fig, ax = plt.subplots(figsize=(12, 3.6))
    ax.bar(filt["Date"], filt["Rainfall"], width=1.2, color="#1d3557")
    ax.axhline(64.5, color=AMBER, ls="--", lw=1, label="Heavy rain (>64.5 mm)")
    ax.axhline(115.6, color=RED, ls="--", lw=1, label="Very heavy (>115.6 mm)")
    ax.legend(fontsize=8)
    ax.set_ylabel("Daily rainfall (mm)")
    style_ax(ax)
    ax.xaxis.set_major_locator(mdates.YearLocator(2))
    st.pyplot(fig)

    c1, c2 = st.columns(2)
    with c1:
        st.markdown("**Top-10 wettest days**")
        top = daily_st.nlargest(10, "Rainfall").sort_values("Date")
        st.dataframe(top.rename(columns={"Date": "Date", "Rainfall": "Rainfall (mm)"}),
                     width="stretch", hide_index=True)
    with c2:
        st.markdown("**Monthly rainfall by station (mm)**")
        agg = raw_rain[raw_rain["Station"].isin(sel)].copy()
        agg["Month"] = agg["Date"].dt.month
        by = agg.groupby(["Station", "Month"])["Rainfall"].sum().unstack()
        st.dataframe(by.round(0).fillna(0).astype(int), width="stretch")


def tab_reservoir():
    st.subheader("🏞️ Reservoir & Inflow Monitoring")
    st.markdown("Storage, inflow and outflow for Chennai's water supply lakes.")

    res = st.selectbox("Reservoir", list(ld.RESERVOIR_CAPACITY.keys()))
    cap = ld.RESERVOIR_CAPACITY[res]

    c1, c2 = st.columns(2)
    with c1:
        st.markdown(f"**Storage of {res} (mcft)**")
        sub = lakes[lakes["reservoir"] == res]
        fig, ax = plt.subplots(figsize=(9, 3.2))
        ax.plot(sub["date"], sub["mcft"], color="#1d3557", lw=1.4)
        ax.axhline(cap, color=RED, ls="--", lw=1.2, label=f"Capacity ({cap} mcft)")
        ax.legend(fontsize=8)
        ax.set_ylabel("Storage (mcft)")
        style_ax(ax)
        ax.xaxis.set_major_locator(mdates.YearLocator(4))
        st.pyplot(fig)
    with c2:
        st.markdown(f"**Storage of {res} (% capacity)**")
        fig, ax = plt.subplots(figsize=(9, 3.2))
        ax.plot(sub["date"], sub["storage_pct"], color="#2a9d8f", lw=1.4)
        ax.axhline(90, color=RED, ls="--", lw=1.2)
        ax.set_ylabel("% capacity")
        style_ax(ax)
        ax.xaxis.set_major_locator(mdates.YearLocator(4))
        st.pyplot(fig)

    st.markdown("---")
    st.markdown("**Daily inflow & outflow (2021–2024)**")
    cols = [c for c in inflow.columns
            if c.startswith(res) and ("Inflow Total" in c or "Outflow Total" in c)]
    if not cols:
        st.warning("No inflow/outflow data for this reservoir.")
        return
    cols = cols[:2]
    fig, ax = plt.subplots(figsize=(12, 3.4))
    for c, colr in zip(cols, ["#2a9d8f", "#e63946"]):
        ax.plot(inflow["date"], inflow[c], label=c, lw=0.8, alpha=0.85, color=colr)
    ax.legend(fontsize=8)
    ax.set_ylabel("Water flow (units)")
    style_ax(ax)
    st.pyplot(fig)
    st.caption("Values are daily totals. Units differ per dataset source.")


def tab_prediction():
    show_prediction_ui()

    st.markdown("---")
    st.subheader("📈 Model performance")

    _, lstm_data = get_lstm()
    lstm_acc = lstm_data.get("test_accuracy", 0)
    m1, m2, m3 = st.columns(3)
    m1.metric("Random Forest accuracy", "93.7%")
    m2.metric("LSTM accuracy", f"{lstm_acc * 100:.1f}%")
    m3.metric("Classes", "LOW / MODERATE / HIGH")

    st.markdown(
        "**Comparison:** Both models are trained on the same features and data "
        "split. Random Forest is faster, simpler and slightly more accurate on "
        "this small tabular dataset. The LSTM (deep learning) reads the past "
        "14 days as a sequence and predicts a continuous flood-risk score "
        "(0–1), which is then mapped to the risk level. LSTM captures temporal "
        "patterns natively; RF relies on engineered rolling-window features."
    )

    c_l, c_r = st.columns(2)
    with c_l:
        st.markdown("**Random Forest — feature importance**")
        imp = pd.Series(model.feature_importances_, index=features).sort_values()
        fig, ax = plt.subplots(figsize=(7, 4.5))
        ax.barh(imp.index, imp.values, color="#457b9d")
        ax.set_xlabel("Importance")
        style_ax(ax)
        st.pyplot(fig)
    with c_r:
        st.markdown("**About the models**")
        st.markdown(
            "- **Random Forest**: 300 trees, depth 12, Gini criterion\n"
            "- **LSTM**: 2 layers × 64 hidden units, dropout 0.25, 60 epochs, "
            "14-day sliding windows\n"
            "- **Inputs**: rainfall (today + 2/3/5/7/14-day windows), reservoir "
            "storage (avg/max % + total mcft), month, day-of-year\n"
            "- **Output**: flood risk level (LOW / MODERATE / HIGH)\n"
            "- **Training data**: daily records 2003–2017; validation 2018–2021\n"
            "- **Labels**: derived from rainfall intensity + reservoir fullness "
            "thresholds (no official flood labels in the source data)"
        )


def tab_groundwater():
    st.subheader("💧 Groundwater Monitoring")
    st.markdown("Water table depth (m below ground level) across Chennai wells.")

    sel = st.selectbox("Dataset snapshot", sorted(gw["src_file"].unique()))
    sub = gw[gw["src_file"] == sel]
    locs = sub["Location"].value_counts().head(15).index.tolist()
    sl = st.multiselect("Locations", sorted(sub["Location"].unique()), default=locs[:5])
    if not sl:
        st.info("Select at least one location.")
        return
    d2 = sub[sub["Location"].isin(sl)]

    fig, ax = plt.subplots(figsize=(11, 3.6))
    for loc, grp in d2.groupby("Location"):
        grp = grp.sort_values("month_num")
        ax.plot(grp["month_num"], grp["depth_m"], marker="o", ms=3, lw=1.2, label=loc)
    ax.set_ylabel("Water table depth (m)")
    ax.set_xlabel("Month")
    ax.legend(fontsize=7, ncol=3)
    style_ax(ax)
    st.pyplot(fig)
    st.caption("Smaller depth = water table closer to surface (higher flood / "
               "waterlogging risk).")


def _color_for_cat(cat):
    cat = str(cat).upper()
    return {"LOW": [42, 157, 143], "MODERATE": [244, 162, 97],
            "HIGH": [230, 57, 70], "VERY LOW": [76, 201, 240],
            "VERY HIGH": [133, 13, 28]}.get(cat, [100, 100, 100])


def tab_map():
    st.subheader("🗺️ Chennai Flood Map")
    st.markdown(
        "Real flood layers from the Chennai flood study: 2015 flood water-stagnation "
        "points, observed inundation depths, city inundation zones and storm "
        "return-period flood extents.")

    p15, ip, iz, rp = get_kml_data()

    layer = st.selectbox(
        "Layer",
        ["2015 flood stagnation points", "Observed inundation depth (inches)",
         "Inundation risk zones", "Return-period flood extents",
         "Nearby Shelters"],
    )

    selected = None
    layers = []

    if layer == "2015 flood stagnation points":
        selected = p15
        sel_rng = st.slider("2015 Zone filter", 0, 15, (0, 15))
        selected = selected[selected["ZONE"].between(*sel_rng)]
        st.caption(f"Showing {len(selected)} of 753 flood points. "
                   "Use the Zone filter (1–15) to focus on one zone.")
        layers.append(pdk.Layer(
            "ScatterplotLayer", data=selected, get_position=["LONG_", "LAT"],
            get_fill_color=[230, 57, 70, 160], get_radius=90,
            pickable=True, opacity=0.9,
            tooltip={"text": "{name}\nZone {ZONE} / Division {DIVISION}"}))
        center = [80.27, 13.08]
        zoom = 11.2

    elif layer == "Observed inundation depth (inches)":
        selected = ip
        max_d = st.slider("Min depth (inches)", 0, 60, 0)
        selected = selected[selected["DEPTH"] >= max_d]
        st.caption(f"Showing {len(selected)} points with depth ≥ {max_d} in. "
                   f"Max observed depth: {ip['DEPTH'].max():.0f} in.")
        selected = selected.copy()
        selected["color"] = selected["DEPTH"].apply(
            lambda d: [230, 57, 70, 255] if d >= 12
            else ([244, 162, 97, 220] if d >= 8 else [42, 157, 143, 200]))
        layers.append(pdk.Layer(
            "ScatterplotLayer", data=selected, get_position=["F_LONGITUDE", "F_LATITUDE"],
            get_fill_color="color", get_radius=120,
            pickable=True, opacity=0.9,
            tooltip={"text": "Depth: {DEPTH} in\n{F_REMARKS}"}))
        center = [80.27, 13.08]
        zoom = 11.2

    elif layer == "Inundation risk zones":
        selected = iz
        cat_map = {"VERY HIGH": 5, "HIGH": 4, "MODERATE": 3, "LOW": 2, "VERY LOW": 1}
        selected = selected.copy()
        selected["risk_score"] = selected["CATEGORY"].map(cat_map).fillna(0)
        selected["color"] = selected["CATEGORY"].apply(_color_for_cat)
        rng = st.slider("Minimum risk category",
                        options=["Very Low", "Low", "Moderate", "High", "Very High"],
                        value="Low")
        sel_score = cat_map[rng.upper()]
        selected = selected[selected["risk_score"] >= sel_score]
        st.caption(f"Showing {len(selected)} of 7453 zone centroids "
                   f"with risk ≥ {rng}.")
        layers.append(pdk.Layer(
            "ScatterplotLayer", data=selected, get_position=["lon", "lat"],
            get_fill_color="color", get_radius=200,
            pickable=True, opacity=0.85,
            tooltip={"text": "Risk: {CATEGORY}"}))
        center = [80.24, 13.04]
        zoom = 10.3

    elif layer == "Nearby Shelters":
        shelters = get_shelters()
        selected = shelters
        st.caption(
            "⚠️ **Demo/Prototype Shelter Locations** — These are placeholder "
            "coordinates for UI development. They are NOT verified government-" 
            "designated relief centers."
        )
        layers.append(pdk.Layer(
            "ScatterplotLayer", data=selected,
            get_position=["longitude", "latitude"],
            get_fill_color=[0, 150, 136, 220],  # teal — distinct from red flood layers
            get_radius=250,
            pickable=True, opacity=0.95,
            tooltip={"text": "{name}\nCapacity: {capacity}"}))
        center = [80.24, 13.05]
        zoom = 11.5

    else:
        rp_list = ["5-year", "10-year", "25-year", "50-year", "100-year", "200-year"]
        rp_sel = st.multiselect("Return periods", rp_list, default=rp_list[:3])
        cat_sel = st.multiselect("Categories", ["HIGH", "MODERATE", "LOW"],
                                 default=["HIGH", "MODERATE", "LOW"])
        selected = rp[rp["return_period"].isin(rp_sel) & rp["CATEGORY"].isin(cat_sel)]
        selected = selected.copy()
        selected["color"] = selected["CATEGORY"].apply(_color_for_cat)
        st.caption(f"Showing {len(selected)} flood-extent centroids. A HIGH area "
                   "in the 5-year map floods in frequent storms; in the 200-year "
                   "map it needs an extreme event.")
        layers.append(pdk.Layer(
            "ScatterplotLayer", data=selected, get_position=["lon", "lat"],
            get_fill_color="color", get_radius=120,
            pickable=True, opacity=0.8,
            tooltip={"text": "Return period: {return_period}\nRisk: {CATEGORY}"}))
        center = [80.24, 13.05]
        zoom = 10.5

    deck = pdk.Deck(
        map_style="light",
        initial_view_state=pdk.ViewState(latitude=center[1], longitude=center[0],
                                         zoom=zoom, pitch=0),
        layers=layers,
        tooltip={"text": "{name}"},
    )
    st.pydeck_chart(deck)

    if selected is not None and not selected.empty:
        with st.expander("Show table"):
            st.dataframe(selected, width="stretch", hide_index=True)


def _build_forecast_features(historical_rain_series: pd.Series,
                            forecast_rain: list, reservoir_pct: float,
                            forecast_date: pd.Timestamp) -> dict:
    """Build a single day's feature row given a history + forecast extension.

    Parameters
    ----------
    historical_rain_series : pd.Series
        Index=date, values=rainfall_mm for historical days (most recent last).
    forecast_rain : list[float]
        Accumulated forecast rainfall values up to and including the target day.
    reservoir_pct : float
        Latest known reservoir max % fullness.
    forecast_date : pd.Timestamp
        The target forecast date.

    Returns
    -------
    dict  with all 11 features the model expects.
    """
    # Combine historical + forecast into a single daily series
    all_rain = list(historical_rain_series.values) + forecast_rain
    series = pd.Series(all_rain, dtype=float)

    today_val = float(series.iloc[-1]) if len(series) > 0 else 0.0
    rain_2d = float(series.iloc[-2:].sum()) if len(series) >= 2 else today_val
    rain_3d = float(series.iloc[-3:].sum()) if len(series) >= 3 else float(series.sum())
    rain_5d = float(series.iloc[-5:].sum()) if len(series) >= 5 else float(series.sum())
    rain_7d = float(series.iloc[-7:].sum()) if len(series) >= 7 else float(series.sum())
    rain_14d = float(series.iloc[-14:].sum()) if len(series) >= 14 else float(series.sum())

    total_mcft = reservoir_pct / 100 * sum(ld.RESERVOIR_CAPACITY.values())

    return {
        "rainfall_mm": today_val,
        "rain_2d": rain_2d,
        "rain_3d": rain_3d,
        "rain_5d": rain_5d,
        "rain_7d": rain_7d,
        "rain_14d": rain_14d,
        "reservoir_avg_pct": reservoir_pct,
        "reservoir_max_pct": reservoir_pct,
        "reservoir_total_mcft": total_mcft,
        "month": forecast_date.month,
        "dayofyear": forecast_date.dayofyear,
    }


def tab_forecast():
    st.subheader("📈 Chennai Flood Risk Forecast — Open-Meteo Weather Input")
    st.caption(
        "7-day flood risk forecast using live Open-Meteo precipitation data.\n"
        "Rolling rainfall features are built by appending forecast values to the\n"
        "latest known historical rainfall from the project dataset."
    )

    # --- Get latest historical rainfall ---
    daily_hist = daily.copy()  # from get_datasets()
    if daily_hist.empty:
        st.warning("No historical rainfall data available.")
        return
    last_date = daily_hist["date"].max()
    last_rainfall = float(daily_hist[daily_hist["date"] == last_date]["rainfall_mm"].iloc[0])

    # Build a 14-day historical tail for rolling features
    hist_14 = daily_hist.tail(14).set_index("date")["rainfall_mm"]

    # --- Latest reservoir info ---
    latest_lake = lakes.sort_values("date").groupby("reservoir").last().reset_index()
    reservoir_pct = float(latest_lake["storage_pct"].mean())

    # --- Fetch Open-Meteo forecast ---
    forecast_df = weather_api.fetch_forecast(forecast_days=7)

    if forecast_df.empty:
        st.warning(
            "⚠️ Live weather forecast unavailable. "
            "Forecast-based flood prediction cannot be updated.\n\n"
            "This may be due to a network issue or the Open-Meteo API being "
            "temporarily unavailable. The rest of the app remains functional."
        )
        st.info(weather_api.get_source_info())
        return

    st.info(weather_api.get_source_info())

    # --- Display forecast table ---
    st.markdown("### 7-Day Rainfall Forecast (mm)")
    display_df = forecast_df[["date", "rainfall_mm_forecast"]].copy()
    display_df.columns = ["Date", "Rainfall (mm)"]
    if "precipitation_probability_max" in forecast_df.columns:
        display_df["Precip Prob Max (%)"] = (
            forecast_df["precipitation_probability_max"].values
        )
    if "temp_max_c" in forecast_df.columns:
        display_df["Temp Max (°C)"] = forecast_df["temp_max_c"].values
    if "temp_min_c" in forecast_df.columns:
        display_df["Temp Min (°C)"] = forecast_df["temp_min_c"].values

    st.dataframe(display_df, width="stretch", hide_index=True)

    # --- Rainfall chart ---
    fig, ax = plt.subplots(figsize=(10, 3.2))
    ax.bar(
        forecast_df["date"], forecast_df["rainfall_mm_forecast"],
        color="#457b9d", width=0.7, label="Forecast",
    )
    ax.set_ylabel("Rainfall (mm)")
    ax.set_title("Open-Meteo 7-Day Precipitation Forecast — Chennai")
    style_ax(ax)
    plt.xticks(rotation=30)
    st.pyplot(fig)

    # --- Build features & run predictions for each forecast day ---
    st.markdown("---")
    st.markdown("### 7-Day Flood Risk Timeline")

    forecast_rain_values = forecast_df["rainfall_mm_forecast"].tolist()
    results = []

    for i, (_, frow) in enumerate(forecast_df.iterrows()):
        fdate = pd.Timestamp(frow["date"])
        # rain up to and including this forecast day
        rain_slice = forecast_rain_values[: i + 1]
        row_features = _build_forecast_features(
            hist_14, rain_slice, reservoir_pct, fdate
        )

        rf_pred, rf_proba = predict_row(row_features, "Random Forest")
        lstm_pred, lstm_proba = predict_row(row_features, "LSTM", prediction_date=fdate)

        rf_score = rf_proba.get("HIGH", 0.0) + 0.5 * rf_proba.get("MODERATE", 0.0)
        lstm_score = lstm_proba.get("score", 0.0)

        results.append({
            "date": fdate,
            "rainfall_mm": frow["rainfall_mm_forecast"],
            "rf_risk": rf_pred,
            "rf_score": round(rf_score, 4),
            "rf_proba": {k: v for k, v in rf_proba.items() if k in ld.CLASSES},
            "lstm_risk": lstm_pred,
            "lstm_score": round(lstm_score, 4),
        })

    # --- Timeline table ---
    timeline_data = []
    for r in results:
        agree = r["rf_risk"] == r["lstm_risk"]
        combined = r["rf_risk"] if agree else "MIXED"
        timeline_data.append({
            "Date": r["date"].strftime("%Y-%m-%d"),
            "Rain (mm)": round(r["rainfall_mm"], 1),
            "RF Risk": r["rf_risk"],
            "RF Score": r["rf_score"],
            "LSTM Risk": r["lstm_risk"],
            "LSTM Score": r["lstm_score"],
            "Combined": combined,
        })

    timeline_df = pd.DataFrame(timeline_data)
    st.dataframe(timeline_df, width="stretch", hide_index=True)

    # --- HIGH risk alerts for forecast days ---
    forecast_alerts = alerts.check_forecast_alerts(results)
    if forecast_alerts:
        for fa in forecast_alerts:
            date_str = fa["date"].strftime("%Y-%m-%d") if fa["date"] else "???"
            st.error(
                f"🚨 **HIGH FLOOD RISK** predicted for **{date_str}** "
                f"by {fa['model']} (score: {fa['score']:.3f}). "
                f"Monitor official IMD and state government flood warnings."
            )
        # Email alerting is OFF by default — no credentials needed to start.
        # See alerts.py for instructions on enabling Gmail SMTP.
        alerts.send_email_alert(
            subject=f"[Chennai Flood Alert] HIGH risk in 7-day forecast",
            body="\n".join(
                f"{fa['date'].strftime('%Y-%m-%d')} — {fa['model']} score={fa['score']:.3f}"
                for fa in forecast_alerts
            ),
        )
    else:
        st.info("✅ No HIGH flood risk days detected in the 7-day forecast.")

    # --- Risk bar chart ---
    fig2, ax2 = plt.subplots(figsize=(10, 3.5))
    x_pos = range(len(results))
    rf_colors = [risk_colors(r["rf_risk"]) for r in results]
    lstm_colors = [risk_colors(r["lstm_risk"]) for r in results]
    labels_x = [r["date"].strftime("%m-%d") for r in results]

    bar_w = 0.35
    ax2.bar(
        [x - bar_w / 2 for x in x_pos],
        [r["rf_score"] for r in results],
        width=bar_w, color="#1d3557", alpha=0.8, label="RF score",
    )
    ax2.bar(
        [x + bar_w / 2 for x in x_pos],
        [r["lstm_score"] for r in results],
        width=bar_w, color="#457b9d", alpha=0.8, label="LSTM score",
    )
    ax2.axhline(0.35, color=AMBER, ls="--", lw=1, alpha=0.6, label="MODERATE threshold")
    ax2.axhline(0.60, color=RED, ls="--", lw=1, alpha=0.6, label="HIGH threshold")
    ax2.set_xticks(list(x_pos))
    ax2.set_xticklabels(labels_x)
    ax2.set_ylabel("Flood risk score")
    ax2.set_title("RF vs LSTM — 7-Day Flood Risk Score Comparison")
    ax2.legend(fontsize=7, loc="upper left")
    style_ax(ax2)
    st.pyplot(fig2)

    # --- Risk level badges ---
    st.markdown("**Daily risk levels:**")
    badge_cols = st.columns(len(results))
    for col, r in zip(badge_cols, results):
        agree = r["rf_risk"] == r["lstm_risk"]
        if agree:
            bg = risk_colors(r["rf_risk"])
            col.markdown(
                f"<div style='background:{bg};color:white;padding:10px;"
                f"border-radius:8px;text-align:center;margin-bottom:4px'>"
                f"<b>{r['date'].strftime('%m-%d')}</b><br>{r['rf_risk']}</div>",
                unsafe_allow_html=True,
            )
        else:
            col.markdown(
                f"<div style='background:#6c757d;color:white;padding:10px;"
                f"border-radius:8px;text-align:center;margin-bottom:4px'>"
                f"<b>{r['date'].strftime('%m-%d')}</b><br>"
                f"RF:{r['rf_risk']} / LSTM:{r['lstm_risk']}</div>",
                unsafe_allow_html=True,
            )

    # --- Detailed per-day breakdown ---
    with st.expander("Detailed per-day prediction breakdown"):
        for r in results:
            agree = r["rf_risk"] == r["lstm_risk"]
            status = "✅ Agree" if agree else "⚠️ Disagreement"
            st.markdown(
                f"**{r['date'].strftime('%Y-%m-%d')}** — "
                f"Rain: {r['rainfall_mm']:.1f} mm — {status}"
            )
            c1, c2 = st.columns(2)
            with c1:
                st.markdown(
                    f"Random Forest: **{r['rf_risk']}** "
                    f"(score {r['rf_score']:.3f})"
                )
                for cls in ld.CLASSES:
                    st.progress(
                        min(r["rf_proba"].get(cls, 0.0), 1.0),
                        text=f"{cls}: {r['rf_proba'].get(cls, 0.0):.1%}",
                    )
            with c2:
                st.markdown(
                    f"LSTM: **{r['lstm_risk']}** "
                    f"(score {r['lstm_score']:.3f})"
                )
            st.divider()

    st.caption(
        "⚠️ Disclaimer: This forecast is based on Open-Meteo weather data "
        "and ML models trained on historical Chennai data. Not a substitute "
        "for official IMD / state government flood warnings."
    )


def tab_validation():
    st.subheader("🔬 Validation Against Real Chennai Flood Events")
    st.caption(
        "Run the trained Random Forest and LSTM models against historical data\n"
        "from known flood events. This is for validation only — models are NOT\n"
        "retrained. Manual reference events curated for model evaluation."
    )

    events = ld.get_known_flood_events()
    events["event_date"] = pd.to_datetime(events["event_date"])

    # --- Verify model availability ---
    rf_ok = model is not None
    lstm_ok = False
    try:
        lstm_model, lstm_data = get_lstm()
        lstm_ok = True
    except Exception:
        pass

    if not rf_ok:
        st.error("Random Forest model is not loaded. Cannot run validation.")
        return

    # --- For each event, look up features and run models ---
    results = []
    for _, evt in events.iterrows():
        evt_date = pd.Timestamp(evt["event_date"])
        label = evt["event_label"]

        # Find exact match in model_df
        match = model_df[model_df["date"] == evt_date]

        if match.empty:
            results.append({
                "Event": label,
                "Date": evt_date.strftime("%Y-%m-%d"),
                "Rainfall (mm)": "—",
                "RF Risk": "Insufficient data",
                "RF Score": "—",
                "LSTM Risk": "Insufficient data",
                "LSTM Score": "—",
            })
            continue

        row = match.iloc[0]
        rain_mm = row.get("rainfall_mm", 0.0)

        # Build feature dict from the dataset row
        row_dict = {f: float(row[f]) for f in ld.FEATURES if f in row and pd.notna(row[f])}

        # RF prediction
        rf_pred, rf_proba = predict_row(row_dict, "Random Forest")
        rf_score_val = rf_proba.get("HIGH", 0.0) + 0.5 * rf_proba.get("MODERATE", 0.0)

        # LSTM prediction
        lstm_risk_str = "N/A"
        lstm_score_val = "—"
        if lstm_ok:
            try:
                lstm_pred, lstm_proba = predict_row(row_dict, "LSTM", prediction_date=evt_date)
                lstm_risk_str = lstm_pred
                lstm_score_val = f"{lstm_proba.get('score', 0.0):.3f}"
            except Exception:
                lstm_risk_str = "Error"
                lstm_score_val = "—"

        results.append({
            "Event": label,
            "Date": evt_date.strftime("%Y-%m-%d"),
            "Rainfall (mm)": round(rain_mm, 1),
            "RF Risk": rf_pred,
            "RF Score": f"{rf_score_val:.3f}",
            "LSTM Risk": lstm_risk_str,
            "LSTM Score": lstm_score_val,
        })

    # --- Display results table ---
    st.markdown("### Prediction Results")
    st.dataframe(pd.DataFrame(results), width="stretch", hide_index=True)

    # --- Color-coded risk badges ---
    st.markdown("### Visual Risk Comparison")
    for r in results:
        st.markdown(f"**{r['Event']}** — {r['Date']}")
        c1, c2, c3, c4 = st.columns(4)
        c1.metric("Rainfall", f"{r['Rainfall (mm)']} mm")

        rf_risk = r["RF Risk"]
        if rf_risk in ("LOW", "MODERATE", "HIGH"):
            c2.metric("RF Risk", rf_risk)
            c2.markdown(
                f"<div style='background:{risk_colors(rf_risk)};color:white;"
                f"padding:6px;border-radius:6px;text-align:center'>"
                f"{rf_risk}</div>",
                unsafe_allow_html=True,
            )
        else:
            c2.metric("RF Risk", rf_risk)

        lstm_risk = r["LSTM Risk"]
        if lstm_risk in ("LOW", "MODERATE", "HIGH"):
            c3.metric("LSTM Risk", lstm_risk)
            c3.markdown(
                f"<div style='background:{risk_colors(lstm_risk)};color:white;"
                f"padding:6px;border-radius:6px;text-align:center'>"
                f"{lstm_risk}</div>",
                unsafe_allow_html=True,
            )
        else:
            c3.metric("LSTM Risk", lstm_risk)

        if r["RF Score"] != "—" and r["LSTM Score"] != "—":
            try:
                rf_s = float(r["RF Score"])
                lstm_s = float(r["LSTM Score"])
                agree = (rf_risk == lstm_risk) if (rf_risk in ld.CLASSES and lstm_risk in ld.CLASSES) else False
                verdict = "✅ Agree" if agree else "⚠️ Disagree"
                c4.metric("Verdict", verdict)
            except (ValueError, TypeError):
                c4.metric("Verdict", "—")
        else:
            c4.metric("Verdict", "—")

    st.divider()

    st.markdown("### Methodology")
    st.markdown(
        "- **Event dates** are manually curated historical references (NOT training data).\n"
        "- Features are extracted from `build_model_dataset()` for the exact event date.\n"
        "- Both trained models (RF and LSTM) are run on the same features.\n"
        "- No model retraining occurs. This is purely inference on existing models.\n"
        "- **Rainfall values** come from the Chennai Rainfall Dataset (station-level daily sums).\n"
        "- **Reservoir values** are the closest available monthly average for the event period."
    )

    st.caption(
        "⚠️ Disclaimer: Educational validation exercise for a college project. "
        "Models were not trained on these specific events. Results are for reference only."
    )


def main():
    header()
    t1, t2, t3, t4, t5, t6, t7, t8 = st.tabs(
        ["Dashboard", "Rainfall", "Reservoirs", "Prediction", "Groundwater",
         "Flood Map", "Forecast", "Validation"])
    with t1:
        tab_dashboard()
    with t2:
        tab_rainfall()
    with t3:
        tab_reservoir()
    with t4:
        tab_prediction()
    with t5:
        tab_groundwater()
    with t6:
        tab_map()
    with t7:
        tab_forecast()
    with t8:
        tab_validation()


if __name__ == "__main__":
    main()
