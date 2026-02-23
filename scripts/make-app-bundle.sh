#!/bin/bash
# Creates a proper .app bundle from the SPM-built executable for testing
# Services, Spotlight, and other features that require a bundle.
#
# Usage: ./scripts/make-app-bundle.sh
# Then: open ~/Applications/Cider.app

set -euo pipefail

SCRIPT_DIR_FOR_BUILD=$(cd "$(dirname "$0")" && pwd)
PROJECT_DIR_FOR_BUILD=$(dirname "$SCRIPT_DIR_FOR_BUILD")

# Prefer swift build output (.build/debug), fall back to Xcode DerivedData
SWIFT_BUILD_EXEC="$PROJECT_DIR_FOR_BUILD/.build/debug/Cider"
DERIVED_DATA="$HOME/Library/Developer/Xcode/DerivedData"
XCODE_EXEC=$(find "$DERIVED_DATA" -path "*/Cider-*/Build/Products/Debug/Cider" -not -path "*.app*" -type f 2>/dev/null | head -1)

if [ -f "$SWIFT_BUILD_EXEC" ]; then
    EXEC_PATH="$SWIFT_BUILD_EXEC"
    PRODUCT_DIR=$(dirname "$EXEC_PATH")
elif [ -n "$XCODE_EXEC" ]; then
    EXEC_PATH="$XCODE_EXEC"
    PRODUCT_DIR=$(dirname "$EXEC_PATH")
else
    echo "Error: No Cider executable found. Run 'swift build' or build in Xcode first."
    exit 1
fi
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
PROJECT_DIR=$(dirname "$SCRIPT_DIR")

# Use ~/Applications so macOS treats it as a trusted app location
mkdir -p "$HOME/Applications"
APP_PATH="$HOME/Applications/Cider.app"
CONTENTS="$APP_PATH/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"

echo "Executable: $EXEC_PATH"
echo "Bundle:     $APP_PATH"

# Kill existing Cider if running
killall Cider 2>/dev/null || true
sleep 0.5

# Clean previous bundle
rm -rf "$APP_PATH"
# Also clean old /tmp bundle if it exists
rm -rf /tmp/Cider.app

# Create bundle structure
mkdir -p "$MACOS" "$RESOURCES"

# Copy executable
cp "$EXEC_PATH" "$MACOS/Cider"

# Copy Info.plist to bundle root (where pbs reads it)
cp "$PROJECT_DIR/Sources/Cider/Resources/Info.plist" "$CONTENTS/Info.plist"

# Add required bundle keys if missing
/usr/libexec/PlistBuddy -c "Add :CFBundleIdentifier string com.cider.app" "$CONTENTS/Info.plist" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Add :CFBundleName string Cider" "$CONTENTS/Info.plist" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Add :CFBundleExecutable string Cider" "$CONTENTS/Info.plist" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Add :CFBundlePackageType string APPL" "$CONTENTS/Info.plist" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Add :CFBundleVersion string 1.0" "$CONTENTS/Info.plist" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Add :CFBundleShortVersionString string 1.0" "$CONTENTS/Info.plist" 2>/dev/null || true

# Copy resource bundle (TipTap editor assets)
if [ -d "$PRODUCT_DIR/Cider_Cider.bundle" ]; then
    cp -R "$PRODUCT_DIR/Cider_Cider.bundle" "$RESOURCES/"
fi

# Unregister old entries and register fresh
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -u "$APP_PATH" 2>/dev/null || true
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$APP_PATH"
/System/Library/CoreServices/pbs -flush 2>/dev/null || true
/System/Library/CoreServices/pbs -update

echo ""
echo "Done! Launch with:"
echo "  open ~/Applications/Cider.app"
echo ""
echo "After launching, wait ~10 seconds, then check Services in other apps."
echo "If still not visible, try: System Settings → Keyboard → Keyboard Shortcuts → Services"
