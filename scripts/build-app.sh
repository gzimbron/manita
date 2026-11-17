#!/usr/bin/env bash
# Builds Manita with SwiftPM and wraps the binary in a runnable .app bundle.
# Usage: scripts/build-app.sh [debug|release]   (default: release)
set -euo pipefail

CONFIG="${1:-release}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/build/Manita.app"

cd "$ROOT"
swift build -c "$CONFIG"
BIN="$(swift build -c "$CONFIG" --show-bin-path)/Manita"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Manita"
# SwiftPM resource bundles (bundled SVG designs). BuiltInSkins looks them up in Contents/Resources.
for bundle in "$(dirname "$BIN")"/*.bundle; do
    [ -e "$bundle" ] && cp -R "$bundle" "$APP/Contents/Resources/"
done
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
cp "$ROOT/Resources/Icon/Manita.icns" "$APP/Contents/Resources/Manita.icns"

# Sign with a real certificate when one is available: macOS ties the Accessibility permission
# (presentation mode) to the signature, and only a certificate keeps it valid across rebuilds.
# An ad-hoc signature changes with every build, so the permission would be lost each time.
# Override with MANITA_SIGN_IDENTITY="<name or hash>", or MANITA_SIGN_IDENTITY=- for ad-hoc.
IDENTITY="${MANITA_SIGN_IDENTITY:-}"
if [ -z "$IDENTITY" ]; then
    IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null \
        | sed -n 's/.*"\(Apple Development: [^"]*\)".*/\1/p' | head -1)"
fi
IDENTITY="${IDENTITY:--}"
codesign --force --sign "$IDENTITY" "$APP" >/dev/null
if [ "$IDENTITY" = "-" ]; then
    echo "Signed ad-hoc: Accessibility permission must be granted again after each rebuild."
else
    echo "Signed with: $IDENTITY"
fi

echo "Built $APP"
