#!/usr/bin/env python3
from __future__ import annotations

import json
import os
import re
import threading
import time
import urllib.error
import urllib.parse
import urllib.request
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any


try:
    from .settings import DATA_DIR, SETTINGS_FILE, apply_runtime_settings, load_settings, save_settings
except ImportError:  # pragma: no cover - script path
    from settings import DATA_DIR, SETTINGS_FILE, apply_runtime_settings, load_settings, save_settings

APP_NAME = "Beast Remote"
APP_ID = "beastremote"
APP_VERSION = "1.1.0"
YOUTUBE_VIDEO_RE = re.compile(r"(?:v=|youtu\.be/)([A-Za-z0-9_-]{11})")
PLAYLIST_RE = re.compile(r"[?&]list=([A-Za-z0-9_-]+)")

# Runtime knobs — filled by apply_settings() before serve.
HOST = "0.0.0.0"
PORT = 8787
COMPANION_BASE = "http://127.0.0.1:9863/api/v1"
STATE_CACHE_TTL = 15.0
COMPANION_MIN_INTERVAL = 5.1
TOKEN_FILE = DATA_DIR / "token.json"
CODE_FILE = DATA_DIR / "pairing-code.json"

STATE_CACHE_LOCK = threading.Lock()
STATE_CACHE: dict[str, Any] = {
    "state": None,
    "fetched_at": 0.0,
    "error": None,
}


def _mapping(value: Any) -> dict[str, Any]:
    return value if isinstance(value, dict) else {}


def _largest_thumbnail_url(thumbnails: Any) -> str | None:
    if not isinstance(thumbnails, list):
        return None
    best_url = None
    best_area = -1
    for thumbnail in thumbnails:
        if not isinstance(thumbnail, dict):
            continue
        url = thumbnail.get("url")
        if not url:
            continue
        width = int(thumbnail.get("width") or 0)
        height = int(thumbnail.get("height") or 0)
        area = width * height
        if area >= best_area:
            best_area = area
            best_url = url
    return best_url


def _parse_duration_seconds(duration: Any) -> float | None:
    if not isinstance(duration, str):
        return None
    parts = [part.strip() for part in duration.split(":")]
    if len(parts) not in {2, 3}:
        return None
    try:
        values = [int(part) for part in parts]
    except ValueError:
        return None
    if len(values) == 2:
        minutes, seconds = values
        return float(minutes * 60 + seconds)
    hours, minutes, seconds = values
    return float(hours * 3600 + minutes * 60 + seconds)


def _selected_queue_item(player: dict[str, Any]) -> tuple[dict[str, Any] | None, int | None]:
    queue = _mapping(player.get("queue"))
    items = queue.get("items")
    if not isinstance(items, list) or not items:
        return None, None

    selected_index = queue.get("selectedItemIndex")
    if isinstance(selected_index, int) and 0 <= selected_index < len(items):
        item = _mapping(items[selected_index])
        return item, selected_index

    for index, item in enumerate(items):
        if isinstance(item, dict) and item.get("selected"):
            return item, index

    first_item = items[0] if isinstance(items[0], dict) else None
    return first_item, 0 if first_item is not None else None


