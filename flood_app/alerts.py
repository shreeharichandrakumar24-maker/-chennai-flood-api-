"""Flood alert formatting and optional email notification.

This module provides:
  - check_and_format_alert(): generate a clear flood warning message
  - send_email_alert(): optional SMTP-based email alert (disabled by default)

Email functionality is OFF by default and requires no credentials to start.
See the send_email_alert docstring for setup instructions.
"""

import os
import smtplib
from email.mime.text import MIMEText


# ──────────────────────────────────────────────────────────────────────
# Alert formatting
# ──────────────────────────────────────────────────────────────────────

def check_and_format_alert(risk, score=None, zone=None):
    """Generate a flood warning message when risk is HIGH.

    Parameters
    ----------
    risk : str
        One of "LOW", "MODERATE", "HIGH".
    score : float or None
        Flood-risk score if available (0–1 for LSTM, composite for RF).
    zone : str or None
        Affected zone / area name, if known.

    Returns
    -------
    str or None
        A formatted multi-line alert string when risk == "HIGH",
        otherwise None.
    """
    if risk != "HIGH":
        return None

    lines = ["🚨 **HIGH FLOOD RISK ALERT** 🚨"]

    if score is not None:
        lines.append(f"Flood risk score: **{score:.3f}** (threshold ≥ 0.60)")
    else:
        lines.append("Flood risk level: **HIGH**")

    if zone:
        lines.append(f"Affected zone: **{zone}**")

    lines.append("")
    lines.append("**Recommended actions:**")
    lines.append("- Monitor official IMD and state government flood warnings.")
    lines.append("- Stay away from waterlogged or low-lying areas.")
    lines.append("- Keep emergency supplies and contacts ready.")
    lines.append("- Follow local authority / NDRF / SDRF advisories.")
    lines.append("")
    lines.append(
        "⚠️ This is an ML-based prediction for educational purposes. "
        "Always follow official emergency guidance."
    )

    return "\n".join(lines)


def check_forecast_alerts(results):
    """Scan a list of forecast-day result dicts and collect HIGH alerts.

    Parameters
    ----------
    results : list[dict]
        Each dict should have keys: date, rf_risk, lstm_risk,
        rf_score, lstm_score.

    Returns
    -------
    list[dict]
        Each dict has: date, model ("RF" / "LSTM"), risk, score, message.
    """
    alerts = []
    for r in results:
        for model_key, score_key in [("rf_risk", "rf_score"),
                                     ("lstm_risk", "lstm_score")]:
            risk = r.get(model_key)
            if risk == "HIGH":
                msg = check_and_format_alert(
                    risk="HIGH",
                    score=r.get(score_key),
                    zone=r.get("date").strftime("%Y-%m-%d") if r.get("date") else None,
                )
                alerts.append({
                    "date": r.get("date"),
                    "model": "RF" if model_key == "rf_risk" else "LSTM",
                    "risk": risk,
                    "score": r.get(score_key),
                    "message": msg,
                })
    return alerts


# ──────────────────────────────────────────────────────────────────────
# Optional email alerting (DISABLED by default)
# ──────────────────────────────────────────────────────────────────────
#
# To enable email alerts for a deployment, set the environment variables
# below and call send_email_alert() explicitly.
#
# Gmail example (requires an App Password, NOT your normal password):
#   1. Enable 2-Step Verification on your Google Account.
#   2. Go to https://myaccount.google.com/apppasswords
#   3. Create an App Password for "Mail" on this device.
#   4. Set these environment variables:
#        export ALERT_SMTP_HOST=smtp.gmail.com
#        export ALERT_SMTP_PORT=587
#        export ALERT_EMAIL_FROM=your.email@gmail.com
#        export ALERT_EMAIL_TO=recipient@example.com
#        export ALERT_EMAIL_PASSWORD=<your-16-char-app-password>
#
# IMPORTANT:
#   - Never hardcode passwords or API keys in source code.
#   - Never commit credentials to version control.
#   - Use environment variables or a secrets manager in production.
#   - Email sending is OFF by default — no credentials needed to start.
#

def _smtp_config():
    """Load SMTP config from environment variables. Returns dict or None."""
    host = os.environ.get("ALERT_SMTP_HOST")
    port = int(os.environ.get("ALERT_SMTP_PORT", "587"))
    user = os.environ.get("ALERT_EMAIL_FROM")
    password = os.environ.get("ALERT_EMAIL_PASSWORD")
    recipient = os.environ.get("ALERT_EMAIL_TO")

    if not all([host, user, password, recipient]):
        return None

    return {
        "host": host,
        "port": port,
        "user": user,
        "password": password,
        "recipient": recipient,
    }


def send_email_alert(subject, body):
    """Send a flood-alert email via SMTP.

    This function is a **no-op** unless the required environment variables
    are set (ALERT_SMTP_HOST, ALERT_EMAIL_FROM, ALERT_EMAIL_PASSWORD,
    ALERT_EMAIL_TO).  This ensures the application starts without any
    credentials configured.

    Parameters
    ----------
    subject : str
        Email subject line.
    body : str
        Email body (plain text / markdown).

    Returns
    -------
    bool
        True if the email was sent successfully, False otherwise.
    """
    cfg = _smtp_config()
    if cfg is None:
        # Email not configured — silently skip (this is normal during dev)
        return False

    msg = MIMEText(body, plain=True)
    msg["Subject"] = subject
    msg["From"] = cfg["user"]
    msg["To"] = cfg["recipient"]

    try:
        with smtplib.SMTP(cfg["host"], cfg["port"], timeout=15) as server:
            server.starttls()
            server.login(cfg["user"], cfg["password"])
            server.send_message(msg)
        return True
    except Exception:
        # Never crash the app because of a failed email
        return False
