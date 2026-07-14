#!/bin/bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DERIVED_DATA="${TMPDIR:-/tmp}/BuoyLocalDerivedData"
PRODUCT="$DERIVED_DATA/Build/Products/Release/Buoy.app"
DESTINATION="/Applications/Buoy.app"

identity="$({ security find-identity -v -p codesigning || true; } \
    | awk '/Apple Development:/ { print $2; exit }')"

if [[ -z "$identity" ]]; then
    echo "No Apple Development signing identity was found in the login keychain." >&2
    echo "Install or create one in Xcode before building Buoy so macOS can keep its privacy grants stable." >&2
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
codesign --force --options runtime --sign "$identity" "$PRODUCT"
codesign --verify --deep --strict --verbose=2 "$PRODUCT"

echo "Installing ${DESTINATION}…"
pkill -x Buoy 2>/dev/null || true
rm -rf "$DESTINATION"
ditto "$PRODUCT" "$DESTINATION"
codesign --verify --deep --strict --verbose=2 "$DESTINATION"

echo "Installed a stable signed copy at ${DESTINATION}"
echo "Open Buoy, grant Screen Recording and Accessibility once, then relaunch it."
