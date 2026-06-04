#!/bin/bash
# AI Usage Tray — macOS web installer (counterpart to the Windows install.ps1).
#
# One-line install:
#   curl -fsSL https://raw.githubusercontent.com/LSX-Apps/CC-Nutzung-Releases/main/install-macos.sh | bash
#
# Downloads the latest build, removes the Gatekeeper quarantine flag (the macOS
# equivalent of the Windows `Unblock-File` / SAC workaround), installs to
# /Applications, enables launch-at-login and starts the app.
set -euo pipefail

MANIFEST_URL="${MANIFEST_URL:-https://raw.githubusercontent.com/LSX-Apps/CC-Nutzung-Releases/main/usagetray-macos-manifest.json}"
APP_NAME="UsageTray.app"
DEST="/Applications/$APP_NAME"

echo "AI Usage Tray — Installation"
echo "==> Manifest laden"
MANIFEST="$(curl -fsSL "$MANIFEST_URL")"

read_json() { /usr/bin/python3 -c "import json,sys;print(json.loads(sys.stdin.read()).get('$1',''))" <<<"$MANIFEST"; }
VERSION="$(read_json version)"
DOWNLOAD_URL="$(read_json download_url)"
SHA="$(read_json sha256)"
[ -n "$DOWNLOAD_URL" ] || { echo "Manifest enthält keine download_url"; exit 1; }
echo "    Version $VERSION"

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
ZIP="$TMP/UsageTray.zip"

echo "==> Herunterladen"
curl -fsSL "$DOWNLOAD_URL" -o "$ZIP"

if [ -n "$SHA" ]; then
  ACTUAL="$(shasum -a 256 "$ZIP" | awk '{print $1}')"
  [ "$ACTUAL" = "$SHA" ] || { echo "SHA256 passt nicht (erwartet $SHA, bekommen $ACTUAL)"; exit 1; }
  echo "    SHA256 ok"
fi

echo "==> Entpacken + Quarantäne entfernen"
ditto -x -k "$ZIP" "$TMP/extract"
SRC="$(/usr/bin/find "$TMP/extract" -maxdepth 2 -name "$APP_NAME" -print -quit)"
[ -n "$SRC" ] || { echo "Im ZIP wurde keine $APP_NAME gefunden"; exit 1; }
xattr -dr com.apple.quarantine "$SRC" 2>/dev/null || true

echo "==> Installieren nach $DEST"
osascript -e 'quit app "UsageTray"' 2>/dev/null || true
rm -rf "$DEST"
cp -R "$SRC" "$DEST"
xattr -dr com.apple.quarantine "$DEST" 2>/dev/null || true

echo "==> Auto-Start aktivieren"
"$DEST/Contents/MacOS/UsageTray" --enable-login || true

echo "==> Starten"
open "$DEST"

echo ""
echo "Fertig. Das Icon erscheint oben rechts in der Menüleiste."