def build_media_snapshot(state: dict[str, Any], *, fetched_at: float | None = None) -> dict[str, Any]:
    player = _mapping(state.get("player"))
    queue = _mapping(player.get("queue"))
    queue_item, queue_index = _selected_queue_item(player)
    details = _mapping(player.get("videoDetails"))
    video = _mapping(state.get("video"))
    video = video or details
    item = queue_item or details or video

    title = (
        video.get("title")
        or details.get("title")
        or (item.get("title") if item else None)
        or "Nothing playing"
    )
    author = (
        video.get("author")
        or details.get("author")
        or (item.get("author") if item else None)
        or "Unknown artist"
    )
    album = video.get("album") or details.get("album")
    artwork_url = (
        _largest_thumbnail_url(video.get("thumbnails"))
        or _largest_thumbnail_url(details.get("thumbnails"))
        or _largest_thumbnail_url(item.get("thumbnails") if item else None)
    )
    duration_seconds = (
        video.get("durationSeconds")
        or details.get("durationSeconds")
        or _parse_duration_seconds(item.get("duration") if item else None)
    )
    progress_seconds = player.get("videoProgress")
    if progress_seconds is None:
        progress_seconds = state.get("videoProgress")
    track_state = player.get("trackState")
    is_playing = track_state == 1
    volume = player.get("volume")
    muted = player.get("muted")
    repeat_mode = queue.get("repeatMode")
    queue_items = queue.get("items")
    automix_items = queue.get("automixItems")
    queue_length = 0
    if isinstance(queue_items, list):
        queue_length += len(queue_items)
    if isinstance(automix_items, list):
        queue_length += len(automix_items)

    return {
        "title": title,
        "author": author,
        "album": album,
        "artworkUrl": artwork_url,
        "videoId": video.get("id") or details.get("id") or (item.get("videoId") if item else None),
        "playlistId": state.get("playlistId") or queue.get("playlistId"),
        "trackState": track_state,
        "isPlaying": is_playing,
        "muted": muted,
        "volume": volume,
        "repeatMode": repeat_mode,
        "durationSeconds": duration_seconds,
        "progressSeconds": progress_seconds,
        "progressPercent": (progress_seconds / duration_seconds * 100.0) if duration_seconds and progress_seconds is not None else None,
        "fetchedAt": fetched_at if fetched_at is not None else time.time(),
        "queueIndex": queue_index,
        "queueLength": queue_length or None,
        "selected": bool(queue_item.get("selected")) if queue_item else False,
        "source": "companion",
    }


def invalidate_state_cache() -> None:
    # Expire freshness only. Keep last good companion snapshot so /api/state still
    # has media when the companion rate-limits (1 req / ~5s).
    with STATE_CACHE_LOCK:
        STATE_CACHE["fetched_at"] = 0.0
        STATE_CACHE["error"] = None


def apply_optimistic_command(command: str, data: Any = None) -> dict[str, Any] | None:
    """Patch cached companion state so immediate /api/state polls look right.
    Returns media snapshot when cache exists.
    """
    with STATE_CACHE_LOCK:
        state = STATE_CACHE.get("state")
        if not isinstance(state, dict):
            return None
        player = state.get("player")
        if not isinstance(player, dict):
            player = {}
            state["player"] = player
        queue = player.get("queue")
        if not isinstance(queue, dict):
            queue = {}
            player["queue"] = queue

        if command == "playPause":
            ts = player.get("trackState")
            player["trackState"] = 0 if ts == 1 else 1
        elif command == "setVolume" and data is not None:
            try:
                player["volume"] = int(data)
            except (TypeError, ValueError):
                pass
        elif command == "mute":
            player["muted"] = True
        elif command == "unmute":
            player["muted"] = False
        elif command in {"next", "previous"}:
            items = queue.get("items") if isinstance(queue.get("items"), list) else []
            automix = queue.get("automixItems") if isinstance(queue.get("automixItems"), list) else []
            # Build flat playable list: selected queue first, then automix tail.
            playlist = [i for i in items if isinstance(i, dict)]
            auto_tail = [i for i in automix if isinstance(i, dict)]
            flat = playlist + auto_tail
            if flat:
                idx = queue.get("selectedItemIndex")
                if not isinstance(idx, int) or not (0 <= idx < len(playlist)):
                    idx = next((i for i, it in enumerate(playlist) if it.get("selected")), 0)
                if command == "next":
                    idx = idx + 1 if idx + 1 < len(flat) else idx
                else:
                    idx = idx - 1 if idx > 0 else 0
                # Clear selected flags; mark new item when still inside main items.
                for i, it in enumerate(playlist):
                    it["selected"] = i == idx
                if idx < len(playlist):
                    queue["selectedItemIndex"] = idx
                    chosen = playlist[idx]
                else:
                    # Stepped into automix — keep index at last real item edge.
                    queue["selectedItemIndex"] = max(0, len(playlist) - 1)
                    chosen = flat[idx]
                details = {
                    "title": chosen.get("title"),
                    "author": chosen.get("author"),
                    "id": chosen.get("videoId"),
                    "thumbnails": chosen.get("thumbnails"),
                    "durationSeconds": _parse_duration_seconds(chosen.get("duration")),
                }
                player["videoDetails"] = details
                state["video"] = details
                player["videoProgress"] = 0
                player["trackState"] = 1
        STATE_CACHE["state"] = state
        return build_media_snapshot(state, fetched_at=time.time())


