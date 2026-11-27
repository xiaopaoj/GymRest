#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build
# Let the destination and target configuration select the device SDK.
result_bundle="build/Release-$(date +%s)-$$.xcresult"
xcodebuild -project GymRest.xcodeproj -scheme GymRest -configuration Release \
  -destination 'generic/platform=iOS' -derivedDataPath DerivedData \
  -resultBundlePath "$result_bundle" \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY='' build \
  2>&1 | tee build/release-build.log
