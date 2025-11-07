#!/bin/bash

# Build script for Cortex Chrome Extension
# Creates a zip file ready for distribution

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EXTENSION_DIR="$SCRIPT_DIR/chrome-extension"
BUILD_DIR="$SCRIPT_DIR/build"
VERSION=$(grep -o '"version": "[^"]*"' "$EXTENSION_DIR/manifest.json" | cut -d'"' -f4)
ZIP_NAME="cortex-extension-v${VERSION}.zip"
ZIP_PATH="$BUILD_DIR/$ZIP_NAME"

echo "Building Cortex Chrome Extension v${VERSION}..."

# Create build directory
mkdir -p "$BUILD_DIR"

# Remove old build if exists
if [ -f "$ZIP_PATH" ]; then
  echo "Removing old build..."
  rm "$ZIP_PATH"
fi

# Create zip file
echo "Packaging extension..."
cd "$EXTENSION_DIR"

zip -r "$ZIP_PATH" . \
  -x "*.git*" \
  -x "*.DS_Store" \
  -x "icons/README.md" \
  -x "icons/*.sh" \
  -x "icons/*.txt" \
  -x "icons/*.placeholder" \
  -x "notes.md" \
  -x ".cursor/*" \
  > /dev/null

cd "$SCRIPT_DIR"

# Get file size
FILE_SIZE=$(du -h "$ZIP_PATH" | cut -f1)

echo ""
echo "✓ Build complete!"
echo "  File: $ZIP_PATH"
echo "  Size: $FILE_SIZE"
echo ""
echo "To load in Chrome:"
echo "  1. Go to chrome://extensions/"
echo "  2. Enable 'Developer mode'"
echo "  3. Click 'Load unpacked'"
echo "  4. Select the 'chrome-extension' folder"
echo ""
echo "Or extract and load the zip file."


