#!/bin/bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$PROJECT_DIR/.build"
APP_NAME="ScreenRecorder"
APP_BUNDLE="$PROJECT_DIR/$APP_NAME.app"

echo "Building $APP_NAME..."
cd "$PROJECT_DIR"
swift build -c release 2>&1

echo "Creating app bundle..."
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

# Copy executable
cp "$BUILD_DIR/release/$APP_NAME" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"

# Copy Info.plist
cp "$PROJECT_DIR/Resources/Info.plist" "$APP_BUNDLE/Contents/Info.plist"

# Ad-hoc code sign (required for TCC/permission system)
codesign --force --sign - "$APP_BUNDLE"

echo ""
echo "Successfully built: $APP_BUNDLE"
echo "Run with: open $APP_BUNDLE"
