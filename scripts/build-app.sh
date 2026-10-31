#!/bin/sh
# Builds Weft.app into build/. `scripts/build-app.sh run` also launches it;
# anything after `run` is passed to the app, e.g. `-GraphPath ~/reflect`.
set -e
cd "$(dirname "$0")/.."

swift build -c release --product WeftMac
app="build/Weft.app"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$(swift build -c release --show-bin-path)/WeftMac" "$app/Contents/MacOS/WeftMac"
cp Resources/Info.plist "$app/Contents/Info.plist"

codesign --force --sign - "$app" >/dev/null 2>&1
echo "built $app"

if [ "$1" = run ]; then
  shift
  pkill -x WeftMac 2>/dev/null || true
  open "$app" --args "$@"
fi
