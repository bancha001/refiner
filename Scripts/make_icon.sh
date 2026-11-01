#!/bin/zsh
# Renders Resources/AppIcon.png and packs it into Resources/AppIcon.icns.
set -euo pipefail
cd "$(dirname "$0")/.."

swift Scripts/make_icon.swift Resources/AppIcon.png

ICONSET=$(mktemp -d)/AppIcon.iconset
mkdir -p "$ICONSET"
for px in 16 32 128 256 512; do
  sips -z $px $px Resources/AppIcon.png --out "$ICONSET/icon_${px}x${px}.png" >/dev/null
  sips -z $((px * 2)) $((px * 2)) Resources/AppIcon.png --out "$ICONSET/icon_${px}x${px}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o Resources/AppIcon.icns
echo "Wrote Resources/AppIcon.icns"
