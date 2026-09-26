#!/bin/zsh
# Packages build/Gust.app into build/Gust.dmg with a "drag to Applications" window. Needs uv or pipx.
set -euo pipefail
cd "$(dirname "$0")"
if command -v uvx >/dev/null; then RUN=(uvx --from dmgbuild dmgbuild); else RUN=(pipx run dmgbuild); fi
/bin/rm -f build/Gust.dmg
$RUN -s scripts/dmg-settings.py -D app=build/Gust.app -D root=. Gust build/Gust.dmg
echo "built $(pwd)/build/Gust.dmg"
