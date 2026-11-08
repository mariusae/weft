#!/bin/zsh
# Archives Weft for the iPhone and iPad and uploads it to App Store Connect,
# for TestFlight. `scripts/testflight.sh --export` makes the .ipa in
# build/testflight/ instead, uploading nothing.
#
# Signed as Xcode signs: automatically, with the team's certificates, made
# as needed — by the account Xcode is signed in to (Settings → Accounts), or
# by an App Store Connect API key, when these are set:
#
#     ASC_KEY_PATH=~/.appstoreconnect/AuthKey_XXXXXXXXXX.p8
#     ASC_KEY_ID=XXXXXXXXXX
#     ASC_ISSUER_ID=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
#
# Each build is numbered by when it was made (20261108.1530, UTC), so each
# upload's is higher than the last; the version is MARKETING_VERSION's.
set -euo pipefail
cd "$(dirname "$0")/.."

destination=upload
[[ "${1:-}" == --export ]] && destination=export

project=iOS/Weft.xcodeproj
scheme=Weft
team=G3V66M4637
build=$(date -u +%Y%m%d.%H%M)
out=build/testflight
archive=$out/Weft-$build.xcarchive

auth=()
if [[ -n "${ASC_KEY_ID:-}" ]]; then
  auth=(-authenticationKeyPath "${ASC_KEY_PATH/#\~/$HOME}" -authenticationKeyID "$ASC_KEY_ID" -authenticationKeyIssuerID "$ASC_ISSUER_ID")
fi

# Signing in to GitHub needs the GitHub App's details (iOS/GitHub.xcconfig
# says where they're kept): a build without them can't sign in.
if ! xcodebuild -showBuildSettings -project $project -scheme $scheme -configuration Release 2>/dev/null \
    | grep -Eq '^ *GITHUB_CLIENT_ID = [^ ]'; then
  echo "No GITHUB_CLIENT_ID: the GitHub App's details aren't in a GitHub.local.xcconfig (see iOS/GitHub.xcconfig)." >&2
  exit 1
fi

mkdir -p $out
xcodebuild archive -project $project -scheme $scheme -configuration Release \
  -destination 'generic/platform=iOS' -archivePath "$archive" \
  -allowProvisioningUpdates "${auth[@]}" \
  CURRENT_PROJECT_VERSION="$build"

options=$out/ExportOptions.plist
cat > $options <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>method</key>
	<string>app-store-connect</string>
	<key>destination</key>
	<string>$destination</string>
	<key>teamID</key>
	<string>$team</string>
	<key>signingStyle</key>
	<string>automatic</string>
	<key>uploadSymbols</key>
	<true/>
	<key>manageAppVersionAndBuildNumber</key>
	<false/>
</dict>
</plist>
EOF

xcodebuild -exportArchive -archivePath "$archive" -exportOptionsPlist $options \
  -exportPath $out/Weft-$build -allowProvisioningUpdates "${auth[@]}"

if [[ $destination == upload ]]; then
  echo "Weft $build uploaded: in TestFlight once App Store Connect has processed it."
else
  echo "Weft $build exported to $out/Weft-$build."
fi
