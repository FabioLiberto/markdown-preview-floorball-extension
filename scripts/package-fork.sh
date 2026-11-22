#!/bin/sh
#
# Builds a Release copy of Markdown Preview Floorball, signed ad hoc (no
# Apple Developer ID), and zips it for a GitHub release. Prints the zip's path.
#
#   scripts/package-fork.sh
#
# The project's DEVELOPMENT_TEAM and signing settings are overridden on the
# command line only; project.pbxproj is not changed. The hardened runtime is
# off: it is only needed for notarization, and with it on macOS refuses to
# load the ad hoc signed Sparkle and Sentry frameworks (library validation
# wants a team ID that ad hoc code does not have).

set -eu
cd "$(dirname "$0")/.."
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

out=build/package
rm -rf "$out"
xcodebuild -project md-preview.xcodeproj -scheme md-preview -configuration Release \
  -derivedDataPath "$out/dd" \
  CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM= CODE_SIGN_STYLE=Manual ENABLE_HARDENED_RUNTIME=NO \
  build -quiet

app="$out/dd/Build/Products/Release/Markdown Preview Floorball.app"
codesign --verify --deep --strict "$app"
version=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$app/Contents/Info.plist")
zip="build/Markdown-Preview-Floorball-$version.zip"
rm -f "$zip"
ditto -c -k --keepParent "$app" "$zip"
echo "$zip"
