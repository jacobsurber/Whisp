#!/bin/bash
set -euo pipefail

# Whisp Release Build Script
# For development, use: swift build && swift run
# This script is for creating distributable releases

# Change to repo root (parent of scripts/)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/.." || exit 1

source "$SCRIPT_DIR/swiftpm-preflight.sh"
ensure_swiftpm_manifest_is_healthy "$PWD" || exit 1
source "$SCRIPT_DIR/signing-common.sh"

# Parse command line arguments
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

# Generate version info
GIT_HASH=$(git rev-parse HEAD 2>/dev/null || echo "unknown")
BUILD_DATE=$(date '+%Y-%m-%d')

# Read version from VERSION file or use environment variable
DEFAULT_VERSION=$(cat VERSION | tr -d '[:space:]')
VERSION="${WHISP_VERSION:-$DEFAULT_VERSION}"
UNINSTALLER_APP_NAME="Uninstall Whisp"
UNINSTALLER_APP_PATH="${UNINSTALLER_APP_NAME}.app"
UNINSTALLER_EXECUTABLE="WhispUninstaller"

echo "🎙️ Building Whisp version $VERSION..."

# Update Info.plist with current version
if [ -f "Info.plist" ]; then
  echo "Updating Info.plist version to $VERSION..."
  # Update CFBundleShortVersionString
  /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" Info.plist 2>/dev/null ||
    sed -i '' "s|<key>CFBundleShortVersionString</key>[[:space:]]*<string>[^<]*</string>|<key>CFBundleShortVersionString</key><string>$VERSION</string>|" Info.plist

  # Update CFBundleVersion (remove dots for build number)
  BUILD_NUMBER="${VERSION//./}"
  /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" Info.plist 2>/dev/null ||
    sed -i '' "s|<key>CFBundleVersion</key>[[:space:]]*<string>[^<]*</string>|<key>CFBundleVersion</key><string>$BUILD_NUMBER</string>|" Info.plist
fi

# Clean previous builds
rm -rf .build/release
rm -rf .build/apple
rm -rf Whisp.app
rm -rf "$UNINSTALLER_APP_PATH"
rm -f Sources/AudioProcessorCLI

# Create version file from template
if [ -f "Sources/VersionInfo.swift.template" ]; then
  sed -e "s/VERSION_PLACEHOLDER/$VERSION/g" \
    -e "s/GIT_HASH_PLACEHOLDER/$GIT_HASH/g" \
    -e "s/BUILD_DATE_PLACEHOLDER/$BUILD_DATE/g" \
    Sources/VersionInfo.swift.template >Sources/Utilities/VersionInfo.swift
  echo "Generated VersionInfo.swift from template"
else
  echo "Warning: VersionInfo.swift.template not found, using fallback"
  cat >Sources/Utilities/VersionInfo.swift <<EOF
import Foundation

struct VersionInfo {
    static let version = "$VERSION"
    static let gitHash = "$GIT_HASH"
    static let buildDate = "$BUILD_DATE"

    static var displayVersion: String {
        if gitHash != "unknown" && !gitHash.isEmpty {
            let shortHash = String(gitHash.prefix(7))
            return "\(version) (\(shortHash))"
        }
        return version
    }

    static var fullVersionInfo: String {
        var info = "Whisp \(version)"
        if gitHash != "unknown" && !gitHash.isEmpty {
            let shortHash = String(gitHash.prefix(7))
            info += " • \(shortHash)"
        }
        if buildDate.count > 0 {
            info += " • \(buildDate)"
        }
        return info
    }
}
EOF
fi

# Build for release
echo "📦 Building for release..."
build_status=0
set +e
swift build -c release --arch arm64 --arch x86_64
build_status=$?
set -e

if [ "$build_status" -ne 0 ]; then
  echo "⚠️ swift build exited with status $build_status; validating release binaries before failing..."
fi

