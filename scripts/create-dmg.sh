#!/bin/bash

# VoiceFlow DMG Creator
# Creates a distributable DMG with an Applications symlink

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/.." || exit 1

VERSION=$(cat VERSION | tr -d '[:space:]')
APP_NAME="VoiceFlow"
DMG_NAME="${APP_NAME}-${VERSION}.dmg"
STAGING_DIR=$(mktemp -d)

# Check if app bundle exists
if [ ! -d "${APP_NAME}.app" ]; then
  echo "Error: ${APP_NAME}.app not found. Run 'make build' first."
  exit 1
fi

echo "Creating ${DMG_NAME}..."

# Stage the app and Applications symlink
cp -R "${APP_NAME}.app" "${STAGING_DIR}/"
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

# Clean up
rm -rf "${STAGING_DIR}"

if [ -f "${DMG_NAME}" ]; then
  echo "Created ${DMG_NAME} ($(du -h "${DMG_NAME}" | cut -f1))"
  open -R "${DMG_NAME}"
else
  echo "Error: Failed to create DMG"
  exit 1
fi
