#!/bin/zsh
# Universal Swift app; no Xcode project required.
set -euo pipefail
cd "$(dirname "$0")/.."
exec bun app/scripts/build.ts "$@"
