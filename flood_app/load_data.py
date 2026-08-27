import os
import re
import xml.etree.ElementTree as ET
import numpy as np
import pandas as pd

BASE = os.path.dirname(os.path.abspath(__file__))
DATA = os.path.dirname(BASE)

KML_DIR = os.path.join(DATA, "Chennai Flooding Data")

RETURN_PERIOD_FILES = {
    "ef3286de-1c9b-41a2-a5f2-a075863e26f6.kml": "5-year",
    "1bfef958-d4cc-4e50-a926-445e65bac7a8.kml": "10-year",
    "a6b4f2b1-f2b4-4dbc-93da-37be6dc7a345.kml": "25-year",
    "a6b20b7c-d771-4572-a2c7-9d8c125e6e5d.kml": "50-year",
    "994a99a1-6104-40c7-ac10-2b7a7ab74437.kml": "100-year",
    "61f1f06f-1fa1-4ef0-94c7-224d892efbef.kml": "200-year",
}

KML_LAYERS = {
    "flood_2015_points": "93d2905a-a580-482d-96b0-4d9ccf5273ef.kml",
    "inundation_inches": "814ca028-4c84-4bd0-aa67-6dbaeb9b6ba5.kml",
    "inundation_zones": "7f29da20-6621-4b49-b0cf-28b9d1de232b.kml",
}


def _kml_root(path):
    tree = ET.parse(path)
    return tree.getroot()


def parse_kml_points(path):
    root = _kml_root(path)
    ns = {"k": "http://www.opengis.net/kml/2.2"}
    rows = []
    for pm in root.iter("{http://www.opengis.net/kml/2.2}Placemark"):
        name_el = pm.find("k:name", ns)
        name = name_el.text if name_el is not None else None
        data = {"name": name}
        for sd in pm.iter("{http://www.opengis.net/kml/2.2}SimpleData"):
            data[sd.attrib["name"]] = sd.text
        coord_el = pm.find(".//k:Point/k:coordinates", ns)
        if coord_el is not None and coord_el.text:
            parts = coord_el.text.strip().split(",")
            data["lon"], data["lat"] = float(parts[0]), float(parts[1])
        rows.append(data)
    return pd.DataFrame(rows)


def _poly_centroid(points):
    pts = [tuple(map(float, p.split(",")[:2])) for p in points.split()]
    xs, ys = zip(*pts)
    return np.mean(xs), np.mean(ys)


def parse_kml_polygons(path):
    root = _kml_root(path)
    rows = []
    for pm in root.iter("{http://www.opengis.net/kml/2.2}Placemark"):
        data = {}
        for sd in pm.iter("{http://www.opengis.net/kml/2.2}SimpleData"):
            data[sd.attrib["name"]] = sd.text
        coord_el = pm.find(".//k:Polygon/k:outerBoundaryIs/k:LinearRing/k:coordinates", {
            "k": "http://www.opengis.net/kml/2.2"})
        if coord_el is not None and coord_el.text:
            data["lon"], data["lat"] = _poly_centroid(coord_el.text.strip())
        rows.append(data)
    return pd.DataFrame(rows)


def load_2015_flood_points():
    df = parse_kml_points(os.path.join(KML_DIR, KML_LAYERS["flood_2015_points"]))
    for c in ("LAT", "LONG_", "ZONE", "DIVISION"):
        if c in df:
            df[c] = pd.to_numeric(df[c], errors="coerce")
    return df


def load_inundation_points():
    df = parse_kml_points(os.path.join(KML_DIR, KML_LAYERS["inundation_inches"]))
    for c in ("F_LATITUDE", "F_LONGITUDE", "DEPTH"):
        if c in df:
            df[c] = pd.to_numeric(df[c], errors="coerce")
    return df


def load_inundation_zones():
    df = parse_kml_polygons(os.path.join(KML_DIR, KML_LAYERS["inundation_zones"]))
    df["lon"] = pd.to_numeric(df["lon"], errors="coerce")
    df["lat"] = pd.to_numeric(df["lat"], errors="coerce")
    return df


def load_return_periods():
    frames = []
    for fname, label in RETURN_PERIOD_FILES.items():
        path = os.path.join(KML_DIR, fname)
        if not os.path.exists(path):
            continue
        df = parse_kml_polygons(path)
        df["return_period"] = label
        df["lon"] = pd.to_numeric(df["lon"], errors="coerce")
        df["lat"] = pd.to_numeric(df["lat"], errors="coerce")
        df["CATEGORY"] = df["CATEGORY"].str.upper()
        frames.append(df)
    return pd.concat(frames, ignore_index=True)

RESERVOIR_CAPACITY = {
    "Poondi": 3231,
    "Chembarambakkam": 3645,
    "Red Hills": 3300,
    "Cholavaram": 881,
    "Thervoy Kandigai": 500,
}

