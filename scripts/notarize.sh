#!/usr/bin/env bash
# Notarize + staple a DMG. REQUIRES a paid Apple Developer account (Developer ID).
# The app/helper inside the DMG must already be signed with a "Developer ID
# Application" certificate and Hardened Runtime — ad-hoc ("-") signed builds will
# be REJECTED by notarytool.
#
# Set up once:
#   xcrun notarytool store-credentials nimbus-profile \
#       --apple-id "you@example.com" --team-id "TEAMID1234" --password "app-specific-pw"
#
# Then:
#   scripts/notarize.sh [build/Nimbus.dmg]
set -euo pipefail

DMG="${1:-build/Nimbus.dmg}"
PROFILE="${NOTARY_PROFILE:-nimbus-profile}"

[ -f "$DMG" ] || { echo "DMG not found: $DMG (run scripts/package-dmg.sh first)"; exit 1; }

echo "▶ Submitting $DMG to Apple notary service (profile: $PROFILE)…"
xcrun notarytool submit "$DMG" --keychain-profile "$PROFILE" --wait

echo "▶ Stapling ticket…"
xcrun stapler staple "$DMG"
xcrun stapler validate "$DMG"

echo "✅ Notarized + stapled: $DMG"
