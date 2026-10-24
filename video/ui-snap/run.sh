#!/bin/bash
# Render the Settings window, keystroke by keystroke, into ../ui/ for scene 4.
# Router.config saves on every change, so the real config is backed up and restored.
set -euo pipefail
cd "$(dirname "$0")"
SRC=../../Sources; TMP=$(mktemp -d); CFG=~/.config/link-router/config.json
KEEP='.filter { ["com.google.Chrome", "com.apple.Safari", "company.thebrowser.dia"].contains($0.id) }'
sed -e 's/^@main$//' -e 's/showOthers = false/showOthers = true/' \
    -e "s/installed = installedBrowsers()\$/installed = installedBrowsers()$KEEP/" $SRC/App.swift > $TMP/App.swift
swiftc -parse-as-library -target arm64-apple-macos15 $TMP/App.swift $SRC/Router.swift $SRC/Decision.swift Snap.swift -o $TMP/snap
[ -f "$CFG" ] && cp "$CFG" $TMP/config.json
trap '[ -f $TMP/config.json ] && cp $TMP/config.json "$CFG"' EXIT
rm -rf ../ui && mkdir ../ui && $TMP/snap "$PWD/../ui"
