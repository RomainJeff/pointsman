#!/bin/bash
# Build Link Router.app, run the self-test, install into ~/Applications.
set -euo pipefail
cd "$(dirname "$0")"

mkdir -p build
swiftc -parse-as-library Sources/Decision.swift Tests/SelfTest.swift -o build/selftest
build/selftest

APP=build/LinkRouter.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp Info.plist "$APP/Contents/"
swiftc -O -parse-as-library -target arm64-apple-macos14 Sources/*.swift -o "$APP/Contents/MacOS/LinkRouter"
codesign --force --sign - "$APP"

if [[ "${1:-}" == "--install" ]]; then
  pkill -x LinkRouter || true
  rm -rf ~/Applications/LinkRouter.app
  cp -R "$APP" ~/Applications/
  open ~/Applications/LinkRouter.app
  echo "Installed ~/Applications/LinkRouter.app"
fi
