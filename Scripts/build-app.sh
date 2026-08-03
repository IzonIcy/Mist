#!/usr/bin/env bash
#
# Builds a distributable Mist.app bundle.
#
# Mist is a Swift Package (no .xcodeproj), so we assemble a real .app bundle by
# hand. This is the script anyone runs after `git clone` to produce the artifact
# that then lands in /Applications.
#
# Usage:
#   ./Scripts/build-app.sh [--release]
#
# Output:  build/Mist.app
#
# The resulting bundle is unsigned (or ad-hoc signed) by default. To ship to the
# public, sign with a Developer ID + notarize; the distributed .app then carries
# the signature. Nothing in the app bundle requires a provisioning profile.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

CONFIG="debug"
if [[ "${1:-}" == "--release" ]]; then
    CONFIG="release"
fi

echo "==> Building MistCore + Mist ($CONFIG)"
swift build -c "$CONFIG"

BIN=".build/$CONFIG/Mist"
if [[ ! -x "$BIN" ]]; then
    echo "error: expected binary at $BIN" >&2
    exit 1
fi

APP="$ROOT/build/Mist.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$BIN" "$APP/Contents/MacOS/Mist"
cp "$ROOT/Support/Info.plist" "$APP/Contents/Info.plist"

# Sign (ad-hoc if no identity is configured).
IDENTITY="${MIST_SIGNING_IDENTITY:-}"
if [[ -n "$IDENTITY" ]]; then
    codesign --force --deep --sign "$IDENTITY" --options runtime "$APP"
    echo "==> Signed with '$IDENTITY'"
else
    codesign --force --sign - "$APP"
    echo "==> Ad-hoc signed"
fi

echo "==> Built $APP"
echo "    Install: cp -R '$APP' /Applications/"