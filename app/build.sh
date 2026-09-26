#!/bin/zsh
# Builds Gust.app with swiftc (no Xcode / SwiftPM required).
set -euo pipefail
cd "$(dirname "$0")"
OUT=build; APP=$OUT/Gust.app
mkdir -p $OUT
FLAGS=(-O -swift-version 5 -target arm64-apple-macos14.0 -I Sources/CSMC/include)
clang -c -O2 -target arm64-apple-macos14.0 -ISources/CSMC/include Sources/CSMC/smc.c -o $OUT/smc.o
swiftc $FLAGS Sources/Shared/*.swift Sources/GustHelper/*.swift $OUT/smc.o -framework IOKit -o $OUT/GustHelper
swiftc $FLAGS -parse-as-library Sources/Shared/*.swift Sources/Gust/*.swift $OUT/smc.o -framework IOKit -o $OUT/Gust
/bin/rm -rf $APP
mkdir -p $APP/Contents/{MacOS,Resources}
cp $OUT/Gust $OUT/GustHelper $APP/Contents/MacOS/
cp Resources/Info.plist $APP/Contents/
[[ -f Resources/AppIcon.icns ]] && cp Resources/AppIcon.icns $APP/Contents/Resources/
codesign --force --sign - $APP/Contents/MacOS/GustHelper
codesign --force --sign - $APP
echo "built $APP"
