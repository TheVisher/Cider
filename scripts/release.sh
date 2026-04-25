#!/bin/bash
#
# Cider Release Script
# Usage: ./scripts/release.sh <version>
# Example: ./scripts/release.sh 0.1.0-beta.1
#
# Prerequisites:
#   - Developer ID Application certificate installed in Keychain
#   - Notarization credentials stored: xcrun notarytool store-credentials "CiderNotary"
#   - gh CLI authenticated: gh auth login
#
# What it does:
#   1. Updates version number in Xcode project
#   2. Builds a release archive
#   3. Exports with Developer ID signing
#   4. Notarizes with Apple
#   5. Creates a .dmg
#   6. Creates a GitHub Release with the .dmg attached
#

set -euo pipefail

# --- Configuration ---
SCHEME="CiderApp"
PROJECT="Cider.xcodeproj"
TEAM_ID="S9SS3NNGSW"
BUNDLE_ID="com.cider.app"
NOTARY_PROFILE="CiderNotary"
EXPORT_OPTIONS="scripts/ExportOptions.plist"

# --- Paths ---
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="$ROOT_DIR/build"
ARCHIVE_PATH="$BUILD_DIR/Cider.xcarchive"
EXPORT_DIR="$BUILD_DIR/export"
DMG_DIR="$BUILD_DIR/dmg"
XCODE_DERIVED_DATA_DIR="$ROOT_DIR/.build/xcode/DerivedData"
XCODE_PACKAGE_DIR="$ROOT_DIR/.build/xcode/SourcePackages"

# --- Colors ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

step() { echo -e "\n${BLUE}==>${NC} ${1}"; }
success() { echo -e "${GREEN}✓${NC} ${1}"; }
warn() { echo -e "${YELLOW}⚠${NC} ${1}"; }
fail() { echo -e "${RED}✗${NC} ${1}"; exit 1; }

find_sparkle_tool() {
    local tool_name="$1"
    local candidate
    for candidate in \
        "$ROOT_DIR/.build/xcode/SourcePackages/artifacts/sparkle/Sparkle/bin/$tool_name" \
        "$ROOT_DIR/.build/artifacts/sparkle/Sparkle/bin/$tool_name" \
        "$ROOT_DIR/.build/checkouts/Sparkle/bin/$tool_name" \
        "$ROOT_DIR/.build/checkouts/Sparkle/$tool_name"; do
        if [ -x "$candidate" ]; then
            echo "$candidate"
            return 0
        fi
    done
    return 1
}

# --- Validate arguments ---
if [ $# -lt 1 ]; then
    echo "Usage: $0 <version> [--skip-notarize] [--skip-github]"
    echo "Example: $0 0.1.0-beta.1"
    exit 1
fi

VERSION="$1"
SKIP_NOTARIZE=false
SKIP_GITHUB=false

for arg in "${@:2}"; do
    case "$arg" in
        --skip-notarize) SKIP_NOTARIZE=true ;;
        --skip-github) SKIP_GITHUB=true ;;
        *) warn "Unknown flag: $arg" ;;
    esac
done

cd "$ROOT_DIR"

# --- Preflight checks ---
step "Preflight checks"

# Xcode project exists
[ -d "$PROJECT" ] || fail "Xcode project not found: $PROJECT"

# Developer ID certificate
if ! security find-identity -v -p codesigning | grep -q "Developer ID Application"; then
    fail "Developer ID Application certificate not found in Keychain"
fi
success "Developer ID certificate found"

# Notarization credentials (unless skipping)
if [ "$SKIP_NOTARIZE" = false ]; then
    if ! xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" 2>/dev/null | head -1 > /dev/null 2>&1; then
        echo ""
        warn "Notarization credentials not found for profile '$NOTARY_PROFILE'"
        echo "  Run this first (one-time setup):"
        echo "  xcrun notarytool store-credentials \"$NOTARY_PROFILE\" --apple-id YOUR_APPLE_ID --team-id $TEAM_ID"
        echo ""
        echo "  You'll be prompted for an app-specific password."
        echo "  Generate one at: https://appleid.apple.com/account/manage → Sign-In and Security → App-Specific Passwords"
        echo ""
        fail "Set up notarization credentials, then re-run this script"
    fi
    success "Notarization credentials found"
fi

# gh CLI (unless skipping)
if [ "$SKIP_GITHUB" = false ]; then
    command -v gh > /dev/null 2>&1 || fail "gh CLI not installed (brew install gh)"
    gh auth status > /dev/null 2>&1 || fail "gh CLI not authenticated (run: gh auth login)"
    success "GitHub CLI authenticated"
fi

# --- Step 1: Update version ---
step "Setting version to $VERSION"

# Extract build number: increment from current, or use 1
CURRENT_BUILD=$(grep -A1 'CURRENT_PROJECT_VERSION' "$PROJECT/project.pbxproj" | grep -o '[0-9]*' | head -1)
BUILD_NUMBER=$((CURRENT_BUILD + 1))

