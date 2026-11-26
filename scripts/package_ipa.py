"""Package only the unsigned iPhoneOS release product, preserving symlinks."""
from pathlib import Path
import plistlib
import json
import re
import shutil
import subprocess
import zipfile

root = Path(__file__).resolve().parents[1]
app = root / "DerivedData/Build/Products/Release-iphoneos/GymRest.app"
extension = app / "PlugIns/GymRestWidgets.appex"
spec = (root / "project.yml").read_text()
version = re.search(r'MARKETING_VERSION: "([^\"]+)"', spec).group(1)
build = re.search(r'CURRENT_PROJECT_VERSION: "([^\"]+)"', spec).group(1)
for bundle, expected in [(app, "dev.gymrest.personal"), (extension, "dev.gymrest.personal.widgets")]:
    with (bundle / "Info.plist").open("rb") as f:
        info = plistlib.load(f)
    assert info["CFBundleIdentifier"] == expected
    assert info["CFBundleShortVersionString"] == version
    assert info["CFBundleVersion"] == build
    assert (bundle / info["CFBundleExecutable"]).is_file()
    assert info["MinimumOSVersion"].startswith("26.")
with (app / "Info.plist").open("rb") as f:
    assert plistlib.load(f)["NSAlarmKitUsageDescription"]
with (extension / "Info.plist").open("rb") as f:
    assert plistlib.load(f)["NSExtension"]["NSExtensionPointIdentifier"] == "com.apple.widgetkit-extension"
# Check the actual Release product, not only the source tree or simulator bundle.
catalog = json.loads((app / "ExerciseCatalog.json").read_text())
guide_sources = json.loads((app / "WorkoutGuideSources.json").read_text())
extra_sources = json.loads((app / "EverkineticSources.json").read_text())
frames = {frame["file"] for item in guide_sources["exercises"] + extra_sources["exercises"] for frame in item["frames"]}
assert len(frames) == 912, "Release bundle must include all 906 source and 6 supplementary original frames"
for filename in frames:
    assert (app / filename).is_file() or (app / "ExerciseFrames" / filename).is_file(), filename
shown = {filename for item in catalog["exercises"] for filename in item["media"].get("frameAssets", [])}
assert shown.issubset(frames)
for filename in ["ExerciseGuides.json", "WorkoutGuideMediaReview.json", "WorkoutGuideSources.json", "EverkineticSources.json", "Everkinetic-LICENSE.txt", "WorkoutGuide-LICENSE.txt", "WorkoutGuide-LICENSE-ASSETS.txt", "WorkoutGuide-LICENSES.txt", "WorkoutGuide-ATTRIBUTION.txt"]:
    assert (app / filename).is_file(), filename
print(f"Validated {version} ({build}), {len(catalog['exercises'])} exercises, {len(frames)} source images / {len(shown)} displayed frames, guides and source/license notices")
staging = root / "build/ipa-staging"
if staging.exists(): shutil.rmtree(staging)
(staging / "Payload").mkdir(parents=True)
shutil.copytree(app, staging / "Payload/GymRest.app", symlinks=True)
out = root / "build/GymRest-unsigned.ipa"
out.unlink(missing_ok=True)
subprocess.run(["zip", "-qry", "-y", str(out), "Payload"], cwd=staging, check=True)
with zipfile.ZipFile(out) as archive:
    assert "Payload/GymRest.app/Info.plist" in archive.namelist()
print(out)
