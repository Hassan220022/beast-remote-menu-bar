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

# Seed settings if missing
if [[ ! -f "$CONFIG/settings.json" ]]; then
  /usr/bin/python3 - <<PY
from pathlib import Path
import json, sys
sys.path.insert(0, "$SHARE")
from beast_ytm_control.settings import DEFAULTS, SETTINGS_FILE, save_settings
save_settings(DEFAULTS)
print("wrote", SETTINGS_FILE)
PY
fi

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
echo "Open from app menu, or: $BIN/$APP_ID"
echo "Daemon only:            $BIN/$APP_ID --daemon"
echo "Stop:                   systemctl --user stop beast-ytm-control"
echo "Quit tray:              tray menu → Quit"