# Update MARKETING_VERSION and CURRENT_PROJECT_VERSION in pbxproj
sed -i '' "s/MARKETING_VERSION = [^;]*/MARKETING_VERSION = $VERSION/" "$PROJECT/project.pbxproj"
sed -i '' "s/CURRENT_PROJECT_VERSION = [^;]*/CURRENT_PROJECT_VERSION = $BUILD_NUMBER/" "$PROJECT/project.pbxproj"

success "Version: $VERSION (build $BUILD_NUMBER)"

# --- Step 2: Clean build directory ---
step "Cleaning build directory"
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"
success "Clean"

# --- Step 3: Archive ---
step "Building release archive (this may take a minute)"

mkdir -p "$XCODE_DERIVED_DATA_DIR" "$XCODE_PACKAGE_DIR"

xcodebuild archive \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration Release \
    -archivePath "$ARCHIVE_PATH" \
    -derivedDataPath "$XCODE_DERIVED_DATA_DIR" \
    -clonedSourcePackagesDirPath "$XCODE_PACKAGE_DIR" \
    -destination "generic/platform=macOS" \
    CODE_SIGN_IDENTITY="Developer ID Application" \
    DEVELOPMENT_TEAM="$TEAM_ID" \
    CODE_SIGN_STYLE=Manual \
    ENABLE_HARDENED_RUNTIME=YES \
    ARCHS=arm64 \
    ONLY_ACTIVE_ARCH=NO \
    OTHER_CODE_SIGN_FLAGS="--options=runtime" \
    2>&1 | tail -5

[ -d "$ARCHIVE_PATH" ] || fail "Archive failed — no .xcarchive produced"
success "Archive created"

# --- Step 4: Export ---
step "Exporting with Developer ID signing"

xcodebuild -exportArchive \
    -archivePath "$ARCHIVE_PATH" \
    -exportPath "$EXPORT_DIR" \
    -exportOptionsPlist "$EXPORT_OPTIONS" \
    2>&1 | tail -5

APP_PATH="$EXPORT_DIR/Cider.app"
[ -d "$APP_PATH" ] || fail "Export failed — no .app produced"
success "Exported: $APP_PATH"

# Verify code signing
codesign --verify --deep --strict "$APP_PATH" 2>&1 || fail "Code signing verification failed"
success "Code signature valid"

# --- Step 5: Notarize ---
if [ "$SKIP_NOTARIZE" = true ]; then
    warn "Skipping notarization (--skip-notarize)"
else
    step "Notarizing with Apple (this takes 5-10 minutes)"

    # Create a zip for notarization submission
    NOTARIZE_ZIP="$BUILD_DIR/Cider-notarize.zip"
    ditto -c -k --keepParent "$APP_PATH" "$NOTARIZE_ZIP"

    NOTARIZE_OUTPUT=$(xcrun notarytool submit "$NOTARIZE_ZIP" \
        --keychain-profile "$NOTARY_PROFILE" \
        --wait \
        2>&1)
    echo "$NOTARIZE_OUTPUT"

    # Check if notarization succeeded
    if echo "$NOTARIZE_OUTPUT" | grep -q "status: Invalid"; then
        echo ""
        warn "Notarization failed. Check the log:"
        SUBMISSION_ID=$(echo "$NOTARIZE_OUTPUT" | grep "id:" | head -1 | awk '{print $2}')
        if [ -n "$SUBMISSION_ID" ]; then
            echo "  xcrun notarytool log $SUBMISSION_ID --keychain-profile $NOTARY_PROFILE"
        fi
        fail "Notarization returned Invalid status"
    fi

    # Staple the notarization ticket
    step "Stapling notarization ticket"
    xcrun stapler staple "$APP_PATH" 2>&1 || fail "Stapling failed"
    success "Notarization complete and stapled"

    rm -f "$NOTARIZE_ZIP"
fi

# --- Step 6: Create DMG ---
step "Creating .dmg"

DMG_NAME="Cider-${VERSION}.dmg"
DMG_PATH="$BUILD_DIR/$DMG_NAME"
DMG_STAGING="$DMG_DIR/staging"

mkdir -p "$DMG_STAGING"
cp -R "$APP_PATH" "$DMG_STAGING/"

# Create a symlink to Applications for drag-and-drop install
ln -s /Applications "$DMG_STAGING/Applications"

# Create DMG using hdiutil
hdiutil create \
    -volname "Cider" \
    -srcfolder "$DMG_STAGING" \
    -ov \
    -format UDZO \
    "$DMG_PATH" \
    2>&1

[ -f "$DMG_PATH" ] || fail "DMG creation failed"

# Sign the DMG itself
codesign --sign "Developer ID Application: Erik Holum (S9SS3NNGSW)" "$DMG_PATH" 2>&1
success "DMG created: $DMG_PATH"

# Clean up staging
rm -rf "$DMG_DIR"

# --- Step 7: Generate Sparkle appcast ---
step "Generating Sparkle appcast"

APPCAST_DIR="$BUILD_DIR/appcast"
RELEASES_DIR="$APPCAST_DIR/releases"
mkdir -p "$RELEASES_DIR"

