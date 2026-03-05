#!/bin/bash
#
# reset-accessibility.sh
# Resets and re-grants accessibility permission for VoiceFlow
#

set -e

BUNDLE_ID="com.voiceflow.app"
APP_PATH="/Applications/VoiceFlow.app"

echo "🔧 VoiceFlow Accessibility Permission Reset"
echo "=========================================="
echo ""

# Check if app exists
if [ ! -d "$APP_PATH" ]; then
    echo "❌ VoiceFlow not found at $APP_PATH"
    echo "   Run 'make install' first"
    exit 1
fi

echo "📍 Found VoiceFlow at: $APP_PATH"
echo "🆔 Bundle ID: $BUNDLE_ID"
echo ""

# Step 1: Quit VoiceFlow
echo "1️⃣  Quitting VoiceFlow..."
pkill -x VoiceFlow 2>/dev/null && sleep 1 || echo "   (VoiceFlow was not running)"

# Step 2: Try to reset TCC database (requires SIP disabled or Full Disk Access)
echo ""
echo "2️⃣  Attempting to reset accessibility permission..."
if tccutil reset Accessibility "$BUNDLE_ID" 2>/dev/null; then
    echo "   ✅ Permission reset successful!"
else
    echo "   ⚠️  Cannot reset automatically (expected on modern macOS)"
    echo "   📖 Manual step required:"
    echo ""
    echo "      1. Open System Settings → Privacy & Security → Accessibility"
    echo "      2. Find 'VoiceFlow' in the list"
    echo "      3. Click the (-) minus button to REMOVE it"
    echo "      4. Remove ALL VoiceFlow entries if you see multiple"
    echo ""
    read -p "      Press ENTER when you've removed VoiceFlow from Accessibility... " -r
fi

# Step 3: Launch VoiceFlow
echo ""
echo "3️⃣  Launching VoiceFlow..."
open "$APP_PATH"
sleep 2

# Step 4: Instructions for re-granting permission
echo ""
echo "4️⃣  Now grant accessibility permission:"
echo ""
echo "   • VoiceFlow should show a permission dialog"
echo "   • Click 'Grant Permission'"
echo "   • System Settings will open to Accessibility"
echo "   • Click the (+) plus button"
echo "   • Select VoiceFlow.app from Applications"
echo "   • Ensure the toggle is ON"
echo ""
echo "5️⃣  Test Smart Paste:"
echo ""
echo "   • Open Notes or TextEdit"
echo "   • Click in a text field"
echo "   • Press and hold Left Control key"
echo "   • Speak something (e.g., 'Testing smart paste')"
echo "   • Release Control key"
echo "   • Text should auto-paste after transcription"
echo ""
echo "✅ Script complete! Follow the steps above to finish setup."
