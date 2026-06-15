#!/usr/bin/env bash
set -euo pipefail

# Usage:
#   APPLE_TEAM_ID=XXXXXXXXXX \
#   APPLE_ID="you@example.com" \
#   APP_SPECIFIC_PASSWORD="xxxx-xxxx-xxxx-xxxx" \
#   CODESIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
#   ./scripts/release_macos_notarize.sh
#
# Optional:
#   APP_NAME=mbworkflow
#   BUNDLE_ID=mb.app.com
#   OUTPUT_DIR=dist/macos

APP_NAME="${APP_NAME:-mbworkflow}"
BUNDLE_ID="${BUNDLE_ID:-mb.app.com}"
OUTPUT_DIR="${OUTPUT_DIR:-dist/macos}"

: "${APPLE_TEAM_ID:?APPLE_TEAM_ID is required}"
: "${APPLE_ID:?APPLE_ID is required}"
: "${APP_SPECIFIC_PASSWORD:?APP_SPECIFIC_PASSWORD is required}"
: "${CODESIGN_IDENTITY:?CODESIGN_IDENTITY is required}"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_PATH="$ROOT_DIR/build/macos/Build/Products/Release/${APP_NAME}.app"
ZIP_PATH="$ROOT_DIR/${OUTPUT_DIR}/${APP_NAME}.zip"
KEYCHAIN_PROFILE="notary-${APP_NAME}"

echo "==> Building macOS release"
cd "$ROOT_DIR"
flutter build macos

if [[ ! -d "$APP_PATH" ]]; then
  echo "App not found at $APP_PATH"
  exit 1
fi

echo "==> Signing app with: $CODESIGN_IDENTITY"
codesign --force --deep --options runtime --timestamp \
  --sign "$CODESIGN_IDENTITY" \
  "$APP_PATH"

echo "==> Verifying signature"
codesign --verify --deep --strict --verbose=2 "$APP_PATH"
spctl --assess --type execute --verbose "$APP_PATH" || true

echo "==> Packaging zip"
mkdir -p "$(dirname "$ZIP_PATH")"
rm -f "$ZIP_PATH"
ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$ZIP_PATH"

echo "==> Configuring notarytool profile (idempotent)"
xcrun notarytool store-credentials "$KEYCHAIN_PROFILE" \
  --apple-id "$APPLE_ID" \
  --team-id "$APPLE_TEAM_ID" \
  --password "$APP_SPECIFIC_PASSWORD" >/dev/null 2>&1 || true

echo "==> Submitting to Apple notarization"
xcrun notarytool submit "$ZIP_PATH" \
  --keychain-profile "$KEYCHAIN_PROFILE" \
  --wait

echo "==> Stapling ticket to app"
xcrun stapler staple "$APP_PATH"
xcrun stapler validate "$APP_PATH"

echo "==> Re-packaging notarized app"
ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$ZIP_PATH"

echo "Done."
echo "Notarized app: $APP_PATH"
echo "Notarized zip: $ZIP_PATH"
echo "Bundle ID: $BUNDLE_ID"
