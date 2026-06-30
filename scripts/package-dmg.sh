#!/usr/bin/env bash
# Build a Release Nimbus.app and package it into a DMG.
#
# Works WITHOUT an Apple Developer ID: the app is ad-hoc signed ("-"), which runs
# locally (Gatekeeper will warn on other Macs until notarized — see notarize.sh).
#
#   scripts/package-dmg.sh
#
# Output: build/Nimbus.dmg
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

DERIVED="build/dd-release"
APP="$DERIVED/Build/Products/Release/Nimbus.app"
DMG="build/Nimbus.dmg"

echo "▶ Generating Xcode project…"
command -v xcodegen >/dev/null || { echo "Install XcodeGen: brew install xcodegen"; exit 1; }
xcodegen generate >/dev/null

echo "▶ Building Release (universal Rust lib via pre-build phase)…"
xcodebuild -project Nimbus.xcodeproj -scheme Nimbus \
    -configuration Release -derivedDataPath "$DERIVED" \
    build

[ -d "$APP" ] || { echo "Build product not found at $APP"; exit 1; }

echo "▶ Ad-hoc signing (deep)…"
codesign --force --deep --options runtime --sign - "$APP" || \
    codesign --force --deep --sign - "$APP"

echo "▶ Building DMG…"
STAGING="$(mktemp -d)"
cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"
rm -f "$DMG"
mkdir -p build
hdiutil create -volname "Nimbus" -srcfolder "$STAGING" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGING"

echo "✅ $DMG"
echo "   (ad-hoc signed — for a distributable build, sign with Developer ID then run scripts/notarize.sh)"