INDEX_HTML = "Beast Remote is API-only now. Use the macOS menu bar controller."


def json_response(data: Any, status: int = HTTPStatus.OK) -> tuple[int, str, bytes]:
    body = json.dumps(data, indent=2, sort_keys=True).encode("utf-8")
    return status, "application/json; charset=utf-8", body


def text_response(text: str, status: int = HTTPStatus.OK, content_type: str = "text/plain; charset=utf-8") -> tuple[int, str, bytes]:
    return status, content_type, text.encode("utf-8")


def ensure_data_dir() -> None:
    try:
        from .settings import ensure_data_dir as _ensure
    except ImportError:
        from settings import ensure_data_dir as _ensure
    _ensure()


def read_json(path: Path) -> dict[str, Any] | None:
    if not path.exists():
        return None
    try:
        return json.loads(path.read_text())
    except (OSError, json.JSONDecodeError):
        return None


def write_json(path: Path, payload: dict[str, Any]) -> None:
    path.write_text(json.dumps(payload, indent=2, sort_keys=True))
    try:
        path.chmod(0o600)
    except OSError:
        pass


def load_token() -> str | None:
    data = read_json(TOKEN_FILE)
    if not data:
        return None
    return data.get("token")


def save_token(token: str) -> None:
    ensure_data_dir()
    write_json(TOKEN_FILE, {"token": token, "savedAt": int(time.time())})


def save_pairing_code(code: str) -> None:
    ensure_data_dir()
    write_json(CODE_FILE, {"code": code, "savedAt": int(time.time())})


def load_pairing_code() -> str | None:
    data = read_json(CODE_FILE)
    if not data:
        return None
    return data.get("code")


COMPANION_LOCK = threading.Lock()
_COMMAND_SLOTS = threading.BoundedSemaphore(2)  # ponytail: drop burst backlog under companion 5s gate
_LAST_COMPANION_CALL = 0.0
MAX_BODY_BYTES = 64 * 1024


class CompanionRateLimited(RuntimeError):
    pass


def companion_request(path: str, *, method: str = "GET", body: dict[str, Any] | None = None, token: str | None = None, wait: bool = False) -> Any:
    # YTM companion header: x-ratelimit-limit=1, reset~5s. Serialize calls.
    # wait=False (default for state): fail fast with CompanionRateLimited if too soon.
    # wait=True (commands): block until the window opens, then send.
    global _LAST_COMPANION_CALL
    url = f"{COMPANION_BASE.rstrip('/')}/{path.lstrip('/')}"
    headers = {"Content-Type": "application/json"}
    if token:
        headers["Authorization"] = token
    data = None if body is None else json.dumps(body).encode("utf-8")
    request = urllib.request.Request(url, data=data, headers=headers, method=method)

    got_slot = False
    if wait:
        got_slot = _COMMAND_SLOTS.acquire(blocking=False)
        if not got_slot:
            raise CompanionRateLimited("command queue full")
    try:
        with COMPANION_LOCK:
            now = time.monotonic()
            wait_for = COMPANION_MIN_INTERVAL - (now - _LAST_COMPANION_CALL)
            if wait_for > 0:
                if not wait:
                    raise CompanionRateLimited(f"companion cooldown {wait_for:.2f}s")
                time.sleep(wait_for)
            try:
                with urllib.request.urlopen(request, timeout=35) as response:
                    payload = response.read().decode("utf-8")
                    return json.loads(payload) if payload else None
            except urllib.error.HTTPError as exc:
                if exc.code == 429:
                    raise CompanionRateLimited(exc.read().decode("utf-8", errors="replace") or "429") from exc
                raise
            finally:
                _LAST_COMPANION_CALL = time.monotonic()
    finally:
        if got_slot:
            _COMMAND_SLOTS.release()