LAKE_LEVEL_FILES = {
    "e7000bbf-9db8-42a2-9564-c57c33dfbd5b.csv": "Poondi",
    "9c99a6e3-8abc-4f61-925a-6710eb062c42.csv": "Chembarambakkam",
    "35219738-923b-4685-a0bf-0147f7ceaac7.csv": "Red Hills",
    "321ab75f-29bf-4bf7-8784-3e2c32bfdf1f.csv": "Cholavaram",
    "109dc3c7-7d5d-4f1d-bd64-2227a1bd1f81.csv": "Thervoy Kandigai",
}


def load_rainfall():
    df = pd.read_csv(os.path.join(DATA, "Rainfall_Dataset.csv"))
    df["Date"] = pd.to_datetime(df["Date"], dayfirst=True)
    daily = df.groupby("Date")["Rainfall"].sum().reset_index()
    daily.columns = ["date", "rainfall_mm"]
    daily = daily.sort_values("date").reset_index(drop=True)
    daily = daily[daily["rainfall_mm"] > 0]
    return daily, df


def load_lake_levels():
    frames = []
    for fname, name in LAKE_LEVEL_FILES.items():
        raw = pd.read_csv(os.path.join(DATA, "Lake level", fname))
        months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun",
                  "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
        keep = [c for c in raw.columns if c in months or c == "Year"]
        raw = raw[keep]
        df = raw.melt(id_vars="Year", var_name="Month", value_name="mcft")
        df["month_num"] = df["Month"].map({m: i + 1 for i, m in enumerate(months)})
        df["day"] = 1
        df["date"] = pd.to_datetime(df[["Year", "month_num", "day"]].rename(
            columns={"Year": "year", "month_num": "month"}))
        df["reservoir"] = name
        df["capacity_mcft"] = RESERVOIR_CAPACITY[name]
        df["mcft"] = pd.to_numeric(df["mcft"], errors="coerce")
        df["storage_pct"] = df["mcft"] / df["capacity_mcft"] * 100
        frames.append(df[["date", "reservoir", "mcft", "storage_pct", "capacity_mcft"]])
    return pd.concat(frames, ignore_index=True).sort_values("date")


def _load_inflow(path):
    raw = pd.read_csv(path, header=None, engine="python")
    raw.columns = [str(c).replace("\n", " ").strip() for c in raw.iloc[0]]
    raw = raw.iloc[1:].reset_index(drop=True)
    raw = raw.rename(columns={raw.columns[0]: "date"})
    raw["date"] = pd.to_datetime(raw["date"], format="%d-%b-%y", errors="coerce")
    for c in raw.columns[1:]:
        raw[c] = pd.to_numeric(raw[c], errors="coerce")
    raw = raw.dropna(subset=["date"])
    return raw


def load_inflow_outflow():
    files = [f for f in os.listdir(os.path.join(DATA, "Lake inflow and outflow"))
             if f.endswith(".csv")]
    frames = []
    for f in files:
        df = _load_inflow(os.path.join(DATA, "Lake inflow and outflow", f))
        df["src_file"] = f
        frames.append(df)
    return pd.concat(frames, ignore_index=True).sort_values("date")


def load_groundwater():
    files = [f for f in os.listdir(os.path.join(DATA, "Groundwater Levels"))
             if f.endswith(".csv")]
    frames = []
    months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun",
              "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
    for f in files:
        df = pd.read_csv(os.path.join(DATA, "Groundwater Levels", f))
        df = df.rename(columns={df.columns[0]: "S.No"})
        df = df[df["S.No"].apply(lambda x: str(x).replace(".", "").isdigit())]
        present = [c for c in months if c in df.columns]
        sub = df[["Location"] + present].copy()
        sub = sub.melt(id_vars="Location", var_name="Month", value_name="depth_m")
        sub["Month"] = sub["Month"].str.strip()
        sub["depth_m"] = pd.to_numeric(sub["depth_m"].replace("#REF!", np.nan),
                                       errors="coerce")
        sub["src_file"] = f
        sub["month_num"] = sub["Month"].map({m: i + 1 for i, m in enumerate(months)})
        frames.append(sub)
    return pd.concat(frames, ignore_index=True)


def build_model_dataset():
    daily, _ = load_rainfall()
    lakes = load_lake_levels()

    pivot = lakes.pivot_table(index="date", columns="reservoir",
                              values="mcft", aggfunc="mean").reset_index()
    pct = lakes.pivot_table(index="date", columns="reservoir",
                            values="storage_pct", aggfunc="mean").reset_index()
    pct = pct.rename(columns={c: c + "_pct" for c in pct.columns if c != "date"})

    start = daily["date"].min()
    end = daily["date"].max()
    calendar = pd.DataFrame({"date": pd.date_range(start, end, freq="D")})

    pivot = calendar.merge(pivot, on="date", how="left").sort_values("date").reset_index(drop=True)
    pct = calendar.merge(pct, on="date", how="left").sort_values("date").reset_index(drop=True)

    for col in pivot.columns[1:]:
        pivot[col] = pivot[col].ffill()
    for col in pct.columns[1:]:
        pct[col] = pct[col].ffill()

    df = calendar.merge(daily, on="date", how="left")
    df = df.merge(pivot, on="date", how="left").merge(pct, on="date", how="left")
    df = df.sort_values("date").reset_index(drop=True)

    df["reservoir_total_mcft"] = df[[c for c in pivot.columns if c != "date"]].sum(axis=1, min_count=1)
    pct_cols = [c for c in pct.columns if c != "date"]
    df["reservoir_avg_pct"] = df[pct_cols].mean(axis=1)
    df["reservoir_max_pct"] = df[pct_cols].max(axis=1)
    df["rainfall_mm"] = df["rainfall_mm"].fillna(0)

    for w in (2, 3, 5, 7, 14):
        df[f"rain_{w}d"] = df["rainfall_mm"].rolling(w, min_periods=1).sum()

    df = df.dropna(subset=["reservoir_avg_pct"]).reset_index(drop=True)

    df["month"] = df["date"].dt.month
    df["dayofyear"] = df["date"].dt.dayofyear
    df["year"] = df["date"].dt.year

    return df


