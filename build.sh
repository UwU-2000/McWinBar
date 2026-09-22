#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

echo "==> Compiling (release)…"
swift build -c release

APP="McWinBar.app"
BIN=".build/release/McWinBar"

echo "==> Assembling ${APP}…"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/McWinBar"
cp Info.plist "$APP/Contents/Info.plist"

# Sign with a stable self-signed identity so TCC permissions (Accessibility,
# Screen Recording) persist across rebuilds. Falls back to ad-hoc if the cert
# isn't present. NOTE: the cert keeps its original "Taskbar Dev Cert" name on
# purpose — renaming it would change the signing identity and reset TCC grants.
SIGN_ID="Taskbar Dev Cert"
if security find-identity -p codesigning 2>/dev/null | grep -q "$SIGN_ID"; then
    echo "==> Signing with '$SIGN_ID'…"
    codesign --force --deep --sign "$SIGN_ID" "$APP"
else
    echo "==> '$SIGN_ID' not found; ad-hoc signing…"
    codesign --force --deep --sign - "$APP"
fi

echo "==> Done: $(pwd)/$APP"
