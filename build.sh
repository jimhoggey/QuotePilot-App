#!/bin/bash
# Builds "build/Quote Pilot.app" from the release binary. Run it from anywhere: ./build.sh
set -euo pipefail
cd "$(dirname "$0")"

# Command Line Tools 27.0's macOS 27 SDK makes SwiftUI's @State a macro whose plugin only Xcode
# ships. Build against the macOS 26.5 SDK the tools also include, when it's there.
if [ -z "${SDKROOT:-}" ] && sdk="$(xcrun --sdk macosx26.5 --show-sdk-path 2>/dev/null)"; then
    export SDKROOT="$sdk"
fi

swift build -c release --product QuotePilotApp
binary="$(swift build -c release --show-bin-path)/QuotePilotApp"
app="build/Quote Pilot.app"

mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$binary" "$app/Contents/MacOS/Quote Pilot"
cp Resources/Info.plist "$app/Contents/Info.plist"
# An ad-hoc signature, so macOS runs the app on this Mac.
codesign --force --sign - "$app"
echo "Built $app"
