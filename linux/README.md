# Beast YTM Control (Linux)

GTK tray app that bridges **YouTube Music Desktop companion** → local HTTP API for the macOS **Beast Remote** menu bar app.

## What you get

- Open/close from the app menu or tray
- **Settings** window (bind host, port, companion URL, cache TTL, rate-limit interval, autostart)
- Pair flow for the YTM companion token
- Start/Stop API from the tray
- User systemd unit + desktop entry

Config lives in `~/.config/beast-ytm-control/`:

- `settings.json` — app settings
- `token.json` — companion auth token
- `pairing-code.json` — temporary pair code

## Install (on beast)

```sh
cd linux
./install.sh
```

Requires: Python 3, `python3-gi`, GTK 3, `gir1.2-ayatanaappindicator3-0.1`.

## Run

```sh
beast-ytm-control           # tray UI (needs DISPLAY)
beast-ytm-control --daemon  # API only
beast-ytm-control --settings
systemctl --user status beast-ytm-control
systemctl --user stop beast-ytm-control
systemctl --user start beast-ytm-control
```

Default API: `http://0.0.0.0:8787` (`/api/state`, `/api/command`, `/api/load-url`, pair routes).

## macOS client

Point the menu bar app at the beast host:

```sh
export BEAST_REMOTE_URL="http://192.168.1.99:8787"
```
