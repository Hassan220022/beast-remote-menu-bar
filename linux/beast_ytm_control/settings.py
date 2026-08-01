from __future__ import annotations

import json
import os
import secrets
from pathlib import Path
from typing import Any

DATA_DIR = Path(os.environ.get("BEAST_YTM_CONTROL_DATA", Path.home() / ".config/beast-ytm-control"))
SETTINGS_FILE = DATA_DIR / "settings.json"

DEFAULTS: dict[str, Any] = {
    "bind_host": "0.0.0.0",
    "port": 8787,
    "companion_base": "http://127.0.0.1:9863/api/v1",
    "state_ttl_seconds": 15.0,
    "companion_min_interval": 5.1,
    "autostart": True,
    # Shared secret for LAN clients (macOS menu bar BEAST_REMOTE_TOKEN).
    "api_token": "",
}


def ensure_data_dir() -> None:
    DATA_DIR.mkdir(parents=True, exist_ok=True)
    try:
        DATA_DIR.chmod(0o700)
    except OSError:
        pass


def _normalize(raw: dict[str, Any]) -> dict[str, Any]:
    cfg = dict(DEFAULTS)
    cfg.update({k: raw[k] for k in DEFAULTS if k in raw})
    cfg["bind_host"] = str(cfg["bind_host"]).strip() or "0.0.0.0"
    cfg["port"] = int(cfg["port"])
    cfg["companion_base"] = str(cfg["companion_base"]).strip().rstrip("/")
    cfg["state_ttl_seconds"] = float(cfg["state_ttl_seconds"])
    cfg["companion_min_interval"] = float(cfg["companion_min_interval"])
    cfg["autostart"] = bool(cfg["autostart"])
    cfg["api_token"] = str(cfg.get("api_token") or "").strip()
    return cfg


def load_settings() -> dict[str, Any]:
    ensure_data_dir()
    if not SETTINGS_FILE.exists():
        return dict(DEFAULTS)
    try:
        raw = json.loads(SETTINGS_FILE.read_text())
    except (OSError, json.JSONDecodeError):
        return dict(DEFAULTS)
    if not isinstance(raw, dict):
        return dict(DEFAULTS)
    return _normalize(raw)


def save_settings(settings: dict[str, Any]) -> dict[str, Any]:
    ensure_data_dir()
    cfg = _normalize(settings)
    SETTINGS_FILE.write_text(json.dumps(cfg, indent=2, sort_keys=True) + "\n")
    try:
        SETTINGS_FILE.chmod(0o600)
    except OSError:
        pass
    return cfg


def ensure_api_token(settings: dict[str, Any] | None = None) -> dict[str, Any]:
    """Guarantee a non-empty api_token and persist it."""
    cfg = load_settings() if settings is None else _normalize(settings)
    if not cfg["api_token"]:
        cfg["api_token"] = secrets.token_urlsafe(32)
        save_settings(cfg)
    return cfg


def apply_runtime_settings(settings: dict[str, Any] | None = None) -> dict[str, Any]:
    """settings.json base, optional explicit dict, then env overrides."""
    cfg = ensure_api_token(settings)
    if os.environ.get("BEAST_YTM_CONTROL_PORT"):
        cfg["port"] = int(os.environ["BEAST_YTM_CONTROL_PORT"])
    if os.environ.get("BEAST_YTM_COMPANION"):
        cfg["companion_base"] = os.environ["BEAST_YTM_COMPANION"].rstrip("/")
    if os.environ.get("BEAST_YTM_STATE_TTL"):
        cfg["state_ttl_seconds"] = float(os.environ["BEAST_YTM_STATE_TTL"])
    if os.environ.get("BEAST_YTM_COMPANION_MIN_INTERVAL"):
        cfg["companion_min_interval"] = float(os.environ["BEAST_YTM_COMPANION_MIN_INTERVAL"])
    if os.environ.get("BEAST_YTM_BIND_HOST"):
        cfg["bind_host"] = os.environ["BEAST_YTM_BIND_HOST"]
    if os.environ.get("BEAST_YTM_API_TOKEN"):
        cfg["api_token"] = os.environ["BEAST_YTM_API_TOKEN"].strip()
    return cfg