# Check for the actual binary instead of exit code (swift-collections emits spurious errors)
if [ ! -f ".build/apple/Products/Release/Whisp" ]; then
  echo "❌ Build failed - binary not found!"
  exit 1
fi
if [ ! -f ".build/apple/Products/Release/${UNINSTALLER_EXECUTABLE}" ]; then
  echo "❌ Build failed - ${UNINSTALLER_EXECUTABLE} binary not found!"
  exit 1
fi

if [ "$build_status" -ne 0 ]; then
  echo "⚠️ Continuing despite non-zero swift build exit because release binaries were produced."
fi

# Create app bundle
echo "Creating app bundle..."
mkdir -p Whisp.app/Contents/MacOS
mkdir -p Whisp.app/Contents/Resources
mkdir -p Whisp.app/Contents/Resources/bin

# Set build number for Info.plist
BUILD_NUMBER="${VERSION//./}"

# Copy executable (universal binary)
cp .build/apple/Products/Release/Whisp Whisp.app/Contents/MacOS/

# Copy dashboard logo
if [ -f "Sources/Resources/DashboardLogo.jpg" ]; then
  cp Sources/Resources/DashboardLogo.jpg Whisp.app/Contents/Resources/
  echo "Copied dashboard logo"
fi

# Copy verify scripts
if [ -f "Sources/verify_parakeet.py" ]; then
  cp Sources/verify_parakeet.py Whisp.app/Contents/Resources/
  echo "Copied verify_parakeet.py"
fi

# Copy ML daemon entrypoint and package
if [ -f "Sources/ml_daemon.py" ]; then
  cp Sources/ml_daemon.py Whisp.app/Contents/Resources/
  echo "Copied ML daemon entrypoint"
fi
if [ -d "Sources/ml" ]; then
  cp -R Sources/ml Whisp.app/Contents/Resources/
  # Remove __pycache__ directories
  find Whisp.app/Contents/Resources/ml -name "__pycache__" -type d -exec rm -rf {} + 2>/dev/null || true
  echo "Copied ml package"
else
  echo "⚠️ Sources/ml package not found, ML daemon will not work"
fi

# Bundle uv (Apple Silicon). Prefer repo copy; else fall back to system uv if available
if [ -f "Sources/Resources/bin/uv" ]; then
  cp Sources/Resources/bin/uv Whisp.app/Contents/Resources/bin/uv
  chmod +x Whisp.app/Contents/Resources/bin/uv
  echo "Bundled uv binary (from repo)"
else
  if command -v uv >/dev/null 2>&1; then
    UV_PATH=$(command -v uv)
    cp "$UV_PATH" Whisp.app/Contents/Resources/bin/uv
    chmod +x Whisp.app/Contents/Resources/bin/uv
    echo "Bundled uv binary (from system: $UV_PATH)"
  else
    echo "ℹ️ No bundled uv found and no system uv available; runtime will try PATH"
  fi
fi

# Bundle pyproject.toml and uv.lock if present
if [ -f "Sources/Resources/pyproject.toml" ]; then
  cp Sources/Resources/pyproject.toml Whisp.app/Contents/Resources/pyproject.toml
  echo "Bundled pyproject.toml"
else
  echo "ℹ️ No pyproject.toml found in Sources/Resources"
fi

# Note: AudioProcessorCLI binary no longer needed - using direct Swift audio processing

# Create proper Info.plist
echo "Creating Info.plist..."
cat >Whisp.app/Contents/Info.plist <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>Whisp</string>
    <key>CFBundleIdentifier</key>
    <string>com.whisp.app</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>Whisp</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
    <key>CFBundleVersion</key>
    <string>$BUILD_NUMBER</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSMicrophoneUsageDescription</key>
    <string>Whisp needs access to your microphone to record audio for transcription.</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSAppTransportSecurity</key>
    <dict>
        <key>NSExceptionDomains</key>
        <dict>
            <key>api.openai.com</key>
            <dict>
                <key>NSIncludesSubdomains</key>
                <true/>
            </dict>
            <key>generativelanguage.googleapis.com</key>
            <dict>
                <key>NSIncludesSubdomains</key>
                <true/>
            </dict>
            <key>huggingface.co</key>
            <dict>
                <key>NSIncludesSubdomains</key>
                <true/>
            </dict>
        </dict>
    </dict>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
