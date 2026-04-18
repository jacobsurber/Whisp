#!/bin/bash
set -euo pipefail

# Whisp DMG Creator
# Creates a distributable DMG with an Applications symlink

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/.." || exit 1

NOTARIZE=false
while [[ $# -gt 0 ]]; do
  case $1 in
  --notarize)
    NOTARIZE=true
    shift
    ;;
  *)
    echo "Unknown option: $1"
    echo "Usage: $0 [--notarize]"
    exit 1
    ;;
  esac
done

DEFAULT_VERSION=$(cat VERSION | tr -d '[:space:]')
VERSION="${WHISP_VERSION:-$DEFAULT_VERSION}"
APP_NAME="Whisp"
UNINSTALLER_APP_NAME="Uninstall Whisp"
DMG_NAME="${APP_NAME}-${VERSION}.dmg"
STAGING_DIR=$(mktemp -d)

# Check if app bundle exists
if [ ! -d "${APP_NAME}.app" ]; then
  echo "Error: ${APP_NAME}.app not found. Run 'make build' or 'make build-notarize' first."
  exit 1
fi
if [ ! -d "${UNINSTALLER_APP_NAME}.app" ]; then
  echo "Error: ${UNINSTALLER_APP_NAME}.app not found. Run 'make build' or 'make build-notarize' first."
  exit 1
fi

echo "Creating ${DMG_NAME}..."

# Stage the app and Applications symlink
cp -R "${APP_NAME}.app" "${STAGING_DIR}/"
cp -R "${UNINSTALLER_APP_NAME}.app" "${STAGING_DIR}/"
ln -s /Applications "${STAGING_DIR}/Applications"

# Remove old DMG if it exists
rm -f "${DMG_NAME}"

# Create the DMG
hdiutil create \
  -volname "${APP_NAME}" \
  -srcfolder "${STAGING_DIR}" \
  -ov \
  -format UDZO \
  "${DMG_NAME}"

if [ "$NOTARIZE" = true ]; then
  if [ -z "${WHISP_APPLE_ID:-}" ] || [ -z "${WHISP_APPLE_PASSWORD:-}" ] || [ -z "${WHISP_TEAM_ID:-}" ]; then
    echo "❌ DMG notarization requires the following environment variables:"
    echo "   WHISP_APPLE_ID - Your Apple ID email"
    echo "   WHISP_APPLE_PASSWORD - App-specific password for notarization"
    echo "   WHISP_TEAM_ID - Your Apple Developer Team ID"
    exit 1
  fi

  echo "📤 Submitting ${DMG_NAME} to Apple for notarization..."
  xcrun notarytool submit "${DMG_NAME}" \
    --apple-id "$WHISP_APPLE_ID" \
    --password "$WHISP_APPLE_PASSWORD" \
    --team-id "$WHISP_TEAM_ID" \
    --wait 2>&1 | tee notarization-dmg.log

  if grep -q "status: Accepted" notarization-dmg.log; then
    echo "📎 Stapling notarization ticket to ${DMG_NAME}..."
    if ! xcrun stapler staple "${DMG_NAME}"; then
      echo "❌ Failed to staple notarization ticket for ${DMG_NAME}"
      exit 1
    fi
    rm -f notarization-dmg.log
  else
    echo "❌ DMG notarization failed. Check notarization-dmg.log for details"
    exit 1
  fi
fi

# Clean up
rm -rf "${STAGING_DIR}"

if [ -f "${DMG_NAME}" ]; then
  echo "Created ${DMG_NAME} ($(du -h "${DMG_NAME}" | cut -f1))"
  open -R "${DMG_NAME}"
else
  echo "Error: Failed to create DMG"
  exit 1
fi
