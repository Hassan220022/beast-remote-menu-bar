#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
APP_ID="beast-ytm-control"
SHARE="${XDG_DATA_HOME:-$HOME/.local/share}/$APP_ID"
BIN="${XDG_BIN_HOME:-$HOME/.local/bin}"
APPS="${XDG_DATA_HOME:-$HOME/.local/share}/applications"
UNIT_DIR="$HOME/.config/systemd/user"
CONFIG="$HOME/.config/beast-ytm-control"

mkdir -p "$SHARE" "$BIN" "$APPS" "$UNIT_DIR" "$CONFIG"

# Install package tree
rm -rf "$SHARE/beast_ytm_control"
cp -a "$ROOT/beast_ytm_control" "$SHARE/beast_ytm_control"
cp -a "$ROOT/run.py" "$SHARE/run.py"
chmod 755 "$SHARE/run.py"

# Wrapper on PATH
cat >"$BIN/$APP_ID" <<EOF
#!/usr/bin/env bash
exec /usr/bin/python3 "$SHARE/run.py" "\$@"
EOF
chmod 755 "$BIN/$APP_ID"

# Desktop entry
sed "s|^Exec=.*|Exec=$BIN/$APP_ID|" "$ROOT/beast-ytm-control.desktop" >"$APPS/beast-ytm-control.desktop"
chmod 644 "$APPS/beast-ytm-control.desktop"

# User systemd unit runs API daemon; desktop entry opens tray UI.
sed "s|ExecStart=.*|ExecStart=$BIN/$APP_ID --daemon|" "$ROOT/beast-ytm-control.service" >"$UNIT_DIR/beast-ytm-control.service"

# Seed/upgrade settings and ensure LAN API bearer token exists
TOKEN_LINE="$(
  /usr/bin/python3 - <<PY
import sys
sys.path.insert(0, "$SHARE")
from beast_ytm_control.settings import SETTINGS_FILE, ensure_api_token
cfg = ensure_api_token()
print(cfg.get("api_token") or "")
print(SETTINGS_FILE, file=sys.stderr)
print("api_token_len", len(cfg.get("api_token") or ""), file=sys.stderr)
PY
)"

# Stop legacy bare app.py service path if running, then enable new unit
systemctl --user daemon-reload || true
systemctl --user disable --now beast-ytm-control.service 2>/dev/null || true

# Remove old single-file deploy if present (keep token/settings)
if [[ -f "$HOME/.local/share/beast-ytm-control/app.py" && ! -d "$HOME/.local/share/beast-ytm-control/beast_ytm_control" ]]; then
  mkdir -p "$HOME/.local/share/beast-ytm-control/legacy"
  mv "$HOME/.local/share/beast-ytm-control/app.py" "$HOME/.local/share/beast-ytm-control/legacy/" 2>/dev/null || true
fi

systemctl --user enable --now beast-ytm-control.service

if command -v update-desktop-database >/dev/null 2>&1; then
  update-desktop-database "$APPS" >/dev/null 2>&1 || true
fi

echo "Installed Beast YTM Control"
echo "  launcher: $BIN/$APP_ID"
echo "  desktop:  $APPS/beast-ytm-control.desktop"
echo "  config:   $CONFIG/settings.json"
echo "  service:  systemctl --user status beast-ytm-control"
echo
echo "macOS client auth (required):"
echo "  export BEAST_REMOTE_URL=\"http://192.168.1.99:8787\""
echo "  export BEAST_REMOTE_TOKEN=\"$TOKEN_LINE\""
echo
echo "Open from app menu, or: $BIN/$APP_ID"
echo "Daemon only:            $BIN/$APP_ID --daemon"
echo "Stop:                   systemctl --user stop beast-ytm-control"
echo "Quit tray:              tray menu → Quit"
