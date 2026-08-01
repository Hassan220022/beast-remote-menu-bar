# Beast Remote Menu Bar

Tiny macOS menu bar remote for a Beast controller that exposes a local HTTP API. The app polls the configured Beast URL, shows the current YouTube Music state, and sends playback, volume, seek, and load-URL commands.

## Requirements

- macOS 26 or newer on Apple silicon.
- Swift command line tools.
- A Beast controller reachable on your LAN.

## Configure

The app reads `BEAST_REMOTE_URL` at launch. If unset, it uses `http://192.168.1.99:8787`.

```sh
export BEAST_REMOTE_URL="http://192.168.1.99:8787"
```

Use an `http` or `https` URL with a host. The app rejects malformed values and shows a disabled/offline state until fixed.

Prefer `https://` whenever the Beast server supports it. `http://` is allowed for trusted-LAN use, but the control channel sends commands in cleartext over plain HTTP, so only use it on networks you trust.

### Shared-secret token (required against current Linux bridge)

The Linux Beast YTM Control API requires a bearer token. Set `BEAST_REMOTE_TOKEN` to the `api_token` from beast `~/.config/beast-ytm-control/settings.json`. The menu bar app attaches `Authorization: Bearer <token>` on every request.

```sh
export BEAST_REMOTE_TOKEN="your-shared-secret"
```

## Build And Test

```sh
./build.sh check
```

Useful commands:

```sh
./build.sh build      # compile into ./build without launching
./build.sh test       # run lightweight core tests
./build.sh open       # build and open for this user session
./build.sh quit       # ask the running app to quit
./build.sh install    # copy the app to ~/Applications
./build.sh uninstall  # quit and remove installed/legacy app files
```

`open`, `install`, and `uninstall` also remove the old LaunchAgent if it exists. The app does not install a persistent login item.

## Local Network And Security

`Info.plist` allows local-network HTTP through `NSAllowsLocalNetworking` because the Beast controller is expected to live on a LAN address such as `192.168.x.x`. It does not enable broad arbitrary network loads.

The app sends commands only to the configured `BEAST_REMOTE_URL`. It validates the base URL scheme/host before enabling controls and uses short URLSession timeouts so an offline Beast does not hang the menu.

## Linux controller (Beast host)

The beast-side bridge is a real app under [`linux/`](linux/), not a one-off script:

- GTK tray UI (open/close, Start/Stop API, Settings, Pair)
- `~/.config/beast-ytm-control/settings.json`
- Desktop entry + user systemd unit

```sh
cd linux && ./install.sh
beast-ytm-control            # tray
beast-ytm-control --daemon   # API only
```

Details: [`linux/README.md`](linux/README.md).
