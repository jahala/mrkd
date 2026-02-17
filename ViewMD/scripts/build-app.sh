#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="$PROJECT_DIR/.build"
APP_NAME="mrkd"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"

# Build
echo "Building $APP_NAME..."
cd "$PROJECT_DIR"
swift build "$@"

# Determine build configuration
if [[ " $* " == *" -c release "* ]] || [[ " $* " == *" --configuration release "* ]]; then
    CONFIG="release"
else
    CONFIG="debug"
fi

BINARY="$BUILD_DIR/$CONFIG/$APP_NAME"

if [ ! -f "$BINARY" ]; then
    echo "Error: Binary not found at $BINARY"
    exit 1
fi

# Create .app bundle structure
echo "Creating $APP_NAME.app bundle..."
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

# Copy binary
cp "$BINARY" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"

# Copy Info.plist
cp "$PROJECT_DIR/Sources/Resources/Info.plist" "$APP_BUNDLE/Contents/Info.plist"

# Copy Highlightr resources (themes + highlight.js) into the bundle
HIGHLIGHTR_BUNDLE=$(find "$BUILD_DIR" -name "Highlightr_Highlightr.bundle" -path "*/$CONFIG/*" 2>/dev/null | head -1)
if [ -n "$HIGHLIGHTR_BUNDLE" ] && [ -d "$HIGHLIGHTR_BUNDLE" ]; then
    cp -R "$HIGHLIGHTR_BUNDLE" "$APP_BUNDLE/Contents/Resources/"
    echo "  Copied Highlightr resources"
fi

echo "Done: $APP_BUNDLE"
echo ""
echo "Run with:  open $APP_BUNDLE"
echo "Or:        $APP_BUNDLE/Contents/MacOS/$APP_NAME [file.md]"
