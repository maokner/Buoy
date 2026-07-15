#!/bin/bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DERIVED_DATA="${TMPDIR:-/tmp}/BuoyLocalDerivedData"
PRODUCT="$DERIVED_DATA/Build/Products/Release/Buoy.app"
DESTINATION="/Applications/Buoy.app"

# Sign with the stable self-signed "Buoy Self-Signed" identity, the same one
# release DMGs use. Sharing one identity keeps macOS Screen Recording and
# Accessibility grants attached across local rebuilds AND released updates.
# Create it once with scripts/make-signing-cert.sh.
identity="Buoy Self-Signed"

if ! security find-identity -p codesigning | grep -q "$identity"; then
    echo "The '$identity' code-signing identity was not found in your keychain." >&2
    echo "Create it once by running: ./scripts/make-signing-cert.sh" >&2
    exit 1
fi

echo "Building Buoy Release…"
xcodebuild \
    -project "$ROOT_DIR/Buoy.xcodeproj" \
    -scheme Buoy \
    -configuration Release \
    -destination "platform=macOS,arch=arm64" \
    -derivedDataPath "$DERIVED_DATA" \
    clean build \
    CODE_SIGNING_ALLOWED=NO

echo "Signing with the local Apple Development identity…"
codesign --force --sign "$identity" "$PRODUCT"
codesign --verify --deep --strict --verbose=2 "$PRODUCT"

echo "Installing ${DESTINATION}…"
pkill -x Buoy 2>/dev/null || true
rm -rf "$DESTINATION"
ditto "$PRODUCT" "$DESTINATION"
codesign --verify --deep --strict --verbose=2 "$DESTINATION"

echo "Installed a stable signed copy at ${DESTINATION}"
echo "Open Buoy, grant Screen Recording and Accessibility once, then relaunch it."
