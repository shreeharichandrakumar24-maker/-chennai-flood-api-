"""FastAPI backend for the Chennai Flood mobile app.

Endpoints
---------
GET  /api/v1/status        health + last auto-refresh info
GET  /api/v1/weather       live Chennai weather (auto-fetched from Open-Meteo)
GET  /api/v1/prediction    latest automatic prediction
POST /api/v1/prediction/refresh   force a refresh now
GET  /api/v1/complaints    list complaints (?status=)
POST /api/v1/complaints    submit a complaint
GET  /api/v1/complaints/{id}
PATCH /api/v1/complaints/{id}/status   update status
DELETE /api/v1/complaints/{id}
"""
import json
import logging
from contextlib import asynccontextmanager
from typing import Optional

from apscheduler.schedulers.background import BackgroundScheduler
from apscheduler.triggers.interval import IntervalTrigger
from fastapi import FastAPI, HTTPException, Query
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, Field

import predictor
import store
import weather as weather_mod

logging.basicConfig(level=logging.INFO)
log = logging.getLogger("flood-api")

STATE = {
    "last_refresh": None,
    "weather": None,
    "prediction": None,
    "error": None,
}

_scheduler = None


def do_refresh() -> None:
    try:
        w = weather_mod.fetch_weather()
        pred = predictor.run_prediction(w["history"], w["today_iso"])
        pred["weather"] = w
        pred["generated_at"] = w["fetched_at"]
        STATE["last_refresh"] = w["fetched_at"]
        STATE["weather"] = w
        STATE["prediction"] = pred
        STATE["error"] = None
        store.save_prediction(pred)
        log.info("Prediction refreshed at %s", w["fetched_at"])
    except Exception as exc:
        STATE["error"] = str(exc)
        log.exception("refresh failed")


@asynccontextmanager
async def lifespan(app: FastAPI):
    store.init_db()
    do_refresh()
    global _scheduler
    # Reuse scheduler if already created (e.g. by --duckdns flag)
    if _scheduler is None:
        _scheduler = BackgroundScheduler()
        _scheduler.start()
    _scheduler.add_job(
        do_refresh,
        IntervalTrigger(minutes=30),
        id="weather_refresh",
        name="Auto weather + prediction refresh",
        replace_existing=True,
    )
    yield
    if _scheduler:
        _scheduler.shutdown(wait=False)


app = FastAPI(title="Chennai Flood Prediction API", version="1.0.0",
              lifespan=lifespan)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


# ---------------- Schemas ----------------

class ComplaintIn(BaseModel):
    name: str = Field(..., min_length=1, max_length=120)
    phone: Optional[str] = Field(None, max_length=20)
    location: str = Field(..., min_length=1, max_length=200)
    lat: Optional[float] = None
    lon: Optional[float] = None
    category: str = "Other"
    description: str = Field(..., min_length=1, max_length=2000)


class StatusIn(BaseModel):
    status: str = Field(..., description="submitted | in_progress | resolved")


# ---------------- Status / Weather / Prediction ----------------

@app.get("/api/v1/status")
def status():
    return {
        "service": "chennai-flood-api",
        "status": "ok" if STATE["prediction"] else "degraded",
        "last_refresh": STATE["last_refresh"],
        "lstm_available": predictor.lstm_available(),
        "lstm_error": predictor.lstm_error(),
        "error": STATE["error"],
    }


@app.get("/api/v1/weather")
def get_weather():
    if STATE["weather"] is None:
        do_refresh()
    if STATE["weather"] is None:
        raise HTTPException(503, "Weather unavailable: " + str(STATE["error"]))
    return STATE["weather"]


@app.get("/api/v1/prediction")
def get_prediction():
    if STATE["prediction"] is None:
        do_refresh()
    if STATE["prediction"] is None:
        raise HTTPException(503, "Prediction unavailable: " + str(STATE["error"]))
    return STATE["prediction"]


@app.post("/api/v1/prediction/refresh")
def refresh_prediction():
    do_refresh()
    if STATE["prediction"] is None:
        raise HTTPException(503, "Prediction unavailable: " + str(STATE["error"]))
    return {"refreshed_at": STATE["last_refresh"], "prediction": STATE["prediction"]}


