#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build
exec > >(tee build/build.log) 2>&1
# Choose an installed Xcode with an actual iOS 26 SDK; fail rather than silently use an older SDK.
ls -d /Applications/Xcode*.app
selected=""
for candidate in /Applications/Xcode_26*.app; do
  [[ -d "$candidate" ]] || continue
  sdk=$(DEVELOPER_DIR="$candidate/Contents/Developer" xcrun --sdk iphoneos --show-sdk-version)
  if [[ "$sdk" == 26.* ]]; then selected="$candidate/Contents/Developer"; break; fi
done
[[ -n "$selected" ]] || { echo 'No installed Xcode with iOS 26 SDK'; exit 1; }
export DEVELOPER_DIR="$selected"
xcodebuild -version
xcrun --sdk iphoneos --show-sdk-version
xcodegen --version
xcodegen generate
# Select a real available simulator and boot it, without assuming a particular iPhone model.
xcrun simctl list devices available --json > build/devices.json
simulator_info=$(python3 - <<'PYTHON'
import json
j=json.load(open('build/devices.json'))
for runtime,devices in sorted(j['devices'].items(),reverse=True):
    if 'iOS-26-' in runtime:
        for d in devices:
            if d['isAvailable'] and d['name'].startswith('iPhone'):
                print(d['udid'], d['state']);raise SystemExit(0)
raise SystemExit('No available iOS 26 iPhone simulator')
PYTHON
)
read -r simulator simulator_state <<< "$simulator_info"
if [[ "$simulator_state" != "Booted" ]]; then xcrun simctl boot "$simulator"; fi
xcrun simctl bootstatus "$simulator" -b
xcodebuild -project GymRest.xcodeproj -scheme GymRest -configuration Debug \
  -destination "platform=iOS Simulator,id=$simulator" -derivedDataPath DerivedData \
  -resultBundlePath "build/Tests-$(date +%s).xcresult" CODE_SIGNING_ALLOWED=NO test
xcodebuild -project GymRest.xcodeproj -scheme GymRest -configuration Release \
  -sdk iphoneos -destination 'generic/platform=iOS' -derivedDataPath DerivedData \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY='' build
python3 scripts/package_ipa.py
