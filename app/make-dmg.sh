#!/bin/zsh
# Packages app/build/Gust.app into app/build/Gust.dmg with a drag-to-Applications layout.
set -euo pipefail
cd "$(dirname "$0")/build"
STAGE=dmg-stage
/bin/rm -rf $STAGE Gust.dmg
mkdir $STAGE
cp -R Gust.app $STAGE/
ln -s /Applications $STAGE/Applications
hdiutil create -volname Gust -srcfolder $STAGE -fs HFS+ -format UDZO -imagekey zlib-level=9 -ov Gust.dmg >/dev/null
/bin/rm -rf $STAGE
echo "built $(pwd)/Gust.dmg"