def make_labels(df):
    rain = df["rainfall_mm"]
    r3 = df["rain_3d"]
    fullness = df["reservoir_max_pct"].fillna(0)

    score = (np.minimum(rain / 120, 1) * 0.65 +
             np.minimum(r3 / 250, 1) * 0.20 +
             np.minimum(fullness / 100, 1) * 0.15)

    labels = pd.Series("LOW", index=df.index)
    labels[score >= 0.35] = "MODERATE"
    labels[score >= 0.60] = "HIGH"
    return score, labels


FEATURES = [
    "rainfall_mm", "rain_2d", "rain_3d", "rain_5d", "rain_7d", "rain_14d",
    "reservoir_avg_pct", "reservoir_max_pct", "reservoir_total_mcft",
    "month", "dayofyear",
]

CLASSES = ["LOW", "MODERATE", "HIGH"]


def make_lstm_sequences(model_df, window=14):
    df = model_df.dropna(subset=FEATURES).reset_index(drop=True)
    scores, labels = make_labels(df)

    X, y, score_targets, dates = [], [], [], []
    for i in range(len(df) - window):
        X.append(df.loc[i:i + window - 1, FEATURES].values)
        y.append(CLASSES.index(labels.iloc[i + window]))
        score_targets.append(float(scores.iloc[i + window]))
        dates.append(df["date"].iloc[i + window])
    return (np.array(X, dtype=np.float32),
            np.array(y, dtype=np.int64),
            np.array(score_targets, dtype=np.float32),
            pd.Series(dates))


def get_known_flood_events():
    """Return a manually curated set of significant Chennai flood events.

    This is a validation reference — NOT training data.
    Each event includes a primary date for matching against build_model_dataset().
    """
    return pd.DataFrame([
        {
            "event_date": "2015-12-01",
            "event_label": "2015 Chennai Floods (Dec 1–2, extreme rainfall)",
        },
        {
            "event_date": "2015-12-02",
            "event_label": "2015 Chennai Floods — peak rainfall day",
        },
        {
            "event_date": "2021-11-01",
            "event_label": "Nov 2021 NE Monsoon Flooding",
        },
        {
            "event_date": "2023-12-04",
            "event_label": "Cyclone Michaung — peak flooding day",
        },
        {
            "event_date": "2023-12-05",
            "event_label": "Cyclone Michaung — continued flooding",
        },
    ])


def get_shelters():
    """Return demo/prototype shelter locations for Chennai.

    IMPORTANT: These are **demo/prototype locations** for UI development.
    They are NOT verified government-designated relief centers.
    Real shelter data should be sourced from the Greater Chennai Corporation
    or Tamil Nadu SDMA before any production deployment.
    """
    return pd.DataFrame([
        {"name": "Chennai Corporation Relief Camp — Teynampet Zone",
         "latitude": 13.0350, "longitude": 80.2450, "capacity": 500},
        {"name": "Anna Nagar Community Hall (Demo)",
         "latitude": 13.0850, "longitude": 80.2100, "capacity": 350},
        {"name": "Adyar Relief Center (Demo)",
         "latitude": 13.0010, "longitude": 80.2570, "capacity": 400},
        {"name": "Tondiarpet Shelter (Demo)",
         "latitude": 13.1100, "longitude": 80.2700, "capacity": 300},
        {"name": "Velachery Relief Camp (Demo)",
         "latitude": 12.9815, "longitude": 80.2180, "capacity": 450},
        {"name": "Sholinganallur Community Center (Demo)",
         "latitude": 12.9010, "longitude": 80.2270, "capacity": 300},
        {"name": "Ambattur Relief Center (Demo)",
         "latitude": 13.1140, "longitude": 80.1550, "capacity": 400},
        {"name": "Mylapore Shelter (Demo)",
         "latitude": 13.0340, "longitude": 80.2700, "capacity": 250},
        {"name": "Perambur Relief Camp (Demo)",
         "latitude": 13.1070, "longitude": 80.2350, "capacity": 350},
        {"name": "Chennai Port Trust Shelter (Demo)",
         "latitude": 13.0820, "longitude": 80.3000, "capacity": 200},
    ])

