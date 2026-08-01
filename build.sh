#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_NAME="BeastRemoteMenuBar"
BUNDLE_ID="com.mikawi.beastremote.menubar"
BUILD_DIR="$ROOT_DIR/build"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"
EXECUTABLE_PATH="$APP_BUNDLE/Contents/MacOS/$APP_NAME"
RESOURCES_DIR="$APP_BUNDLE/Contents/Resources"
PLIST_PATH="$APP_BUNDLE/Contents/Info.plist"
ICON_NAME="AppIcon"
ICON_MASTER="$BUILD_DIR/icon_1024.png"
ICON_ICNS="$BUILD_DIR/$ICON_NAME.icns"
ICON_GENERATOR="$ROOT_DIR/Tools/make_icon.swift"
# Ad-hoc code signing identity ("-" means no developer cert needed). A locally
# built+signed bundle launches via double-click without Gatekeeper "damaged" errors.
CODESIGN_IDENTITY="-"
TEST_EXECUTABLE="$BUILD_DIR/BeastRemoteCoreTests"
# Install to /Applications so the app is discoverable in Spotlight/Launchpad/Dock
# for a normal double-click experience. /Applications is writable by the admin
# group on a standard Mac (no sudo needed); we fall back to sudo only if required.
INSTALL_DIR="/Applications"
INSTALLED_APP="$INSTALL_DIR/$APP_NAME.app"
LEGACY_APP_DIR="$HOME/Library/Application Support/BeastRemoteMenuBar"
LEGACY_APP="$LEGACY_APP_DIR/$APP_NAME.app"
AGENT_LABEL="$BUNDLE_ID"
LAUNCH_AGENT="$HOME/Library/LaunchAgents/$AGENT_LABEL.plist"
# App sources: the full refactored tree under Sources/. Order doesn't matter to
# swiftc (it resolves declarations across all files in one compilation), so we
# glob each layer for resilience as files are added/removed.
SWIFT_SOURCES=()
while IFS= read -r -d '' file; do
  SWIFT_SOURCES+=("$file")
done < <(find "$ROOT_DIR/Sources" -name '*.swift' ! -path "$ROOT_DIR/Sources/Tools/*" -print0 | sort -z)

# Test sources: the framework-light core (Support + Models + Networking) plus
# the test harness. These layers import only Foundation/Combine, so the headless
# test binary builds without AppKit/SwiftUI. The Views/App layers are UI-only and
# excluded.
TEST_SOURCES=(
  "$ROOT_DIR/Sources/Support/Formatting.swift"
  "$ROOT_DIR/Sources/Support/URLValidation.swift"
  "$ROOT_DIR/Sources/Models/RemoteState.swift"
  "$ROOT_DIR/Sources/Models/BeastMediaSnapshot.swift"
  "$ROOT_DIR/Sources/Models/BeastRemoteModel.swift"
  "$ROOT_DIR/Sources/Networking/BeastRemoteError.swift"
  "$ROOT_DIR/Sources/Networking/BeastRemoteModel+API.swift"
  "$ROOT_DIR/Tests/BeastRemoteCoreTests.swift"
  "$ROOT_DIR/Tests/main.swift"
)

usage() {
  cat <<EOF
Usage: $0 [command]

Commands:
  build      Compile $APP_NAME.app into ./build (default, safe: no launch/install)
  test       Build and run lightweight core tests
  check      Lint plist, syntax-check this script, build, and test
  install    Build and copy the signed app to /Applications
  open       Build and open the app for this user session
  quit       Ask the running app to quit normally
  stop       Alias for quit
  uninstall  Quit the app and remove installed/legacy app files and old LaunchAgent
  help       Show this help
EOF
}

