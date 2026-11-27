#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build
export GYMREST_WATCH="${GYMREST_WATCH:-${GYMREST_HEALTHKIT:-true}}"
# Keep tee in the foreground pipeline so diagnostics are fully drained before exit.
(
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
  if [[ "$sdk" == 26.* && "$simsdk" == 26.* ]]; then
    if [[ "$GYMREST_WATCH" == "true" ]]; then
      watch_sdk=$(DEVELOPER_DIR="$candidate" xcrun --sdk watchos --show-sdk-version 2>/dev/null) || continue
      watch_sim_sdk=$(DEVELOPER_DIR="$candidate" xcrun --sdk watchsimulator --show-sdk-version 2>/dev/null) || continue
      [[ "$watch_sdk" == 26.* && "$watch_sim_sdk" == 26.* ]] || continue
    fi
    selected="$candidate"; break
  fi
done < build/xcode-candidates.txt
[[ -n "$selected" ]] || { echo 'No installed Xcode with iOS 26 device and simulator SDKs'; exit 1; }
export DEVELOPER_DIR="$selected"
xcodebuild -version
xcodebuild -showsdks
xcodegen --version
bash scripts/prepare_icon.sh
python3 -m unittest discover -s scripts -p 'test_*.py' -q
python3 scripts/prepare_media_project.py
echo "Optional HealthKit build: ${GYMREST_HEALTHKIT:-true}"
if [[ "${GYMREST_HEALTHKIT:-true}" == "true" ]]; then
  python3 scripts/health_project.py .gymrest-media.yml
  task_spec=.gymrest-health.yml
else
  task_spec=.gymrest-media.yml
fi
if [[ "$GYMREST_WATCH" == "true" ]]; then
  python3 scripts/watch_project.py "$task_spec"
  task_spec=.gymrest-watch.yml
fi
xcodegen generate --spec "$task_spec" --project .
if [[ "$GYMREST_WATCH" == "true" ]]; then
  xcodebuild -project GymRest.xcodeproj -scheme GymRestWatch -configuration Debug \
    -destination 'generic/platform=watchOS Simulator' -derivedDataPath DerivedData CODE_SIGNING_ALLOWED=NO build
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
# Compile first so source errors fail without waiting for simulator boot.
xcodebuild -project GymRest.xcodeproj -scheme GymRest -configuration Debug \
  -destination "platform=iOS Simulator,id=$simulator" -derivedDataPath DerivedData \
  CODE_SIGNING_ALLOWED=NO build-for-testing
if [[ "$simulator_state" != "Booted" ]]; then xcrun simctl boot "$simulator"; fi
xcrun simctl bootstatus "$simulator" -b
xcodebuild -project GymRest.xcodeproj -scheme GymRest -configuration Debug \
  -destination "platform=iOS Simulator,id=$simulator" -derivedDataPath DerivedData \
  -resultBundlePath "build/Tests-$(date +%s).xcresult" CODE_SIGNING_ALLOWED=NO test-without-building
bash scripts/build_release.sh
python3 scripts/package_ipa.py
python3 scripts/build_media_pack.py --source-archive build/GymRest-Media-Sources.zip

) 2>&1 | tee build/build.log
