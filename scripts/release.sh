#!/usr/bin/env bash
set -euo pipefail

# Build, sign, notarize, and package PDFBrochure as a distributable DMG, then
# regenerate the Sparkle appcast. Adapted from AudioXplorer's release.sh.
#
# Requirements:
#   - Xcode command line tools
#   - create-dmg:           brew install create-dmg
#   - A "Developer ID Application" certificate in your login keychain
#   - A notarytool keychain profile (one-time setup):
#       xcrun notarytool store-credentials PB_NOTARY \
#           --apple-id you@example.com \
#           --team-id YOURTEAMID \
#           --password <app-specific-password>
#   - Sparkle EdDSA private key in your login keychain under account
#     "pdfbrochure" (separate from AudioXplorer's default "ed25519" account)
#
# Usage:
#   ./scripts/release.sh                    # build + sign + notarize
#   SKIP_NOTARIZE=1 ./scripts/release.sh    # local test build, no notarization

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"

APP_NAME="PDFBrochure"
SCHEME="PDFBrochure"
CONFIG="Release"
BUILD_DIR="$PROJECT_DIR/build"
RELEASE_DIR="$BUILD_DIR/$CONFIG"
APP_PATH="$RELEASE_DIR/$APP_NAME.app"
DIST_DIR="$PROJECT_DIR/dist"
SPARKLE_ACCOUNT="pdfbrochure"

SIGN_IDENTITY="${SIGN_IDENTITY:-Developer ID Application}"
NOTARY_PROFILE="${NOTARY_PROFILE:-PB_NOTARY}"

# project.yml drives Info.plist generation, so we have to point at the version
# fields there rather than at the generated Info.plist (which only exists after
# a build).
VERSION=$(awk '/CFBundleShortVersionString:/ {gsub(/[",]/,""); print $2; exit}' "$PROJECT_DIR/project.yml")
DMG_NAME="$APP_NAME-$VERSION.dmg"
DMG_PATH="$DIST_DIR/$DMG_NAME"

echo "==> Building $APP_NAME $VERSION ($CONFIG)"
xcodebuild \
    -project "$APP_NAME.xcodeproj" \
    -scheme "$SCHEME" \
    -configuration "$CONFIG" \
    -derivedDataPath "$BUILD_DIR/DerivedData" \
    CONFIGURATION_BUILD_DIR="$RELEASE_DIR" \
    clean build

if [[ ! -d "$APP_PATH" ]]; then
    echo "error: $APP_PATH not found after build" >&2
    exit 1
fi

echo "==> Signing app with hardened runtime"
codesign --force --deep --options runtime --timestamp \
    --entitlements "$PROJECT_DIR/PDFBrochure.entitlements" \
    --sign "$SIGN_IDENTITY" "$APP_PATH"
codesign --verify --deep --strict --verbose=2 "$APP_PATH"

mkdir -p "$DIST_DIR"
rm -f "$DMG_PATH"

echo "==> Creating DMG"
create-dmg \
    --volname "$APP_NAME $VERSION" \
    --window-size 540 360 \
    --icon-size 96 \
    --icon "$APP_NAME.app" 140 180 \
    --app-drop-link 400 180 \
    --hide-extension "$APP_NAME.app" \
    --no-internet-enable \
    "$DMG_PATH" \
    "$APP_PATH"

echo "==> Signing DMG"
codesign --force --sign "$SIGN_IDENTITY" --timestamp "$DMG_PATH"

if [[ "${SKIP_NOTARIZE:-0}" == "1" ]]; then
    echo "==> SKIP_NOTARIZE=1, skipping notarization"
    echo "Built: $DMG_PATH"
    exit 0
fi

echo "==> Submitting to notary service (this can take a few minutes)"
xcrun notarytool submit "$DMG_PATH" \
    --keychain-profile "$NOTARY_PROFILE" \
    --wait

echo "==> Stapling ticket"
xcrun stapler staple "$DMG_PATH"
xcrun stapler validate "$DMG_PATH"
spctl --assess --type open --context context:primary-signature --verbose "$DMG_PATH" || true

GENERATE_APPCAST="$PROJECT_DIR/scripts/sparkle/generate_appcast"
DOCS_DIR="$PROJECT_DIR/docs"
RELNOTES_SRC="$DOCS_DIR/releasenotes/$VERSION.md"
if [[ -f "$RELNOTES_SRC" ]]; then
    cp "$RELNOTES_SRC" "$DIST_DIR/$APP_NAME-$VERSION.md"
    echo "==> Including release notes from $RELNOTES_SRC"
else
    echo "warning: no release notes at $RELNOTES_SRC; appcast item will have no description" >&2
fi
if [[ -x "$GENERATE_APPCAST" ]]; then
    echo "==> Generating appcast (Sparkle account: $SPARKLE_ACCOUNT)"
    mkdir -p "$DOCS_DIR"
    "$GENERATE_APPCAST" "$DIST_DIR" \
        --account "$SPARKLE_ACCOUNT" \
        --download-url-prefix "https://github.com/jean-bovet/PDFBrochure/releases/download/v$VERSION/" \
        --embed-release-notes \
        -o "$DOCS_DIR/appcast.xml"
    echo "Appcast written to $DOCS_DIR/appcast.xml"
    echo "Commit and push docs/appcast.xml after the GitHub release is published."
else
    echo "warning: $GENERATE_APPCAST not found, skipping appcast generation" >&2
fi

echo ""
echo "Done: $DMG_PATH"