</dict>
</plist>
EOF

# Generate app icon from our source image
if [ -f "WhispIcon.png" ]; then
  "$SCRIPT_DIR/generate-icons.sh"

  # Create proper icns file directly in app bundle
  if command -v iconutil >/dev/null 2>&1; then
    iconutil -c icns Whisp.iconset -o Whisp.app/Contents/Resources/AppIcon.icns 2>/dev/null || echo "Note: iconutil failed, app will use default icon"
  fi

  # Clean up temporary files
  rm -rf Whisp.iconset
  rm -f AppIcon.icns # Remove any stray icns file from root
else
  echo "⚠️ WhispIcon.png not found, app will use default icon"
fi

# Make executable
chmod +x Whisp.app/Contents/MacOS/Whisp

# Create uninstaller app bundle
echo "Creating uninstaller app bundle..."
mkdir -p "$UNINSTALLER_APP_PATH/Contents/MacOS"
mkdir -p "$UNINSTALLER_APP_PATH/Contents/Resources"

cp ".build/apple/Products/Release/${UNINSTALLER_EXECUTABLE}" "$UNINSTALLER_APP_PATH/Contents/MacOS/${UNINSTALLER_EXECUTABLE}"
chmod +x "$UNINSTALLER_APP_PATH/Contents/MacOS/${UNINSTALLER_EXECUTABLE}"

cat >"$UNINSTALLER_APP_PATH/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleExecutable</key>
  <string>${UNINSTALLER_EXECUTABLE}</string>
  <key>CFBundleIdentifier</key>
  <string>com.whisp.app.uninstaller</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>${UNINSTALLER_APP_NAME}</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>$VERSION</string>
  <key>CFBundleVersion</key>
  <string>$BUILD_NUMBER</string>
  <key>LSMinimumSystemVersion</key>
  <string>14.0</string>
</dict>
</plist>
EOF

# Create entitlements file for hardened runtime
echo "Creating entitlements for hardened runtime..."
cat >Whisp.entitlements <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.device.audio-input</key>
    <true/>
    <key>com.apple.security.network.client</key>
    <true/>
</dict>
</plist>
EOF

cat >WhispUninstaller.entitlements <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict/>
</plist>
EOF

# Code sign the app. Prefer a stable identity so macOS privacy permissions persist across rebuilds.
SIGNING_IDENTITY="$(whisp_detect_signing_identity || true)"
SIGNING_NAME="$(whisp_detect_signing_identity_name || true)"

if [ -n "$SIGNING_IDENTITY" ]; then
  if [ -n "$SIGNING_NAME" ]; then
    echo "🔍 Using signing identity: $SIGNING_NAME"
  fi

  echo "🔏 Code signing app with stable identity..."
  whisp_sign_app_bundle \
    "Whisp.app" \
    "Whisp.entitlements" \
    "Whisp.app/Contents/Resources/bin/uv" \
    "$SIGNING_IDENTITY" \
    "com.whisp.app"

  whisp_sign_app_bundle \
    "$UNINSTALLER_APP_PATH" \
    "WhispUninstaller.entitlements" \
    "" \
    "$SIGNING_IDENTITY" \
    "com.whisp.app.uninstaller"
