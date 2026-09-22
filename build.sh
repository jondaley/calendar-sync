#!/bin/bash
set -e

echo "Building calendar-sync..."
xcodebuild -scheme "calendar-sync" -configuration Release build

echo "Copying app bundle..."
SETTINGS=$(xcodebuild -scheme "calendar-sync" -configuration Release -showBuildSettings 2>/dev/null)
BUILT_PRODUCTS_DIR=$(echo "$SETTINGS" | grep "BUILT_PRODUCTS_DIR" | head -1 | sed 's/.*= //')
WRAPPER_NAME=$(echo "$SETTINGS" | grep " WRAPPER_NAME " | head -1 | sed 's/.*= //')

APP_BUNDLE="$BUILT_PRODUCTS_DIR/$WRAPPER_NAME"

if [ ! -d "$APP_BUNDLE" ]; then
    echo "Error: App bundle not found at $APP_BUNDLE"
    exit 1
fi

# Copy the whole .app bundle, not just the raw executable. A bare copied
# executable loses its Info.plist/sealed-resources binding, which macOS's
# dynamic code-identity checks need — without it, Keychain calls fail with
# errSecMissingEntitlement / code-signing errors even though the code hash
# is unchanged.
mkdir -p ./bin
rm -rf ./bin/calendar-sync.app
cp -R "$APP_BUNDLE" ./bin/calendar-sync.app

echo "✓ Build complete - run with: ./bin/calendar-sync.app/Contents/MacOS/calendar-sync"
