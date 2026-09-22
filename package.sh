#!/bin/bash
set -e

echo "Building calendar-sync..."
./build.sh

VERSION=$(date +%Y%m%d)
PACKAGE_NAME="calendar-sync-${VERSION}"
STAGING_DIR="./dist/${PACKAGE_NAME}"

echo ""
echo "Assembling package..."
rm -rf ./dist
mkdir -p "$STAGING_DIR"

# The built app -- no rebuild needed by the recipient.
cp -R ./bin/calendar-sync.app "$STAGING_DIR/"

# Source code. Required to accompany the binary under this project's GPL-3.0
# license, and useful if the recipient ever needs to rebuild for their own Mac
# (e.g. an Intel Mac -- this build is arm64-only).
mkdir -p "$STAGING_DIR/source"
cp -R calendar-sync "$STAGING_DIR/source/"
cp -R calendar-sync.xcodeproj "$STAGING_DIR/source/"
find "$STAGING_DIR/source/calendar-sync.xcodeproj" -name "xcuserdata" -type d -exec rm -rf {} +
cp build.sh package.sh "$STAGING_DIR/source/"

# Docs and a credentials template. Deliberately NOT including the real .env --
# the recipient needs their own Google OAuth credentials (either as a test
# user on your OAuth client, or their own Google Cloud project).
cp README.md DOCS.md BUILD.md LICENSE .env.example "$STAGING_DIR/"

echo "Zipping..."
(cd ./dist && zip -r -q "${PACKAGE_NAME}.zip" "${PACKAGE_NAME}")
rm -rf "$STAGING_DIR"

echo ""
echo "✓ Package created: ./dist/${PACKAGE_NAME}.zip"
echo ""
echo "Before sharing, remember the recipient still needs to:"
echo "  - Provide their own Google OAuth credentials in a .env file (see .env.example)"
echo "  - Approve the app in System Settings > Privacy & Security (it's ad-hoc signed,"
echo "    not notarized, so Gatekeeper will flag it as from an unidentified developer)"
echo "  - Complete first-time setup themselves (calendar picker, Google consent, Touch ID)"
echo "  - Be on Apple Silicon -- this build is arm64-only"
