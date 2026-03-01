#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="$PROJECT_DIR/build"
APP_NAME="mrkd"

# Determine configuration (default: Release)
CONFIG="Release"
if [[ "${1:-}" == "--debug" ]]; then
    CONFIG="Debug"
    shift
fi

APP_BUNDLE="$BUILD_DIR/Build/Products/$CONFIG/$APP_NAME.app"

echo "Building $APP_NAME ($CONFIG)..."
cd "$PROJECT_DIR"
xcodebuild -project mrkd.xcodeproj \
    -scheme mrkd \
    -configuration "$CONFIG" \
    -derivedDataPath "$BUILD_DIR" \
    build "$@"

if [ ! -d "$APP_BUNDLE" ]; then
    echo "Error: App bundle not found at $APP_BUNDLE"
    exit 1
fi

echo ""
echo "Done: $APP_BUNDLE"
echo ""
echo "Run with:  open $APP_BUNDLE"
echo "Or:        $APP_BUNDLE/Contents/MacOS/$APP_NAME [file.md]"
echo ""
echo "Install:   trash /Applications/$APP_NAME.app && cp -R $APP_BUNDLE /Applications/"
