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

echo "Built ios/Nolabel-unsigned.ipa"
