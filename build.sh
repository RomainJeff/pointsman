#!/bin/bash
# Build Pointsman.app, run the self-test, install into ~/Applications.
set -euo pipefail
cd "$(dirname "$0")"

mkdir -p build
swiftc -parse-as-library Sources/Decision.swift Tests/SelfTest.swift -o build/selftest
build/selftest

APP=build/Pointsman.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp Info.plist "$APP/Contents/"
cp -R Resources "$APP/Contents/"
swiftc -O -parse-as-library -target arm64-apple-macos15 Sources/*.swift -o "$APP/Contents/MacOS/Pointsman"
codesign --force --sign - "$APP"

if [[ "${1:-}" == "--install" ]]; then
  pkill -x Pointsman || true
  rm -rf ~/Applications/Pointsman.app
  cp -R "$APP" ~/Applications/
  open ~/Applications/Pointsman.app
  echo "Installed ~/Applications/Pointsman.app"
fi