@app.get("/api/v1/prediction/history")
def prediction_history(limit: int = Query(10, ge=1, le=100)):
    conn = store._conn()
    rows = conn.execute(
        "SELECT id, generated_at, rf_risk, rf_score, lstm_risk, lstm_score "
        "FROM predictions ORDER BY generated_at DESC LIMIT ?", (limit,)).fetchall()
    conn.close()
    return [dict(r) for r in rows]


# ---------------- Complaints ----------------

@app.get("/api/v1/complaints")
def list_complaints(status: Optional[str] = None):
    if status and status not in store.STATUSES:
        raise HTTPException(422, f"Invalid status, use {store.STATUSES}")
    return {"count": len(store.list_complaints(status)),
            "items": store.list_complaints(status)}


@app.post("/api/v1/complaints", status_code=201)
def create_complaint(c: ComplaintIn):
    if c.category not in store.CATEGORIES:
        raise HTTPException(422, f"Invalid category, use {store.CATEGORIES}")
    return store.create_complaint(c.model_dump())


@app.get("/api/v1/complaints/{cid}")
def get_complaint(cid: int):
    row = store.get_complaint(cid)
    if not row:
        raise HTTPException(404, "Complaint not found")
    return row


@app.patch("/api/v1/complaints/{cid}/status")
def update_status(cid: int, body: StatusIn):
    try:
        row = store.update_complaint_status(cid, body.status)
    except ValueError as exc:
        raise HTTPException(422, str(exc))
    if not row:
        raise HTTPException(404, "Complaint not found")
    return row


@app.delete("/api/v1/complaints/{cid}", status_code=204)
def delete_complaint(cid: int):
    if not store.delete_complaint(cid):
        raise HTTPException(404, "Complaint not found")


def get_local_ip() -> str:
    """Auto-detect the machine's LAN IP address."""
    import socket
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.connect(("8.8.8.8", 80))
        ip = s.getsockname()[0]
        s.close()
        return ip
    except Exception:
        return "127.0.0.1"


def start_tunnel(port: int) -> str | None:
    """Start a Cloudflare Tunnel and return the public URL."""
    import subprocess
    import threading
    import time
    import re

    # Find cloudflared binary
    _dir = os.path.dirname(os.path.abspath(__file__))
    cf_path = os.path.join(_dir, "cloudflared.exe")
    if not os.path.exists(cf_path):
        cf_path = "cloudflared"  # try PATH

    try:
        proc = subprocess.Popen(
            [cf_path, "tunnel", "--url", f"http://localhost:{port}", "--no-autoupdate"],
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
        )

        # Read output until we find the public URL
        public_url = None
        deadline = time.time() + 15
        while time.time() < deadline:
            line = proc.stdout.readline()
            if not line:
                time.sleep(0.1)
                continue
            log.info("cloudflared: %s", line.strip())
            # Look for the URL in output
            match = re.search(r'(https://[a-z0-9\-]+\.trycloudflare\.com)', line)
            if match:
                public_url = match.group(1)
                break

        return public_url
    except Exception as exc:
        log.warning("cloudflared tunnel failed: %s", exc)
        return None


def update_duckdns(domain: str, token: str) -> str | None:
    """Update DuckDNS with the current public IP. Returns the public IP."""
    import urllib.request
    import urllib.error

    try:
        # DuckDNS update URL: ip= (empty) means use the caller's public IP
        url = f"https://www.duckdns.org/update?domains={domain}&token={token}&ip="
        req = urllib.request.urlopen(url, timeout=10)
        response = req.read().decode().strip()
        log.info("DuckDNS update response: %s", response)

        # Also get the actual public IP for display
        ip_req = urllib.request.urlopen("https://api.ipify.org", timeout=5)
        public_ip = ip_req.read().decode().strip()
        return public_ip
    except Exception as exc:
        log.warning("DuckDNS update failed: %s", exc)
        return None


def get_public_ip() -> str | None:
    """Get the machine's public IP address."""
    import urllib.request
    try:
        req = urllib.request.urlopen("https://api.ipify.org", timeout=5)
        return req.read().decode().strip()
    except Exception:
        return None


