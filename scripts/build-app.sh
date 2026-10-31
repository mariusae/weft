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

# The GitHub App weft signs in through, for instant sync: Prism's, from the
# file kept beside reflect-mac's iOS xcconfig and never committed. Read
# here, never printed.
github_config=../reflect-mac/iOS/GitHub.local.xcconfig
github_value() {
  [ -f "$github_config" ] || return 0
  sed -n "s/^[[:space:]]*$1[[:space:]]*=[[:space:]]*//p" "$github_config" | tail -1 | sed 's/[[:space:]]*$//'
}
for pair in GitHubClientID:GITHUB_CLIENT_ID GitHubClientSecret:GITHUB_CLIENT_SECRET \
            GitHubAppSlug:GITHUB_APP_SLUG SyncRelayHost:SYNC_RELAY_HOST; do
  /usr/libexec/PlistBuddy -c "Add :${pair%%:*} string $(github_value "${pair#*:}")" "$app/Contents/Info.plist" >/dev/null
done

codesign --force --sign - "$app" >/dev/null 2>&1
echo "built $app"

if [ "$1" = run ]; then
  shift
  pkill -x WeftMac 2>/dev/null || true
  open "$app" --args "$@"
fi
