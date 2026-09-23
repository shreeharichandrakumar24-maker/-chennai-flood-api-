"""SQLite persistence for complaints and automatic predictions."""
import os
import sqlite3
from datetime import datetime, timezone

BASE = os.path.dirname(os.path.abspath(__file__))
DB_PATH = os.path.join(BASE, "flood.db")

STATUSES = ("submitted", "in_progress", "resolved")
CATEGORIES = ("Waterlogging", "Drainage blocked", "River/Storm surge",
              "Road closure", "House/Property damage", "Power outage", "Other")


def _conn():
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    return conn


def now_iso():
    return datetime.now(timezone.utc).isoformat()


def init_db():
    conn = _conn()
    conn.executescript(
        """
        CREATE TABLE IF NOT EXISTS complaints (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            phone TEXT,
            location TEXT NOT NULL,
            lat REAL,
            lon REAL,
            category TEXT NOT NULL DEFAULT 'Other',
            description TEXT NOT NULL,
            status TEXT NOT NULL DEFAULT 'submitted',
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL
        );
        CREATE TABLE IF NOT EXISTS predictions (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            generated_at TEXT NOT NULL,
            weather_json TEXT,
            rf_risk TEXT,
            rf_score REAL,
            lstm_risk TEXT,
            lstm_score REAL,
            features_json TEXT
        );
        """
    )
    conn.commit()
    conn.close()
    seed_sample_complaints()


def seed_sample_complaints():
    """Seed 2-3 realistic sample reports so the Report flow demonstrates
    end-to-end even before real submissions arrive.

    SEED-ONLY helper: does not modify any existing endpoint signatures.
    Runs on startup via init_db(); inserts only when the table is empty.
    """
    conn = _conn()
    try:
        count = conn.execute("SELECT COUNT(*) AS c FROM complaints").fetchone()["c"]
    except Exception:
        conn.close()
        return
    if count and count > 0:
        conn.close()
        return
    samples = [
        {
            "name": "Priya R.",
            "phone": "98400-12345",
            "location": "T. Nagar, G N Chetty Rd (near bus depot)",
            "lat": 13.0410,
            "lon": 80.2340,
            "category": "Waterlogging",
            "description": "Knee-deep waterlogging after overnight rain; two-wheelers stalled.",
            "status": "submitted",
        },
        {
            "name": "Karthik S.",
            "phone": None,
            "location": "Velachery 100 Feet Rd, opp. bus stand",
            "lat": 12.9815,
            "lon": 80.2180,
            "category": "Road closure",
            "description": "Blocked road: fallen branch + waterlogging, one lane closed.",
            "status": "in_progress",
        },
        {
            "name": "Deepa M.",
            "phone": "98410-67890",
            "location": "Adyar, LB Rd near signal",
            "lat": 13.0062,
            "lon": 80.2574,
            "category": "Drainage blocked",
            "description": "Storm drain blocked with debris; water entering footpath shops.",
            "status": "submitted",
        },
    ]
    ts = now_iso()
    for s in samples:
        conn.execute(
            """INSERT INTO complaints
               (name, phone, location, lat, lon, category, description, status,
                created_at, updated_at)
               VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)""",
            (s["name"], s["phone"], s["location"], s["lat"], s["lon"],
             s["category"], s["description"], s["status"], ts, ts),
        )
    conn.commit()
    conn.close()


# ---------------- Complaints ----------------

def create_complaint(data: dict) -> dict:
    status = data.get("status", "submitted")
    if status not in STATUSES:
        status = "submitted"
    conn = _conn()
    ts = now_iso()
    cur = conn.execute(
        """INSERT INTO complaints
           (name, phone, location, lat, lon, category, description, status,
            created_at, updated_at)
           VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)""",
        (data["name"], data.get("phone"), data["location"],
         data.get("lat"), data.get("lon"), data.get("category", "Other"),
         data["description"], status, ts, ts),
    )
    conn.commit()
    cid = cur.lastrowid
    row = conn.execute("SELECT * FROM complaints WHERE id = ?", (cid,)).fetchone()
    conn.close()
    return dict(row)


def list_complaints(status: str = None) -> list:
    conn = _conn()
    if status:
        rows = conn.execute(
            "SELECT * FROM complaints WHERE status = ? ORDER BY created_at DESC",
            (status,)).fetchall()
    else:
        rows = conn.execute(
            "SELECT * FROM complaints ORDER BY created_at DESC").fetchall()
    conn.close()
    return [dict(r) for r in rows]


def get_complaint(cid: int):
    conn = _conn()
    row = conn.execute("SELECT * FROM complaints WHERE id = ?", (cid,)).fetchone()
    conn.close()
    return dict(row) if row else None


def update_complaint_status(cid: int, status: str) -> dict:
    if status not in STATUSES:
        raise ValueError(f"Invalid status. Must be one of {STATUSES}")
    conn = _conn()
    conn.execute(
        "UPDATE complaints SET status = ?, updated_at = ? WHERE id = ?",
        (status, now_iso(), cid),
    )
    conn.commit()
    row = conn.execute("SELECT * FROM complaints WHERE id = ?", (cid,)).fetchone()
    conn.close()
    return dict(row) if row else None


def delete_complaint(cid: int) -> bool:
    conn = _conn()
    cur = conn.execute("DELETE FROM complaints WHERE id = ?", (cid,))
    conn.commit()
    conn.close()
    return cur.rowcount > 0


# ---------------- Predictions ----------------

def save_prediction(pred: dict) -> None:
    rf = pred.get("random_forest") or {}
    lstm = pred.get("lstm") or {}
    import json

    conn = _conn()
    conn.execute(
        """INSERT INTO predictions
           (generated_at, weather_json, rf_risk, rf_score,
            lstm_risk, lstm_score, features_json)
           VALUES (?, ?, ?, ?, ?, ?, ?)""",
        (pred["generated_at"], json.dumps(pred.get("weather", {})),
         rf.get("risk"), rf.get("score"),
         lstm.get("risk") if lstm else None,
         lstm.get("score") if lstm else None,
         json.dumps(pred.get("features", {}))),
    )
    conn.commit()
    conn.close()


def last_prediction() -> dict:
    conn = _conn()
    row = conn.execute(
        "SELECT * FROM predictions ORDER BY generated_at DESC LIMIT 1").fetchone()
    conn.close()
    if row is None:
        return None
    import json

    return {
        "generated_at": row["generated_at"],
        "rf_risk": row["rf_risk"],
        "rf_score": row["rf_score"],
        "lstm_risk": row["lstm_risk"],
        "lstm_score": row["lstm_score"],
        "weather": json.loads(row["weather_json"] or "{}"),
        "features": json.loads(row["features_json"] or "{}"),
    }
