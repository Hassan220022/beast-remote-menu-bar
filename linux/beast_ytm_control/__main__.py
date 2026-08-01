from __future__ import annotations

import argparse
import sys


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="beast-ytm-control", description="Beast YTM Control app")
    parser.add_argument("--daemon", action="store_true", help="HTTP API only (no tray UI)")
    parser.add_argument("--settings", action="store_true", help="Print settings path/json and exit")
    args = parser.parse_args(argv)

    if args.settings:
        from .settings import SETTINGS_FILE, load_settings
        import json

        print(SETTINGS_FILE)
        print(json.dumps(load_settings(), indent=2, sort_keys=True))
        return 0

    if args.daemon or not _display_available():
        from .server import main as daemon_main

        daemon_main()
        return 0

    from .app import run_app

    return run_app()


def _display_available() -> bool:
    import os

    return bool(os.environ.get("DISPLAY") or os.environ.get("WAYLAND_DISPLAY"))


if __name__ == "__main__":
    sys.exit(main())