def companion_public_request(path: str) -> Any:
    parsed = urllib.parse.urlsplit(COMPANION_BASE)
    origin = f"{parsed.scheme}://{parsed.netloc}" if parsed.scheme and parsed.netloc else "http://127.0.0.1:9863"
    url = f"{origin.rstrip('/')}/{path.lstrip('/')}"
    request = urllib.request.Request(url, method="GET")
    with urllib.request.urlopen(request, timeout=15) as response:
        payload = response.read().decode("utf-8")
        return json.loads(payload) if payload else None


def current_state() -> dict[str, Any]:
    token = load_token()
    if not token:
        return {"ok": False, "error": "not paired"}

    now = time.monotonic()
    with STATE_CACHE_LOCK:
        cached_state = STATE_CACHE["state"]
        cached_at = STATE_CACHE["fetched_at"]
        cached_error = STATE_CACHE["error"]
        cache_age = now - cached_at if cached_at else None
        if cached_state is not None and cache_age is not None and cache_age < STATE_CACHE_TTL:
            return {
                "ok": True,
                "state": cached_state,
                "media": build_media_snapshot(cached_state, fetched_at=time.time() - cache_age),
                "cached": True,
                "cacheAgeSeconds": cache_age,
            }

    try:
        state = companion_request("/state", token=token, wait=False)
        fetched_at = time.time()
        with STATE_CACHE_LOCK:
            STATE_CACHE["state"] = state
            STATE_CACHE["fetched_at"] = time.monotonic()
            STATE_CACHE["error"] = None
        return {
            "ok": True,
            "state": state,
            "media": build_media_snapshot(state, fetched_at=fetched_at),
            "cached": False,
            "fetchedAt": fetched_at,
        }
    except Exception as exc:  # pragma: no cover - network path
        with STATE_CACHE_LOCK:
            if cached_state is not None:
                age = now - cached_at if cached_at else None
                return {
                    "ok": True,
                    "state": cached_state,
                    "media": build_media_snapshot(cached_state, fetched_at=time.time() - age if age is not None else None),
                    "cached": True,
                    "stale": True,
                    "warning": str(exc),
                    "cacheAgeSeconds": age,
                }
            STATE_CACHE["error"] = str(exc)
        return {"ok": False, "error": str(exc)}


def extract_ids(url: str) -> dict[str, str | None]:
    parsed = urllib.parse.urlparse(url)
    query = urllib.parse.parse_qs(parsed.query)
    playlist_id = None
    video_id = None

    if "list" in query and query["list"]:
        playlist_id = query["list"][0]

    match = PLAYLIST_RE.search(url)
    if match and not playlist_id:
        playlist_id = match.group(1)

    video_match = YOUTUBE_VIDEO_RE.search(url)
    if video_match:
        video_id = video_match.group(1)
    elif parsed.hostname in {"youtu.be"} and parsed.path.strip("/"):
        candidate = parsed.path.strip("/")
        if len(candidate) == 11:
            video_id = candidate

    return {"playlistId": playlist_id, "videoId": video_id}