generate_icon() {
  # Produce build/AppIcon.icns from the Swift icon generator. Best-effort: if any
  # step fails, warn and continue so the build never blocks on the icon.
  if [[ -f "$ICON_ICNS" && "$ICON_ICNS" -nt "$ICON_GENERATOR" ]]; then
    return 0
  fi
  if [[ ! -f "$ICON_GENERATOR" ]]; then
    echo "warning: icon generator missing ($ICON_GENERATOR); skipping icon" >&2
    return 0
  fi

  if ! swift "$ICON_GENERATOR" "$ICON_MASTER" >/dev/null 2>&1; then
    echo "warning: failed to render icon master; skipping icon" >&2
    return 0
  fi

  local iconset="$BUILD_DIR/$ICON_NAME.iconset"
  rm -rf "$iconset"
  mkdir -p "$iconset"
  local specs=(
    "16:icon_16x16" "32:icon_16x16@2x" "32:icon_32x32" "64:icon_32x32@2x"
    "128:icon_128x128" "256:icon_128x128@2x" "256:icon_256x256"
    "512:icon_256x256@2x" "512:icon_512x512" "1024:icon_512x512@2x"
  )
  local spec px name
  for spec in "${specs[@]}"; do
    px="${spec%%:*}"
    name="${spec##*:}"
    sips -z "$px" "$px" "$ICON_MASTER" --out "$iconset/$name.png" >/dev/null 2>&1 || true
  done

  if iconutil -c icns "$iconset" -o "$ICON_ICNS" >/dev/null 2>&1; then
    rm -rf "$iconset"
    echo "Generated icon: $ICON_ICNS"
  else
    echo "warning: iconutil failed; skipping icon" >&2
    rm -rf "$iconset"
  fi
}

sign_app() {
  # Ad-hoc sign the whole bundle so a locally built app launches without the
  # Gatekeeper "is damaged / unidentified developer" prompt on double-click.
  # --deep signs nested code; we omit --options runtime because hardened runtime
  # adds no value for an unnotarized local build and can complicate launch.
  if codesign --force --deep --sign "$CODESIGN_IDENTITY" "$APP_BUNDLE" >/dev/null 2>&1; then
    echo "Signed (ad-hoc): $APP_BUNDLE"
  else
    echo "warning: codesign failed; app may be blocked by Gatekeeper" >&2
  fi
}

build_app() {
  mkdir -p "$BUILD_DIR" "$APP_BUNDLE/Contents/MacOS" "$RESOURCES_DIR"

  swiftc \
    -parse-as-library \
    -O \
    -target arm64-apple-macosx26.0 \
    -framework AppKit \
    -framework Combine \
    -framework Foundation \
    -framework SwiftUI \
    -o "$EXECUTABLE_PATH" \
    "${SWIFT_SOURCES[@]}"

  cp "$ROOT_DIR/Info.plist" "$PLIST_PATH"

  generate_icon
  if [[ -f "$ICON_ICNS" ]]; then
    cp "$ICON_ICNS" "$RESOURCES_DIR/$ICON_NAME.icns"
  fi

  sign_app
  echo "Built: $APP_BUNDLE"
}

test_core() {
  mkdir -p "$BUILD_DIR"
  swiftc \
    -target arm64-apple-macosx26.0 \
    -framework Combine \
    -framework Foundation \
    -o "$TEST_EXECUTABLE" \
    "${TEST_SOURCES[@]}"
  "$TEST_EXECUTABLE"
}

check_project() {
  plutil -lint "$ROOT_DIR/Info.plist"
  bash -n "$ROOT_DIR/build.sh"
  build_app
  test_core
}

remove_legacy_launch_agent() {
  if [[ -f "$LAUNCH_AGENT" ]]; then
    launchctl bootout "gui/$(id -u)" "$LAUNCH_AGENT" >/dev/null 2>&1 || true
    rm -f "$LAUNCH_AGENT"
    echo "Removed old LaunchAgent: $LAUNCH_AGENT"
  fi
}

quit_app() {
  osascript -e "tell application id \"$BUNDLE_ID\" to quit" >/dev/null 2>&1 || true
}

