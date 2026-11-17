#!/usr/bin/env bash
# Builds a release of Manita ready for GitHub Releases and the Homebrew tap:
# Developer ID signature (hardened runtime) -> Apple notarization -> stapled ticket -> zip + SHA-256.
#
# Usage: scripts/release.sh <version>        e.g. scripts/release.sh 1.0.0
# One-time setup (see docs/RELEASING.md):
#   xcrun notarytool store-credentials manita-notary --apple-id <you@…> --team-id <TEAMID>
# Overrides: MANITA_DEVELOPER_ID="Developer ID Application: …", MANITA_NOTARY_PROFILE=manita-notary,
#            MANITA_NOTARY_KEYCHAIN=<path> (keychain holding the notary profile; used by CI, default: login keychain)
set -euo pipefail

VERSION="${1:?Usage: scripts/release.sh <version>}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/build/Manita.app"
DIST="$ROOT/dist"
ZIP="$DIST/Manita-$VERSION.zip"
PROFILE="${MANITA_NOTARY_PROFILE:-manita-notary}"
NOTARY_KEYCHAIN_ARGS=()
[ -z "${MANITA_NOTARY_KEYCHAIN:-}" ] || NOTARY_KEYCHAIN_ARGS=(--keychain "$MANITA_NOTARY_KEYCHAIN")
IDENTITY="${MANITA_DEVELOPER_ID:-$(security find-identity -v -p codesigning \
    | sed -n 's/.*"\(Developer ID Application: [^"]*\)".*/\1/p' | head -1)}"
[ -n "$IDENTITY" ] || { echo "No 'Developer ID Application' certificate found in the keychain." >&2; exit 1; }

cd "$ROOT"
# The version shown in About and read by Homebrew comes from Info.plist.
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" Resources/Info.plist
MANITA_SIGN_IDENTITY=- scripts/build-app.sh release >/dev/null

# Notarization requires a Developer ID signature with the hardened runtime and a secure timestamp.
codesign --force --deep --options runtime --timestamp --sign "$IDENTITY" "$APP"
codesign --verify --strict --verbose=2 "$APP"

mkdir -p "$DIST"
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"
echo "Submitting to Apple for notarization (usually a few minutes)…"
xcrun notarytool submit "$ZIP" --keychain-profile "$PROFILE" ${NOTARY_KEYCHAIN_ARGS[@]+"${NOTARY_KEYCHAIN_ARGS[@]}"} --wait
# Staple the ticket so Gatekeeper accepts the app offline, then zip the stapled app again.
xcrun stapler staple "$APP"
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"
spctl --assess --type execute --verbose "$APP"

SHA="$(shasum -a 256 "$ZIP" | cut -d' ' -f1)"
echo
echo "Release ready: $ZIP"
echo "version: $VERSION"
echo "sha256:  $SHA"
echo "Next: upload the zip to the GitHub release v$VERSION and update version/sha256 in Casks/manita.rb of the tap."
