#!/usr/bin/env bash
# Runs the package tests on an Apple TV simulator. Xcode names the scheme of a single-product
# package after the package (TVProfilePicker) and adds a TVProfilePicker-Package scheme once there
# are more products; the script uses whichever exists.
# Usage: scripts/test.sh [tvOS]
set -euo pipefail

PLATFORM="${1:-tvOS}"
case "$PLATFORM" in
  tvOS) FAMILY="^Apple TV" ;;
  *) echo "Unknown platform $PLATFORM (use tvOS)" >&2; exit 1 ;;
esac

newest_runtime() {
  xcrun simctl list runtimes available -j | jq -r --arg platform "$PLATFORM" '
    [.runtimes[] | select(.identifier | test($platform))]
    | sort_by(.version | split(".") | map(tonumber)) | last | .identifier // empty'
}

if [ -z "$(newest_runtime)" ]; then
  echo "No $PLATFORM simulator runtime installed, downloading one"
  xcodebuild -downloadPlatform "$PLATFORM"
fi

UDID=$(xcrun simctl list devices available -j | jq -r --arg platform "$PLATFORM" --arg family "$FAMILY" '
  [.devices | to_entries | sort_by(.key) | reverse | .[]
   | select(.key | test($platform)) | .value[] | select(.name | test($family))]
  | .[0].udid // empty')
if [ -z "$UDID" ]; then
  RUNTIME=$(newest_runtime)
  TYPE=$(xcrun simctl list devicetypes -j | jq -r --arg family "$FAMILY" '
    [.devicetypes[] | select(.name | test($family))] | last | .identifier // empty')
  echo "Creating a $PLATFORM simulator ($TYPE, $RUNTIME)"
  UDID=$(xcrun simctl create "Tests $PLATFORM" "$TYPE" "$RUNTIME")
fi
echo "Testing on $PLATFORM simulator $UDID"

SCHEME=TVProfilePicker
if xcodebuild -list -json 2>/dev/null | jq -e '.workspace.schemes // .project.schemes // [] | index("TVProfilePicker-Package")' > /dev/null; then
  SCHEME=TVProfilePicker-Package
fi
echo "Using scheme $SCHEME"

xcodebuild test \
  -scheme "$SCHEME" \
  -destination "id=$UDID" \
  -derivedDataPath build/test-$PLATFORM \
  CODE_SIGNING_ALLOWED=NO
