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

# The icon is Icon Composer's (Resources/Icons/Weft.icon, drawn by
# scripts/make-icons.py): layers the system draws light, dark, clear or
# tinted, compiled by Xcode's actool into Assets.car, which the bundle names.
# (absolute paths: actool's helper may not run where we are)
if xcrun actool "$PWD/Resources/Icons/Weft.icon" --compile "$(cd "$app/Contents/Resources" && pwd)" --app-icon Weft \
     --platform macosx --minimum-deployment-target 26.0 --output-partial-info-plist "$PWD/build/icon-partial.plist" >/dev/null 2>&1 \
   && [ -f "$app/Contents/Resources/Assets.car" ]; then
  /usr/libexec/PlistBuddy -c "Add :CFBundleIconName string Weft" "$app/Contents/Info.plist"
fi
# The Finder and the Dock cache a bundle's icon by its path: touched, and
# registered again, so a new icon shows at the next launch.
touch "$app"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$app" >/dev/null 2>&1 || true

# Signed with an Apple Development identity when there is one, so the
# keychain knows each build for the same app and an Always Allow given to
# one — for the GitHub sign-in — holds for the next; else ad hoc. Given at
# most a minute, should signing wait on a question about the key.
identity=$(security find-identity -v -p codesigning 2>/dev/null | awk '/Apple Development/ { print $2; exit }')
if [ -z "$identity" ] || ! perl -e 'alarm 60; exec @ARGV' codesign --force --sign "$identity" "$app" >/dev/null 2>&1; then
  codesign --force --sign - "$app" >/dev/null 2>&1
fi
echo "built $app"

if [ "$1" = run ]; then
  shift
  pkill -x WeftMac 2>/dev/null || true
  open "$app" --args "$@"
fi