class Handler(BaseHTTPRequestHandler):
    server_version = "BeastRemote/1.0"

    def _send(self, payload: tuple[int, str, bytes]) -> None:
        status, content_type, body = payload
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, format: str, *args: Any) -> None:  # noqa: A003
        return

    def _authorized(self) -> bool:
        # Empty token = misconfig; refuse rather than open LAN.
        if not API_TOKEN:
            return False
        auth = (self.headers.get("Authorization") or "").strip()
        if auth == f"Bearer {API_TOKEN}":
            return True
        # Accept raw token header used by some local tools.
        if auth == API_TOKEN:
            return True
        return False

    def _require_auth(self) -> bool:
        if self._authorized():
            return True
        self._send(json_response({"error": "unauthorized"}, status=HTTPStatus.UNAUTHORIZED))
        return False

    def do_GET(self) -> None:  # noqa: N802
        if self.path == "/" or self.path.startswith("/?"):
            self._send(text_response(INDEX_HTML, status=HTTPStatus.GONE))
            return
        if not self._require_auth():
            return
        if self.path == "/api/state" or self.path.startswith("/api/state?"):
            payload = current_state()
            # ponytail: default omits raw companion `state` (~80-130KB queue blobs).
            # ?full=1 keeps old shape if something still needs it.
            qs = urllib.parse.urlparse(self.path).query
            full = urllib.parse.parse_qs(qs).get("full", ["0"])[0] in {"1", "true", "yes"}
            if not full and isinstance(payload, dict):
                payload = {k: v for k, v in payload.items() if k != "state"}
            self._send(json_response(payload))
            return
        if self.path == "/api/metadata":
            try:
                payload = companion_public_request("/metadata")
                self._send(json_response({"ok": True, "metadata": payload}))
            except Exception as exc:
                self._send(json_response({"ok": False, "error": str(exc)}, status=HTTPStatus.BAD_GATEWAY))
            return
        self._send(json_response({"error": "not found"}, status=HTTPStatus.NOT_FOUND))

    def do_POST(self) -> None:  # noqa: N802
        length = int(self.headers.get("Content-Length", "0") or "0")
        if length < 0 or length > MAX_BODY_BYTES:
            self._send(json_response({"error": "body too large"}, status=HTTPStatus.REQUEST_ENTITY_TOO_LARGE))
            return
        raw = self.rfile.read(length) if length else b"{}"
        try:
            data = json.loads(raw.decode("utf-8") or "{}")
        except json.JSONDecodeError:
            self._send(json_response({"error": "invalid json"}, status=HTTPStatus.BAD_REQUEST))
            return

        if not self._require_auth():
            return

        if self.path == "/api/command":
            command = data.get("command")
            if not command:
                self._send(json_response({"error": "missing command"}, status=HTTPStatus.BAD_REQUEST))
                return
            token = load_token()
            if not token:
                self._send(json_response({"error": "pair first"}, status=HTTPStatus.FORBIDDEN))
                return
            body: dict[str, Any] = {"command": command}
            if "data" in data:
                body["data"] = data["data"]
            try:
                payload = companion_request("/command", method="POST", body=body, token=token, wait=True)
                media = apply_optimistic_command(str(command), body.get("data"))
                if media is None:
                    invalidate_state_cache()
                else:
                    with STATE_CACHE_LOCK:
                        STATE_CACHE["fetched_at"] = time.monotonic()
                        STATE_CACHE["error"] = None
                out: dict[str, Any] = {"ok": True, "result": payload}
                if media is not None:
                    out["media"] = media
                self._send(json_response(out))
            except CompanionRateLimited as exc:
                self._send(json_response({"error": str(exc)}, status=HTTPStatus.TOO_MANY_REQUESTS))
            except Exception as exc:
                self._send(json_response({"error": str(exc)}, status=HTTPStatus.BAD_GATEWAY))
            return

        if self.path == "/api/load-url":
            token = load_token()
            if not token:
                self._send(json_response({"error": "pair first"}, status=HTTPStatus.FORBIDDEN))
                return
            url = data.get("url", "").strip()
            if not url:
                self._send(json_response({"error": "missing url"}, status=HTTPStatus.BAD_REQUEST))
                return
            ids = extract_ids(url)
            if not ids["playlistId"] and not ids["videoId"]:
                self._send(json_response({"error": "could not detect playlistId or videoId"}, status=HTTPStatus.BAD_REQUEST))
                return
            try:
                payload = companion_request(
                    "/command",
                    method="POST",
                    body={
                        "command": "changeVideo",
                        "data": {
                            "videoId": ids["videoId"],
                            "playlistId": ids["playlistId"],
                        },
                    },
                    token=token,
                    wait=True,
                )
                invalidate_state_cache()
                self._send(json_response({"ok": True, "message": "URL sent to Beast", "result": payload}))
            except Exception as exc:
                self._send(json_response({"error": str(exc)}, status=HTTPStatus.BAD_GATEWAY))
            return

        if self.path == "/api/pair/start":
            try:
                payload = companion_request(
                    "/auth/requestcode",
                    method="POST",
                    body={"appId": APP_ID, "appName": APP_NAME, "appVersion": APP_VERSION},
                )
                code = payload.get("code")
                if not code:
                    raise RuntimeError("pairing code missing from response")
                save_pairing_code(code)
                self._send(json_response({"ok": True, "message": "pairing code created", "code": code}))
            except Exception as exc:
                self._send(json_response({"error": str(exc)}, status=HTTPStatus.BAD_GATEWAY))
            return

        if self.path == "/api/pair/finish":
            code = load_pairing_code()
            if not code:
                self._send(json_response({"error": "start pairing first"}, status=HTTPStatus.BAD_REQUEST))
                return
            try:
                payload = companion_request(
                    "/auth/request",
                    method="POST",
                    body={"appId": APP_ID, "code": code},
                )
                token = payload.get("token")
                if not token:
                    raise RuntimeError("token missing from response")
                save_token(token)
                invalidate_state_cache()
                self._send(json_response({"ok": True, "message": "paired", "saved": True}))
            except urllib.error.HTTPError as exc:
                details = exc.read().decode("utf-8", errors="replace")
                self._send(json_response({"error": f"{exc.reason}: {details}"}, status=HTTPStatus.BAD_GATEWAY))
            except Exception as exc:
                self._send(json_response({"error": str(exc)}, status=HTTPStatus.BAD_GATEWAY))
            return

        self._send(json_response({"error": "not found"}, status=HTTPStatus.NOT_FOUND))


