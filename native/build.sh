#!/usr/bin/env bash
# Build claude-rc's menu-bar vibrancy panel — no Xcode project needed.
# Usage: ./build.sh [--run]
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="ClaudeRCPanel"
APP_BUNDLE="$HERE/build/${APP_NAME}.app"

echo "== building $APP_NAME =="

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"

swiftc -O \
  -target arm64-apple-macosx11.0 \
  -framework AppKit -framework WebKit \
  "$HERE/main.swift" \
  -o "$APP_BUNDLE/Contents/MacOS/${APP_NAME}"

chmod +x "$APP_BUNDLE/Contents/MacOS/${APP_NAME}"

cp "$HERE/Info.plist" "$APP_BUNDLE/Contents/Info.plist"
plutil -lint "$APP_BUNDLE/Contents/Info.plist" >/dev/null

codesign --force --deep --sign - "$APP_BUNDLE"
xattr -cr "$APP_BUNDLE" 2>/dev/null || true

echo "== built: $APP_BUNDLE =="

if [ "${1:-}" = "--run" ]; then
  pkill -f "$APP_BUNDLE/Contents/MacOS/${APP_NAME}" 2>/dev/null || true
  sleep 0.5
  open "$APP_BUNDLE"
  echo "== launched =="
fi
