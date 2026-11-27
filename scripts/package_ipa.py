"""Package only the unsigned iPhoneOS release product, preserving symlinks."""
from pathlib import Path
import plistlib
import json
import re
import shutil
import subprocess
import zipfile
import hashlib
import os

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
    app_info = plistlib.load(f)
    assert app_info["NSAlarmKitUsageDescription"]
with (extension / "Info.plist").open("rb") as f:
    assert plistlib.load(f)["NSExtension"]["NSExtensionPointIdentifier"] == "com.apple.widgetkit-extension"
# Check the actual Release product, not only the source tree or simulator bundle.
catalog = json.loads((app / "ExerciseCatalog.json").read_text())
guide_sources = json.loads((app / "WorkoutGuideSources.json").read_text())
extra_sources = json.loads((app / "EverkineticSources.json").read_text())
frames = {frame["file"] for item in guide_sources["exercises"] + extra_sources["exercises"] for frame in item["frames"]}
assert len(frames) == 912, "Release source manifest must reference all 906 source and 6 supplementary original frames"
mode = os.environ.get("MEDIA_MODE", "external")
assert mode in ["external", "bundled"]
assert app_info["GymRestMediaMode"] == mode
assert app_info["GymRestMediaSeedPolicy"] == os.environ.get("MEDIA_SEED_POLICY", "preserve")
assert not list(app.rglob("wg-*.png")) and not list(app.rglob("ek-*.png")), "Loose source images must not enter the production IPA"
pack = app / "MediaResources/Official.gymrestmedia"
if mode == "external":
    assert not pack.exists(), "External build must not embed the media pack"
else:
    assert pack.is_file()
    with zipfile.ZipFile(pack) as archive:
        manifest = json.loads(archive.read("manifest.json"))
        for file in manifest["files"]:
            assert hashlib.sha256(archive.read(file["path"])).hexdigest() == file["sha256"]
shown = {filename for item in catalog["exercises"] for filename in item["media"].get("frameAssets", [])}
assert shown.issubset(frames)
for filename in ["ExerciseGuides.json", "WorkoutGuideMediaReview.json", "WorkoutGuideSources.json", "EverkineticSources.json", "Everkinetic-LICENSE.txt", "WorkoutGuide-LICENSE.txt", "WorkoutGuide-LICENSE-ASSETS.txt", "WorkoutGuide-LICENSES.txt", "WorkoutGuide-ATTRIBUTION.txt"]:
    assert (app / filename).is_file(), filename
print(f"Validated {version} ({build}), {len(catalog['exercises'])} exercises, {len(frames)} source image references / {len(shown)} display references; media={mode}, guides and source/license notices")
assert not (app / "Watch").exists(), "iPhone-only product must not contain a stale Watch bundle"
staging = root / "build/ipa-staging"
if staging.exists(): shutil.rmtree(staging)
(staging / "Payload").mkdir(parents=True)
shutil.copytree(app, staging / "Payload/GymRest.app", symlinks=True)
out = root / "build/GymRest-unsigned.ipa"
out.unlink(missing_ok=True)
subprocess.run(["zip", "-qry", "-y", str(out), "Payload"], cwd=staging, check=True)
with zipfile.ZipFile(out) as archive:
    assert "Payload/GymRest.app/Info.plist" in archive.namelist()
    assert not any(name.startswith("Payload/GymRest.app/Watch/") for name in archive.namelist())
print(out)