# Copy the DMG to releases dir (generate_appcast scans this directory)
cp "$DMG_PATH" "$RELEASES_DIR/"

# If an existing appcast.xml exists in gh-pages, download it so generate_appcast
# can append to it rather than starting fresh
REPO_NAME=$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null || echo "")
if [ -n "$REPO_NAME" ]; then
    EXISTING_APPCAST_URL="https://raw.githubusercontent.com/${REPO_NAME}/gh-pages/appcast.xml"
    curl -sL -o "$APPCAST_DIR/appcast.xml" "$EXISTING_APPCAST_URL" 2>/dev/null || true
    # If we got an HTML error page instead of XML, remove it
    if [ -f "$APPCAST_DIR/appcast.xml" ] && ! head -1 "$APPCAST_DIR/appcast.xml" | grep -q "xml"; then
        rm -f "$APPCAST_DIR/appcast.xml"
    fi
fi

# Find Sparkle's generate_appcast tool
GENERATE_APPCAST="$(find_sparkle_tool generate_appcast || true)"

if [ -z "$GENERATE_APPCAST" ]; then
    warn "generate_appcast not found — skipping appcast generation"
    warn "Run 'swift build' once to fetch Sparkle artifacts, then re-run"
else
    # Set the download URL prefix so appcast items point to GitHub Releases
    DOWNLOAD_URL_PREFIX="https://github.com/${REPO_NAME}/releases/download/v${VERSION}"

    "$GENERATE_APPCAST" \
        --download-url-prefix "$DOWNLOAD_URL_PREFIX/" \
        --link "https://github.com/${REPO_NAME}" \
        -o "$APPCAST_DIR/appcast.xml" \
        "$RELEASES_DIR" \
        2>&1

    if [ -f "$APPCAST_DIR/appcast.xml" ]; then
        success "Appcast generated: $APPCAST_DIR/appcast.xml"
    else
        warn "Appcast generation produced no output"
    fi
fi

# --- Step 8: GitHub Release ---
if [ "$SKIP_GITHUB" = true ]; then
    warn "Skipping GitHub release (--skip-github)"
else
    step "Creating GitHub Release"

    TAG="v${VERSION}"

    # Create git tag
    git tag -a "$TAG" -m "Release $VERSION" 2>/dev/null || warn "Tag $TAG already exists"
    git push origin "$TAG" 2>/dev/null || warn "Tag $TAG already pushed"

    # Create release
    gh release create "$TAG" \
        "$DMG_PATH" \
        --title "Cider $VERSION" \
        --notes "## Cider $VERSION

### Download
Download **$DMG_NAME**, open it, and drag Cider to your Applications folder.

### What's New
- First public beta release

### Requirements
- macOS 26.0 or later
- Apple Silicon Mac" \
        --prerelease

    success "GitHub Release created: $TAG"

    # --- Step 9: Publish appcast to gh-pages ---
    if [ -f "$APPCAST_DIR/appcast.xml" ]; then
        step "Publishing appcast to GitHub Pages"

        GH_PAGES_DIR="$BUILD_DIR/gh-pages"
        rm -rf "$GH_PAGES_DIR"

        # Clone or create gh-pages branch
        if git ls-remote --heads origin gh-pages | grep -q gh-pages; then
            git clone --branch gh-pages --single-branch --depth 1 \
                "$(git remote get-url origin)" "$GH_PAGES_DIR" 2>&1
        else
            mkdir -p "$GH_PAGES_DIR"
            cd "$GH_PAGES_DIR"
            git init
            git checkout -b gh-pages
            git remote add origin "$(cd "$ROOT_DIR" && git remote get-url origin)"
            cd "$ROOT_DIR"
        fi

        # Copy appcast
        cp "$APPCAST_DIR/appcast.xml" "$GH_PAGES_DIR/appcast.xml"

        # Commit and push
        cd "$GH_PAGES_DIR"
        git add appcast.xml
        git commit -m "Update appcast for $VERSION" 2>/dev/null || warn "No appcast changes to commit"
        git push origin gh-pages 2>&1 || warn "Failed to push gh-pages — you may need to push manually"
        cd "$ROOT_DIR"

        success "Appcast published to gh-pages"
        echo "  URL: https://thevisher.github.io/Cider/appcast.xml"

        rm -rf "$GH_PAGES_DIR"
    fi
fi

# --- Done ---
echo ""
echo -e "${GREEN}═══════════════════════════════════════${NC}"
echo -e "${GREEN}  Release $VERSION complete!${NC}"
echo -e "${GREEN}═══════════════════════════════════════${NC}"
echo ""
echo "  DMG: $DMG_PATH"
echo "  Size: $(du -h "$DMG_PATH" | cut -f1)"
if [ "$SKIP_GITHUB" = false ]; then
    echo "  GitHub: https://github.com/$(gh repo view --json nameWithOwner -q .nameWithOwner)/releases/tag/v${VERSION}"
fi
echo ""
