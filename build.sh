#!/bin/zsh
# Builds Refiner.app into ./build. Set SIGN_IDENTITY to a real certificate to keep
# the Accessibility permission across rebuilds (ad-hoc "-" signing resets it).
set -euo pipefail
cd "$(dirname "$0")"

# Universal binary: runs on Apple Silicon and Intel Macs (macOS 14+).
ARCHS=(--arch arm64 --arch x86_64)
swift build -c release "${ARCHS[@]}"
APP=build/Refiner.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$(swift build -c release "${ARCHS[@]}" --show-bin-path)/Refiner" "$APP/Contents/MacOS/Refiner"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
codesign --force --sign "${SIGN_IDENTITY:--}" "$APP"
echo "Built $APP"
