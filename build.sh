#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

if ! xcodebuild -version &>/dev/null; then
  echo "Error: Full Xcode is required (xcode-select points to Command Line Tools only)."
  echo "Install Xcode from the App Store, then run:"
  echo "  sudo xcode-select -s /Applications/Xcode.app/Contents/Developer"
  exit 1
fi

echo "Building DrawOver..."
xcodebuild \
  -project DrawOver.xcodeproj \
  -scheme DrawOver \
  -configuration Release \
  -derivedDataPath "$SCRIPT_DIR/build" \
  build

APP_PATH="$SCRIPT_DIR/build/Build/Products/Release/DrawOver.app"
if [[ -d "$APP_PATH" ]]; then
  echo "Build succeeded: $APP_PATH"
  echo "Run with: open \"$APP_PATH\""
else
  echo "Build finished but app bundle not found at expected path."
  find "$SCRIPT_DIR/build" -name "DrawOver.app" -maxdepth 6 2>/dev/null
fi