if __name__ == "__main__":
    import argparse
    import os
    import socket
    import subprocess
    import uvicorn

    parser = argparse.ArgumentParser(description="Chennai Flood API Server")
    parser.add_argument("--tunnel", action="store_true",
                        help="Expose server via Cloudflare quick tunnel")
    parser.add_argument("--duckdns", action="store_true",
                        help="Auto-update DuckDNS with your public IP")
    parser.add_argument("--duckdns-domain", default="chennai-flood",
                        help="DuckDNS subdomain (default: chennai-flood)")
    parser.add_argument("--duckdns-token",
                        default=os.environ.get("DUCKDNS_TOKEN", "0649a4a8-bd05-44c5-bb74-63cdc99a3ae7"),
                        help="DuckDNS token")
    args = parser.parse_args()

    port = int(os.environ.get("PORT", 8000))
    local_ip = get_local_ip()

    # Auto-kill any old process occupying the port
    sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    result = sock.connect_ex(('127.0.0.1', port))
    if result == 0:
        log.info("Port %d is in use — killing old process...", port)
        try:
            if os.name == 'nt':
                output = subprocess.check_output(
                    ['netstat', '-ano'], text=True, stderr=subprocess.DEVNULL)
                for line in output.splitlines():
                    if f':{port}' in line and 'LISTENING' in line:
                        pid = line.strip().split()[-1]
                        subprocess.run(
                            ['taskkill', '/PID', pid, '/F'],
                            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                        log.info("Killed process %s on port %d", pid, port)
                        break
            else:
                output = subprocess.check_output(
                    ['lsof', '-ti', f':{port}'], text=True, stderr=subprocess.DEVNULL)
                for pid in output.strip().split('\n'):
                    if pid:
                        subprocess.run(['kill', '-9', pid],
                                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                        log.info("Killed process %s on port %d", pid, port)
        except Exception as e:
            log.warning("Could not auto-kill old process: %s", e)
        import time
        time.sleep(1)
    sock.close()

    # ── DuckDNS: update public IP ──
    duckdns_url = None
    public_ip = None
    # Initialize scheduler early so we can add DuckDNS job before uvicorn starts
    if _scheduler is None:
        _scheduler = BackgroundScheduler()
        _scheduler.start()
    if args.duckdns:
        public_ip = update_duckdns(args.duckdns_domain, args.duckdns_token)
        if public_ip:
            duckdns_url = f"http://{args.duckdns_domain}.duckdns.org:{port}"
            log.info("DuckDNS updated: %s → %s", duckdns_url, public_ip)

            # Schedule periodic DuckDNS IP updates (every 5 minutes)
            # This handles dynamic IPs that change periodically
            def _periodic_duckdns():
                update_duckdns(args.duckdns_domain, args.duckdns_token)

            _scheduler.add_job(
                _periodic_duckdns,
                IntervalTrigger(minutes=5),
                id="duckdns_update",
                name="DuckDNS IP auto-update",
                replace_existing=True,
            )
        else:
            log.warning("Could not determine public IP — DuckDNS not updated")

    # Start Cloudflare quick tunnel if requested
    cloudflare_url = None
    if args.tunnel:
        cloudflare_url = start_tunnel(port)

    # ── Print startup banner ──
    print("\n" + "=" * 60)
    print("  CHENNAI FLOOD ALERT API SERVER")
    print("=" * 60)
    print(f"  Local IP  : {local_ip}")
    print(f"  Port      : {port}")

    if duckdns_url:
        print(f"  ✅ Fixed URL: {duckdns_url}")
        print(f"     (DuckDNS → {public_ip})")
        print(f"     Anyone, any network can connect!")
        print(f"")
        print(f"  📋 PORT FORWARDING REQUIRED:")
        print(f"     1. Open your router admin page (usually 192.168.1.1)")
        print(f"     2. Find 'Port Forwarding' or 'Virtual Server'")
        print(f"     3. Add rule:")
        print(f"        External Port: {port}")
        print(f"        Internal IP  : {local_ip}")
        print(f"        Internal Port: {port}")
        print(f"        Protocol     : TCP")
    elif cloudflare_url:
        print(f"  Public URL: {cloudflare_url}")
        print(f"  ⚠️  URL changes on each restart!")
    else:
        print(f"  Mobile URL: http://{local_ip}:{port}")
        print(f"  ⚠️  Same WiFi only.")
        print(f"")
        print(f"  💡 For any-network access, run with --duckdns")

    print("=" * 60)
    print("  Copy this URL into your mobile app Settings screen!")
    print("=" * 60 + "\n")

    uvicorn.run(app, host="0.0.0.0", port=port)