API_TOKEN = ""


def apply_settings(settings: dict[str, Any] | None = None) -> dict[str, Any]:
    """Load settings.json (+ env overrides) into module globals used by handlers."""
    global HOST, PORT, COMPANION_BASE, STATE_CACHE_TTL, COMPANION_MIN_INTERVAL, TOKEN_FILE, CODE_FILE, API_TOKEN
    cfg = apply_runtime_settings(settings)
    HOST = cfg["bind_host"]
    PORT = int(cfg["port"])
    COMPANION_BASE = cfg["companion_base"]
    STATE_CACHE_TTL = float(cfg["state_ttl_seconds"])
    COMPANION_MIN_INTERVAL = float(cfg["companion_min_interval"])
    API_TOKEN = str(cfg.get("api_token") or "")
    TOKEN_FILE = DATA_DIR / "token.json"
    CODE_FILE = DATA_DIR / "pairing-code.json"
    return cfg


class ServerController:
    """Start/stop the HTTP API from the tray app or --daemon mode."""

    def __init__(self) -> None:
        self._server: ThreadingHTTPServer | None = None
        self._thread: threading.Thread | None = None
        self._lock = threading.Lock()

    @property
    def running(self) -> bool:
        return self._thread is not None and self._thread.is_alive()

    @property
    def endpoint(self) -> str:
        host = "127.0.0.1" if HOST in {"0.0.0.0", "::", "[::]"} else HOST
        return f"http://{host}:{PORT}"

    def start(self, settings: dict[str, Any] | None = None) -> str:
        with self._lock:
            if self.running:
                return self.endpoint
            cfg = apply_settings(settings)
            ensure_data_dir()
            server = ThreadingHTTPServer((HOST, PORT), Handler)
            thread = threading.Thread(target=server.serve_forever, name="beast-ytm-http", daemon=True)
            self._server = server
            self._thread = thread
            thread.start()
            return self.endpoint

    def stop(self) -> None:
        with self._lock:
            server = self._server
            thread = self._thread
            self._server = None
            self._thread = None
        if server is not None:
            server.shutdown()
            server.server_close()
        if thread is not None:
            thread.join(timeout=3)

    def restart(self, settings: dict[str, Any] | None = None) -> str:
        self.stop()
        return self.start(settings)


def main() -> None:
    controller = ServerController()
    endpoint = controller.start()
    print(f"Beast Remote listening on {endpoint}")
    print(f"Companion server target: {COMPANION_BASE}")
    print(f"API auth: Bearer token required (settings api_token, len={len(API_TOKEN)})")
    try:
        while True:
            time.sleep(3600)
    except KeyboardInterrupt:
        controller.stop()


if __name__ == "__main__":
    main()