install_app() {
  build_app
  remove_legacy_launch_agent
  quit_app

  # Copy the freshly signed bundle into /Applications. /Applications is normally
  # writable by the admin group; only fall back to sudo if a plain copy fails.
  local use_sudo=""
  if [[ ! -w "$INSTALL_DIR" ]]; then
    use_sudo="sudo"
    echo "note: $INSTALL_DIR not writable; using sudo for install"
  fi

  $use_sudo rm -rf "$INSTALLED_APP"
  if ! $use_sudo cp -R "$APP_BUNDLE" "$INSTALLED_APP"; then
    echo "error: failed to copy app to $INSTALLED_APP" >&2
    return 1
  fi

  # Strip any quarantine flag so double-click launches without a Gatekeeper prompt.
  $use_sudo xattr -dr com.apple.quarantine "$INSTALLED_APP" >/dev/null 2>&1 || true

  # Register with Launch Services so Spotlight/Launchpad/Dock find it immediately.
  local lsregister="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
  if [[ -x "$lsregister" ]]; then
    "$lsregister" -f "$INSTALLED_APP" >/dev/null 2>&1 || true
  fi

  echo "Installed: $INSTALLED_APP"
  echo "Open it from Finder/Spotlight/Launchpad, or run: $0 open"
}

load_dotenv() {
  # ponytail: KEY=VALUE lines only; no shell expansion.
  local env_file="$ROOT_DIR/.env"
  [[ -f "$env_file" ]] || return 0
  local line key value
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ -z "$line" || "$line" == \#* ]] && continue
    key="${line%%=*}"
    value="${line#*=}"
    key="${key#"${key%%[![:space:]]*}"}"
    key="${key%"${key##*[![:space:]]}"}"
    [[ -n "$key" ]] || continue
    export "$key=$value"
  done <"$env_file"
}

open_app() {
  build_app
  remove_legacy_launch_agent
  # Open the freshly built bundle directly (this is the per-session dev path).
  # Use `install` for the persistent /Applications copy.
  # GUI apps launched via `open` do not inherit shell env — inject from .env.
  load_dotenv
  xattr -dr com.apple.quarantine "$APP_BUNDLE" >/dev/null 2>&1 || true
  local bin="$APP_BUNDLE/Contents/MacOS/$APP_NAME"
  if [[ -x "$bin" ]]; then
    # quit existing first so new env is picked up
    quit_app >/dev/null 2>&1 || true
    sleep 0.3
    env \
      BEAST_REMOTE_URL="${BEAST_REMOTE_URL:-http://192.168.1.99:8787}" \
      ${BEAST_REMOTE_TOKEN:+BEAST_REMOTE_TOKEN="$BEAST_REMOTE_TOKEN"} \
      "$bin" >/dev/null 2>&1 &
    disown || true
  else
    /usr/bin/open "$APP_BUNDLE"
  fi
  echo "Opened: $APP_BUNDLE"
  echo "  BEAST_REMOTE_URL=${BEAST_REMOTE_URL:-http://192.168.1.99:8787}"
  if [[ -n "${BEAST_REMOTE_TOKEN:-}" ]]; then
    echo "  BEAST_REMOTE_TOKEN=(set, ${#BEAST_REMOTE_TOKEN} chars)"
  else
    echo "  BEAST_REMOTE_TOKEN=(unset)"
  fi
}

uninstall_app() {
  quit_app
  remove_legacy_launch_agent
  local use_sudo=""
  if [[ -e "$INSTALLED_APP" && ! -w "$INSTALL_DIR" ]]; then
    use_sudo="sudo"
  fi
  $use_sudo rm -rf "$INSTALLED_APP"
  rm -rf "$LEGACY_APP"
  rmdir "$LEGACY_APP_DIR" >/dev/null 2>&1 || true
  echo "Removed installed app files."
}

command="${1:-build}"
case "$command" in
  build)
    build_app
    ;;
  test)
    test_core
    ;;
  check)
    check_project
    ;;
  install)
    install_app
    ;;
  open)
    open_app
    ;;
  quit|stop)
    quit_app
    echo "Quit requested for $APP_NAME."
    ;;
  uninstall)
    uninstall_app
    ;;
  help|-h|--help)
    usage
    ;;
  *)
    usage >&2
    exit 2
    ;;
esac
