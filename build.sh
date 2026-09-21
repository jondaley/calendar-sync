#!/bin/bash
set -e

echo "Building calendar-sync..."
xcodebuild -scheme "calendar-sync" -configuration Release build

echo "Creating symlink..."
SETTINGS=$(xcodebuild -scheme "calendar-sync" -configuration Release -showBuildSettings 2>/dev/null)
BUILT_PRODUCTS_DIR=$(echo "$SETTINGS" | grep "BUILT_PRODUCTS_DIR" | head -1 | sed 's/.*= //')
EXECUTABLE_PATH=$(echo "$SETTINGS" | grep "EXECUTABLE_PATH" | head -1 | sed 's/.*= //')

BINARY="$BUILT_PRODUCTS_DIR/$EXECUTABLE_PATH"

if [ ! -f "$BINARY" ]; then
    echo "Error: Binary not found at $BINARY"
    exit 1
fi

mkdir -p ./bin
ln -sf "$BINARY" ./bin/calendar-sync

echo "✓ Build complete - run with: ./bin/calendar-sync"
