#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

if ! command -v xcodegen >/dev/null 2>&1; then
    brew install xcodegen
fi

xcodegen generate

rm -rf build Payload Nolabel-unsigned.ipa

xcodebuild \
    -project Nolabel.xcodeproj \
    -scheme Nolabel \
    -configuration Release \
    -sdk iphoneos \
    -destination "generic/platform=iOS" \
    -derivedDataPath build \
    CODE_SIGNING_ALLOWED=NO \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGN_IDENTITY="" \
    build

mkdir -p Payload
cp -R build/Build/Products/Release-iphoneos/Nolabel.app Payload/
zip -qry Nolabel-unsigned.ipa Payload

# TEMP: print the measured date-pill geometry from the simulator.
DEVICE_ID=$(xcrun simctl list devices available | grep -E "iPhone (17 Pro|16 Pro|15 Pro|16|15)" | head -1 | sed -E 's/.*\(([0-9A-F-]{36})\).*/\1/' || true)
if [ -n "$DEVICE_ID" ]; then
    xcodebuild -project Nolabel.xcodeproj -scheme Nolabel -configuration Debug -sdk iphonesimulator \
        -destination "platform=iOS Simulator,id=$DEVICE_ID" -derivedDataPath build-sim \
        CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" build >/dev/null 2>&1 || true
    xcrun simctl boot "$DEVICE_ID" >/dev/null 2>&1 || true
    xcrun simctl bootstatus "$DEVICE_ID" -b >/dev/null 2>&1 || true
    xcrun simctl install "$DEVICE_ID" build-sim/Build/Products/Debug-iphonesimulator/Nolabel.app >/dev/null 2>&1 || true
    xcrun simctl launch --console-pty "$DEVICE_ID" com.h2ning.nolabel --preview --preview-screen entry --preview-autoplay-entry > sim.log 2>&1 &
    SIM_PID=$!
    sleep 8
    kill "$SIM_PID" >/dev/null 2>&1 || true
    grep NOLABEL_DEBUG sim.log || true
fi

echo "Built ios/Nolabel-unsigned.ipa"
