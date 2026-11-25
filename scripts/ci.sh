#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build
exec > >(tee build/build.log) 2>&1
# Prefer the runner's selected Xcode, then the newest compatible installed Xcode.
python3 - <<'PYTHON' > build/xcode-candidates.txt
import glob,re,subprocess
selected=subprocess.check_output(['xcode-select','-p'],text=True).strip()
apps=sorted(glob.glob('/Applications/Xcode*.app'), key=lambda p: tuple(map(int,re.findall(r'\d+',p))),reverse=True)
print(selected)
for app in apps:
    path=app+'/Contents/Developer'
    if path!=selected: print(path)
PYTHON
selected=""
while IFS= read -r candidate; do
  sdk=$(DEVELOPER_DIR="$candidate" xcrun --sdk iphoneos --show-sdk-version 2>/dev/null) || continue
  simsdk=$(DEVELOPER_DIR="$candidate" xcrun --sdk iphonesimulator --show-sdk-version 2>/dev/null) || continue
  if [[ "$sdk" == 26.* && "$simsdk" == 26.* ]]; then selected="$candidate"; break; fi
done < build/xcode-candidates.txt
[[ -n "$selected" ]] || { echo 'No installed Xcode with iOS 26 device and simulator SDKs'; exit 1; }
export DEVELOPER_DIR="$selected"
xcodebuild -version
xcodebuild -showsdks
xcodegen --version
bash scripts/prepare_icon.sh
echo "Optional HealthKit build: ${GYMREST_HEALTHKIT:-true}"
if [[ "${GYMREST_HEALTHKIT:-true}" == "true" ]]; then
  python3 scripts/health_project.py
  xcodegen generate --spec .gymrest-health.yml --project .
else
  xcodegen generate
fi
find_simulator() {
  xcrun simctl list devices available --json > build/devices.json
  xcodebuild -project GymRest.xcodeproj -scheme GymRest -showdestinations > build/destinations.log 2>&1
  python3 scripts/select_simulator.py build/devices.json build/destinations.log
}
# simctl availability alone does not prove the selected Xcode can use a runtime.
if ! simulator_info=$(find_simulator); then
  echo 'No eligible destination; install the selected Xcode iOS runtime and retry discovery once.'
  xcodebuild -downloadPlatform iOS
  if ! simulator_info=$(find_simulator); then
    xcrun simctl list runtimes --json > build/runtimes.json
    python3 scripts/provision_simulator.py build/runtimes.json "$simsdk"
    simulator_info=$(find_simulator)
  fi
fi
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
