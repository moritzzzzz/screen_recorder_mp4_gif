#!/bin/bash
# Build, sign with Developer ID, notarize, and package the app as a DMG
# ready to upload to GitHub Releases / your website.
#
# Usage:  bash Scripts/release.sh
#
# Reads SIGN_IDENTITY and NOTARY_PROFILE from Scripts/release.config.sh
# (gitignored). See Scripts/release.config.sh.example for the template.
#
# Bump CFBundleShortVersionString in Resources/Info.plist before running
# to publish a new version. (CFBundleVersion can stay or be bumped too.)

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CONFIG="$PROJECT_DIR/Scripts/release.config.sh"

if [[ -f "$CONFIG" ]]; then
    # shellcheck source=/dev/null
    source "$CONFIG"
fi

: "${SIGN_IDENTITY:?Set SIGN_IDENTITY in Scripts/release.config.sh}"
: "${NOTARY_PROFILE:?Set NOTARY_PROFILE in Scripts/release.config.sh}"

APP_NAME="ScreenRecorder"
APP_BUNDLE="$PROJECT_DIR/$APP_NAME.app"
BUILD_DIR="$PROJECT_DIR/.build"
INFO_PLIST="$PROJECT_DIR/Resources/Info.plist"
ENTITLEMENTS="$PROJECT_DIR/Resources/$APP_NAME.entitlements"

VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$INFO_PLIST")
DMG_PATH="$PROJECT_DIR/${APP_NAME}-${VERSION}.dmg"
ZIP_PATH="$PROJECT_DIR/${APP_NAME}-${VERSION}.zip"

echo "==> Building $APP_NAME $VERSION (release)"
cd "$PROJECT_DIR"
swift build -c release 2>&1 | tail -4

echo "==> Assembling app bundle"
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"
cp "$BUILD_DIR/release/$APP_NAME" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
cp "$INFO_PLIST" "$APP_BUNDLE/Contents/Info.plist"

echo "==> Signing with: $SIGN_IDENTITY"
codesign --force \
         --sign "$SIGN_IDENTITY" \
         --options runtime \
         --timestamp \
         --entitlements "$ENTITLEMENTS" \
         "$APP_BUNDLE/Contents/MacOS/$APP_NAME"

codesign --force \
         --sign "$SIGN_IDENTITY" \
         --options runtime \
         --timestamp \
         --entitlements "$ENTITLEMENTS" \
         "$APP_BUNDLE"

echo "==> Verifying signature"
codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"

echo "==> Creating zip for notarization"
rm -f "$ZIP_PATH"
ditto -c -k --sequesterRsrc --keepParent "$APP_BUNDLE" "$ZIP_PATH"

echo "==> Submitting app to Apple notary service (this can take 1-5 minutes)"
xcrun notarytool submit "$ZIP_PATH" \
                 --keychain-profile "$NOTARY_PROFILE" \
                 --wait

echo "==> Stapling notarization ticket onto the app"
xcrun stapler staple "$APP_BUNDLE"

echo "==> Verifying staple"
xcrun stapler validate "$APP_BUNDLE"
spctl -a -t exec -vvv "$APP_BUNDLE" 2>&1 | head -3

rm -f "$ZIP_PATH"

echo "==> Building DMG"
DMG_STAGE="$(mktemp -d)/dmg-stage"
mkdir -p "$DMG_STAGE"
cp -R "$APP_BUNDLE" "$DMG_STAGE/"
ln -s /Applications "$DMG_STAGE/Applications"

rm -f "$DMG_PATH"
hdiutil create -volname "Screen Recorder" \
               -srcfolder "$DMG_STAGE" \
               -ov -format UDZO \
               -fs HFS+ \
               "$DMG_PATH" >/dev/null
rm -rf "$(dirname "$DMG_STAGE")"

echo "==> Signing DMG"
codesign --force \
         --sign "$SIGN_IDENTITY" \
         --timestamp \
         "$DMG_PATH"

echo "==> Notarizing DMG"
xcrun notarytool submit "$DMG_PATH" \
                 --keychain-profile "$NOTARY_PROFILE" \
                 --wait

echo "==> Stapling DMG"
xcrun stapler staple "$DMG_PATH"

DMG_SIZE=$(du -h "$DMG_PATH" | cut -f1)

echo
echo "============================================================"
echo " Release ready: $(basename "$DMG_PATH")  ($DMG_SIZE)"
echo "============================================================"
echo
echo " Verify before uploading:"
echo "   spctl -a -t open --context context:primary-signature -v \"$DMG_PATH\""
echo "   xcrun stapler validate \"$DMG_PATH\""
echo
echo " Test by:"
echo "   1) double-clicking the DMG"
echo "   2) dragging the app to Applications"
echo "   3) launching from /Applications/ — should open with no Gatekeeper warning"
echo
