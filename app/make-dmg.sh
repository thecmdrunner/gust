#!/bin/zsh
# Packages a versioned DMG with the original "drag to Applications" window.
set -euo pipefail
cd "$(dirname "$0")"
if command -v uvx >/dev/null; then RUN=(uvx --from dmgbuild dmgbuild); else RUN=(pipx run dmgbuild); fi
VERSION=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' build/Gust.app/Contents/Info.plist)
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "Invalid app version" >&2; exit 1; }
DMG="build/Gust-${VERSION}-macos.dmg"
/bin/rm -f "$DMG"
$RUN -s scripts/dmg-settings.py -D app=build/Gust.app -D root=. Gust "$DMG"
echo "built $(pwd)/$DMG"