else
  echo "⚠️  No stable signing identity found. Falling back to ad-hoc signing."
  echo "⚠️  macOS may re-prompt for Microphone, Accessibility, and Input Monitoring after each rebuild."
  echo "💡 Run 'make setup-local-signing' once to create a persistent local signing identity for development."

  whisp_sign_app_bundle \
    "Whisp.app" \
    "Whisp.entitlements" \
    "Whisp.app/Contents/Resources/bin/uv" \
    "" \
    "com.whisp.app"

  whisp_sign_app_bundle \
    "$UNINSTALLER_APP_PATH" \
    "WhispUninstaller.entitlements" \
    "" \
    "" \
    "com.whisp.app.uninstaller"
fi

echo "🔍 Verifying signature..."
codesign --verify --verbose Whisp.app
codesign --verify --verbose "$UNINSTALLER_APP_PATH"
echo "✅ App signed successfully"

# Clean up entitlements file
rm -f Whisp.entitlements
rm -f WhispUninstaller.entitlements

notarize_app_bundle() {
  local app_path="$1"
  local archive_name="$2"
  local log_name="$3"

  echo "Creating zip for notarization: $app_path..."
  ditto -c -k --keepParent "$app_path" "$archive_name"

  echo "📤 Submitting $app_path to Apple for notarization..."
  xcrun notarytool submit "$archive_name" \
    --apple-id "$WHISP_APPLE_ID" \
    --password "$WHISP_APPLE_PASSWORD" \
    --team-id "$WHISP_TEAM_ID" \
    --wait 2>&1 | tee "$log_name"

  if grep -q "status: Accepted" "$log_name"; then
    echo "📎 Stapling notarization ticket to $app_path..."
    if ! xcrun stapler staple "$app_path"; then
      echo "❌ Failed to staple notarization ticket for $app_path"
      exit 1
    fi
  else
    echo "❌ Notarization failed for $app_path. Check $log_name for details"
    exit 1
  fi

  rm -f "$archive_name" "$log_name"
}

# Notarization (requires code signing first)
if [ "$NOTARIZE" = true ]; then
  echo ""
  echo "🔐 Starting notarization process..."

  if ! whisp_is_developer_id_identity "$SIGNING_IDENTITY"; then
    echo "❌ Notarization requires a Developer ID Application signing identity"
    echo "   Current signing identity: ${SIGNING_NAME:-$SIGNING_IDENTITY}"
    echo "   Provide CODE_SIGN_IDENTITY with a Developer ID Application certificate or install one in Keychain."
    exit 1
  fi

  # Check for required environment variables
  if [ -z "${WHISP_APPLE_ID:-}" ] || [ -z "${WHISP_APPLE_PASSWORD:-}" ] || [ -z "${WHISP_TEAM_ID:-}" ]; then
    echo "❌ Notarization requires the following environment variables:"
    echo "   WHISP_APPLE_ID - Your Apple ID email"
    echo "   WHISP_APPLE_PASSWORD - App-specific password for notarization"
    echo "   WHISP_TEAM_ID - Your Apple Developer Team ID"
    echo ""
    echo "To create an app-specific password:"
    echo "1. Go to https://appleid.apple.com/account/manage"
    echo "2. Sign in and go to Security > App-Specific Passwords"
    echo "3. Generate a new password for Whisp notarization"
    echo ""
    exit 1
  fi

  # Check if app is signed
  if codesign -dvvv Whisp.app 2>&1 | grep -q "Signature=adhoc"; then
    echo "❌ App must be properly signed before notarization (not adhoc signed)"
    echo "Please ensure CODE_SIGN_IDENTITY is set or a Developer ID is available"
    exit 1
  fi

  notarize_app_bundle "Whisp.app" "Whisp.zip" "notarization.log"
  notarize_app_bundle "$UNINSTALLER_APP_PATH" "WhispUninstaller.zip" "notarization-uninstaller.log"
fi

echo "✅ Build complete!"
echo ""

if [ -n "${CI:-}" ] || [ -n "${GITHUB_ACTIONS:-}" ]; then
  echo "📦 Built artifact: Whisp.app"
else
  open -R Whisp.app
fi
