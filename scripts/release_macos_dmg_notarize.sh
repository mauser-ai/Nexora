#!/usr/bin/env bash
set -euo pipefail

# Usage:
#   APPLE_TEAM_ID=XXXXXXXXXX \
#   APPLE_ID="you@example.com" \
#   APP_SPECIFIC_PASSWORD="xxxx-xxxx-xxxx-xxxx" \
#   CODESIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
#   ./scripts/release_macos_dmg_notarize.sh
#
# Optional:
#   APP_NAME=mbworkflow
#   OUTPUT_DIR=dist/macos

APP_NAME="${APP_NAME:-mbworkflow}"
OUTPUT_DIR="${OUTPUT_DIR:-dist/macos}"

: "${APPLE_TEAM_ID:?APPLE_TEAM_ID is required}"
: "${APPLE_ID:?APPLE_ID is required}"
: "${APP_SPECIFIC_PASSWORD:?APP_SPECIFIC_PASSWORD is required}"
: "${CODESIGN_IDENTITY:?CODESIGN_IDENTITY is required}"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_PATH="$ROOT_DIR/build/macos/Build/Products/Release/${APP_NAME}.app"
OUT_DIR="$ROOT_DIR/${OUTPUT_DIR}"
DMG_PATH="${OUT_DIR}/${APP_NAME}.dmg"
VOL_NAME="${APP_NAME}"
KEYCHAIN_PROFILE="notary-${APP_NAME}"

TMP_ROOT="$(mktemp -d)"
STAGING_DIR="${TMP_ROOT}/dmg_staging"
RW_DMG="${TMP_ROOT}/${APP_NAME}-rw.dmg"

cleanup() {
  rm -rf "$TMP_ROOT"
}
trap cleanup EXIT

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

echo "==> Verifying app signature"
codesign --verify --deep --strict --verbose=2 "$APP_PATH"
spctl --assess --type execute --verbose "$APP_PATH" || true

echo "==> Creating DMG staging"
mkdir -p "$STAGING_DIR" "$OUT_DIR"
cp -R "$APP_PATH" "$STAGING_DIR/"
ln -s /Applications "$STAGING_DIR/Applications"

echo "==> Building DMG"
hdiutil create -size 300m -fs HFS+ -volname "$VOL_NAME" -srcfolder "$STAGING_DIR" "$RW_DMG" -ov
hdiutil convert "$RW_DMG" -format UDZO -o "$DMG_PATH" -ov

echo "==> Signing DMG"
codesign --force --timestamp --sign "$CODESIGN_IDENTITY" "$DMG_PATH"
codesign --verify --verbose=2 "$DMG_PATH"

echo "==> Configuring notarytool profile (idempotent)"
xcrun notarytool store-credentials "$KEYCHAIN_PROFILE" \
  --apple-id "$APPLE_ID" \
  --team-id "$APPLE_TEAM_ID" \
  --password "$APP_SPECIFIC_PASSWORD" >/dev/null 2>&1 || true

echo "==> Submitting DMG to notarization"
xcrun notarytool submit "$DMG_PATH" \
  --keychain-profile "$KEYCHAIN_PROFILE" \
  --wait

echo "==> Stapling notarization ticket"
xcrun stapler staple "$DMG_PATH"
xcrun stapler validate "$DMG_PATH"

echo "Done."
echo "Notarized DMG: $DMG_PATH"
